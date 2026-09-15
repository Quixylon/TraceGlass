import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit
import AVFoundation

struct ImportSheet: View {
    var imported: (Data,String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var files = false
    @State private var camera = false
    @State private var error: String?
    @State private var busy = false
    @State private var pdf: PDFDocument?
    @State private var pdfPage = 1
    var body: some View {
        VStack(spacing:18) {
            Capsule().fill(.secondary.opacity(0.3)).frame(width:32,height:4).padding(.top,10)
            HStack { Text("Choose a reference").font(.title2.weight(.semibold)); Spacer(); Button("Close",systemImage:"xmark"){dismiss()}.labelStyle(.iconOnly) }
            VStack(spacing:10) {
                PhotosPicker(selection:$photo,matching:.images,photoLibrary:.shared()) {
                    row("Photos",subtitle:"Choose from your photo library",symbol:"photo.on.rectangle.angled")
                }
                Button { files = true } label: { row("Files",subtitle:"PNG, JPEG, HEIC or a PDF page",symbol:"folder") }
                Button {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else { error=TraceError.cameraUnavailable.localizedDescription; return }
                    Task {
                        let status=AVCaptureDevice.authorizationStatus(for:.video)
                        let granted = status == .authorized ? true : (status == .notDetermined ? await AVCaptureDevice.requestAccess(for:.video) : false)
                        if granted { camera=true } else { error=TraceError.cameraDenied.localizedDescription }
                    }
                } label: { row("Camera",subtitle:"Photograph a drawing",symbol:"camera") }
                Button {
                    if let data=UIPasteboard.general.image?.pngData() { complete(data,"Pasted reference") }
                    else { error="Copy an image first, then tap Paste." }
                } label: { row("Paste",subtitle:"Use an image you copied",symbol:"doc.on.clipboard") }
            }.buttonStyle(.plain)
            if busy { ProgressView("Opening image…") }
            Text("Your references stay on this iPhone.").font(.caption).foregroundStyle(.secondary).padding(.bottom,12)
        }.padding(.horizontal,22).presentationDetents([.medium,.large])
        .onChange(of:photo) { _,item in
            guard let item else { return }; busy=true
            Task {
                do { guard let data=try await item.loadTransferable(type:Data.self) else { throw TraceError.invalidImage }; complete(data,"Photo reference") }
                catch { self.error=TraceError.invalidImage.localizedDescription }; busy=false
            }
        }
        .fileImporter(isPresented:$files,allowedContentTypes:[.image,.pdf],allowsMultipleSelection:false) { result in
            guard case .success(let urls)=result,let url=urls.first else { return }
            busy=true
            Task {
                do {
                    let data=try await Task.detached {
                        let access=url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                        guard size<=ImageImporter.maxFileBytes else { throw TraceError.tooLarge }
                        return try Data(contentsOf:url,options:.mappedIfSafe)
                    }.value
                    if url.pathExtension.lowercased()=="pdf" {
                        guard let document=PDFDocument(data:data),document.pageCount>0 else { throw TraceError.invalidImage }; pdf=document; pdfPage=1
                    } else { complete(data,url.deletingPathExtension().lastPathComponent) }
                } catch { self.error=(error as? TraceError)?.localizedDescription ?? TraceError.invalidImage.localizedDescription }; busy=false
            }
        }
        .fullScreenCover(isPresented:$camera) { CameraCapture { image in camera=false; if let data=image?.jpegData(compressionQuality:0.96) { complete(data,"Camera reference") } }.ignoresSafeArea() }
        .sheet(isPresented:Binding(get:{pdf != nil},set:{if !$0 {pdf=nil}})) {
            if let document=pdf {
                VStack(spacing:18) {
                    Text("Choose a PDF page").font(.title2.weight(.semibold))
                    if let page=document.page(at:pdfPage-1) {
                        Image(uiImage:page.thumbnail(of:CGSize(width:600,height:800),for:.mediaBox)).resizable().scaledToFit().frame(maxHeight:360)
                    }
                    Stepper("Page \(pdfPage) of \(document.pageCount)",value:$pdfPage,in:1...document.pageCount)
                    PrimaryButton(title:"Import page",symbol:"arrow.down") {
                        if let data=renderPDF(document,page:pdfPage-1) { pdf=nil; complete(data,"PDF page \(pdfPage)") }
                        else {pdf=nil;error="This PDF page could not be opened. Choose another page or file."}
                    }
                }.padding(24)
            }
        }
        .alert("Could not open reference",isPresented:Binding(get:{error != nil},set:{if !$0 {error=nil}})) {
            Button("OK"){error=nil}
        } message: { Text(error ?? "") }
    }
    private func row(_ title:String,subtitle:String,symbol:String)->some View {
        HStack(spacing:16) {
            Image(systemName:symbol).font(.system(size:23)).foregroundStyle(TraceDesign.accent).frame(width:44,height:52)
            VStack(alignment:.leading,spacing:3){Text(title).font(.headline);Text(subtitle).font(.caption).foregroundStyle(.secondary)}
            Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(10).background(.secondary.opacity(0.07),in:RoundedRectangle(cornerRadius:18))
    }
    private func complete(_ data:Data,_ name:String){imported(data,name);dismiss()}
    private func renderPDF(_ document:PDFDocument,page index:Int)->Data? {
        guard let page=document.page(at:index) else{return nil}
        let rect=page.bounds(for:.mediaBox)
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {return nil}
        let scale=2560/max(rect.width,rect.height)
        let size=CGSize(width:rect.width*scale,height:rect.height*scale),format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:size,format:format).image { ctx in
            UIColor.white.setFill();ctx.fill(CGRect(origin:.zero,size:size))
            ctx.cgContext.translateBy(x:0,y:size.height);ctx.cgContext.scaleBy(x:scale,y:-scale)
            ctx.cgContext.translateBy(x:-rect.minX,y:-rect.minY);page.draw(with:.mediaBox,to:ctx.cgContext)
        }.pngData()
    }
}

struct CameraCapture:UIViewControllerRepresentable {
    var completion:(UIImage?)->Void
    func makeCoordinator()->Coordinator{Coordinator(completion)}
    func makeUIViewController(context:Context)->UIImagePickerController{
        let picker=UIImagePickerController();picker.sourceType = .camera;picker.cameraCaptureMode = .photo;picker.delegate=context.coordinator;return picker
    }
    func updateUIViewController(_ uiViewController:UIImagePickerController,context:Context){}
    final class Coordinator:NSObject,UIImagePickerControllerDelegate,UINavigationControllerDelegate{
        let completion:(UIImage?)->Void
        init(_ completion:@escaping(UIImage?)->Void){self.completion=completion}
        func imagePickerControllerDidCancel(_ picker:UIImagePickerController){completion(nil)}
        func imagePickerController(_ picker:UIImagePickerController,didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]){completion(info[.originalImage] as? UIImage)}
    }
}
