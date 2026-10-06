import SwiftUI
import BucksCore

/// A file sent in a chat: its place in the `chat` bucket, name, type and size (the message's `attachment` jsonb).
struct ChatAttachment: Hashable {
    var path: String
    var name: String
    var mime: String
    var size: Int

    init?(_ json: JSONValue?) {
        guard let o = json?.object else { return nil }
        func s(_ k: String) -> String { o[k]?.string ?? o[k]?.number.map { String(Int($0)) } ?? "" }
        path = s("path"); name = s("name"); mime = s("mime"); size = Int(s("size")) ?? 0
    }
    var isImage: Bool { mime.hasPrefix("image/") }
    var isVideo: Bool { mime.hasPrefix("video/") }
}

/// Opens the screen a notification's `route` names (a route Push.safeRoute accepts). Port of the onRoute lambda in BucksAppUi.kt.
enum NotificationRouteOpener {
    @MainActor static func open(_ raw: String, router: Router) {
        guard let r = Push.safeRoute(raw) else { return }
        func tail(_ prefix: String) -> String { String(r.dropFirst(prefix.count)) }
        switch r {
        case "home", "feed": router.popToRoot()
        case "sync": router.push(.sync)
        case "messages": break
        case "invites": router.push(.invites)
        case "my/orders": router.push(.myOrders)
        case "my/applications": router.push(.myApplications)
        case "my/listings": router.push(.myListings)
        case "jobs-near": router.push(.jobsNear)
        case "bucks-id": router.push(.bucksId)
        default:
            if r.hasPrefix("chat/") { router.push(.chat(tail("chat/"))) }
            else if r.hasPrefix("cloud-order/") { router.push(.order(tail("cloud-order/"))) }
            else if r.hasPrefix("orders-for/") { router.push(.vendorOrders(tail("orders-for/"))) }
            else if r.hasPrefix("delivery/") { router.push(.deliveryTrack(tail("delivery/"))) }
            else if r.hasPrefix("moments/") { router.push(.moments(tail("moments/"))) }
            else if r.hasPrefix("l/") { router.push(.listing(tail("l/"))) }
            else if r.hasPrefix("job/") { router.push(.job(tail("job/"))) }
            else if r.hasPrefix("jobs-of/") { router.push(.listingJobs(tail("jobs-of/"))) }
            else if r.hasPrefix("members/") { router.push(.members(tail("members/"))) }
            else if r.hasPrefix("studio/") { router.push(.studio(tail("studio/"))) }
            else if r.hasPrefix("listing-docs/") { router.push(.listingDocs(tail("listing-docs/"))) }
            else if r.hasPrefix("doc-requests/") { router.push(.showcaseDocs(tail("doc-requests/"))) }
            else if r.hasPrefix("post/") { router.push(.post(tail("post/"))) }
        }
    }
}

/// The icon of a notification line, by kind.
func noteSymbol(_ kind: String) -> String {
    switch kind {
    case "SYNC_REQUEST", "SYNC_ACCEPTED": "person.badge.plus"
    case "INVITE": "envelope"
    case "ORDER_NEW", "ORDER_UPDATE": "bag"
    case "RECOMMENDED": "hand.thumbsup"
    case "LISTING_LIVE": "checkmark.seal"
    case "LISTING_PAUSED": "nosign"
    case "DOCUMENT_VERIFIED", "DOCUMENT_REJECTED": "doc.text"
    case "REVIEW": "star"
    default: "bell"
    }
}

/// A search box with a magnifier and a clear button (OutlinedTextField with leading and trailing icons).
struct ChatSearchField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(BucksColor.onSurfaceVariant)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(BucksColor.onSurfaceVariant))
                .textFieldStyle(.plain).font(.bucks(.bodyLarge)).foregroundStyle(BucksColor.onSurface).focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 32, height: 32) }
                    .buttonStyle(.plain).accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surface))
        .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(focused ? BucksColor.primary : BucksColor.outline, lineWidth: focused ? 2 : 1))
    }
}

/// A round checkbox-style mark for pick lists.
struct ChatCheckmark: View {
    let on: Bool
    var body: some View {
        Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 22))
            .foregroundStyle(on ? BucksColor.primary : BucksColor.onSurfaceVariant).accessibilityHidden(true)
    }
}

/// Pick synced people by name: a search box, then a checklist. Shared by New group and Add people.
struct PeoplePicker: View {
    let people: [ProfileRow]
    let selected: Set<String>
    let onToggle: (String) -> Void
    let emptyText: String
    @State private var q = ""

    private var shown: [ProfileRow] {
        let t = q.trimmingCharacters(in: .whitespaces)
        return people.filter { t.isEmpty || $0.name.localizedCaseInsensitiveContains(t) || $0.area.localizedCaseInsensitiveContains(t) || $0.shortCode.localizedCaseInsensitiveContains(t.replacingOccurrences(of: " ", with: "")) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatSearchField(text: $q, placeholder: "Search by name or Bucks ID").padding(.horizontal, Gutter)
            if !selected.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(people.filter { selected.contains($0.id) }) { p in
                            BucksChip(p.name.components(separatedBy: " ")[0], selected: true, systemImage: "xmark") { onToggle(p.id) }
                        }
                    }.padding(.horizontal, Gutter).padding(.vertical, 8)
                }
            }
            if people.isEmpty { Muted(emptyText).padding(Gutter) }
            else if shown.isEmpty { Muted("No one synced with you matches \"\(q.trimmingCharacters(in: .whitespaces))\".").padding(Gutter) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { p in
                        ListRow(p.name, subtitle: p.area.isEmpty ? BucksIdCode.pretty(p.shortCode) : p.area, onTap: { onToggle(p.id) },
                                leading: { Avatar(initials: initials(p.name), size: 40) }, trailing: { ChatCheckmark(on: selected.contains(p.id)) })
                        BucksDivider()
                    }
                }
            }.padding(.top, 4)
        }
    }
}
