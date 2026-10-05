import SwiftUI
import BucksCore

/// One conversation: a direct chat, a group or a listing inbox. Messages load once, then stay current through Realtime plus a light poll.
struct ChatScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    @State private var msgs: [MessageRow] = []
    @State private var text = ""
    @State private var seen: String?
    @State private var editing: MessageRow?
    @State private var menuFor: MessageRow?
    @State private var viewing: AttachmentRef?
    @State private var conv: ConversationRow?
    @State private var members: [ConversationMemberRow] = []
    @State private var showMembers = false
    @State private var pickPhoto = false
    @State private var pickFile = false
    @State private var takePhoto = false
    @State private var recordVideo = false

    private var chat: ChatStore { session.chat }
    private var meId: String? { session.me?.id }
    private var inboxRow: InboxRow? { chat.inbox.first { $0.conversationId == id } }
    /// The conversation row is the source of truth for kind and title; the inbox row fills in until it loads (and names the other person in a DM).
    private var kind: String { conv?.kind ?? inboxRow?.kind ?? "DIRECT" }
    private var listingTitle: String { conv?.title ?? inboxRow?.title ?? "Listing" }
    /// A listing chat is named after the shop or pro; the people who run it see the customer's name instead. Until the members load,
    /// the inbox row names the customer (the server fills other_name only for the people who run the listing).
    private var customer: String? {
        guard kind == "LISTING" else { return nil }
        if members.contains(where: { $0.profileId == meId && $0.role == "ADMIN" }) { return members.first { $0.role == "MEMBER" }.map { session.social.nameOf($0.profileId) } }
        return members.isEmpty ? inboxRow?.otherName : nil
    }
    private var title: String {
        switch kind {
        case "DIRECT": inboxRow?.title ?? "Chat"
        case "LISTING": customer ?? listingTitle
        default: conv?.title ?? inboxRow?.title ?? "Group"
        }
    }
    private var listingId: String? { conv?.listingId }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if msgs.isEmpty {
                Muted(kind == "GROUP" ? "No messages yet. Say hello to the group." : kind == "LISTING" ? "No messages yet. Ask about prices, timings or availability." : "No messages yet. Say hello.").padding(Gutter)
            }
            messageList
            if chat.uploading { ProgressView().progressViewStyle(.linear).tint(BucksColor.primary) }
            if editing != nil { editBanner }
            composer
        }
        .bucksBackground().bucksHideNavigationBar()
        .task(id: id) {
            conv = await chat.conversation(id)
            if let rows = try? await chat.messages(id) { msgs = rows }
            chat.markRead(id)
            seen = await chat.seenUpTo(id)
        }
        .task(id: kind) { if kind != "DIRECT" { members = await chat.members(id) } }
        .task(id: id) { await live() }
        .task(id: id) { await poll() }
        .bucksPhotoPicker(isPresented: $pickPhoto, maxCount: 1, allowVideo: true) { picked in sendPicked(picked.first) }
        .bucksFilePicker(isPresented: $pickFile) { picked in sendPicked(picked) }
        .bucksCamera(isPresented: $takePhoto, video: false) { sendPicked($0) }
        .bucksCamera(isPresented: $recordVideo, video: true) { sendPicked($0) }
        .bucksAttachmentViewer(item: $viewing)
        .confirmationDialog("Your message", isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }), titleVisibility: .visible, presenting: menuFor) { m in
            if !m.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Button("Edit") { editing = m; text = m.body } }
            Button("Delete for everyone", role: .destructive) { delete(m) }
            Button("Close", role: .cancel) {}
        }
        .sheet(isPresented: $showMembers) {
            MembersSheet(conv: id, kind: kind, title: title, members: members, onReload: { Task { members = await chat.members(id) } },
                         onRenamed: { t in if var c = conv { c.title = t; conv = c } }, onLeft: { showMembers = false; router.pop() },
                         onOpenListing: listingId.map { l in { showMembers = false; router.push(.listing(l)) } })
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }

    // MARK: top bar

    @ViewBuilder private var topBar: some View {
        switch kind {
        case "DIRECT": BucksTopBar(title: title, onBack: { router.pop() })
        case "LISTING":
            ChatTopBar(title: title, subtitle: customer != nil ? "Customer · about \(listingTitle)" : listingId != nil ? "Shop or pro · tap to open" : nil, onBack: { router.pop() },
                       onTitle: listingId.map { l in { router.push(.listing(l)) } }) {
                if let l = listingId { barIcon("storefront", "Open listing") { router.push(.listing(l)) } }
                barIcon("person.2", "People in this chat") { showMembers = true }
            }
        default:
            ChatTopBar(title: title, subtitle: members.isEmpty ? "Group" : "\(members.count) people · tap for details", onBack: { router.pop() }, onTitle: { showMembers = true }) {
                barIcon("person.2", "Members") { showMembers = true }
            }
        }
    }
    private func barIcon(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    // MARK: messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(msgs) { m in
                        MessageBubble(m: m, mine: m.senderId == meId, showSender: kind != "DIRECT", sender: session.social.nameOf(m.senderId),
                                      onLongPress: { if m.senderId == meId && m.deletedAt == nil { menuFor = m } }, onOpen: open)
                            .id(m.id).padding(.bottom, 8)
                    }
                    if let lastMine = msgs.last(where: { $0.senderId == meId }), let seen, seen >= lastMine.createdAt {
                        Text("Seen").bucks(.labelSmall).foregroundStyle(BucksColor.onSurfaceVariant).frame(maxWidth: .infinity, alignment: .trailing).id("seen")
                    }
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: msgs.count) { _, _ in withAnimation { proxy.scrollTo(msgs.last?.id, anchor: .bottom) } }
            .scrollDismissesKeyboard(.interactively)
        }.frame(maxHeight: .infinity)
    }

    /// Photos and videos open inside Bucks; documents open with the phone's own viewer. Nothing goes to a browser.
    private func open(_ a: ChatAttachment) {
        if a.isImage || a.isVideo { viewing = AttachmentRef(bucket: "chat", path: a.path, name: a.name, mime: a.mime); return }
        session.toast("Opening…")
        Task {
            if let f = try? await FileOpener.download(bucket: "chat", path: a.path, name: a.name) { FileOpener.present(f) }
            else { session.toast("No app on this phone can open that file, or the download failed.") }
        }
    }

    // MARK: composer

    private var editBanner: some View {
        HStack {
            Muted("Editing")
            Button { editing = nil; text = "" } label: { Image(systemName: "xmark").foregroundStyle(BucksColor.onSurface).frame(width: 40, height: 40).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel("Cancel edit")
        }.padding(.horizontal, 16).padding(.vertical, 6).background(BucksColor.surfaceContainer)
    }

    private var composer: some View {
        HStack(spacing: 0) {
            attachButton("photo", "Photo or video") { pickPhoto = true }
            Menu {
                Button("Take photo") { takePhoto = true }
                Button("Record video") { recordVideo = true }
            } label: { attachIcon("camera") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(chat.uploading).accessibilityLabel("Camera")
            attachButton("paperclip", "File") { pickFile = true }
            TextField("", text: $text, prompt: Text("Message").foregroundStyle(BucksColor.onSurfaceVariant), axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...4).font(.bucks(.bodyLarge)).foregroundStyle(BucksColor.onSurface)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14).padding(.vertical, 14).frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surface))
                .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
                .padding(.leading, 4)
            let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button(action: sendTapped) {
                Image(systemName: "paperplane.fill").font(.system(size: 18)).foregroundStyle(BucksColor.onPrimary).frame(width: 48, height: 48)
                    .background(Circle().fill(empty ? BucksColor.onSurface.opacity(0.12) : BucksColor.primary))
            }.buttonStyle(.plain).disabled(empty).padding(.leading, 8).accessibilityLabel("Send")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(BucksColor.surfaceContainerLow.ignoresSafeArea(edges: .bottom))
    }
    private func attachIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(BucksColor.onSurfaceVariant.opacity(chat.uploading ? 0.4 : 1)).frame(width: 44, height: 44).contentShape(Rectangle())
    }
    private func attachButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { attachIcon(symbol) }.buttonStyle(.plain).disabled(chat.uploading).accessibilityLabel(label)
    }

    // MARK: actions

    private func sendTapped() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let e = editing {
            chat.editMessage(e.id, body: t)
            msgs = msgs.map { var m = $0; if m.id == e.id { m.body = t; m.editedAt = "now" }; return m }
            editing = nil
        } else {
            Task { if let m = await chat.send(id, body: t) { append(m) } }
        }
        text = ""
    }
    private func delete(_ m: MessageRow) {
        chat.deleteMessage(m.id)
        msgs = msgs.map { var x = $0; if x.id == m.id { x.body = ""; x.attachment = nil; x.deletedAt = "now" }; return x }
    }
    /// Photos and videos from the gallery or camera; a file that can't be read (or is over 25 MB) says so instead of doing nothing.
    private func sendPicked(_ f: Picked?) {
        guard let f else { session.toast("Couldn't open that file. Files up to 25 MB."); return }
        if f.data.count > 25 * 1024 * 1024 { session.toast("Files up to 25 MB."); return }
        Task { if let m = await chat.sendFile(id, f) { append(m) } }
    }
    private func append(_ m: MessageRow) { if !msgs.contains(where: { $0.id == m.id }) { msgs.append(m) } }

    // MARK: live updates

    private func live() async {
        for await change in Backend.shared.changes(table: "messages", filter: "conversation_id=eq.\(id)", events: ["INSERT"]) {
            guard let data = change.record, let m = Backend.shared.decodeRecord(MessageRow.self, from: data), !msgs.contains(where: { $0.id == m.id }) else { continue }
            await session.social.namesFor([m.senderId])
            append(m)
            if m.senderId != meId { chat.markRead(id) }
        }
    }
    /// Realtime is a nudge; this keeps the chat right when it is slow, and picks up edits, deletes and read receipts.
    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            guard let rows = try? await chat.messages(id) else { continue }
            let newFromOthers = rows.contains { r in r.senderId != meId && !msgs.contains(where: { $0.id == r.id }) }
            // A message I sent or that Realtime delivered while this poll was on its way is newer than the page it fetched: keep it.
            let newest = rows.last?.createdAt ?? ""
            let late = msgs.filter { m in !rows.contains(where: { $0.id == m.id }) && m.createdAt > newest }
            let merged = rows + late
            if merged != msgs { msgs = merged }
            if newFromOthers { chat.markRead(id) }
            seen = await chat.seenUpTo(id)
        }
    }
}

