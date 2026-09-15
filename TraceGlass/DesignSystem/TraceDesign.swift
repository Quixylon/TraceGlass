import SwiftUI
import UIKit

enum TraceDesign {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red:0.57,green:0.96,blue:0.83,alpha:1) : UIColor(red:0.0,green:0.42,blue:0.32,alpha:1)
    })
    static let buttonText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red:0.04,green:0.065,blue:0.085,alpha:1) : .white
    })
    static let ink = Color(red: 0.04, green: 0.065, blue: 0.085)
    static let space: CGFloat = 16
    static let radius: CGFloat = 28
    static let target: CGFloat = 48
    static let motion = Animation.spring(response: 0.38, dampingFraction: 0.84)
}
extension RGBA {
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(uiColor: uiColor) }
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: r, g: g, b: b, a: a)
    }
}
struct GlassSurface: ViewModifier {
    var radius: CGFloat = TraceDesign.radius
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}
extension View {
    func traceGlass(radius: CGFloat = TraceDesign.radius) -> some View { modifier(GlassSurface(radius: radius)) }
}
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 12) { content } }
        else { content }
    }
}
struct ToolButton: View {
    let title: String
    let symbol: String
    var selected = false
    var compact = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                if !compact { Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1) }
            }
            .foregroundStyle(selected ? TraceDesign.buttonText : .primary)
            .frame(minWidth: TraceDesign.target, minHeight: TraceDesign.target)
            .padding(.horizontal, 3)
            .background(selected ? TraceDesign.accent : Color.clear, in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}
struct PrimaryButton: View {
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity).frame(height: 58)
                .foregroundStyle(TraceDesign.buttonText).background(TraceDesign.accent, in: Capsule())
        }.buttonStyle(.plain)
    }
}
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format = "%.2f"
    var editing: (Bool) -> Void = { _ in }
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: format, value)).monospacedDigit().font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, onEditingChanged: editing).tint(TraceDesign.accent).accessibilityLabel(title)
        }
    }
}
