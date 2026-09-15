import Foundation
import Combine

enum DoubleTapAction: String, Codable, CaseIterable, Identifiable {
    case fit = "Fit", center = "Center", actual = "100%", original = "Original"
    var id: String { rawValue }
}
enum TwoFingerAction: String, Codable, CaseIterable, Identifiable {
    case hide = "Hide Reference", original = "Original"
    var id: String { rawValue }
}
enum Quality: String, Codable, CaseIterable, Identifiable {
    case automatic = "Automatic", high = "High", performance = "Performance"
    var id: String { rawValue }
}
struct Preferences: Codable, Equatable {
    var haptics = true
    var sounds = false
    var snap = true
    var animationQuality: Quality = .automatic
    var arQuality: Quality = .automatic
    var unlockDuration: Double = 1.1
    var maxBrightnessOnLock = true
    var doubleTap: DoubleTapAction = .fit
    var twoFingerHold: TwoFingerAction = .hide
    var defaultBackground = RGBA.white
    var followSystemTheme = false
    var tutorialSeen = false
    var importTipSeen = false
    var calibratedPointsPerMM: Double? = nil
}
@MainActor final class AppSettings: ObservableObject {
    @Published var value: Preferences { didSet { save() } }
    init() {
        if let data = UserDefaults.standard.data(forKey: "TraceGlass.preferences"),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) { value = decoded }
        else { value = Preferences() }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "TraceGlass.preferences") }
    }
}
