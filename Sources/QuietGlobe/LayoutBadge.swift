import AppKit

/// Draws the menu bar badge for the current layout: a short label in a
/// rounded frame, like the system input menu. Template image, so it follows
/// the menu bar appearance (light/dark, tinted wallpaper).
enum LayoutBadge {
    private static var cache: [String: NSImage] = [:]

    static func image(label: String) -> NSImage {
        if let cached = cache[label] { return cached }

        let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let text = NSAttributedString(string: label, attributes: attributes)
        let textSize = text.size()

        let height: CGFloat = 16
        let frameHeight: CGFloat = 14
        let padding: CGFloat = 3.5
        let width = max(ceil(textSize.width + padding * 2), frameHeight + 4)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let frame = NSRect(x: 0.5, y: (height - frameHeight) / 2, width: width - 1, height: frameHeight)
            let path = NSBezierPath(roundedRect: frame, xRadius: 3.5, yRadius: 3.5)
            path.lineWidth = 1.2
            NSColor.black.setStroke()
            path.stroke()
            let origin = NSPoint(
                x: (width - textSize.width) / 2,
                y: (height - textSize.height) / 2 + 0.5
            )
            text.draw(at: origin)
            return true
        }
        image.isTemplate = true
        cache[label] = image
        return image
    }
}
