import Foundation
import Network

/// Minimal HTTP server so any agent can report events with curl. Binds only
/// loopback (for the local hook) and the Tailscale address (for the phone) —
/// never the whole LAN. Sandbox-compatible via network.server entitlement.
///
///   POST /event  {"agent":"myproject","event":"tool","tool":"Bash"}
///   GET  /agents -> current garden state as JSON
///
///   POST /approval/request      {"id","agent","tool","detail"} -> hook opens a request
///   GET  /approval/<id>         -> {"decision": null|"allow"|"deny"}, hook polls this
///   GET  /approvals             -> pending approvals, for the dashboard to render
///   POST /approval/<id>/decide  {"decision":"allow"|"deny"} -> dashboard answers
///
///   POST /prompt                {"agent","text"} -> phone queues a prompt
///   GET  /prompt/<agent>        -> {"prompt": null|"..."}, Stop hook drains this
///
///   POST /terminal              {"agent","screen"} -> tmux bridge mirrors the pane
///   GET  /terminal/<agent>      -> {"screen":"..."}, phone renders the live terminal
///   POST /keys                  {"agent","keys":[...]} -> phone sends keystrokes
///   GET  /keys/<agent>          -> {"keys":[...]}, tmux bridge replays them
///
/// Every endpoint except the dashboard shell (GET /, /icon.png) requires the
/// shared token from `GardenToken`, sent either as `Authorization: Bearer <t>`
/// (the hook) or a `?token=<t>` query param (the phone). Missing/wrong -> 401.
final class GardenServer {
    static let defaultPort: UInt16 = 4141

    private let store: AgentStore
    private let port: UInt16
    private var listeners: [NWListener] = []
    private let queue = DispatchQueue(label: "garden.server")
    let usage = UsageMonitor.shared

    init(store: AgentStore, port: UInt16) {
        self.store = store
        self.port = port
    }

    func start() {
        // Mint/load the token up front so the file exists before any hook fires.
        _ = GardenToken.value

        // Bind only where we need to: loopback for the local hook, and the
        // Tailscale address for the phone. Deliberately NOT 0.0.0.0, so the
        // dashboard isn't exposed to the rest of the LAN.
        var hosts = ["127.0.0.1"]
        if let tailscale = Self.tailscaleIPv4() {
            hosts.append(tailscale)
            NSLog("GardenServer: binding loopback + Tailscale \(tailscale):\(port)")
        } else {
            NSLog("GardenServer: no Tailscale interface found — dashboard reachable "
                + "only via localhost. Start Tailscale and relaunch to reach it from the phone.")
        }
        for host in hosts { startListener(on: host) }
        usage.start()
    }

    private func startListener(on host: String) {
        let params = NWParameters.tcp
        // Each host binds the SAME port on a different local address (loopback
        // + Tailscale). Without endpoint reuse the second bind fails with
        // "address in use", which is exactly why the Tailscale listener used to
        // die silently and the phone/QR couldn't connect.
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            NSLog("GardenServer: failed to create listener on \(host):\(port): \(error)")
            return
        }
        // The bind actually succeeds/fails asynchronously here, not at start() —
        // observe it so a failure is loud instead of a phantom "listening" log.
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("GardenServer: listening on \(host):\(self.port)")
            case .failed(let error):
                NSLog("GardenServer: bind FAILED on \(host):\(self.port): \(error)")
            case .cancelled:
                NSLog("GardenServer: listener cancelled on \(host):\(self.port)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.start(queue: queue)
        listeners.append(listener)
    }

    /// The URL to open the dashboard from the phone, tokenised. Prefers the
    /// Tailscale address (reachable from the phone) over the local hostname.
    static func phoneURL() -> String {
        let host = tailscaleIPv4() ?? ProcessInfo.processInfo.hostName
        return "http://\(host):\(defaultPort)/?token=\(GardenToken.value)"
    }

