import Foundation
import Combine

/// Scans Claude Code transcripts (~/.claude/projects/**/*.jsonl) and computes
/// AI-model spend per day and per model, so the Island, the phone dashboard,
/// and the watch can all show one number: "$ used today / daily budget".
///
/// Cost = tokens × per-model price (input / output / cache-write / cache-read),
/// summed by the message's local calendar day. Refreshes on a timer; serves a
/// cached JSON blob at GET /usage. The daily budget is user-set (UserDefaults
/// `usageDailyBudget`, default $6/day) and drives the 80% / 100% warnings.
final class UsageMonitor: ObservableObject {
    static let shared = UsageMonitor()

    // Published summary for SwiftUI (Island). Updated on the main thread.
    @Published private(set) var today: Double = 0
    @Published private(set) var budget: Double = 6
    @Published private(set) var pct: Double = 0
    @Published private(set) var spark: [Double] = []      // 7-day daily cost
    @Published private(set) var topModel: String = ""

    struct Price { let inTok, outTok, cacheWrite, cacheRead: Double } // $ per 1M

    // From the claude-api skill (2026-06). Cache write = 5-min TTL (1.25×);
    // cache read = 0.1×. Unknown models fall back to Opus-tier pricing.
    private static let prices: [String: Price] = [
        "claude-opus-4-8":   Price(inTok: 5,  outTok: 25, cacheWrite: 6.25,  cacheRead: 0.50),
        "claude-opus-4-7":   Price(inTok: 5,  outTok: 25, cacheWrite: 6.25,  cacheRead: 0.50),
        "claude-opus-4-6":   Price(inTok: 5,  outTok: 25, cacheWrite: 6.25,  cacheRead: 0.50),
        "claude-fable-5":    Price(inTok: 10, outTok: 50, cacheWrite: 12.50, cacheRead: 1.00),
        "claude-mythos-5":   Price(inTok: 10, outTok: 50, cacheWrite: 12.50, cacheRead: 1.00),
        "claude-sonnet-5":   Price(inTok: 3,  outTok: 15, cacheWrite: 3.75,  cacheRead: 0.30),
        "claude-sonnet-4-6": Price(inTok: 3,  outTok: 15, cacheWrite: 3.75,  cacheRead: 0.30),
        "claude-haiku-4-5":  Price(inTok: 1,  outTok: 5,  cacheWrite: 1.25,  cacheRead: 0.10),
    ]
    private static let fallbackPrice = Price(inTok: 5, outTok: 25, cacheWrite: 6.25, cacheRead: 0.50)

    private let root = ("~/.claude/projects" as NSString).expandingTildeInPath
    private let queue = DispatchQueue(label: "garden.usage", qos: .utility)
    private var timer: DispatchSourceTimer?

    /// Latest computed snapshot as a JSON string (what GET /usage returns).
    private(set) var json: String = "{\"today\":0,\"budget\":6,\"pct\":0,\"byModel\":[],\"days\":[]}"

    var dailyBudget: Double {
        let v = UserDefaults.standard.double(forKey: "usageDailyBudget")
        return v > 0 ? v : 6.0
    }
    func setDailyBudget(_ v: Double) {
        UserDefaults.standard.set(v, forKey: "usageDailyBudget")
        refresh()
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 60)
        t.setEventHandler { [weak self] in self?.compute() }
        t.resume()
        timer = t
    }

    func refresh() { queue.async { [weak self] in self?.compute() } }

    // MARK: - computation

    private func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func compute() {
        let fm = FileManager.default
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        // last 7 local days (today last)
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var dayKeys: [String] = []
        for i in stride(from: 6, through: 0, by: -1) {
            if let d = cal.date(byAdding: .day, value: -i, to: todayStart) {
                dayKeys.append(dayKey(d))
            }
        }
        let todayK = dayKeys.last ?? dayKey(Date())

        var perDay: [String: Double] = [:]
        var todayModel: [String: Double] = [:]

        guard let en = fm.enumerator(atPath: root) else { publish(perDay, todayModel, dayKeys, todayK); return }
        let cutoff = Date().addingTimeInterval(-8 * 86400)
        for case let rel as String in en where rel.hasSuffix(".jsonl") {
            let path = (root as NSString).appendingPathComponent(rel)
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let mod = attrs[.modificationDate] as? Date, mod < cutoff { continue }
            guard let data = fm.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let ld = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
                      let msg = obj["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any] else { continue }
                let ts = obj["timestamp"] as? String
                let date = ts.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
                guard let date = date else { continue }
                let k = dayKey(date)
                guard dayKeys.contains(k) else { continue }
                let model = (msg["model"] as? String) ?? "unknown"
                let p = Self.prices[model] ?? Self.fallbackPrice
                let inTok = (usage["input_tokens"] as? Double) ?? 0
                let outTok = (usage["output_tokens"] as? Double) ?? 0
                let cw = (usage["cache_creation_input_tokens"] as? Double) ?? 0
                let cr = (usage["cache_read_input_tokens"] as? Double) ?? 0
                let cost = (inTok * p.inTok + outTok * p.outTok + cw * p.cacheWrite + cr * p.cacheRead) / 1_000_000
                perDay[k, default: 0] += cost
                if k == todayK { todayModel[model, default: 0] += cost }
            }
        }
        publish(perDay, todayModel, dayKeys, todayK)
    }

    private func publish(_ perDay: [String: Double], _ todayModel: [String: Double],
                         _ dayKeys: [String], _ todayK: String) {
        let today = perDay[todayK] ?? 0
        let budget = dailyBudget
        let pct = budget > 0 ? min(today / budget, 9.99) : 0
        let days = dayKeys.map { ["date": $0, "cost": (perDay[$0] ?? 0)] as [String: Any] }
        let byModel = todayModel.sorted { $0.value > $1.value }
            .map { ["model": $0.key, "cost": $0.value] as [String: Any] }
        let blob: [String: Any] = [
            "today": today, "budget": budget, "pct": pct,
            "byModel": byModel, "days": days,
        ]
        if let d = try? JSONSerialization.data(withJSONObject: blob),
           let s = String(data: d, encoding: .utf8) {
            queue.async { self.json = s }
        }
        let spark = dayKeys.map { perDay[$0] ?? 0 }
        let top = todayModel.max { $0.value < $1.value }?.key ?? ""
        DispatchQueue.main.async {
            self.today = today; self.budget = budget; self.pct = pct
            self.spark = spark; self.topModel = top
        }
    }
}
