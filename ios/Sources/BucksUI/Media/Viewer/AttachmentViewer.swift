import SwiftUI
import PDFKit
import BucksCore

/// A chat or post attachment to show full screen.
public struct AttachmentRef: Identifiable, Hashable {
    public var bucket: String
    public var path: String
    public var name: String
    public var mime: String
    public var id: String { bucket + "/" + path }
    public init(bucket: String, path: String, name: String = "", mime: String) { self.bucket = bucket; self.path = path; self.name = name; self.mime = mime }
}

public extension View {
    /// Presents the attachment viewer full screen while `item` is set.
    func bucksAttachmentViewer(item: Binding<AttachmentRef?>) -> some View {
        bucksFullScreenCover(isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })) {
            if let a = item.wrappedValue { AttachmentViewer(bucket: a.bucket, path: a.path, name: a.name, mime: a.mime, onClose: { item.wrappedValue = nil }) }
        }
    }
}

/// Opens a chat or post attachment inside Bucks: photos full screen (pinch to zoom, double-tap to reset), videos in the player, PDFs page by page.
/// Nothing here sends the person to a browser. Present it with `bucksAttachmentViewer(item:)` or a full-screen cover; `onClose` defaults to dismissing.
public struct AttachmentViewer: View {
    let bucket: String, path: String, name: String, mime: String
    var onClose: (() -> Void)?
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    public init(bucket: String, path: String, name: String = "", mime: String, onClose: (() -> Void)? = nil) {
        self.bucket = bucket; self.path = path; self.name = name; self.mime = mime; self.onClose = onClose
    }

    @State private var url: URL?
    @State private var file: URL?
    @State private var failed = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var isVideo: Bool { mime.hasPrefix("video/") }
    private var isImage: Bool { mime.hasPrefix("image/") }
    private var isPDF: Bool { mime == "application/pdf" || path.lowercased().hasSuffix(".pdf") }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            topBar
        }
        .preferredColorScheme(.dark)
        .task(id: path) { await load() }
    }

    @ViewBuilder private var content: some View {
        if failed {
            VStack(spacing: 8) {
                Text("Couldn't load this").bucks(.titleMedium).foregroundStyle(.white)
                Text("Check your connection and try again.").bucks(.bodyMedium).foregroundStyle(.white.opacity(0.7))
            }
        } else if isVideo {
            if let url { MomentVideo(url: url, paused: false, loop: true).ignoresSafeArea() } else { BucksLoader(color: .white) }
        } else if isImage {
            if let url { zoomable(url) } else { BucksLoader(color: .white) }
        } else if isPDF {
            if let file { PDFPane(url: file).ignoresSafeArea(edges: .bottom) } else { BucksLoader(color: .white) }
        } else if let file {
            VStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 44)).foregroundStyle(.white)
                Text(name.isEmpty ? (path as NSString).lastPathComponent : name).bucks(.titleMedium).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, 32)
                SmallButton("Open in…", tonal: true) { FileOpener.present(file) }
            }
        } else { BucksLoader(color: .white) }
    }

    private func zoomable(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            case .failure: Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(.white.opacity(0.7))
            default: BucksLoader(color: .white)
            }
        }
        .scaleEffect(scale).offset(offset)
        .gesture(MagnificationGesture().onChanged { v in scale = min(max(lastScale * v, 1), 5); if scale <= 1 { offset = .zero } }.onEnded { _ in lastScale = scale })
        .simultaneousGesture(DragGesture().onChanged { v in if scale > 1 { offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) } }.onEnded { _ in lastOffset = offset })
        .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero } }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button("Save") { Task { await save() } }.buttonStyle(.plain).bucksFont(.labelLarge).foregroundStyle(.white).padding(.horizontal, 12).frame(minHeight: 44)
            iconButton("square.and.arrow.up", "Share") { Task { await share() } }
            iconButton("xmark", "Close") { if let onClose { onClose() } else { dismiss() } }
        }.padding(.horizontal, 4)
    }
    private func iconButton(_ systemImage: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemImage).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func load() async {
        failed = false
        if isVideo || isImage {
            if let u = try? await Backend.shared.signedURL(bucket: bucket, path: path) { url = u } else { failed = true }
        } else if let f = try? await FileOpener.download(bucket: bucket, path: path, name: name.isEmpty ? nil : name) { file = f } else { failed = true }
    }

    private func save() async {
        switch await MediaSaver.save(bucket: bucket, path: path, mime: mime) {
        case .saved: session.toast("Saved to your Photos.")
        case .denied: session.toast("Allow Photos access to save to your gallery.")
        case .failed: session.toast("Couldn't save. Check your connection and try again.")
        }
    }
    private func share() async {
        if let file { FileOpener.present(file); return }
        if !(await FileOpener.share(bucket: bucket, path: path, name: name.isEmpty ? nil : name)) { session.toast("Couldn't share that. Check your connection.") }
    }
}

#if canImport(UIKit)
private struct PDFPane: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView { let v = PDFView(); v.autoScales = true; v.document = PDFDocument(url: url); v.backgroundColor = .black; return v }
    func updateUIView(_ v: PDFView, context: Context) {}
}
#else
private struct PDFPane: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView { let v = PDFView(); v.autoScales = true; v.document = PDFDocument(url: url); return v }
    func updateNSView(_ v: PDFView, context: Context) {}
}
#endif