    /// The interface address Tailscale assigns from the 100.64.0.0/10 CGNAT
    /// range, or nil if Tailscale isn't up.
    static func tailscaleIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let sa = ifa.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }

            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                              &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: buf)

            // 100.64.0.0/10 == first octet 100, second octet in 64...127.
            let parts = ip.split(separator: ".")
            if parts.count == 4, parts[0] == "100",
               let second = Int(parts[1]), (64...127).contains(second) {
                return ip
            }
        }
        return nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = HTTPRequest(raw: buffer) {
                self.route(request, conn)
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buffer)
            }
        }
    }

    /// Endpoints safe to serve without the token: the static shell and the
    /// avatar images (browsers can't attach the Bearer header to <img src>).
    private func isPublic(_ path: String) -> Bool {
        path == "/" || path == "/icon.png" || path == "/apple-touch-icon.png"
            || path.hasPrefix("/avatar/")
    }

    private func route(_ req: HTTPRequest, _ conn: NWConnection) {
        if !isPublic(req.path), req.token != GardenToken.value {
            respond(conn, status: "401 Unauthorized", body: "{\"error\":\"unauthorized\"}")
            return
        }
        switch (req.method, req.path) {
        case ("GET", "/"):
            respond(conn, status: "200 OK", body: Data(DashboardPage.html.utf8),
                    contentType: "text/html; charset=utf-8")
        case ("GET", "/icon.png"), ("GET", "/apple-touch-icon.png"):
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
               let data = try? Data(contentsOf: url) {
                respond(conn, status: "200 OK", body: data, contentType: "image/png")
            } else {
                respond(conn, status: "404 Not Found", body: "{\"error\":\"no icon\"}")
            }
        case let (method, path) where method == "GET" && path.hasPrefix("/avatar/"):
            // Only ever serve a bundled `avatar-<n>.webp`; reject anything with
            // a slash or other characters so the path can't escape the bundle.
            let name = String(path.dropFirst("/avatar/".count))
            let ok = name.hasSuffix(".webp")
                && name.dropLast(".webp".count).allSatisfy { $0.isNumber || $0 == "-"
                    || $0.isLetter }
                && !name.contains("/") && !name.contains("..")
            let base = String(name.dropLast(".webp".count))
            if ok, let url = Bundle.main.url(forResource: base, withExtension: "webp"),
               let data = try? Data(contentsOf: url) {
                respond(conn, status: "200 OK", body: data, contentType: "image/webp")
            } else {
                respond(conn, status: "404 Not Found", body: "{\"error\":\"no avatar\"}")
            }
        case ("POST", "/event"):
            if let event = try? JSONDecoder().decode(GardenEvent.self, from: req.body) {
                DispatchQueue.main.async { self.store.apply(event) }
                respond(conn, status: "200 OK", body: "{\"ok\":true}")
            } else {
                respond(conn, status: "400 Bad Request", body: "{\"error\":\"bad event json\"}")
            }
        case ("GET", "/agents"):
            DispatchQueue.main.async {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let json = (try? encoder.encode(self.store.agents)).flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? "[]"
                self.queue.async { self.respond(conn, status: "200 OK", body: json) }
            }
        case ("GET", "/usage"):
            respond(conn, status: "200 OK", body: usage.json)
        case ("GET", "/approvals"):
            DispatchQueue.main.async {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let pending = self.store.approvals.filter { $0.decision == nil }
                let json = (try? encoder.encode(pending)).flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? "[]"
                self.queue.async { self.respond(conn, status: "200 OK", body: json) }
            }
        case ("POST", "/approval/request"):
            if let payload = try? JSONDecoder().decode(ApprovalRequest.self, from: req.body) {
                DispatchQueue.main.async {
                    self.store.requestApproval(
                        id: payload.id, agent: payload.agent, tool: payload.tool, detail: payload.detail)
                }
                respond(conn, status: "200 OK", body: "{\"ok\":true}")
            } else {
                respond(conn, status: "400 Bad Request", body: "{\"error\":\"bad approval json\"}")
            }
        case let (method, path) where method == "GET" && path.hasPrefix("/approval/"):
            let id = String(path.dropFirst("/approval/".count))
            DispatchQueue.main.async {
                let decision = self.store.decision(for: id)
                let json = decision.map { "{\"decision\":\"\($0)\"}" } ?? "{\"decision\":null}"
                self.queue.async { self.respond(conn, status: "200 OK", body: json) }
            }
        case let (method, path)
            where method == "POST" && path.hasPrefix("/approval/") && path.hasSuffix("/decide"):
            let id = String(path.dropFirst("/approval/".count).dropLast("/decide".count))
            if let payload = try? JSONDecoder().decode(ApprovalDecision.self, from: req.body) {
                DispatchQueue.main.async { self.store.decide(id: id, decision: payload.decision) }
                respond(conn, status: "200 OK", body: "{\"ok\":true}")
            } else {
                respond(conn, status: "400 Bad Request", body: "{\"error\":\"bad decision json\"}")
            }
        case ("POST", "/new-project"):
            if let payload = try? JSONDecoder().decode(NewProjectRequest.self, from: req.body),
               !payload.name.trimmingCharacters(in: .whitespaces).isEmpty {
                let name = payload.name.trimmingCharacters(in: .whitespaces)
                let ok = self.spawnProject(name: name, dir: payload.dir)
                if ok {
                    DispatchQueue.main.async {
                        self.store.apply(GardenEvent(agent: name, event: "start", task: payload.dir, tool: nil))
                    }
                    respond(conn, status: "200 OK", body: "{\"ok\":true,\"agent\":\"\(name)\"}")
                } else {
                    respond(conn, status: "500 Internal Server Error", body: "{\"error\":\"spawn failed — cek tmux/claude di PATH\"}")
                }
            } else {
                respond(conn, status: "400 Bad Request", body: "{\"error\":\"need a project name\"}")
            }
        case ("POST", "/prompt"):
            if let payload = try? JSONDecoder().decode(PromptRequest.self, from: req.body) {
                DispatchQueue.main.async {
                    self.store.enqueuePrompt(agent: payload.agent, text: payload.text)
                }
                respond(conn, status: "200 OK", body: "{\"ok\":true}")
            } else {
                respond(conn, status: "400 Bad Request", body: "{\"error\":\"bad prompt json\"}")
            }
        case let (method, path) where method == "GET" && path.hasPrefix("/prompt/"):
            let raw = String(path.dropFirst("/prompt/".count))
            let agent = raw.removingPercentEncoding ?? raw
            DispatchQueue.main.async {
                let json: String
                if let prompt = self.store.dequeuePrompt(agent: agent),
                   let data = try? JSONEncoder().encode(PromptResponse(prompt: prompt)),
                   let str = String(data: data, encoding: .utf8) {
                    json = str
                } else {
                    json = "{\"prompt\":null}"
                }
                self.queue.async { self.respond(conn, status: "200 OK", body: json) }
            }
        case ("POST", "/terminal"):
            if let payload = try? JSONDecoder().decode(TerminalRequest.self, from: req.body) {
                DispatchQueue.main.async {
                    self.store.setTerminal(agent: payload.agent, screen: payload.screen)
                }
                respond(conn, status: "200 OK", body: "{\"ok\":true}")
            } else {
                respond(conn, status: "400 Bad Request", body: "{\"error\":\"bad terminal json\"}")
            }
        case let (method, path) where method == "GET" && path.hasPrefix("/terminal/"):
            let raw = String(path.dropFirst("/terminal/".count))
            let agent = raw.removingPercentEncoding ?? raw
            DispatchQueue.main.async {
                let screen = self.store.terminal(agent: agent)
                let json = (try? JSONEncoder().encode(TerminalResponse(screen: screen)))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"screen\":null}"
                self.queue.async { self.respond(conn, status: "200 OK", body: json) }
            }
        case ("POST", "/keys"):
            if let payload = try? JSONDecoder().decode(KeysRequest.self, from: req.body) {
                DispatchQueue.main.async {
                    self.store.enqueueKeys(agent: payload.agent, keys: payload.keys)
                }
                respond(conn, status: "200 OK", body: "{\"ok\":true}")
            } else {
                respond(conn, status: "400 Bad Request", body: "{\"error\":\"bad keys json\"}")
            }
        case let (method, path) where method == "GET" && path.hasPrefix("/keys/"):
            let raw = String(path.dropFirst("/keys/".count))
            let agent = raw.removingPercentEncoding ?? raw
            DispatchQueue.main.async {
                let keys = self.store.dequeueKeys(agent: agent)
                let json = (try? JSONEncoder().encode(KeysResponse(keys: keys)))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"keys\":[]}"
                self.queue.async { self.respond(conn, status: "200 OK", body: json) }
            }
        default:
            respond(conn, status: "404 Not Found", body: "{\"error\":\"not found\"}")
        }
    }

    /// Start a detached Claude Code session + phone bridge for a new project via
    /// hooks/garden-spawn.sh, run through a login shell so tmux/claude are on
    /// PATH. Name/dir are passed as positional args ($1/$2) — never interpolated
    /// into the command string — so a project name can't inject shell.
    private func spawnProject(name: String, dir: String?) -> Bool {
        let hooks = ProcessInfo.processInfo.environment["GARDEN_HOOKS_DIR"]
            ?? UserDefaults.standard.string(forKey: "gardenHooksDir")
            ?? "\(NSHomeDirectory())/Documents/lab/2026/notTouch/AgentGarden/hooks"
        let script = "\(hooks)/garden-spawn.sh"
        guard FileManager.default.isExecutableFile(atPath: script) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", "\"\(script)\" \"$1\" \"$2\"", "garden-spawn", name, dir ?? ""]
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func respond(_ conn: NWConnection, status: String, body: String) {
        respond(conn, status: status, body: Data(body.utf8),
                contentType: "application/json")
    }

    private func respond(
        _ conn: NWConnection, status: String, body: Data, contentType: String
    ) {
        let head = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}

