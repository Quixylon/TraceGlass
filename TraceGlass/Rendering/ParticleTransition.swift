import SwiftUI
import MetalKit

struct TransitionGeometry {
    var from: [CGPoint]
    var to: [CGPoint]
    @MainActor static func lightbox(store: TraceStore) -> [CGPoint] {
        guard let t=store.selected?.transform else{return []}
        let size=store.baseImageSize
        let transform=CGAffineTransform(translationX:store.viewport.width/2+t.offset.x,y:store.viewport.height/2+t.offset.y)
            .rotated(by:t.rotation).scaledBy(x:t.scale*(t.mirrorX ? -1:1),y:t.scale*(t.mirrorY ? -1:1))
        return [CGPoint(x:-size.width/2,y:-size.height/2),CGPoint(x:size.width/2,y:-size.height/2),
                CGPoint(x:size.width/2,y:size.height/2),CGPoint(x:-size.width/2,y:size.height/2)].map{$0.applying(transform)}
    }
    static func paper(_ corners:[Point2],frame:CGSize,viewport:CGSize) -> [CGPoint] {
        guard corners.count==4 else {
            return [CGPoint(x:viewport.width*0.16,y:viewport.height*0.25),CGPoint(x:viewport.width*0.84,y:viewport.height*0.25),
                    CGPoint(x:viewport.width*0.84,y:viewport.height*0.75),CGPoint(x:viewport.width*0.16,y:viewport.height*0.75)]
        }
        let s=max(viewport.width/frame.width,viewport.height/frame.height)
        return corners.map{CGPoint(x:$0.x*frame.width*s+(viewport.width-frame.width*s)/2,y:$0.y*frame.height*s+(viewport.height-frame.height*s)/2)}
    }
    @MainActor static func referenceOnPaper(_ quad: [CGPoint], store: TraceStore) -> [CGPoint] {
        guard quad.count == 4, let homography = GeometryMath.homography(to: quad), let image = store.reference else { return quad }
        let paper = store.project.canvas.paper == .custom ? store.project.canvas.customPaper : store.project.canvas.paper.size
        let ph = 1000 * paper.y / max(1, paper.x)
        let fit = min(1000 / image.size.width, ph / image.size.height)
        let width = image.size.width * fit, height = image.size.height * fit
        let p = store.project.ar.placement
        let t = CGAffineTransform(translationX: 500 + p.offset.x, y: ph / 2 + p.offset.y)
            .rotated(by: p.rotation).scaledBy(x: p.scale * (p.mirrorX ? -1 : 1), y: p.scale * (p.mirrorY ? -1 : 1))
        return [CGPoint(x:-width/2,y:-height/2),CGPoint(x:width/2,y:-height/2),CGPoint(x:width/2,y:height/2),CGPoint(x:-width/2,y:height/2)].map {
            let point = $0.applying(t), x = point.x / 1000, y = point.y / ph
            let divisor = homography[6] * x + homography[7] * y + 1
            return CGPoint(x:(homography[0]*x+homography[1]*y+homography[2])/divisor,
                           y:(homography[3]*x+homography[4]*y+homography[5])/divisor)
        }
    }
}
struct ParticleTransition: UIViewRepresentable {
    let image: UIImage
    var geometry: TransitionGeometry
    var quality: Quality
    var completion: () -> Void
    func makeCoordinator()->ParticleRenderer{ParticleRenderer(completion:completion)}
    func makeUIView(context:Context)->MTKView {
        let view=MTKView(frame:.zero,device:MTLCreateSystemDefaultDevice())
        view.isOpaque=false;view.backgroundColor = .clear;view.clearColor=MTLClearColorMake(0,0,0,0)
        view.isUserInteractionEnabled=false;view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond=quality == .performance ? 60 : UIScreen.main.maximumFramesPerSecond
        context.coordinator.configure(view:imageView(view),image:image,geometry:geometry,quality:quality)
        return view
    }
    private func imageView(_ view:MTKView)->MTKView{view}
    func updateUIView(_ view:MTKView,context:Context){context.coordinator.geometry=geometry}
    static func dismantleUIView(_ view:MTKView,coordinator:ParticleRenderer){view.isPaused=true;view.delegate=nil}
}
final class ParticleRenderer:NSObject,MTKViewDelegate {
    struct Uniforms {var c0,c1,c2,c3:SIMD4<Float>;var viewport:SIMD4<Float>;var parameters:SIMD4<Float>}
    var geometry=TransitionGeometry(from:[],to:[])
    private var queue:MTLCommandQueue?
    private var pipeline:MTLRenderPipelineState?
    private var texture:MTLTexture?
    private var start=CACurrentMediaTime()
    private var columns=48,rows=48
    private var done=false
    private let completion:()->Void
    init(completion:@escaping()->Void){self.completion=completion}
    func configure(view:MTKView,image:UIImage,geometry:TransitionGeometry,quality:Quality){
        self.geometry=geometry
        guard let device=view.device,let library=device.makeDefaultLibrary(),let cg=image.cgImage else{finish(view);return}
        queue=device.makeCommandQueue()
        let descriptor=MTLRenderPipelineDescriptor()
        descriptor.vertexFunction=library.makeFunction(name:"traceParticleVertex")
        descriptor.fragmentFunction=library.makeFunction(name:"traceParticleFragment")
        descriptor.colorAttachments[0].pixelFormat=view.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled=true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            pipeline=try device.makeRenderPipelineState(descriptor:descriptor)
            texture=try MTKTextureLoader(device:device).newTexture(cgImage:cg,options:[.SRGB:true,.generateMipmaps:true])
        } catch {finish(view);return}
        columns=quality == .performance || ProcessInfo.processInfo.thermalState != .nominal ? 28:56
        rows=max(8,min(96,Int(Double(columns)*image.size.height/image.size.width)))
        start=CACurrentMediaTime();view.delegate=self;view.isPaused=false
    }
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize){}
    func draw(in view:MTKView){
        guard !done,geometry.from.count==4,geometry.to.count==4,view.bounds.width>0,
              let drawable=view.currentDrawable,let pass=view.currentRenderPassDescriptor,
              let command=queue?.makeCommandBuffer(),let pipeline,let encoder=command.makeRenderCommandEncoder(descriptor:pass) else{return}
        let progress=min(1,(CACurrentMediaTime()-start)/1.15)
        func packed(_ i:Int)->SIMD4<Float>{SIMD4(Float(geometry.from[i].x),Float(geometry.from[i].y),Float(geometry.to[i].x),Float(geometry.to[i].y))}
        var uniforms=Uniforms(c0:packed(0),c1:packed(1),c2:packed(2),c3:packed(3),viewport:SIMD4(Float(view.bounds.width),Float(view.bounds.height),0,0),parameters:SIMD4(Float(progress),Float(columns),Float(rows),1))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:0)
        encoder.setFragmentTexture(texture,index:0)
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:6,instanceCount:columns*rows)
        encoder.endEncoding();command.present(drawable);command.commit()
        if progress>=1{finish(view)}
    }
    private func finish(_ view:MTKView){guard !done else{return};done=true;view.isPaused=true;DispatchQueue.main.async(execute:completion)}
}
