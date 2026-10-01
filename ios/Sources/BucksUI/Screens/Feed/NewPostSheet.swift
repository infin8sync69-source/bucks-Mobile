import SwiftUI
import BucksCore

/// The post composer (NewPostSheet): text, who can see it, up to four photos or one video, Post.
struct NewPostForm: View {
    @Environment(AppSession.self) private var session
    var showTitle = true
    let onDone: () -> Void

    @State private var text = ""
    @State private var visibility = "LOCAL"
    @State private var photos: [Picked] = []
    @State private var pickGallery = false
    @State private var takePhoto = false
    @State private var recordVideo = false

    private var busy: Bool { session.feed.busy }
    private var canPost: Bool { !busy && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showTitle { Text("New post").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface) }
            BucksField($text, placeholder: "Ask for a recommendation, share a deal, thank a provider", singleLine: false, minLines: 4).padding(.top, 14)
            FieldLabel("Who can see it")
            HStack(spacing: 6) {
                ForEach([("LOCAL", "Nearby"), ("SYNCED", "Synced only"), ("PUBLIC", "Everyone")], id: \.0) { k, l in BucksChip(l, selected: visibility == k) { visibility = k } }
            }
            HStack(spacing: 6) {
                SmallButton("Camera", tonal: true) { takePhoto = true }
                SmallButton("Record", tonal: true) { recordVideo = true }
                SmallButton(photos.isEmpty ? "Gallery" : "\(photos.count) attached", tonal: true) { pickGallery = true }
                if !photos.isEmpty { Button("Remove") { photos = [] }.buttonStyle(.plain).bucksFont(.labelLarge).foregroundStyle(BucksColor.primary).padding(.horizontal, 8).frame(minHeight: 44) }
            }.padding(.top, 12)
            PrimaryButton(busy ? "Posting…" : "Post", enabled: canPost) {
                let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let area = session.user?.area.split(separator: ",").first.map(String.init) ?? ""
                let media = photos, vis = visibility
                Task { await session.feed.post(body: body, media: media, visibility: vis, area: area) }
                onDone()
            }.padding(.top, 14)
        }
        .bucksPhotoPicker(isPresented: $pickGallery, maxCount: 4, allowVideo: true) { picked in addPicked(picked) }
        .bucksCapture(isPresented: $takePhoto, video: false, onCaptured: { addCaptured($0) }, onError: { session.toast($0) })
        .bucksCapture(isPresented: $recordVideo, video: true, maxVideoBytes: FeedStore.maxPostVideoBytes, onCaptured: { addCaptured($0) }, onError: { session.toast($0) })
    }

    /// Photos and MP4 videos (one video at most, up to 15 MB: the posts bucket's limit).
    private func addPicked(_ picked: [Picked]) {
        var videos = 0, skipped = 0
        var kept: [Picked] = []
        for f in picked {
            if f.isVideo {
                if f.mime != "video/mp4" { session.toast("Only MP4 videos can be posted. Phone camera videos are MP4."); continue }
                videos += 1
                if videos > 1 { skipped += 1; continue }
                if f.data.count > FeedStore.maxPostVideoBytes { session.toast("That video is over 15 MB. Pick a shorter one, or share it as a Moment (up to 30 MB)."); continue }
            }
            kept.append(f)
        }
        photos = kept
        if skipped > 0 { session.toast("One video per post.") }
    }

    private func addCaptured(_ f: Picked) {
        if photos.count >= 4 { session.toast("Up to 4 attachments per post."); return }
        if f.isVideo && photos.contains(where: \.isVideo) { session.toast("One video per post."); return }
        if f.isVideo && f.data.count > FeedStore.maxPostVideoBytes { session.toast("That video is over 15 MB. Record a shorter one, or share it as a Moment (up to 30 MB)."); return }
        photos.append(f)
    }
}

/// The create-post route: the composer on its own screen.
struct CreatePostScreen: View {
    @Environment(Router.self) private var router
    var body: some View {
        VStack(spacing: 0) {
            BucksTopBar(title: "New post", onBack: { router.pop() })
            ScrollView { NewPostForm(showTitle: false) { router.pop() }.padding(Gutter) }.scrollDismissesKeyboard(.interactively)
        }
        .bucksBackground()
        .bucksHideNavigationBar()
    }
}
