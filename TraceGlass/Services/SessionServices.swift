import UIKit
import Combine
import AudioToolbox

@MainActor final class DisplaySession: ObservableObject {
    @Published private(set) var brightness: Double = Double(UIScreen.main.brightness)
    private var originalBrightness: CGFloat?
    private var originalIdle = false
    private var active = false
    private var desiredBrightness: Double?
    func begin() {
        guard !active else { return }
        active = true; originalIdle = UIApplication.shared.isIdleTimerDisabled
        originalBrightness = UIScreen.main.brightness
        brightness = Double(UIScreen.main.brightness)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    func setBrightness(_ value: Double) {
        guard active else { return }
        brightness = min(1, max(0.05, value)); desiredBrightness = brightness
        UIScreen.main.brightness = brightness
    }
    func suspend() {
        guard active else { return }
        if let originalBrightness { UIScreen.main.brightness = originalBrightness }
        UIApplication.shared.isIdleTimerDisabled = originalIdle
    }
    func resume() {
        guard active else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        if let desiredBrightness { UIScreen.main.brightness = desiredBrightness }
    }
    func end() { suspend(); originalBrightness = nil; desiredBrightness = nil; active = false }
}

@MainActor final class ThermalManager: ObservableObject {
    @Published private(set) var state = ProcessInfo.processInfo.thermalState
    private var observer: AnyCancellable?
    init() {
        observer = NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.state = ProcessInfo.processInfo.thermalState }
    }
    var warm: Bool { state == .serious || state == .critical }
    var reduced: Bool { state != .nominal }
}
@MainActor enum Feedback {
    static func tick(_ enabled: Bool) { if enabled { UISelectionFeedbackGenerator().selectionChanged() } }
    static func impact(_ enabled: Bool, sound: Bool = false) {
        if enabled { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7) }
        if sound { AudioServicesPlaySystemSound(1104) }
    }
}
@MainActor final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .allButUpsideDown
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { Self.orientationMask }
    static func freezeOrientation(_ locked: Bool) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        if locked {
            switch scene.interfaceOrientation {
            case .landscapeLeft: orientationMask = .landscapeLeft
            case .landscapeRight: orientationMask = .landscapeRight
            case .portraitUpsideDown: orientationMask = .portraitUpsideDown
            default: orientationMask = .portrait
            }
        } else { orientationMask = .allButUpsideDown }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationMask)) { _ in }
    }
}
