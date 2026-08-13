import AppKit

enum MenuBarGlyph: Equatable {
    case asset(name: String)
    case systemSymbol(name: String)
}

@MainActor
enum MenuBarIconRenderer {
    private static let size = NSSize(width: 18, height: 18)

    static func image(
        for glyph: MenuBarGlyph,
        accessibilityDescription: String,
        resourceDirectory: URL? = Bundle.main.resourceURL
    ) -> NSImage? {
        let image: NSImage?
        switch glyph {
        case let .asset(name):
            guard let resourceDirectory else { return nil }
            image = NSImage(
                contentsOf: resourceDirectory.appendingPathComponent("\(name).svg")
            )
        case let .systemSymbol(name):
            image = NSImage(
                systemSymbolName: name,
                accessibilityDescription: accessibilityDescription
            )
        }

        image?.size = size
        image?.isTemplate = true
        image?.accessibilityDescription = accessibilityDescription
        return image
    }
}
