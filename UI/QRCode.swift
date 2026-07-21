import AppKit
import CoreImage.CIFilterBuiltins

/// Generates a crisp QR code image for a string, so the phone can scan the
/// dashboard link instead of typing the token.
enum QRCode {
    private static let context = CIContext()

    static func image(for string: String, side: CGFloat = 180) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        // Scale the tiny generated image up to the requested pixel size, kept
        // sharp with nearest-neighbour (no blurring between modules).
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }
}
