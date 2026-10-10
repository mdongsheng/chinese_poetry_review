import SwiftUI

/// 诗词正文。横排居中，或像古籍一样竖排、从右往左读。
struct PoemTextView: View {
    let poem: Poem
    var vertical: Bool
    var scale: Double = 1

    var body: some View {
        if vertical {
            VerticalPoemView(poem: poem, scale: scale)
        } else {
            HorizontalPoemView(poem: poem, scale: scale)
        }
    }
}

private struct HorizontalPoemView: View {
    let poem: Poem
    let scale: Double

    var body: some View {
        VStack(spacing: 14 * scale) {
            Text(poem.title)
                .font(Theme.title(24 * scale))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(poem.byline)
                .font(Theme.poem(15 * scale))
                .foregroundStyle(Theme.inkLight)
                .padding(.bottom, 10 * scale)
            VStack(spacing: 12 * scale) {
                ForEach(Array(poem.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Theme.poem(19 * scale))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6 * scale)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity)
    }
}

private struct VerticalPoemView: View {
    let poem: Poem
    let scale: Double

    private let maxPerColumn = 13
    private var fontSize: CGFloat { 21 * scale }

    /// 竖排时去掉标点，每个分句一列，过长再折列
    private var columns: [String] {
        let separators = CharacterSet(charactersIn: "，。、；：？！,.;:?!「」『』“”‘’（）()《》·")
        return poem.lines
            .flatMap { $0.components(separatedBy: separators) }
            .filter { !$0.isEmpty }
            .flatMap { clause -> [String] in
                let chars = Array(clause)
                return stride(from: 0, to: chars.count, by: maxPerColumn).map {
                    String(chars[$0..<min($0 + maxPerColumn, chars.count)])
                }
            }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: fontSize * 0.9) {
                // 数组倒序 + 默认滚到最右侧：第一列在最右
                ForEach(Array(columns.enumerated().reversed()), id: \.offset) { _, col in
                    column(col, font: Theme.poem(fontSize), color: Theme.ink)
                }
                VStack(spacing: 6) {
                    column(poem.byline.replacingOccurrences(of: "〔", with: "").replacingOccurrences(of: "〕", with: " "),
                           font: Theme.poem(14 * scale), color: Theme.inkLight)
                }
                .padding(.top, fontSize * 3)
                column(poem.title.replacingOccurrences(of: "·", with: "・"),
                       font: Theme.title(24 * scale), color: Theme.ink)
                    .padding(.leading, fontSize * 0.5)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .frame(minWidth: UIScreen.main.bounds.width, alignment: .trailing)
        }
        .defaultScrollAnchor(.trailing)
    }

    private func column(_ text: String, font: Font, color: Color) -> some View {
        VStack(spacing: 4 * scale) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(font)
                    .foregroundStyle(color)
            }
        }
    }
}
