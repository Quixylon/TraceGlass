import SwiftUI

struct SettingsView:View {
    @ObservedObject var settings:AppSettings
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack{Text("Settings").font(.largeTitle.weight(.semibold));Spacer();Button("Done"){dismiss()}}
                group("Feel") {
                    Toggle("Haptics",isOn:binding(\.haptics))
                    Toggle("Interface sounds",isOn:binding(\.sounds))
                    Toggle("Magnetic snap",isOn:binding(\.snap))
                    Picker("Animation quality",selection:binding(\.animationQuality)){ForEach(Quality.allCases){Text($0.rawValue).tag($0)}}
                    Picker("AR quality",selection:binding(\.arQuality)){ForEach(Quality.allCases){Text($0.rawValue).tag($0)}}
                }
                group("Tracing") {
                    Toggle("Max brightness on Lock",isOn:binding(\.maxBrightnessOnLock))
                    ValueSlider(title:"Hold to unlock, seconds",value:binding(\.unlockDuration),range:0.8...1.5,format:"%.1f")
                    Picker("Double tap",selection:binding(\.doubleTap)){ForEach(DoubleTapAction.allCases){Text($0.rawValue).tag($0)}}
                    Picker("Two-finger hold",selection:binding(\.twoFingerHold)){ForEach(TwoFingerAction.allCases){Text($0.rawValue).tag($0)}}
                    ColorPicker("Default background",selection:Binding(get:{settings.value.defaultBackground.color},set:{settings.value.defaultBackground=RGBA($0)}),supportsOpacity:false)
                }
                group("Appearance & help") {
                    Toggle("Follow system appearance",isOn:binding(\.followSystemTheme))
                    Button("Show tips again"){settings.value.tutorialSeen=false;settings.value.importTipSeen=false}
                    Text("For paper placed on the screen, Lock protects the reference inside the app. iOS still handles its own system gestures. Guided Access in iPhone Settings can keep the session on screen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("TraceGlass 1.0\nAll image processing stays on your iPhone. No account. No image uploads.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.presentationDetents([.large])
    }
    private func binding<T>(_ path:WritableKeyPath<Preferences,T>)->Binding<T>{Binding(get:{settings.value[keyPath:path]},set:{settings.value[keyPath:path]=$0})}
    private func group<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:18){Text(title).font(.headline);content()}.padding(20).traceGlass(radius:26)
    }
}
