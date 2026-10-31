import PaperclipKit
import SwiftUI

// MARK: - Agent palettes

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// The two gradient stops of each Paperclip character palette (`CAP_V1_COLORS` on the server),
/// so cards and bubbles can carry the same colors as the agent's avatar.
enum AgentPalette {
    private static let stops: [String: (UInt32, UInt32)] = [
        "bubblegum-sky": (0x8BD4FF, 0xFF51BF), "pink-lemonade": (0xFF26A8, 0xFFF78A),
        "orchid-peach": (0xE771FF, 0xFFD87C), "coral-mint": (0xBEFFE8, 0xFF797B),
        "lime-lagoon": (0xB4FFA4, 0x26DFFF), "arctic-blue": (0x97FFF3, 0x0084FF),
        "solar-flare": (0xECCA5C, 0xFE3C3F), "violet-ember": (0xFF5C43, 0x6262FF),
        "deep-tide": (0x003D60, 0x32FFFC), "coral-current": (0x26E2FF, 0xFF6666),
        "golden-hour": (0xFFCD4F, 0xFDE5BA), "tangerine-cobalt": (0xFFAD32, 0x4169FF),
        "electric-grove": (0xB4FF32, 0x008D58), "flamingo-jade": (0xFF4F9A, 0x36EDAA),
        "cherry-pop": (0xFF69DB, 0xD51C46), "turquoise-cherry": (0x37F0DB, 0xFF4F64),
        "ultraviolet-tide": (0x7516CF, 0x00E8D1), "muted-dream": (0xA6AAAD, 0x44464A),
    ]

    private static func hexStops(for agent: Agent?) -> (UInt32, UInt32) {
        guard let agent else { return (0x8E8E93, 0x8E8E93) }
        let id = agent.status == .terminated ? "muted-dream" : (agent.resolvedAppearance.paletteId ?? "arctic-blue")
        return stops[id] ?? stops["arctic-blue"]!
    }

    static func colors(for agent: Agent?) -> (Color, Color) {
        let (a, b) = hexStops(for: agent)
        return (Color(hex: a), Color(hex: b))
    }

    /// Relative luminance (sRGB, WCAG) of a hex color.
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    /// The darker stop, scaled down until it reaches roughly 3:1 contrast on white, so palettes
    /// like pink-lemonade (whose light stop is pale yellow) stay readable as text.
    static func accentHex(for agent: Agent?) -> UInt32 {
        let (a, b) = hexStops(for: agent)
        var hex = luminance(a) < luminance(b) ? a : b
        for _ in 0..<12 where luminance(hex) > 0.30 {
            let r = (hex >> 16) & 0xFF, g = (hex >> 8) & 0xFF, bl = hex & 0xFF
            hex = (r * 85 / 100) << 16 | (g * 85 / 100) << 8 | (bl * 85 / 100)
        }
        return hex
    }

    static func gradient(for agent: Agent?) -> LinearGradient {
        let (a, b) = colors(for: agent)
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The darker-feeling stop, readable as a text/icon accent on light and dark backgrounds.
    static func accent(for agent: Agent?) -> Color { Color(hex: accentHex(for: agent)) }
}

// MARK: - Surfaces

extension View {
    /// Solid content card: grouped background, soft continuous corners.
    func card(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Floating control surface: Liquid Glass on iOS 26+, a material elsewhere.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 24, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular,
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Glass capsule for chips and small floating controls.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let glass = tint.map { Glass.regular.tint($0.opacity(0.3)) } ?? .regular
            self.glassEffect(interactive ? glass.interactive() : glass, in: Capsule())
        } else {
            self.background(tint.map { AnyShapeStyle($0.opacity(0.15)) } ?? AnyShapeStyle(.thinMaterial), in: Capsule())
        }
    }

    /// Primary call-to-action button: glass prominent on iOS 26+, bordered prominent before.
    @ViewBuilder
    func prominentButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Secondary button: glass on iOS 26+, bordered before.
    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

// MARK: - Progress

/// Circular progress with a rounded cap.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 8
    var tint: Color = .green

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: fraction)
        }
        .accessibilityElement()
        .accessibilityLabel(AppL10n.text("a11y.completed_percent", "\(Int(fraction * 100))% complete"))
    }
}

// MARK: - Chips

/// A compact pill with an icon and text, used for task metadata and filters.
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(filled ? Color.white : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)), in: Capsule())
    }
}

/// Small uppercase-ish section title used inside cards.
struct CardTitle: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(tint)
    }
}

/// An agent avatar sitting on a soft halo of its palette, with an optional live-status ring.
struct HaloAvatar: View {
    let agent: Agent?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(AgentPalette.gradient(for: agent).opacity(0.22))
            AgentAvatar(agent: agent, size: size * 0.78)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let status = agent?.status, status == .running || status == .error {
                Circle()
                    .fill(status.tint)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
            }
        }
    }
}

// MARK: - Assistant

/// Look of everything the AI task assistant touches, so it reads as one feature.
enum AssistantStyle {
    static let symbol = "wand.and.sparkles"
    static let colors = [Color(hex: 0x6366F1), Color(hex: 0xEC4899), Color(hex: 0xF59E0B)]
    static var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The assistant's mark: a wand on the assistant gradient, in a continuous rounded tile.
struct AssistantIcon: View {
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: AssistantStyle.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(AssistantStyle.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Readable width

/// On wide screens (iPad, landscape), keeps scrolling content in a centered column of
/// `maxWidth` points while the scroll view and its background still span the screen.
private struct ReadableWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var margin: CGFloat = 0

    func body(content: Content) -> some View {
        Group {
            // A margin replaces the scroll view's default inset, so only set one when the screen
            // is wider than the column; narrow screens keep the system inset.
            if margin > 0 {
                content.contentMargins(.horizontal, margin, for: .scrollContent)
            } else {
                content
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            margin = width > maxWidth + 40 ? (width - maxWidth) / 2 : 0
        }
    }
}

extension View {
    func readableWidth(_ maxWidth: CGFloat = 760) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}

// MARK: - Keyboard

extension View {
    /// Lets the user put the keyboard away: drag the content, or tap 完成 above the keyboard.
    func dismissableKeyboard() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AppL10n.text("action.done", "Done")) {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
            }
    }
}
