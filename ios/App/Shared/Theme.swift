import DailyCommandCore
import SwiftUI

// Daily Command tokens — the same values as the web app's Daily Command section
// (execclone-apps web/src/app/globals.css). Dark only.

enum DC {
    static let bg = Color(hex: 0x000000)
    static let panel = Color(hex: 0x111111)
    static let card = Color(hex: 0x151515)
    static let cardHi = Color(hex: 0x1A1A1A)
    static let line = Color(hex: 0x242424)
    static let text = Color(hex: 0xF2F2F2)
    static let text2 = Color(hex: 0xC9C9C9)
    static let muted = Color(hex: 0x8F8F8F)
    static let dim = Color(hex: 0x6B6B6B)
    static let gold = Color(hex: 0xD4A43C)
    static let goldText = Color(hex: 0xE3BB5C)
    static let goldSoft = Color(hex: 0xD4A43C).opacity(0.14)
    static let red = Color(hex: 0xFF5A52)
    static let blue = Color(hex: 0x4C8DFF)
    static let green = Color(hex: 0x30D158)
    static let orange = Color(hex: 0xFF9F0A)

    static let radius: CGFloat = 12

    enum Font {
        static let display = SwiftUI.Font.system(size: 30, weight: .semibold)
        static let title = SwiftUI.Font.system(size: 22, weight: .semibold)
        static let headline = SwiftUI.Font.system(size: 16, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 15)
        static let small = SwiftUI.Font.system(size: 13)
        static let kicker = SwiftUI.Font.system(size: 10, weight: .semibold)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct Kicker: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(DC.Font.kicker).tracking(2.6).foregroundStyle(DC.goldText)
    }
}

struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack {
                    Kicker(title)
                    Spacer()
                    if let trailing { trailing }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DC.card, in: RoundedRectangle(cornerRadius: DC.radius))
        .overlay(RoundedRectangle(cornerRadius: DC.radius).stroke(DC.line))
    }
}

extension Card {
    func trailing<T: View>(@ViewBuilder _ view: () -> T) -> Card {
        var c = self
        c.trailing = AnyView(view())
        return c
    }
}

/// A 1–5 picker used by the check-ins and the day rating.
struct Scale: View {
    let value: Int?
    let onChange: (Int?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { n in
                Button {
                    onChange(value == n ? nil : n)
                } label: {
                    Text("\(n)")
                        .font(DC.Font.small.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(value == n ? DC.gold : DC.cardHi, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(value == n ? DC.bg : DC.text2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Text(message)
            .font(DC.Font.small)
            .foregroundStyle(DC.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DC.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Short date labels for `yyyy-MM-dd` strings.
enum DateText {
    static func long(_ ymd: String) -> String {
        guard let d = Planning.date(ymd) else { return ymd }
        var f = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        f.timeZone = TimeZone(identifier: "UTC")!
        return d.formatted(f)
    }

    static func short(_ ymd: String) -> String {
        guard let d = Planning.date(ymd) else { return ymd }
        var f = Date.FormatStyle.dateTime.weekday(.abbreviated).day()
        f.timeZone = TimeZone(identifier: "UTC")!
        return d.formatted(f)
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}
