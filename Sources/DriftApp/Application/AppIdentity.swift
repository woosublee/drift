import Foundation

struct AppIdentity: Equatable, Sendable {
    let displayName: String

    var quitTitle: String {
        "Quit \(displayName)"
    }

    static var current: AppIdentity {
        load(from: Bundle.main.infoDictionary ?? [:])
    }

    static func load(from infoDictionary: [String: Any]) -> AppIdentity {
        let candidate = (infoDictionary["CFBundleDisplayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let candidate, !candidate.isEmpty {
            return AppIdentity(displayName: candidate)
        }
        return AppIdentity(displayName: "Drift")
    }
}
