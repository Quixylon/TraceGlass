import SwiftUI

struct EditorView:View {
    @ObservedObject var store:TraceStore
    var onClose:(()->Void)? = nil
    @StateObject private var camera=PaperCamera()
    @StateObject private var world=WorldTrackingService()
    @StateObject private var thermal=ThermalManager()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tool:TraceTool?
    @State private var importing=false
    @State private var cropping=false
    @State private var settingsOpen=false
    @State private var manualPaper=false
    @State private var manualCorners:[Point2]=[]
    @State private var transitionID:UUID?
    @State private var transitionImage:UIImage?
    @State private var returning=false
    @State private var savedLightboxQuad:[CGPoint]=[]
    @State private var savedWorldQuad:[CGPoint]=[]
    @State private var lockWave=false
    @State private var ready=false
    @State private var showTip=false
    @Namespace private var toolbarSpace
    var body:some View {
        GeometryReader { proxy in
            let landscape=proxy.size.width>proxy.size.height
            ZStack {
                canvas.ignoresSafeArea()
                if let transitionID,let image=transitionImage {
                    if reduceMotion {
                        Image(uiImage:image).resizable().scaledToFit().padding(48)
                            .rotation3DEffect(.degrees(returning ? -4:4),axis:(x:1,y:0,z:0))
                            .transition(.scale(scale:0.97).combined(with:.opacity))
                            .task(id:transitionID){try? await Task.sleep(for:.milliseconds(300));finishTransition()}
                            .allowsHitTesting(false)
                    } else {
                        ParticleTransition(image:image,geometry:transitionGeometry,quality:thermal.reduced ? .performance:store.settings.value.animationQuality,completion:finishTransition)
                            .id(transitionID).ignoresSafeArea().allowsHitTesting(false)
                    }
                }
                if lockWave {
                    RoundedRectangle(cornerRadius:50).stroke(TraceDesign.accent.opacity(0.55),lineWidth:1.5)
                        .padding(4).allowsHitTesting(false).transition(.opacity)
                }
                if store.locked {
                    VStack { HStack {
                        if thermal.warm { Text("Getting warm · lower brightness when ready").font(.caption2).padding(8).traceGlass(radius:16).allowsHitTesting(false) }
                        if store.project.mode != .lightbox {
                            Button {store.temporaryHidden.toggle()}label:{Image(systemName:store.temporaryHidden ? "eye.slash":"eye").frame(width:52,height:52)}
                                .traceGlass(radius:26).accessibilityLabel("Show or hide reference")
                        }
                        Spacer()
                        HoldToUnlock(duration:store.settings.value.unlockDuration){withAnimation(reduceMotion ? nil:TraceDesign.motion){store.unlock()}}
                    };Spacer() }.padding(18)
                } else {
                    VStack(spacing:12) {
                        topBar
                        if let label=store.gestureLabel {Text(label).font(.system(.caption,design:.monospaced)).padding(9).traceGlass(radius:15).allowsHitTesting(false)}
                        if showTip {Text("Pinch to scale · Drag to move · Lock to trace").font(.caption).padding(12).traceGlass(radius:20).onTapGesture{showTip=false}}
                        if store.project.mode != .lightbox {trackingStatus}
                        Spacer(minLength:0)
                        if thermal.warm {Text("iPhone is getting warm. Lowering brightness may help.").font(.caption).padding(12).traceGlass(radius:18)}
                        if landscape {
                            HStack {Spacer();toolbar(inspectorHeight:max(80,proxy.size.height-210)).frame(width:330)}
                        } else {toolbar(inspectorHeight:210)}
                    }.padding(.horizontal,14).padding(.vertical,8)
                }
            }.frame(width:proxy.size.width,height:proxy.size.height)
        }
        .statusBarHidden(store.locked)
        .persistentSystemOverlays(store.locked ? .hidden:.automatic)
        .preferredColorScheme(store.settings.value.followSystemTheme ? nil:.dark)
        .sheet(isPresented:$importing){ImportSheet{data,name in Task{await store.addImage(data,name:name)}}}
        .sheet(isPresented:$cropping){CropPerspectiveView(store:store)}
        .sheet(isPresented:$settingsOpen){SettingsView(settings:store.settings)}
        .alert("TraceGlass",isPresented:Binding(get:{store.message != nil || camera.message != nil || world.message != nil},set:{if !$0{store.message=nil;camera.message=nil;world.message=nil}})){
            Button("OK"){store.message=nil;camera.message=nil;world.message=nil}
            if camera.message==TraceError.cameraDenied.localizedDescription || world.message==TraceError.cameraDenied.localizedDescription {
                Button("Open Settings"){if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}
            }
        }message:{Text(store.message ?? camera.message ?? world.message ?? "")}
        .task {
            await store.load();ready=true;world.store=store;startMode()
            if !store.settings.value.importTipSeen{showTip=true;store.settings.value.importTipSeen=true}
        }
        .onChange(of:store.project.mode){_,_ in guard ready else{return};startMode()}
        .onChange(of:scenePhase){_,phase in
            if phase == .active {store.display.resume();if ready{startMode()}}
            else {store.temporaryHidden=false;store.originalVisible=false;camera.stop();world.stop();store.display.suspend();Task{await store.flush()}}
        }
        .onChange(of:thermal.state){_,_ in camera.setQuality(store.settings.value.arQuality,warm:thermal.warm)}
        .onChange(of:camera.stability){old,new in if old != .excellent && new == .excellent{Feedback.tick(store.settings.value.haptics)}}
        .onDisappear{camera.stop();world.stop();store.display.end();AppDelegate.freezeOrientation(false)}
    }
    @ViewBuilder private var canvas:some View {
        switch store.project.mode {
        case .lightbox: TraceCanvas(store:store)
        case .paper: PaperARView(store:store,camera:camera,manual:manualPaper,onManualChange:{manualCorners=$0})
        case .world: WorldARView(store:store,service:world)
        }
    }
    private var topBar:some View {
        HStack(spacing:10) {
            Button {
                Task{await store.close();if let onClose{onClose()}else{dismiss()}}
            }label:{Image(systemName:"chevron.left").frame(width:46,height:46)}.traceGlass(radius:23).accessibilityLabel("Recent projects")
            Spacer()
            HStack(spacing:2) {
                Button {store.undo()}label:{Image(systemName:"arrow.uturn.backward").frame(width:44,height:44)}.disabled(store.document.undoStack.isEmpty).accessibilityLabel("Undo")
                Button {store.redo()}label:{Image(systemName:"arrow.uturn.forward").frame(width:44,height:44)}.disabled(store.document.redoStack.isEmpty).accessibilityLabel("Redo")
                Menu {
                    Button("Fit",systemImage:"arrow.down.right.and.arrow.up.left"){store.transformCommand("Fit")}
                    Button("Center",systemImage:"scope"){store.transformCommand("Center")}
                    Button("Reset",systemImage:"arrow.counterclockwise"){store.transformCommand("Reset")}
                    Button("Invert",systemImage:"circle.lefthalf.filled"){store.updateLayer{$0.filters.invert.toggle()}}
                    Button("Grid",systemImage:"grid"){store.edit{$0.canvas.grid.density = $0.canvas.grid.density == .off ? .medium:.off}}
                    Button("Max brightness",systemImage:"sun.max"){store.display.setBrightness(1)}
                    Button(store.project.mode == .lightbox ? "AR Trace":"Lightbox",systemImage:"arkit"){changeMode(store.project.mode == .lightbox ? .paper:.lightbox)}
                    Button("Lock",systemImage:"lock.fill"){lock()}
                    Divider();Button("Settings",systemImage:"gearshape"){settingsOpen=true}
                }label:{Image(systemName:"ellipsis").frame(width:44,height:44)}.accessibilityLabel("Quick actions")
            }.traceGlass(radius:24)
        }
    }
    private func toolbar(inspectorHeight:CGFloat)->some View {
        GlassGroup {
            VStack(spacing:8) {
                if store.project.mode != .lightbox {
                    ScrollView {arControls.padding(.horizontal,16).padding(.top,14)}
                        .frame(height:store.project.ar.overhead ? min(130,inspectorHeight):inspectorHeight+20).scrollIndicators(.hidden)
                } else if let tool {
                    HStack {Text(tool.rawValue).font(.headline);Spacer();Button("Close tool",systemImage:"chevron.down"){withAnimation(reduceMotion ? nil:TraceDesign.motion){self.tool=nil}}.labelStyle(.iconOnly).frame(width:44,height:32)}.padding(.horizontal,20).padding(.top,10)
                    ToolInspector(store:store,tool:tool,addImage:{importing=true},crop:{cropping=true})
                        .frame(height:inspectorHeight).id(tool).transition(.opacity.combined(with:.offset(y:8)))
                }
                HStack(spacing:0) {
                    if store.project.mode == .lightbox {
                        ScrollView(.horizontal) {
                            HStack(spacing:0){ForEach(TraceTool.allCases){t in ToolButton(title:t.rawValue,symbol:t.symbol,selected:tool==t){withAnimation(reduceMotion ? nil:TraceDesign.motion){tool = tool==t ? nil:t}}}}
                        }.scrollIndicators(.hidden)
                    }
                    ToolButton(title:store.project.mode == .lightbox ? "AR":"Lightbox",symbol:store.project.mode == .lightbox ? "arkit":"light.panel"){
                        changeMode(store.project.mode == .lightbox ? .paper:.lightbox)
                    }
                    Button(action:lock){Label("LOCK",systemImage:"lock.fill").font(.system(size:12,weight:.bold)).padding(.horizontal,16).frame(height:48).background(TraceDesign.accent,in:Capsule()).foregroundStyle(TraceDesign.buttonText)}
                        .accessibilityIdentifier("lockReference").accessibilityLabel("Lock reference")
                }.padding(8)
            }
            .modifier(ToolbarGlass(namespace:toolbarSpace))
            .animation(reduceMotion ? nil:TraceDesign.motion,value:tool)
        }
    }
    private var trackingStatus:some View {
        HStack(spacing:8) {
            let quality=store.project.mode == .paper ? camera.stability:world.stability
            Circle().fill(quality == .excellent ? TraceDesign.accent:Color.orange).frame(width:6,height:6)
            Text("Stability · \(quality.rawValue)").font(.caption.weight(.medium))
            if store.project.mode == .paper && camera.finding {Text("Finding paper…").font(.caption).foregroundStyle(.secondary)}
            if store.project.mode == .world && !world.placed {Text("Tap a surface").font(.caption).foregroundStyle(.secondary)}
        }.padding(.horizontal,14).padding(.vertical,10).traceGlass(radius:20).allowsHitTesting(false)
    }
    private var arControls:some View {
        VStack(spacing:12) {
            if !store.project.ar.overhead {
                Picker("AR mode",selection:Binding(get:{store.project.mode},set:{changeMode($0)})){
                    Text("Paper Track").tag(TraceMode.paper);Text("World Anchor").tag(TraceMode.world)
                }.pickerStyle(.segmented)
            }
            ValueSlider(title:"Reference opacity",value:Binding(get:{store.project.ar.opacity},set:{v in store.edit{$0.ar.opacity=v}}),range:0.05...1)
            HStack(spacing:10) {
                Button {store.edit{$0.ar.referenceVisible.toggle()}}label:{Label("Reference",systemImage:store.project.ar.referenceVisible ? "eye":"eye.slash")}.buttonStyle(.bordered)
                Toggle("Ghost",isOn:arBinding(\.ghost)).toggleStyle(.button)
                Menu {
                    Toggle("Overhead",isOn:arBinding(\.overhead))
                    if store.project.mode == .paper {
                        Toggle("Projector effect",isOn:arBinding(\.projector))
                        Button(manualPaper ? "Track these corners":"Set four corners"){
                            if manualPaper{camera.seed(manualCorners.isEmpty ? [Point2(x:0.2,y:0.25),Point2(x:0.8,y:0.25),Point2(x:0.8,y:0.75),Point2(x:0.2,y:0.75)]:manualCorners)}
                            manualPaper.toggle()
                        }
                        Button("Find paper again"){camera.reset()}
                    } else {
                        Toggle("Person occlusion",isOn:arBinding(\.occlusion)).disabled(!world.occlusionSupported)
                        Button("Place again"){world.reset()}
                    }
                    Button("Reset AR placement"){store.edit{$0.ar.placement=ImageTransform()}}
                }label:{Image(systemName:"slider.horizontal.3").frame(width:44,height:44)}
            }.font(.caption)
            if store.project.ar.projector && store.project.mode == .paper {
                ValueSlider(title:"Projector intensity",value:Binding(get:{store.project.ar.intensity},set:{v in store.edit{$0.ar.intensity=v}}),range:0...1)
            }
            if store.project.mode == .world && !store.project.ar.overhead {
                ValueSlider(title:"Reference width, m",value:Binding(get:{store.project.ar.worldWidth},set:{v in store.edit{$0.ar.worldWidth=v}}),range:0.05...2)
            }
        }
    }
    private func arBinding(_ path:WritableKeyPath<ARSettings,Bool>)->Binding<Bool>{Binding(get:{store.project.ar[keyPath:path]},set:{v in store.edit{$0.ar[keyPath:path]=v}})}
    private func lock(){
        manualPaper=false;transitionID=nil;transitionImage=nil;store.transitionHidesReference=false
        withAnimation(reduceMotion ? nil:TraceDesign.motion){tool=nil;store.lock();lockWave=true}
        Task{try? await Task.sleep(for:.milliseconds(280));withAnimation(.easeOut(duration:0.15)){lockWave=false}}
    }
    private func startMode(){
        switch store.project.mode {
        case .lightbox:camera.stop();world.stop()
        case .paper:world.stop();camera.setQuality(store.settings.value.arQuality,warm:thermal.warm);camera.start()
        case .world:camera.stop();world.start()
        }
    }
    private func changeMode(_ mode:TraceMode){
        guard !store.locked,mode != store.project.mode else{return}
        tool=nil;manualPaper=false;store.originalVisible=false;store.temporaryHidden=false
        let from=store.project.mode
        if from == .lightbox || mode == .lightbox {
            returning=mode == .lightbox
            savedWorldQuad = from == .world ? world.projectedReferenceCorners : []
            if !returning {
                savedLightboxQuad=TransitionGeometry.lightbox(store:store)
                if let t=store.selected?.transform {
                    let fit=GeometryMath.fitScale(image:store.baseImageSize,canvas:store.viewport)
                    store.edit{$0.ar.placement=ImageTransform(offset:Point2(x:t.offset.x/store.viewport.width*1000,y:t.offset.y/store.viewport.height*1414),scale:t.scale/max(0.01,fit),rotation:t.rotation,mirrorX:t.mirrorX,mirrorY:t.mirrorY)}
                }
            }
            transitionImage=store.reference;transitionID=UUID();store.transitionHidesReference=true
        }
        store.edit{$0.mode=mode}
    }
    private var transitionGeometry:TransitionGeometry {
        let lightbox=savedLightboxQuad.count==4 ? savedLightboxQuad:TransitionGeometry.lightbox(store:store)
        let paperQuad=TransitionGeometry.paper(camera.corners,frame:camera.frameSize,viewport:store.viewport)
        let paper=savedWorldQuad.count == 4 ? savedWorldQuad : TransitionGeometry.referenceOnPaper(paperQuad, store:store)
        return returning ? TransitionGeometry(from:paper,to:lightbox):TransitionGeometry(from:lightbox,to:paper)
    }
    private func finishTransition(){transitionID=nil;transitionImage=nil;store.transitionHidesReference=false;if camera.stability == .excellent{Feedback.tick(store.settings.value.haptics)}}
}

private struct ToolbarGlass:ViewModifier {
    var namespace:Namespace.ID
    @ViewBuilder func body(content:Content)->some View {
        if #available(iOS 26.0,*){content.glassEffect(.regular.interactive(),in:.rect(cornerRadius:30)).glassEffectID("toolbar",in:namespace)}
        else{content.traceGlass(radius:30).matchedGeometryEffect(id:"toolbar",in:namespace)}
    }
}
