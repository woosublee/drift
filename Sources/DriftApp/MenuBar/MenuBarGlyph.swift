import AppKit

enum MenuBarGlyph: Hashable {
    case asset(name: String)
    case systemSymbol(name: String)
}

@MainActor
final class MenuBarIconRenderer {
    typealias AssetLoader = (URL) -> NSImage?

    private static let size = NSSize(width: 18, height: 18)
    private let resourceDirectory: URL?
    private let assetLoader: AssetLoader
    private var cache: [MenuBarGlyph: NSImage] = [:]

    init(
        resourceDirectory: URL? = Bundle.main.resourceURL,
        assetLoader: @escaping AssetLoader = { NSImage(contentsOf: $0) }
    ) {
        self.resourceDirectory = resourceDirectory
        self.assetLoader = assetLoader
    }

    func image(
        for glyph: MenuBarGlyph,
        accessibilityDescription: String
    ) -> NSImage? {
        if let image = cache[glyph] {
            image.accessibilityDescription = accessibilityDescription
            return image
        }

        let image: NSImage?
        switch glyph {
        case let .asset(name):
            guard let resourceDirectory else { return nil }
            image = assetLoader(
                resourceDirectory.appendingPathComponent("\(name).svg")
            )
        case let .systemSymbol(name):
            image = NSImage(
                systemSymbolName: name,
                accessibilityDescription: accessibilityDescription
            )
        }

        guard let image else { return nil }
        image.size = Self.size
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        cache[glyph] = image
        return image
    }
}
