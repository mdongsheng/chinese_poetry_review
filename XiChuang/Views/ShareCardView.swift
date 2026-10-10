import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// 分享 / 通知附件用的诗词卡片
struct ShareCardView: View {
    let poem: Poem
    var summary: String?

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                SealStamp(text: poem.kind.label, size: 30)
            }
            Text(poem.title)
                .font(Theme.title(26))
                .multilineTextAlignment(.center)
            Text(poem.byline)
                .font(Theme.poem(15))
                .foregroundStyle(Theme.inkLight)
            VStack(spacing: 12) {
                ForEach(Array(poem.lines.prefix(14).enumerated()), id: \.offset) { _, line in
                    Text(line).font(Theme.poem(19)).multilineTextAlignment(.center)
                }
                if poem.lines.count > 14 {
                    Text("……").font(Theme.poem(19))
                }
            }
            if let summary {
                OrnamentDivider()
                Text(summary)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkLight)
                    .multilineTextAlignment(.center)
            }
            Text("每日一词")
                .font(Theme.poem(12))
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 8)
        }
        .foregroundStyle(Theme.ink)
        .padding(36)
        .frame(width: 400)
        .background(Theme.paper)
        .environment(\.colorScheme, .light)
    }

    @MainActor
    static func pngData(poem: Poem, summary: String?) -> Data? {
        let renderer = ImageRenderer(content: ShareCardView(poem: poem, summary: summary))
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }
}

/// 让卡片可以直接放进 ShareLink，点分享时才渲染图片
struct PoemCard: Transferable, Sendable {
    let poem: Poem
    let summary: String?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            let data = await MainActor.run { ShareCardView.pngData(poem: card.poem, summary: card.summary) }
            return data ?? Data()
        }
        ProxyRepresentation { card in
            "《\(card.poem.title)》\(card.poem.byline)\n\(card.poem.fullText)"
        }
    }
}
