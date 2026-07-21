import SwiftUI

/// Sprites are ASCII grids: each character is one pixel, mapped through `palette`.
/// '.' is transparent. Rendered with hard edges (no interpolation) for the
/// arcade pixel look. Replace these with real sprite sheets later.
enum Pixel {
    static let palette: [Character: Color] = [
        "y": Color(hex: 0xFFE300), // pac-man yellow
        "r": Color(hex: 0xFF3B30), // ghost / cherry red
        "w": Color(hex: 0xFFFFFF), // eye white / highlight
        "b": Color(hex: 0x3B6EFF), // ghost pupil blue
        "k": Color(hex: 0x1B1B1B), // black
        "t": Color(hex: 0x3FAA38), // cherry stem green
        "e": Color(hex: 0x8E8E8E), // game-over gray
    ]
}

struct PixelSpriteView: View {
    let art: [String]
    var pixel: CGFloat = 1.5

    var body: some View {
        Canvas { ctx, _ in
            for (y, row) in art.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let color = Pixel.palette[ch] else { continue }
                    let rect = CGRect(
                        x: CGFloat(x) * pixel, y: CGFloat(y) * pixel,
                        width: pixel, height: pixel)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(
            width: CGFloat(art.first?.count ?? 0) * pixel,
            height: CGFloat(art.count) * pixel)
    }
}

enum Sprites {
    /// Classic pellet color.
    static let dotColor = Color(hex: 0xFFB897)

    static let pacmanOpen = [
        "....yyyy....",
        "..yyyyyyyy..",
        "..yyykyyyy..",
        ".yyyyyyyy...",
        ".yyyyyy.....",
        ".yyyy.......",
        ".yyyyyy.....",
        ".yyyyyyyy...",
        "..yyyyyyyy..",
        "..yyyyyyyy..",
        "....yyyy....",
        "............",
    ]

    static let pacmanClosed = [
        "....yyyy....",
        "..yyyyyyyy..",
        "..yyykyyyy..",
        ".yyyyyyyyyy.",
        ".yyyyyyyyyy.",
        ".yyyyyyyyyy.",
        ".yyyyyyyyyy.",
        ".yyyyyyyyyy.",
        "..yyyyyyyy..",
        "..yyyyyyyy..",
        "....yyyy....",
        "............",
    ]

    static func pacman(open: Bool) -> [String] {
        open ? pacmanOpen : pacmanClosed
    }

    static let ghost = [
        "....rrrr....",
        "..rrrrrrrr..",
        ".rrrrrrrrrr.",
        ".rwwrrrwwrr.",
        ".rwbrrrwbrr.",
        ".rrrrrrrrrr.",
        ".rrrrrrrrrr.",
        ".rrrrrrrrrr.",
        ".rrrrrrrrrr.",
        ".rr.rr.rr.rr",
        "............",
        "............",
    ]

    static let cherry = [
        "............",
        "......tt....",
        ".....t......",
        "....t.t.....",
        "...t...t....",
        "..rrr...rrr.",
        ".rrrrr.rrrrr",
        ".rwrrr.rwrrr",
        ".rrrrr.rrrrr",
        "..rrr...rrr.",
        "............",
        "............",
    ]

    static let gameOver = [
        "....eeee....",
        "..eeeeeeee..",
        "..eekeekee..",
        ".eeeeeeeeee.",
        ".eeeeeeeeee.",
        ".eeeeeeeeee.",
        ".eeeeeeeeee.",
        ".eeeeeeeeee.",
        "..eeeeeeee..",
        "..eeeeeeee..",
        "....eeee....",
        "............",
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