// MARK: - Pieces

/// Title row for a group or listing chat: the title itself opens the members sheet or the listing.
private struct ChatTopBar<Actions: View>: View {
    let title: String
    let subtitle: String?
    let onBack: () -> Void
    let onTitle: (() -> Void)?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) { Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel("Back")
            let label = VStack(alignment: .leading, spacing: 0) {
                Text(title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                if let subtitle { Muted(subtitle, maxLines: 1) }
            }.padding(.horizontal, 4).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            if let onTitle { Button(action: onTitle) { label }.buttonStyle(.plain) } else { label }
            actions
        }.padding(.horizontal, 8).padding(.vertical, 6)
    }
}

/// Keeps a bubble as wide as its content, up to `maxWidth` (widthIn(max) in Compose).
private struct WrapMax: Layout {
    var maxWidth: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let v = subviews.first else { return .zero }
        return v.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? maxWidth, maxWidth), height: proposal.height))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

private struct MessageBubble: View {
    let m: MessageRow
    let mine: Bool
    let showSender: Bool
    let sender: String
    let onLongPress: () -> Void
    let onOpen: (ChatAttachment) -> Void

    var body: some View {
        let fg = mine ? BucksColor.onPrimary : BucksColor.onSurface
        let attachment = ChatAttachment(m.attachment)
        HStack(spacing: 0) {
            if mine { Spacer(minLength: 0) }
            WrapMax(maxWidth: 320) {
                VStack(alignment: .trailing, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Groups and listing inboxes have several people on the other side, so every bubble that isn't mine carries its sender.
                        if !mine && showSender {
                            Text(sender).bucks(.labelSmall).foregroundStyle(BucksColor.primary).padding(.leading, 10).padding(.top, 6)
                        }
                        if let a = attachment { attachmentView(a, fg) }
                        if m.deletedAt != nil {
                            Text("Message deleted").font(.bucks(.bodyMedium)).fontWeight(.regular).foregroundStyle(fg.opacity(0.7)).padding(.horizontal, 10).padding(.vertical, 8)
                        } else if !m.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(m.body).bucks(.bodyMedium).foregroundStyle(fg).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.vertical, 8)
                        }
                    }
                    Text([feedAgo(m.createdAt), m.editedAt != nil ? "edited" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .bucks(.labelSmall).foregroundStyle(fg.opacity(0.7)).padding(.leading, 10).padding(.trailing, 10).padding(.bottom, 6)
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous).fill(mine ? BucksColor.primary : BucksColor.surfaceContainer))
                .contentShape(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous))
                .onLongPressGesture { onLongPress() }
            }
            if !mine { Spacer(minLength: 0) }
        }
    }

    @ViewBuilder private func attachmentView(_ a: ChatAttachment, _ fg: Color) -> some View {
        if a.isImage {
            SignedImage(bucket: "chat", path: a.path).frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous)).contentShape(Rectangle())
                .onTapGesture { onOpen(a) }
        } else {
            Button { onOpen(a) } label: {
                HStack(spacing: 10) {
                    Image(systemName: a.isVideo ? "video.fill" : "doc.text").foregroundStyle(fg)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(a.name).bucks(.titleSmall).foregroundStyle(fg).lineLimit(1)
                        Text(humanFileSize(a.size)).bucks(.labelSmall).foregroundStyle(fg.opacity(0.8))
                    }
                }
                .padding(12).background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(fg.opacity(0.12)))
            }.buttonStyle(.plain)
        }
    }
}
