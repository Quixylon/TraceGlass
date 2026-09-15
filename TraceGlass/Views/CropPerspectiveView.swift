import SwiftUI

struct CropPerspectiveView:View {
    @ObservedObject var store:TraceStore
    @Environment(\.dismiss) private var dismiss
    @State private var corners=[Point2(x:0,y:0),Point2(x:1,y:0),Point2(x:1,y:1),Point2(x:0,y:1)]
    @State private var crop=CGRect(x:0,y:0,width:1,height:1)
    @State private var perspective=true
    @State private var preview:UIImage?
    @State private var ratio="Free"
    @State private var customRatio:Double=1
    @State private var error:String?
    var body:some View {
        VStack(spacing:16) {
            HStack {
                Button("Cancel"){dismiss()};Spacer();Text("Crop & straighten").font(.headline);Spacer()
                Button("Apply"){apply()}.fontWeight(.semibold)
            }.padding(.horizontal,20)
            Picker("Tool",selection:$perspective){Text("Perspective").tag(true);Text("Crop").tag(false)}.pickerStyle(.segmented).padding(.horizontal,20)
            GeometryReader { proxy in
                let image=perspective ? store.original : preview ?? store.original
                let size=image?.size ?? CGSize(width:1,height:1)
                let scale=min((proxy.size.width-40)/size.width,(proxy.size.height-40)/size.height)
                let rect=CGRect(x:(proxy.size.width-size.width*scale)/2,y:(proxy.size.height-size.height*scale)/2,width:size.width*scale,height:size.height*scale)
                ZStack(alignment:.topLeading) {
                    if let image {Image(uiImage:image).resizable().frame(width:rect.width,height:rect.height).position(x:rect.midX,y:rect.midY)}
                    let points=perspective ? corners : cropPoints
                    Path { path in for (i,p) in points.enumerated(){let q=CGPoint(x:rect.minX+p.x*rect.width,y:rect.minY+p.y*rect.height);if i==0{path.move(to:q)}else{path.addLine(to:q)}};path.closeSubpath() }.stroke(TraceDesign.accent,lineWidth:1.5)
                    ForEach(0..<4,id:\.self){index in
                        Circle().fill(TraceDesign.accent).frame(width:18,height:18).padding(15).contentShape(Circle())
                            .position(x:rect.minX+points[index].x*rect.width,y:rect.minY+points[index].y*rect.height)
                            .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("crop")).onChanged { value in
                                let p=Point2(x:min(1,max(0,(value.location.x-rect.minX)/rect.width)),y:min(1,max(0,(value.location.y-rect.minY)/rect.height)))
                                if perspective {corners[index]=p}else{resizeCrop(index,p)}
                            })
                            .accessibilityLabel(["Top left","Top right","Bottom right","Bottom left"][index]+" corner")
                    }
                }.coordinateSpace(name:"crop")
            }
            if perspective {
                Button("Detect paper automatically",systemImage:"viewfinder"){
                    guard let cg=store.original?.cgImage else{return}
                    Task {if let points=await store.processor.detectRectangle(cg){corners=points}else{error="No clear rectangle found. Place the four corners manually."}}
                }.buttonStyle(.bordered)
            } else {
                Picker("Aspect ratio",selection:$ratio){ForEach(["Free","Original","1:1","A4","A5","Custom"],id:\.self){Text($0).tag($0)}}.pickerStyle(.segmented).padding(.horizontal,16)
                if ratio=="Custom" {ValueSlider(title:"Width / height",value:$customRatio,range:0.2...3).padding(.horizontal,24)}
            }
            Text(perspective ? "Place the four corners on the edges of your drawing." : "Drag a corner to crop. The source image is always preserved.").font(.caption).foregroundStyle(.secondary).padding(.bottom,20)
        }.padding(.top,20).background(TraceDesign.ink)
        .onAppear {
            if let g=store.selected?.geometry {corners=g.corners ?? corners;if let c=g.crop,c.count==4{crop=CGRect(x:c[0],y:c[1],width:c[2],height:c[3])}}
        }
        .onChange(of:perspective){_,value in if !value {updatePreview()}}
        .onChange(of:ratio){_,_ in applyRatio()}.onChange(of:customRatio){_,_ in applyRatio()}
        .alert("Adjust the selection",isPresented:Binding(get:{error != nil},set:{if !$0{error=nil}})){Button("OK"){error=nil}}message:{Text(error ?? "")}
    }
    private var cropPoints:[Point2]{[Point2(x:crop.minX,y:crop.minY),Point2(x:crop.maxX,y:crop.minY),Point2(x:crop.maxX,y:crop.maxY),Point2(x:crop.minX,y:crop.maxY)]}
    private func resizeCrop(_ index:Int,_ p:Point2){
        var x0=crop.minX,y0=crop.minY,x1=crop.maxX,y1=crop.maxY
        if index==0 || index==3{x0=min(p.x,x1-0.03)}else{x1=max(p.x,x0+0.03)}
        if index<2{y0=min(p.y,y1-0.03)}else{y1=max(p.y,y0+0.03)}
        crop=CGRect(x:x0,y:y0,width:x1-x0,height:y1-y0);if ratio != "Free"{applyRatio()}
    }
    private func applyRatio(){
        guard ratio != "Free" else{return}
        let size=(preview ?? store.original)?.size ?? CGSize(width:1,height:1)
        let target:Double=ratio=="Original" ? size.width/size.height : ratio=="1:1" ? 1 : ratio=="Custom" ? customRatio : 1/sqrt(2)
        let normalized=target*size.height/size.width
        var w=crop.width,h=w/normalized
        if h>1{h=1;w=h*normalized}
        crop=CGRect(x:max(0,min(1-w,crop.midX-w/2)),y:max(0,min(1-h,crop.midY-h/2)),width:w,height:h)
    }
    private func validQuad()->Bool{
        let crosses=(0..<4).map {i -> Double in let a=corners[i],b=corners[(i+1)%4],c=corners[(i+2)%4];return (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x)}
        return crosses.allSatisfy{$0>0.0001}
    }
    private func updatePreview(){
        guard validQuad(),let cg=store.original?.cgImage else{return}
        Task {
            do {
                let result = try await store.processor.render(cg, settings: FilterSettings(), geometry: ImageGeometry(corners: corners))
                preview = UIImage(cgImage: result)
            } catch { self.error = TraceError.rendering.localizedDescription }
        }
    }
    private func apply(){
        guard validQuad() else{error="The corners must go around the drawing without crossing.";return}
        store.updateLayer{$0.geometry=ImageGeometry(corners:corners,crop:[crop.minX,crop.minY,crop.width,crop.height])};dismiss()
    }
}
