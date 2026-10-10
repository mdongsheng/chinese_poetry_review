import SwiftUI
import CoreText

/// 参考「西窗烛」的视觉：宣纸底色、浓淡墨色、朱砂印章红、楷体/宋体、大量留白。
enum Theme {
    // 宣纸
    static let paper = Color(light: 0xF6F1E7, dark: 0x1C1B19)
    static let paperDeep = Color(light: 0xEDE5D6, dark: 0x262420)
    // 墨
    static let ink = Color(light: 0x2B2A28, dark: 0xE6E0D4)
    static let inkLight = Color(light: 0x6E6A63, dark: 0xA39D92)
    static let inkFaint = Color(light: 0xB5AFA4, dark: 0x5E5A53)
    // 朱砂
    static let cinnabar = Color(light: 0xB33A2B, dark: 0xD0574A)
    // 黛青
    static let indigo = Color(light: 0x3F5560, dark: 0x8FA6B0)

    /// 打包了霞鹜文楷则用楷体，否则退回系统宋体（衬线）
    static let kaiName = "LXGWWenKai-Regular"
    private(set) static var hasKai = false

    static func registerFonts() {
        let urls = [nil, "Fonts"].flatMap { Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: $0) ?? [] }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        hasKai = UIFont(name: kaiName, size: 12) != nil
    }

    /// 正文字体
    static func poem(_ size: CGFloat) -> Font {
        hasKai ? .custom(kaiName, size: size) : .system(size: size, weight: .regular, design: .serif)
    }

    /// 标题字体
    static func title(_ size: CGFloat) -> Font {
        hasKai ? .custom(kaiName, size: size).weight(.semibold) : .system(size: size, weight: .semibold, design: .serif)
    }

    /// 说明性文字（解析）用宋体衬线更易读
    static func body(_ size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// 宣纸背景：底色 + 极淡的纤维噪点
struct PaperBackground: View {
    var body: some View {
        Theme.paper
            .overlay {
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: 7)
                    for _ in 0..<Int(size.width * size.height / 900) {
                        let x = rng.next() * size.width, y = rng.next() * size.height
                        let len = 2 + rng.next() * 6
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x + len, y: y + (rng.next() - 0.5) * 3))
                        ctx.stroke(path, with: .color(Theme.inkFaint.opacity(0.08)), lineWidth: 0.5)
                    }
                }
            }
            .ignoresSafeArea()
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(UInt32.max >> 1)
    }
}

/// 朱砂印章，例如「今日」「词」
struct SealStamp: View {
    let text: String
    var size: CGFloat = 34

    var body: some View {
        let chars = Array(text)
        let columns = chars.count > 2 ? 2 : 1
        let rows = Int(ceil(Double(chars.count) / Double(columns)))
        // 印文竖排，从右往左
        HStack(spacing: 0) {
            ForEach((0..<columns).reversed(), id: \.self) { c in
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { r in
                        let i = c * rows + r
                        if i < chars.count {
                            Text(String(chars[i]))
                        }
                    }
                }
            }
        }
        .font(Theme.title(size / CGFloat(max(rows, columns)) * 0.78))
        .foregroundStyle(Theme.paper)
        .frame(width: size, height: size)
        .background(Theme.cinnabar, in: RoundedRectangle(cornerRadius: 3))
        .rotationEffect(.degrees(-2))
    }
}

/// 细分隔线，带中间一个小菱形
struct OrnamentDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().frame(height: 0.5)
            Image(systemName: "diamond.fill").font(.system(size: 5))
            Rectangle().frame(height: 0.5)
        }
        .foregroundStyle(Theme.inkFaint)
        .frame(maxWidth: 160)
    }
}

extension View {
    func paperBackground() -> some View {
        background(PaperBackground())
    }
}
