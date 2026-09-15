import SwiftUI

struct HomeView:View {
    @ObservedObject var settings:AppSettings
    let storage:ProjectStorage
    @State private var projects:[TraceProject]=[]
    @State private var active:TraceStore?
    @State private var importing=false
    @State private var settingsOpen=false
    @State private var pendingMode:TraceMode = .lightbox
    @State private var error:String?
    @State private var deleteProject:TraceProject?
    @State private var busy=false
    @State private var fixtureLoaded=false
    var body:some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment:.leading,spacing:26) {
                    HStack {
                        HStack(spacing:9){Image(systemName:"square.stack.3d.up").foregroundStyle(TraceDesign.accent);Text("TRACEGLASS").tracking(3).font(.system(size:13,weight:.semibold,design:.rounded))}
                        Spacer()
                        Button{settingsOpen=true}label:{Image(systemName:"gearshape").frame(width:46,height:46)}.traceGlass(radius:23).accessibilityLabel("Settings")
                    }
                    HStack(alignment:.center,spacing:0) {
                        VStack(alignment:.leading,spacing:14) {
                            Text("A little light.\nYour next line.").font(.system(size:36,weight:.semibold,design:.rounded)).tracking(-1.2).minimumScaleFactor(0.75)
                            Text("Image. Position. Lock. Trace.").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        if proxy.size.width>600{ReferenceArtwork().frame(width:220,height:230)}
                    }
                    if proxy.size.width<=600 {ReferenceArtwork().frame(height:195).frame(maxWidth:.infinity)}
                    VStack(spacing:12) {
                        PrimaryButton(title:"Choose Image",symbol:"plus") {pendingMode = .lightbox;importing=true}
                            .accessibilityIdentifier("chooseImage")
                        HStack(spacing:12) {
                            modeCard("Lightbox",subtitle:"Trace through paper",symbol:"light.panel",mode:.lightbox)
                            modeCard("AR Trace",subtitle:"Draw with your camera",symbol:"arkit",mode:.paper)
                        }
                        Button("Try a sample reference"){Task{await sample()}}.font(.caption).foregroundStyle(.secondary).padding(.top,2)
                    }
                    if !projects.isEmpty {
                        HStack {Text("Recent projects").font(.title3.weight(.semibold));Spacer();Text("\(projects.count)").font(.caption).foregroundStyle(.secondary)}
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:145))],spacing:14) {
                            ForEach(projects) { project in
                                Button {active=TraceStore(project:project,storage:storage,settings:settings)}label:{RecentProjectCard(project:project,storage:storage)}
                                    .buttonStyle(.plain).accessibilityLabel(project.name).accessibilityIdentifier("recentProject").contextMenu{Button("Delete project",role:.destructive){deleteProject=project}}
                            }
                        }
                    } else {
                        Text("Your references will be saved here automatically.").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity).multilineTextAlignment(.center)
                    }
                    if !settings.value.tutorialSeen {
                        VStack(alignment:.leading,spacing:8) {
                            Label("Two ways to trace",systemImage:"sparkle").font(.subheadline.weight(.medium))
                            Text("Lightbox goes under your paper. AR places a virtual reference in the camera view — your phone does not project an image onto the paper.").font(.caption).foregroundStyle(.secondary)
                            Button("Got it"){settings.value.tutorialSeen=true}.font(.caption.weight(.semibold)).padding(.top,4)
                        }.padding(18).traceGlass(radius:24)
                    }
                }.padding(24).frame(maxWidth:850).frame(maxWidth:.infinity)
            }.scrollIndicators(.hidden)
            .background {
                ZStack {
                    Color(uiColor:.systemBackground)
                    RadialGradient(colors:[TraceDesign.accent.opacity(0.07),.clear],center:.topTrailing,startRadius:0,endRadius:550)
                }.ignoresSafeArea()
            }
            .overlay{if busy{ProgressView().padding(24).traceGlass()}}
        }
        .sheet(isPresented:$importing){ImportSheet{data,name in Task{await create(data,name:name)}}}
        .sheet(isPresented:$settingsOpen){SettingsView(settings:settings)}
        .fullScreenCover(item:$active,onDismiss:{Task{await refresh()}}){session in EditorView(store:session,onClose:{active=nil})}
        .alert("TraceGlass",isPresented:Binding(get:{error != nil},set:{if !$0{error=nil}})){Button("OK"){error=nil}}message:{Text(error ?? "")}
        .confirmationDialog("Delete this project and its references?",isPresented:Binding(get:{deleteProject != nil},set:{if !$0{deleteProject=nil}}),titleVisibility:.visible){
            Button("Delete project",role:.destructive){if let p=deleteProject{Task{do{try await storage.remove(p);await refresh()}catch{self.error=TraceError.storage.localizedDescription}}};deleteProject=nil}
        }
        .task {
            await refresh()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitesting"), !fixtureLoaded {fixtureLoaded=true;settings.value.tutorialSeen=true;settings.value.importTipSeen=true;await sample()}
            #endif
        }
    }
    private func modeCard(_ title:String,subtitle:String,symbol:String,mode:TraceMode)->some View {
        Button{pendingMode=mode;importing=true}label:{
            VStack(alignment:.leading,spacing:8){Image(systemName:symbol).font(.system(size:24,weight:.light)).foregroundStyle(TraceDesign.accent);Text(title).font(.headline);Text(subtitle).font(.caption2).foregroundStyle(.secondary)}
                .frame(maxWidth:.infinity,alignment:.leading).padding(18).traceGlass(radius:25)
        }.buttonStyle(.plain)
    }
    private func refresh()async{do{projects=try await storage.recent()}catch{self.error=TraceError.storage.localizedDescription}}
    private func create(_ data:Data,name:String)async{
        busy=true;defer{busy=false}
        var project=TraceProject();project.mode=pendingMode;project.canvas.background=settings.value.defaultBackground
        project.canvas.calibratedPointsPerMM=settings.value.calibratedPointsPerMM
        let store=TraceStore(project:project,storage:storage,settings:settings)
        await store.addImage(data,name:name)
        guard !store.project.layers.isEmpty else{error=store.message;return}
        // Let the import sheet dismiss before presenting the editor.
        try? await Task.sleep(for:.milliseconds(250));active=store
    }
    private func sample()async{pendingMode = .lightbox;if let data=TraceSample.image().pngData(){await create(data,name:"Botanical study")}}
}

