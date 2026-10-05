import SwiftUI
import BucksCore

/// Compose a Moment: pick or capture a photo or video, choose who sees it, add a caption, share for 24 hours.
struct NewMomentScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    @State private var picked: Picked?
    @State private var previewURL: URL?
    @State private var caption = ""
    @State private var audience = "SYNCED"
    @State private var pickPhoto = false
    @State private var pickVideo = false
    @State private var takePhoto = false
    @State private var recordVideo = false
    @FocusState private var captionFocused: Bool

    private var busy: Bool { session.feed.busy }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { router.pop() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
                Text("New moment").bucks(.titleMedium).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                if picked != nil { Button("Change") { picked = nil; previewURL = nil }.buttonStyle(.plain).bucksFont(.labelLarge).foregroundStyle(.white).padding(.horizontal, 12).frame(minHeight: 44) }
            }.padding(8)
            preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            if picked != nil { controls }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .bucksHideNavigationBar()
        .onAppear { audience = session.feed.defaultAudience }
        .bucksPhotoPicker(isPresented: $pickPhoto, maxCount: 1, allowVideo: false) { if let f = $0.first { handle(f) } }
        .bucksPhotoPicker(isPresented: $pickVideo, maxCount: 1, allowVideo: true) { if let f = $0.first { handle(f) } }
        .bucksCapture(isPresented: $takePhoto, video: false, maxPixels: 1920, onCaptured: { handle($0) }, onError: { session.toast($0) })
        .bucksCapture(isPresented: $recordVideo, video: true, maxVideoBytes: FeedStore.maxVideoBytes, maxPixels: 1920, onCaptured: { handle($0) }, onError: { session.toast($0) })
    }

    @ViewBuilder private var preview: some View {
        if let p = picked, p.isVideo, let previewURL { MomentVideo(url: previewURL, paused: false, loop: true) }
        else if let p = picked, let image = Image(data: p.data) { image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
        else {
            VStack(spacing: 0) {
                Text("What do you want to share?").bucks(.titleLarge).foregroundStyle(.white)
                Text("It stays up for 24 hours, then disappears.").bucks(.bodyMedium).foregroundStyle(.white.opacity(0.7)).padding(.top, 6).padding(.bottom, 24)
                HStack(spacing: 14) {
                    choice("camera", "Take photo", "Use the camera") { takePhoto = true }
                    choice("video", "Record video", "Up to 30 seconds") { recordVideo = true }
                }
                HStack(spacing: 14) {
                    choice("photo", "Photo", "From gallery") { pickPhoto = true }
                    choice("video", "Video", "From gallery, up to 30 MB") { pickVideo = true }
                }.padding(.top, 14)
            }.padding(.horizontal, 32).multilineTextAlignment(.center)
        }
    }

    private func choice(_ icon: String, _ title: String, _ hint: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.white).frame(height: 36)
                Text(title).bucks(.titleMedium).foregroundStyle(.white).padding(.top, 8)
                Text(hint).bucks(.labelSmall).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            }
            .padding(.vertical, 22).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous).fill(Color.white.opacity(0.12)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([("SYNCED", "Synced"), ("LOCAL", "Nearby"), ("CLOSE", "Close friends")], id: \.0) { k, l in BucksChip(l, selected: audience == k) { audience = k } }
            }
            TextField("", text: $caption, prompt: Text("Add a caption").foregroundStyle(.white.opacity(0.6)))
                .font(.bucks(.bodyLarge)).foregroundStyle(.white).tint(.white).focused($captionFocused)
                .onChange(of: caption) { _, v in if v.count > 200 { caption = String(v.prefix(200)) } }
                .padding(.horizontal, 14).frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(captionFocused ? .white : .white.opacity(0.5), lineWidth: captionFocused ? 2 : 1))
                .padding(.top, 10)
            PrimaryButton(busy ? "Uploading…" : "Share for 24 hours", enabled: picked != nil && !busy) {
                guard let p = picked else { return }
                let c = caption.trimmingCharacters(in: .whitespacesAndNewlines), a = audience
                Task { await session.feed.postMoment(p, caption: c, audience: a) }
                router.pop()
            }.padding(.top, 12)
        }.padding(16)
    }

    /// One path for a gallery pick and a camera capture: check the type and size, then show it.
    private func handle(_ p: Picked) {
        if p.isVideo {
            if p.mime != "video/mp4" { session.toast("Only MP4 videos can be shared. Phone camera videos are MP4."); return }
            if p.data.count > FeedStore.maxVideoBytes { session.toast("That video is \(humanFileSize(p.data.count)). Videos up to 30 MB, about 30 seconds."); return }
            previewURL = writePreviewFile(p)
        } else { previewURL = nil }
        picked = p
    }
}
