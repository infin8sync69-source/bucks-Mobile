import SwiftUI
import PDFKit
import ImageIO
import BucksCore
#if os(iOS)
import UIKit
#endif

// Showcase documents on a profile (migration showcase_docs.sql; port of ShowcaseDocsUi.kt). Not the compliance documents Bucks staff check
// for go-live. Visibility is decided by the server per document; the app only asks and shows what comes back. A document is "Checked by
// Bucks" only when staff flagged it; viewer opinions are a separate, clearly labelled signal and never called verification.

// MARK: - Shared bits (also used by the Studio manage screen)

func showcaseKindIcon(_ kind: String) -> String {
    switch kind { case "LICENCE", "CERTIFICATE": "checkmark.shield"; case "AFFILIATION": "globe"; default: "doc.text" }
}
func showcaseVisibilityLabel(_ v: String) -> String {
    switch v { case "PUBLIC": "Public"; case "PRIVATE": "Team only"; default: "On request" }
}
/// "Registration · Registrar of Companies".
func showcaseSubtitle(_ d: ShowcaseDoc) -> String {
    let issuer = d.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
    return [ShowcaseKinds.label(d.kind), issuer.isEmpty ? nil : issuer].compactMap { $0 }.joined(separator: " · ")
}
/// "3 of 4 viewers say it looks genuine", only once at least 3 viewers gave an opinion.
func showcaseOpinionLine(_ d: ShowcaseDoc) -> String? {
    d.checks >= 3 ? "\(d.checksUp) of \(d.checks) viewers say it looks genuine. Viewer opinions, not a Bucks check." : nil
}

/// The pills every document row shows: who can open it, whether it has lapsed, and whether Bucks checked it (never implied otherwise).
struct ShowcasePills: View {
    let doc: ShowcaseDoc
    var selfLabelled = false
    var body: some View {
        FlowLayout(spacing: 6) {
            PillGrey(showcaseVisibilityLabel(doc.visibility))
            if selfLabelled { PillGrey("Self-labelled") }
            if doc.expired { PillBad("Expired") } else if let e = doc.expiresOn, !e.isEmpty { PillGrey("Valid till \(humanDate(e))") }
            if doc.bucksChecked { PillGood("Checked by Bucks") } else { PillGrey("Not checked by Bucks") }
        }
    }
}

/// A 48pt-high button with an optional icon. `fill` stretches it to the row.
struct ShowcaseButton: View {
    let title: String
    var systemImage: String?
    var tonal: Bool
    var enabled: Bool
    var fill: Bool
    let action: () -> Void
    init(_ title: String, systemImage: String? = nil, tonal: Bool = false, enabled: Bool = true, fill: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.tonal = tonal; self.enabled = enabled; self.fill = fill; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(.bucks(.labelLarge)).lineLimit(1)
            }
            .foregroundStyle(tonal ? BucksColor.onSecondaryContainer : BucksColor.onPrimary)
            .padding(.horizontal, 16)
            .frame(maxWidth: fill ? CGFloat.infinity : nil)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(tonal ? BucksColor.secondaryContainer : BucksColor.primary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}

/// A plain text action with a 48pt-high touch target.
struct ShowcaseTextButton: View {
    let title: String
    var color: Color
    var enabled: Bool
    let action: () -> Void
    init(_ title: String, color: Color = BucksColor.primary, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.color = color; self.enabled = enabled; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).font(.bucks(.labelLarge)).foregroundStyle(color).lineLimit(1).padding(.horizontal, 8).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - The "N documents" chip under the stats row

/// Shows how many documents I can see on this profile; a tap switches to the About tab where they are. Nothing while loading or when there are none.
struct ShowcaseDocsChip: View {
    let listingId: String
    var onTap: () -> Void
    @State private var count: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0).task(id: listingId) { count = (try? await Backend.shared.showcaseDocs(listingId))?.count }
            if let n = count, n > 0 {
                Button(action: onTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text").font(.system(size: 13))
                        Text(n == 1 ? "1 document" : "\(n) documents").font(.bucks(.labelMedium)).lineLimit(1)
                    }
                    .foregroundStyle(BucksColor.onSurface).padding(.horizontal, 13).padding(.vertical, 8)
                    .background(Capsule().fill(BucksColor.surfaceContainer))
                    .padding(.vertical, 5)   // 44 pt tap target around the chip
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(n == 1 ? "1 document" : "\(n) documents").accessibilityHint("Shows them in About")
            }
        }
    }
}

