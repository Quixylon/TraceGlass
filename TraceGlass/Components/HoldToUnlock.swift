import SwiftUI

struct HoldToUnlock: View {
    let duration: Double
    var unlock: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holding = false
    @State private var progress: CGFloat = 0
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.12), lineWidth: 2)
            Circle().trim(from: 0, to: progress).stroke(TraceDesign.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: holding ? "lock.open.fill" : "lock.fill").font(.system(size: 18, weight: .medium))
        }
        .padding(8).frame(width: 58,height: 58).traceGlass(radius: 29)
        .scaleEffect(holding && !reduceMotion ? 1.08 : 1)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 12, pressing: { value in
            holding = value
            withAnimation(value ? .linear(duration: duration) : .easeOut(duration: 0.17)) { progress = value ? 1 : 0 }
        }, perform: {
            guard scenePhase == .active else { return }
            holding = false; progress = 0; unlock()
        })
        .onChange(of: scenePhase) { _, phase in if phase != .active { holding = false; progress = 0 } }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("unlockReference")
        .accessibilityLabel("Unlock reference")
        .accessibilityHint("Touch and hold for \(String(format: "%.1f", duration)) seconds.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { unlock() }
    }
}
