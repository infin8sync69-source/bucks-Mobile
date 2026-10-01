import SwiftUI
import BucksCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A post's photos and video: one fills the width, several scroll sideways. A video shows a play button and streams when tapped.
struct PostMediaView: View {
    let media: [JSONValue]
    var body: some View {
        let items = postMediaItems(media)
        if !items.isEmpty {
            let row = HStack(spacing: 8) {
                ForEach(items, id: \.path) { item in
                    Group {
                        if item.isVideo { PostVideo(path: item.path) } else { SignedImage(bucket: "posts", path: item.path) }
                    }
                    .frame(width: items.count == 1 ? nil : 280, height: 260)
                    .frame(maxWidth: items.count == 1 ? .infinity : nil)
                    .clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous))
                }
            }
            Group {
                if items.count > 1 { ScrollView(.horizontal, showsIndicators: false) { row } } else { row }
            }.padding(.top, 10)
        }
    }
}

private struct PostVideo: View {
    let path: String
    @State private var playing = false
    @State private var url: URL?
    var body: some View {
        ZStack {
            Color.black
            if playing, let url { MomentVideo(url: url, paused: false, loop: true) }
            else if playing { BucksLoader(color: .white) }
            else {
                VStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 26)).foregroundStyle(.white)
                        .frame(width: 64, height: 64).background(Circle().fill(.white.opacity(0.25)))
                    Text("Video").bucks(.labelMedium).foregroundStyle(.white.opacity(0.8))
                }.accessibilityLabel("Play video")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { playing.toggle() }
        .task(id: playing) { if playing { url = try? await Backend.shared.signedURL(bucket: "posts", path: path) } }
    }
}

/// A centred card over a dimmed screen, the equivalent of an Android AlertDialog with custom content.
struct FeedDialog<Content: View>: View {
    let title: String
    let closeTitle: String
    let onClose: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 16) {
                Text(title).bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface)
                ScrollView { content.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 360)
                Button(closeTitle, action: onClose).buttonStyle(.plain).bucksFont(.labelLarge).foregroundStyle(BucksColor.primary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: BucksRadius.sheet, style: .continuous).fill(BucksColor.surface))
            .padding(.horizontal, 32)
        }
    }
}

/// The inside of a bottom sheet: 20 pt around the content, room under it for the home indicator.
struct SheetBody<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(20).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(BucksColor.surface.ignoresSafeArea())
    }
}

extension View {
    /// Medium-then-large bottom sheet, like Android's ModalBottomSheet.
    func feedSheetStyle() -> some View {
        presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationCornerRadius(BucksRadius.sheet)
    }
}

extension Image {
    /// An image decoded from picked bytes; nil when they are not an image.
    init?(data: Data) {
        #if canImport(UIKit)
        guard let i = UIImage(data: data) else { return nil }
        self.init(uiImage: i)
        #elseif canImport(AppKit)
        guard let i = NSImage(data: data) else { return nil }
        self.init(nsImage: i)
        #else
        return nil
        #endif
    }
}

/// A picked video written to the cache so the player can open it by URL.
func writePreviewFile(_ p: Picked) -> URL? {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-" + UUID().uuidString + ".mp4")
    return (try? p.data.write(to: url)) != nil ? url : nil
}