// MARK: - The profile's Documents block (About tab)

/// The profile's Documents block. Hidden when there is nothing to show and I am not on the team. Locked documents show who issued them and
/// let me ask the owner; the file itself is only ever fetched through `ShowcaseDocViewer`.
struct ShowcaseDocsSection: View {
    let listingId: String
    /// I am the owner or an admin of this listing.
    let team: Bool
    var onManage: () -> Void
    @State private var docs: [ShowcaseDoc]?
    @State private var failed = false
    @State private var reloadTick = 0
    @State private var viewing: ShowcaseDoc?
    @State private var requesting: ShowcaseDoc?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0).task(id: "\(listingId)#\(reloadTick)") { await load() }
            content
        }
        // Coming back from the manage screen (or a viewer opinion) shows the new state.
        .onAppear { if docs != nil { reloadTick += 1 } }
        .bucksFullScreenCover(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) {
            if let d = viewing { ShowcaseDocViewer(doc: d, team: team, onClose: { viewing = nil }, onChanged: { reloadTick += 1 }) }
        }
        .sheet(item: $requesting) { d in
            ShowcaseRequestSheet(doc: d) { requesting = nil; reloadTick += 1 }
        }
    }

    @MainActor private func load() async {
        do { docs = try await Backend.shared.showcaseDocs(listingId); failed = false }
        catch is CancellationError { return }
        catch { if docs == nil { failed = true } }
    }

    @ViewBuilder private var content: some View {
        if let list = docs {
            if !list.isEmpty || team { block(list) }
        } else if failed {
            HStack(spacing: 0) {
                Muted("Couldn't load documents.")
                ShowcaseTextButton("Try again") { failed = false; reloadTick += 1 }
            }.padding(.horizontal, Gutter)
        } else if team {
            // Nothing while loading for a visitor (most profiles have no documents, so no flash); the team always sees the block.
            VStack(alignment: .leading, spacing: 0) {
                SkeletonBox(radius: 6).frame(width: 120, height: 18)
                SkeletonBox(radius: 12).frame(height: 96).padding(.top, 10)
            }.padding(.horizontal, Gutter).padding(.top, 8)
        }
    }

    private func block(_ list: [ShowcaseDoc]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Documents").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
                if !list.isEmpty { Text("\(list.count)").bucks(.bodySmall).foregroundStyle(BucksColor.onSurfaceVariant) }
            }
            Muted(team ? "What you show here is chosen by you, per document. This is separate from the checks Bucks does for going live."
                       : "Shown by the owner. A document is checked by Bucks only when it says so. Locked ones open after the owner agrees.").padding(.top, 2)
            if list.isEmpty { Muted("No documents yet. Add a registration, licence or certificate to help people trust you.").padding(.top, 10) }
            ForEach(list) { d in
                ShowcaseDocCard(doc: d, onOpen: { viewing = d }, onRequest: { requesting = d }).padding(.top, 10)
            }
            if team { ShowcaseButton("Manage documents", systemImage: "pencil", tonal: true, action: onManage).padding(.top, 12) }
        }
        .padding(.horizontal, Gutter).padding(.top, 8)
    }
}