private struct RecentProjectCard:View {
    let project:TraceProject
    let storage:ProjectStorage
    @State private var thumbnail:UIImage?
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            ZStack {
                project.canvas.background.color
                if let thumbnail{Image(uiImage:thumbnail).resizable().scaledToFit().padding(8)}
            }.frame(height:150).clipShape(RoundedRectangle(cornerRadius:20))
            Text(project.name).font(.subheadline.weight(.medium)).lineLimit(1)
            Text(project.modifiedAt,style:.date).font(.caption2).foregroundStyle(.secondary)
        }.padding(10).traceGlass(radius:26)
        .task{if let data=await storage.thumbnail(id:project.id){thumbnail=UIImage(data:data)}}
    }
}

private struct ReferenceArtwork:View {
    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:25).fill(TraceDesign.accent.opacity(0.10)).frame(width:155,height:165).rotationEffect(.degrees(-13)).offset(x:-18,y:4)
            RoundedRectangle(cornerRadius:25).fill(.thinMaterial).frame(width:155,height:165).overlay(RoundedRectangle(cornerRadius:25).stroke(.primary.opacity(0.12),lineWidth:0.7).frame(width:155,height:165)).rotationEffect(.degrees(11)).offset(x:15,y:-2)
            Image(uiImage:TraceSample.image()).resizable().scaledToFit().frame(width:104,height:145).blendMode(.screen).rotationEffect(.degrees(11)).offset(x:15,y:-2)
            Image(systemName:"lock.fill").font(.system(size:16,weight:.medium)).foregroundStyle(TraceDesign.accent).frame(width:44,height:44).traceGlass(radius:22).offset(x:86,y:65)
        }.accessibilityHidden(true)
    }
}

enum TraceSample {
    static func image()->UIImage {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:800,height:1100),format:format).image{ctx in
            UIColor.white.setFill();ctx.fill(CGRect(x:0,y:0,width:800,height:1100))
            UIColor.black.setStroke()
            let stem=UIBezierPath();stem.move(to:CGPoint(x:360,y:1030));stem.addCurve(to:CGPoint(x:430,y:90),controlPoint1:CGPoint(x:230,y:720),controlPoint2:CGPoint(x:560,y:400));stem.lineWidth=5;stem.stroke()
            for i in 0..<9 {
                let y=Double(180+i*86),x=430+sin(Double(i)*0.58)*45
                let direction:Double=i%2==0 ? -1:1
                let width=110+Double(i%3)*22
                let leaf=UIBezierPath();leaf.move(to:CGPoint(x:x,y:y+65))
                leaf.addCurve(to:CGPoint(x:x+direction*width,y:y-55),controlPoint1:CGPoint(x:x+direction*110,y:y+85),controlPoint2:CGPoint(x:x+direction*(width+60),y:y-30))
                leaf.addCurve(to:CGPoint(x:x,y:y+65),controlPoint1:CGPoint(x:x+direction*45,y:y-65),controlPoint2:CGPoint(x:x+direction*25,y:y+30));leaf.lineWidth=3;leaf.stroke()
                let vein=UIBezierPath();vein.move(to:CGPoint(x:x,y:y+65));vein.addQuadCurve(to:CGPoint(x:x+direction*width,y:y-55),controlPoint:CGPoint(x:x+direction*70,y:y+5));vein.lineWidth=1.3;vein.stroke()
            }
        }
    }
}
