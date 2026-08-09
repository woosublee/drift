import Foundation

public struct UpdateConfiguration: Equatable {
    public let feedURL: URL
    public let publicEDKey: String

    public init(feedURL: URL, publicEDKey: String) {
        self.feedURL = feedURL
        self.publicEDKey = publicEDKey
    }

    public static func load(from infoDictionary: [String: Any]) -> UpdateConfiguration? {
        guard let feedString = infoDictionary["SUFeedURL"] as? String,
              let feedURL = URL(string: feedString),
              feedURL.scheme?.lowercased() == "https",
              feedURL.host?.isEmpty == false,
              let publicEDKey = infoDictionary["SUPublicEDKey"] as? String,
              let keyData = Data(base64Encoded: publicEDKey),
              keyData.count == 32 else {
            return nil
        }

        return UpdateConfiguration(feedURL: feedURL, publicEDKey: publicEDKey)
    }
}