private struct ShowcaseDocCard: View {
    let doc: ShowcaseDoc
    var onOpen: () -> Void
    var onRequest: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        let d = doc
        BucksCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Avatar(systemImage: showcaseKindIcon(d.kind), size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(d.title).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    Muted(showcaseSubtitle(d))
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !d.canOpen { Image(systemName: "lock.fill").font(.system(size: 16)).foregroundStyle(BucksColor.onSurfaceVariant).accessibilityLabel("Locked") }
            }
            ShowcasePills(doc: d).padding(.top, 10)
            if !d.number.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 0) {
                    Text("No. \(d.number)").bucks(.bodySmall).foregroundStyle(BucksColor.onSurface)
                    Spacer(minLength: 8)
                    if let s = Registries.url(d.registry), let url = URL(string: s) {
                        ShowcaseTextButton("Check on official site") { openURL(url) }
                    }
                }.padding(.top, 4)
            }
            if let line = showcaseOpinionLine(d) { Muted(line).padding(.top, 4) }
            Group {
                if d.canOpen { ShowcaseButton("Open", systemImage: "eye", action: onOpen) }
                else if d.myRequest == "PENDING" { ShowcaseButton("Requested, waiting", tonal: true, enabled: false) {} }
                else if d.myRequest == "DECLINED" { ShowcaseButton("Declined", tonal: true, enabled: false) {} }
                else if d.visibility == "ON_REQUEST" { ShowcaseButton("Request access", systemImage: "lock", tonal: true, action: onRequest) }
                else { Muted("Not available right now.") }
            }.padding(.top, 8)
        }
    }
}

// MARK: - Ask the owner

/// Ask the owner to share a locked document. The owner sees my name, whether I ordered or follow the page, and this message.
private struct ShowcaseRequestSheet: View {
    let doc: ShowcaseDoc
    var onDone: () -> Void
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        Sheet(scrollable: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ask to see \(doc.title)?").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted("The owner sees your name, whether you have ordered or follow this page, and your message. If they agree you can open it for 30 days.").padding(.top, 4)
                BucksField(Binding(get: { message }, set: { message = String($0.prefix(200)) }), placeholder: "Why you'd like to see it (optional)", singleLine: false, minLines: 2).padding(.top, 12)
                Muted("\(message.count)/200", align: .trailing)
                PrimaryButton(busy ? "Sending…" : "Request access", enabled: !busy) { send() }.padding(.top, 8)
                GhostButton("Cancel", enabled: !busy) { dismiss() }.padding(.top, 8)
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(busy)
    }

    private func send() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let status = try await Backend.shared.requestDocAccess(doc.id, message: text)
                session.toast(status == "APPROVED" ? "You can already open this document." : "Request sent. You'll get a notification when the owner answers.")
                onDone()
            } catch is CancellationError {
            } catch { session.toast(friendlyError(error)) }
        }
    }
}

// MARK: - Full-screen reader

/// What was downloaded, ready to show.
private enum ShowcaseContent {
    case pdf(PDFDocument)
    case image(CGImage)

    /// A PDF, or a photo decoded no larger than 2400 px on its long side so a big scan can't exhaust memory. nil when the bytes are neither.
    static func make(_ data: Data, pdf: Bool) -> ShowcaseContent? {
        if pdf {
            guard let doc = PDFDocument(data: data), doc.pageCount > 0 else { return nil }
            return .pdf(doc)
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        guard let w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue, let h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w > 0, h > 0 else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(2400, max(w, h)),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return .image(cg)
    }
}

private enum ShowcaseViewerPhase {
    case loading
    case failed(String)
    case ready(ShowcaseContent)
}

/// Full-screen reader for one document. The file is fetched with my own sign-in each time and kept in memory only, and a faint watermark
/// with my name and today's date lies over it. The content is hidden while the screen is being recorded or mirrored and whenever the app is
/// not active (so the app switcher shows nothing). Viewers can give an opinion once it is open; the team cannot.
/// iOS has no equivalent of Android's secure window, so a screenshot is not blocked.
struct ShowcaseDocViewer: View {
    let doc: ShowcaseDoc
    /// Owner or admin: no opinion bar.
    let team: Bool
    var onClose: () -> Void
    var onChanged: () -> Void
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: ShowcaseViewerPhase = .loading
    @State private var attempt = 0
    @State private var opened = false
    @State private var screenCaptured = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var mark: String {
        let name = (session.me?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM yyyy"
        return "Viewed by \(name.isEmpty ? "a Bucks member" : name) · \(f.string(from: Date()))"
    }
    private var isReady: Bool { if case .ready = phase { return true } else { return false } }
    private var hidden: Bool { screenCaptured || scenePhase != .active }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                Color(white: 0.11)
                stage
                if isReady { ShowcaseWatermark(text: mark).allowsHitTesting(false) }
                if hidden { privacyCover }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            if !team && opened { ShowcaseOpinionBar(doc: doc, onChanged: onChanged) }
        }
        .bucksBackground()
        .modifier(ShowcaseCaptureWatch(captured: $screenCaptured))
        .task(id: attempt) { await load() }
    }