private struct NewProjectRequest: Codable {
    let name: String
    let dir: String?
}

private struct ApprovalRequest: Codable {
    let id: String
    let agent: String
    let tool: String
    let detail: String
}

private struct ApprovalDecision: Codable {
    let decision: String
}

private struct PromptRequest: Codable {
    let agent: String
    let text: String
}

private struct PromptResponse: Codable {
    let prompt: String?
}

private struct TerminalRequest: Codable {
    let agent: String
    let screen: String
}

private struct TerminalResponse: Codable {
    let screen: String?
}

private struct KeysRequest: Codable {
    let agent: String
    let keys: [String]
}

private struct KeysResponse: Codable {
    let keys: [String]
}

private struct HTTPRequest {
    let method: String
    let path: String        // without the query string
    let token: String?      // from `Authorization: Bearer` or `?token=`
    let body: Data

    /// Returns nil while the request is still incomplete.
    init?(raw: Data) {
        guard let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: raw[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        var contentLength = 0
        var bearer: String?
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = kv[0].lowercased()
            let val = kv[1].trimmingCharacters(in: .whitespaces)
            if key == "content-length" {
                contentLength = Int(val) ?? 0
            } else if key == "authorization", val.lowercased().hasPrefix("bearer ") {
                bearer = String(val.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        let bodyData = raw[headerEnd.upperBound...]
        guard bodyData.count >= contentLength else { return nil }

        method = parts[0]

        // Split path?query and pull `token` from the query if present.
        let target = parts[1]
        var queryToken: String?
        if let q = target.firstIndex(of: "?") {
            path = String(target[..<q])
            for pair in target[target.index(after: q)...].components(separatedBy: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2, kv[0] == "token" {
                    queryToken = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                }
            }
        } else {
            path = target
        }

        token = bearer ?? queryToken
        body = Data(bodyData.prefix(contentLength))
    }
}
