import SwiftUI

struct HUDView: View {
    let message: HUDMessage

    var body: some View {
        VStack(spacing: 4) {
            Text(message.title)
                .font(.headline)
            if let subtitle = message.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