    private var header: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(doc.title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                Muted(showcaseSubtitle(doc), maxLines: 1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Close")
        }
        .padding(.leading, Gutter).padding(.trailing, 4).padding(.vertical, 4)
    }

    @ViewBuilder private var stage: some View {
        switch phase {
        case .loading:
            BucksLoader(color: .white)
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).bucks(.bodyMedium).foregroundStyle(.white).multilineTextAlignment(.center)
                ShowcaseButton("Try again", tonal: true) { attempt += 1 }
            }.padding(Gutter)
        case .ready(let content):
            switch content {
            case .pdf(let document): ShowcasePDFPane(document: document)
            case .image(let image): zoomable(image)
            }
        }
    }

    private func zoomable(_ cg: CGImage) -> some View {
        Image(decorative: cg, scale: 1).resizable().scaledToFit()
            .scaleEffect(scale).offset(offset)
            .gesture(MagnificationGesture().onChanged { v in scale = min(max(lastScale * v, 1), 5); if scale <= 1 { offset = .zero } }.onEnded { _ in lastScale = scale })
            .simultaneousGesture(DragGesture().onChanged { v in if scale > 1 { offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) } }.onEnded { _ in lastOffset = offset })
            .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero } }
            .accessibilityLabel(doc.title)
    }

    private var privacyCover: some View {
        ZStack {
            BucksColor.surface
            VStack(spacing: 10) {
                Image(systemName: "eye.slash").font(.system(size: 32)).foregroundStyle(BucksColor.onSurfaceVariant)
                if screenCaptured { Muted("Hidden while the screen is being recorded or shared.", align: .center).padding(.horizontal, Gutter) }
            }
        }
    }

    @MainActor private func load() async {
        phase = .loading; opened = false
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
        do {
            let o = try await Backend.shared.openShowcaseDoc(doc.id)
            let bytes = try await Backend.shared.downloadShowcaseFile(path: o.path)
            opened = true
            let pdf = (o.mime.isEmpty ? doc.mime : o.mime) == "application/pdf"
            if let content = ShowcaseContent.make(bytes, pdf: pdf) { phase = .ready(content) }
            else { phase = .failed("Couldn't show this file. It may be damaged.") }
        } catch is CancellationError {
        } catch { phase = .failed(friendlyError(error)) }
    }
}

/// Hides the document while the screen is being recorded or mirrored (iOS only; elsewhere it does nothing).
private struct ShowcaseCaptureWatch: ViewModifier {
    @Binding var captured: Bool
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onAppear { captured = ShowcaseCaptureWatch.isCaptured() }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in captured = ShowcaseCaptureWatch.isCaptured() }
        #else
        content
        #endif
    }
    #if os(iOS)
    @MainActor static func isCaptured() -> Bool {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.contains { $0.screen.isCaptured }
    }
    #endif
}

