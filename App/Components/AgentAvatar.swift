import PaperclipKit
import SwiftUI
import UIKit

/// Loads server images with the board credential and caches them in memory.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    func image(for url: URL, client: PaperclipClient) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = inflight[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let data = try? await client.data(for: url) else { return nil }
            return UIImage(data: data)
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// The agent's Paperclip character, posed by status (working, confused, resting...).
struct AgentAvatar: View {
    @Environment(AppModel.self) private var app
    let agent: Agent?
    var size: CGFloat = 40

    @State private var image: UIImage?

    private var url: URL? {
        guard let agent, let client = app.client else { return nil }
        let pixels = size <= 24 ? 32 : size <= 48 ? 64 : size <= 96 ? 128 : 256
        return client.absoluteURL(agent.avatarPath(size: pixels, scale: 2))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        Text(String(agent?.name.prefix(1) ?? "?"))
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            guard let url, let client = app.client else { return }
            image = await ImageCache.shared.image(for: url, client: client)
        }
        .accessibilityHidden(true)
    }
}
