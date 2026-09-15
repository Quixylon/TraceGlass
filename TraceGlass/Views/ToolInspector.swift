import SwiftUI

enum TraceTool: String, CaseIterable, Identifiable {
    case transform = "Transform", image = "Image", filters = "Filters", grid = "Grid", background = "Background"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .transform: return "arrow.up.left.and.arrow.down.right"; case .image: return "square.3.layers.3d"
        case .filters: return "slider.horizontal.3"; case .grid: return "grid"; case .background: return "circle.lefthalf.filled" }
    }
}
struct ToolInspector: View {
    @ObservedObject var store: TraceStore
    let tool: TraceTool
    var addImage: () -> Void
    var crop: () -> Void
    @State private var advanced = false
    @State private var showCalibration = false
    @State private var filterParameter = "Contrast"
    @State private var rename = ""
    @State private var renaming = false
    @State private var physicalExpanded = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch tool {
                case .transform: transformTools
                case .image: imageTools
                case .filters: filterTools
                case .grid: gridTools
                case .background: backgroundTools
                }
            }.padding(.horizontal, 18).padding(.vertical, 8)
        }.scrollIndicators(.hidden)
        .sheet(isPresented: $showCalibration) { CalibrationView(store: store) }
        .alert("Rename reference", isPresented: $renaming) {
            TextField("Name", text: $rename)
            Button("Save") { store.updateLayer { $0.name = String(rename.prefix(80)) } }
            Button("Cancel", role: .cancel) {}
        }
    }
    private func layerBinding<T>(_ path: WritableKeyPath<ReferenceLayer, T>, fallback: T) -> Binding<T> {
        Binding(get: { store.selected?[keyPath: path] ?? fallback }, set: { value in store.updateLayer { $0[keyPath: path] = value } })
    }
    private func filterBinding(_ path: WritableKeyPath<FilterSettings, Double>) -> Binding<Double> {
        Binding(get: { store.selected?.filters[keyPath:path] ?? 0 }, set: { value in store.updateLayer({ $0.filters[keyPath:path] = value }, continuous: true) })
    }
    private func canvasBinding<T>(_ path: WritableKeyPath<CanvasSettings,T>) -> Binding<T> {
        Binding(get: { store.project.canvas[keyPath:path] }, set: { v in store.edit { $0.canvas[keyPath:path] = v } })
    }
    private func gridBinding<T>(_ path: WritableKeyPath<GridSettings,T>) -> Binding<T> {
        Binding(get: { store.project.canvas.grid[keyPath:path] }, set: { v in store.edit { $0.canvas.grid[keyPath:path] = v } })
    }
    private var transformTools: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: 5) {
                ForEach([("Fit","arrow.down.right.and.arrow.up.left"),("Fill","arrow.up.left.and.arrow.down.right"),
                         ("Center","scope"),("1:1","1.square"),("Mirror H","arrow.left.and.right.righttriangle.left.righttriangle.right"),
                         ("Mirror V","arrow.up.and.down.righttriangle.up.righttriangle.down"),("Reset Rotation","rotate.left"),("Reset","arrow.counterclockwise")],id: \.0) { item in
                    ToolButton(title: item.0,symbol: item.1) { store.transformCommand(item.0) }
                }
            }
            DisclosureGroup("Physical size & tiles", isExpanded: $physicalExpanded) {
                VStack(spacing: 12) {
                    Picker("Paper", selection: canvasBinding(\.paper)) { ForEach(PaperPreset.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    if store.project.canvas.paper == .custom {
                        HStack { numeric("Paper width, mm", value: canvasBinding(\.customPaper.x)); numeric("Height, mm", value: canvasBinding(\.customPaper.y)) }
                    }
                    HStack { numeric("Image width, mm", value: canvasBinding(\.physicalWidthMM)); Button("Apply") { store.physicalSize() }.buttonStyle(.bordered) }
                    Button("Calibrate with a ruler") { showCalibration = true }.frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Button("Previous tile", systemImage: "chevron.left") { store.nextTile(-1) }
                        Spacer(); Text("\(store.project.canvas.tileIndex+1)").monospacedDigit()
                        Spacer(); Button("Next tile", systemImage: "chevron.right") { store.nextTile(1) }
                    }.labelStyle(.iconOnly).buttonStyle(.bordered)
                    Toggle("Tile overlap guides", isOn: canvasBinding(\.tileEnabled))
                    Text("Tiles use an 8 mm overlap. Mark the same grid intersections before moving the paper.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top,10)
            }
            Toggle("Magnetic snap", isOn: Binding(get:{store.settings.value.snap},set:{store.settings.value.snap=$0}))
        }
    }
    private func numeric(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading,spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
        }
    }
    private var imageTools: some View {
        VStack(spacing: 12) {
            HStack {
                ToolButton(title:"Add",symbol:"plus",action:addImage)
                ToolButton(title:"Crop",symbol:"crop.rotate",action:crop)
                ToolButton(title:"Compare",symbol:"rectangle.lefthalf.filled",selected:store.comparison) { store.comparison.toggle() }
                ToolButton(title:"Rename",symbol:"pencil") { rename = store.selected?.name ?? ""; renaming = true }
            }
            ValueSlider(title:"Opacity",value:layerBinding(\.opacity,fallback:1),range:0.05...1)
            ForEach(store.project.layers.reversed()) { layer in
                HStack {
                    Button { store.edit { $0.selectedLayerID = layer.id } } label: {
                        HStack {
                            if let image = store.images[layer.id] { Image(uiImage:image).resizable().scaledToFit().frame(width:40,height:40).background(.white.opacity(0.15),in:RoundedRectangle(cornerRadius:8)) }
                            Text(layer.name).font(.subheadline).lineLimit(1)
                            if layer.id == store.selected?.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(TraceDesign.accent) }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.buttonStyle(.plain)
                    Button { store.edit { p in if let i=p.layers.firstIndex(where:{$0.id==layer.id}) { p.layers[i].visible.toggle() } } } label: { Image(systemName:layer.visible ? "eye" : "eye.slash").frame(width:44,height:44) }
                    Button { store.edit { p in if let i=p.layers.firstIndex(where:{$0.id==layer.id}) { p.layers[i].locked.toggle() } } } label: { Image(systemName:layer.locked ? "lock.fill" : "lock.open").frame(width:44,height:44) }
                }.accessibilityElement(children:.contain)
            }
            if store.project.layers.count > 1 {
                Button("Remove selected reference", role:.destructive) {
                    store.edit { p in p.layers.removeAll { $0.id == p.selectedLayerID }; p.selectedLayerID = p.layers.last?.id }
                }
            }
        }
    }
    private var filterTools: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Adjustment",selection:$filterParameter) {
                    ForEach(["Contrast","Brightness","Threshold","Edge strength","Cleanup","Exposure","Saturation","Black point","Highlights","Shadows","Sharpness"],id:\.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
                Spacer()
                Button { store.prepare() } label: {
                    Image(systemName:"wand.and.stars").frame(width:44,height:44)
                }.buttonStyle(.bordered).accessibilityLabel("Prepare for Tracing")
            }
            adjustment
            HStack {
                Toggle("Gray",isOn:layerBinding(\.filters.grayscale,fallback:false)).toggleStyle(.button)
                Toggle("Invert",isOn:layerBinding(\.filters.invert,fallback:false)).toggleStyle(.button)
                Toggle("Threshold",isOn:layerBinding(\.filters.thresholdEnabled,fallback:false)).toggleStyle(.button)
            }.font(.caption)
            Picker("Line mode",selection:layerBinding(\.filters.edgeMode,fallback:.original)) {
                ForEach(EdgeMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).frame(maxWidth:.infinity,alignment:.leading)
            ScrollView(.horizontal) {
                HStack(spacing:8) { ForEach(TracePreset.allCases) { p in
                    Button(p.rawValue) { store.preset(p) }.buttonStyle(.bordered).font(.caption)
                }}
            }.scrollIndicators(.hidden)
            Text("Hold the image to see the original.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var adjustment: some View {
        let entry: (WritableKeyPath<FilterSettings,Double>,ClosedRange<Double>) = {
            switch filterParameter {
            case "Brightness": return (\.brightness,-0.5...0.5)
            case "Threshold": return (\.threshold,0.01...0.99)
            case "Edge strength": return (\.edgeStrength,0.1...8)
            case "Cleanup": return (\.cleanup,0...1)
            case "Exposure": return (\.exposure,-3...3)
            case "Saturation": return (\.saturation,0...2)
            case "Black point": return (\.blackPoint,0...0.6)
            case "Highlights": return (\.highlights,0...1)
            case "Shadows": return (\.shadows,-1...1)
            case "Sharpness": return (\.sharpness,0...2)
            default: return (\.contrast,0.5...3)
            }
        }()
        ValueSlider(title:filterParameter,value:filterBinding(entry.0),range:entry.1,editing:{ editing in
            if editing { store.beginEdit() } else { store.commitEdit() }
        })
    }
    private var gridTools: some View {
        VStack(spacing:12) {
            Picker("Density",selection:gridBinding(\.density)) { ForEach(GridDensity.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            Picker("Grid space",selection:gridBinding(\.space)) { ForEach(GridSpace.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            if store.project.canvas.grid.density == .custom { Stepper("\(store.project.canvas.grid.divisions) divisions",value:gridBinding(\.divisions),in:2...40) }
            ValueSlider(title:"Opacity",value:gridBinding(\.opacity),range:0.05...1)
            ValueSlider(title:"Thickness",value:gridBinding(\.thickness),range:0.25...3)
            ColorPicker("Grid color",selection:Binding(get:{store.project.canvas.grid.color.color},set:{color in store.edit{$0.canvas.grid.color=RGBA(color)}}))
            HStack {
                Toggle("Center",isOn:gridBinding(\.center)).toggleStyle(.button)
                Toggle("Thirds",isOn:gridBinding(\.thirds)).toggleStyle(.button)
                Toggle("Rulers",isOn:Binding(get:{store.project.canvas.grid.rulers},set:{value in
                    store.edit{$0.canvas.grid.rulers=value}
                    if value, store.project.canvas.calibratedPointsPerMM == nil, store.settings.value.calibratedPointsPerMM == nil {showCalibration=true}
                })).toggleStyle(.button)
            }.font(.caption)
        }
    }
    private var backgroundTools: some View {
        VStack(spacing:16) {
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4)) {
                ForEach(RGBA.presets,id:\.0) { name,color in
                    Button { store.edit { $0.canvas.background = color } } label: {
                        VStack(spacing:4) { Circle().fill(color.color).frame(width:32,height:32).overlay(Circle().stroke(.gray.opacity(0.4),lineWidth:1)); Text(name).font(.caption2) }.frame(minWidth:48,minHeight:52)
                    }.buttonStyle(.plain).accessibilityLabel(name + " background")
                }
            }
            ColorPicker("Custom background",selection:Binding(get:{store.project.canvas.background.color},set:{color in store.edit{$0.canvas.background=RGBA(color)}}),supportsOpacity:false)
            BrightnessControl(display:store.display)
        }
    }
}

struct BrightnessControl: View {
    @ObservedObject var display: DisplaySession
    var body: some View {
        VStack(spacing:8) {
            ValueSlider(title:"Screen brightness",value:Binding(get:{display.brightness},set:{display.setBrightness($0)}),range:0.05...1)
            HStack { ForEach([("Low",0.15),("50%",0.5),("Max",1.0)],id:\.0) { name,value in
                Button(name) { display.setBrightness(value) }.buttonStyle(.bordered).frame(maxWidth:.infinity)
            }}
        }
    }
}

struct CalibrationView: View {
    @ObservedObject var store: TraceStore
    @Environment(\.dismiss) private var dismiss
    @State private var points: Double = 190
    var body: some View {
        ScrollView { VStack(spacing:24) {
            Text("Calibrate your screen").font(.title2.weight(.semibold))
            Text("Place a ruler against the line. Adjust it until the distance between the marks is exactly 30 mm.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing:0) { Rectangle().frame(width:1,height:24); Rectangle().frame(width:points,height:1); Rectangle().frame(width:1,height:24) }.frame(height:60)
            Slider(value:$points,in:100...280).tint(TraceDesign.accent)
            Text("30 mm").monospacedDigit()
            PrimaryButton(title:"Save calibration",symbol:"checkmark") {
                let ppm = points / 30
                store.settings.value.calibratedPointsPerMM = ppm
                store.edit { $0.canvas.calibratedPointsPerMM = ppm }; dismiss()
            }
            Text("Recalibrate after changing Display Zoom. No guessed device dimensions are used.").font(.caption).foregroundStyle(.secondary)
        }.padding(28) }.onAppear { points = 30 * (store.project.canvas.calibratedPointsPerMM ?? store.settings.value.calibratedPointsPerMM ?? 6.33) }
        .presentationDetents([.large])
    }
}