/// Faint diagonal repeating text over the whole document; it does not take touches.
private struct ShowcaseWatermark: View {
    let text: String
    var body: some View {
        Canvas { context, size in
            var light = context.resolve(Text(text).font(.system(size: 15)))
            light.shading = .color(Color.white.opacity(0.16))
            var dark = context.resolve(Text(text).font(.system(size: 15)))
            dark.shading = .color(Color.black.opacity(0.16))
            let width = light.measure(in: CGSize(width: 2000, height: 100)).width
            let gapX: CGFloat = 60, stepY: CGFloat = 110
            var ctx = context
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: .degrees(-28))
            let reach = max(size.width, size.height) * 1.2
            var row = 0
            var y = -reach
            while y < reach {
                var x = -reach + (row % 2 == 0 ? 0 : (width + gapX) / 2)
                while x < reach {
                    ctx.draw(light, at: CGPoint(x: x, y: y), anchor: .leading)
                    ctx.draw(dark, at: CGPoint(x: x + 1.2, y: y + 1.2), anchor: .leading)
                    x += width + gapX
                }
                y += stepY; row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

#if canImport(UIKit)
private struct ShowcasePDFPane: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true; v.document = document; v.backgroundColor = UIColor(white: 0.11, alpha: 1); return v
    }
    func updateUIView(_ v: PDFView, context: Context) { if v.document !== document { v.document = document } }
}
#else
private struct ShowcasePDFPane: NSViewRepresentable {
    let document: PDFDocument
    func makeNSView(context: Context) -> PDFView { let v = PDFView(); v.autoScales = true; v.document = document; return v }
    func updateNSView(_ v: PDFView, context: Context) { if v.document !== document { v.document = document } }
}
#endif

// MARK: - Opinion bar

/// "Looks genuine" / "Doesn't look right", with an optional comment; a viewer signal, never a Bucks check. I can change or remove mine.
private struct ShowcaseOpinionBar: View {
    let doc: ShowcaseDoc
    var onChanged: () -> Void
    @Environment(AppSession.self) private var session
    @State private var saved: Int?
    @State private var picked: Int?
    @State private var comment = ""
    @State private var busy = false

    init(doc: ShowcaseDoc, onChanged: @escaping () -> Void) {
        self.doc = doc; self.onChanged = onChanged
        _saved = State(initialValue: doc.myCheck)
    }

    var body: some View {
        let sel = picked ?? saved
        VStack(alignment: .leading, spacing: 0) {
            Muted("Viewer opinions, not a Bucks check. Your name is not shown with it.")
            HStack(spacing: 8) {
                ShowcaseButton("Looks genuine", tonal: sel != 1, enabled: !busy, fill: true) { picked = 1 }
                ShowcaseButton("Doesn't look right", tonal: sel != -1, enabled: !busy, fill: true) { picked = -1 }
            }.padding(.top, 8)
            if let v = picked {
                BucksField(Binding(get: { comment }, set: { comment = String($0.prefix(300)) }), placeholder: "Add a comment (optional)", singleLine: false, minLines: 2).padding(.top, 8)
                Muted("\(comment.count)/300", align: .trailing)
                HStack(spacing: 8) {
                    ShowcaseButton(busy ? "Saving…" : "Save my opinion", enabled: !busy) { save(v) }
                    ShowcaseTextButton("Cancel", enabled: !busy) { picked = nil; comment = "" }
                    Spacer(minLength: 0)
                }
            } else if let s = saved {
                HStack(spacing: 8) {
                    Muted(s == 1 ? "Your opinion: looks genuine." : "Your opinion: doesn't look right.")
                    ShowcaseTextButton("Remove mine", color: BucksColor.error, enabled: !busy) { remove() }
                }
            }
        }
        .padding(.horizontal, Gutter).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .background(BucksColor.surfaceContainer.ignoresSafeArea(edges: .bottom))
    }

    private func save(_ vote: Int) {
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await Backend.shared.checkShowcaseDoc(doc.id, vote: vote, comment: text)
                saved = vote; picked = nil; comment = ""
                session.toast("Thanks, your opinion is saved.")
                onChanged()
            } catch is CancellationError {
            } catch { session.toast(friendlyError(error)) }
        }
    }

    private func remove() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await Backend.shared.clearShowcaseCheck(doc.id)
                saved = nil
                session.toast("Your opinion was removed.")
                onChanged()
            } catch is CancellationError {
            } catch { session.toast(friendlyError(error)) }
        }
    }
}
