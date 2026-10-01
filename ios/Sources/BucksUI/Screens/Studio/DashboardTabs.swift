import SwiftUI
import BucksCore

// The Products / Photos / Feed / Reviews tabs of a listing's dashboard (ListingDashboardScreen.kt).

// MARK: Products / services

struct ItemsTab: View {
    let m: ListingsStore
    let l: ListingRow
    @Environment(Router.self) private var router
    @State private var q = ""
    @State private var group: String?
    @State private var deleting: ItemRow?

    var body: some View {
        let service = l.kind == "SKILL", noun = service ? "service" : "product"
        let rows = m.items[l.id]
        let groups = Array(Set((rows ?? []).map { $0.groupName.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        let shown = (rows ?? []).filter { r in
            (q.trimmingCharacters(in: .whitespaces).isEmpty || r.name.localizedCaseInsensitiveContains(q.trimmingCharacters(in: .whitespaces))) && (group == nil || r.groupName.trimmingCharacters(in: .whitespaces) == group)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    PrimaryButton("Add \(noun)") { router.push(.itemEdit(listing: l.id, item: "new")) }
                    if (rows ?? []).count > 6 { BucksField($q, placeholder: "Search your \(noun)s").padding(.top, 12) }
                    if groups.count > 1 { ChipRow(["All"] + groups, selected: group ?? "All") { group = $0 == "All" ? nil : $0 }.padding(.top, 4) }
                    if let rows, !rows.isEmpty { Muted("\(rows.count) \(noun)s · \(rows.filter(\.inStock).count) \(service ? "available" : "in stock")").padding(.top, 8) }
                }.padding(.horizontal, Gutter).padding(.vertical, 12)
                if rows == nil { CenteredLoading() }
                else if rows?.isEmpty == true {
                    BucksCard {
                        Text("No \(noun)s yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted(service ? "Add each service with its price, like \"Tap repair · ₹300 per visit\" or \"Logo design · ₹4,000\". People request straight from this list."
                                      : "Add what you sell with a price, photos and pack size, like \"Sona masoori rice · ₹62 · 1 kg\". Count stock if you want Bucks to stop orders when you run out.").padding(.top, 4)
                    }.padding(.horizontal, Gutter)
                } else if shown.isEmpty { Muted("Nothing matches.").padding(Gutter) }
                else {
                    ForEach(shown, id: \.id) { row in
                        ItemManageRow(m: m, row: row, service: service, onEdit: { router.push(.itemEdit(listing: l.id, item: row.id)) }, onDelete: { deleting = row })
                        BucksDivider()
                    }
                }
            }.padding(.bottom, 24)
        }
        .studioConfirm($deleting, title: { "Remove \($0.name)?" }, message: { _ in "It disappears from your profile and search. Orders already placed aren't affected." }, confirm: "Remove") { r in m.deleteItem(r) {} }
    }
}

private struct ItemManageRow: View {
    let m: ListingsStore
    let row: ItemRow
    let service: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PhotoOrIcon(url: row.photos.first?.url ?? row.photoUrl, systemImage: service ? "wrench.and.screwdriver.fill" : "bag.fill", size: 56)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(2)
                HStack(spacing: 6) {
                    Text(Studio.rupees(row.price)).font(.bucks(.bodyMedium).weight(.semibold)).foregroundStyle(BucksColor.onSurface)
                    if let mrp = row.mrp, mrp > row.price { Text(Studio.rupees(mrp)).font(.bucks(.labelSmall)).strikethrough().foregroundStyle(BucksColor.onSurfaceVariant) }
                    if !row.unit.isEmpty { Muted(row.unit, maxLines: 1) }
                }
                Muted([row.groupName.isEmpty ? nil : row.groupName, row.stock.map { $0 == 0 ? "Sold out" : "\($0) left" }, row.photos.count > 1 ? "\(row.photos.count) photos" : nil].compactMap { $0 }.joined(separator: " · "), maxLines: 1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: studioSwitchBinding(row.inStock) { m.setInStock(row, $0) }).labelsHidden().tint(BucksColor.primary)
            Menu {
                Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                Button { m.duplicateItem(row) } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                Button(role: .destructive, action: onDelete) { Label("Remove", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18)).foregroundStyle(BucksColor.onSurface).frame(width: 40, height: 40).contentShape(Rectangle())
            }.menuIndicator(.hidden).buttonStyle(.plain).accessibilityLabel("More")
        }
        .padding(.horizontal, Gutter).padding(.vertical, 10).contentShape(Rectangle()).onTapGesture(perform: onEdit)
    }
}

// MARK: Photos / portfolio

private struct OpenPhoto: Identifiable { let photo: MediaPhoto; var id: String { photo.url } }

struct PhotosTab: View {
    let m: ListingsStore
    let l: ListingRow
    @Environment(AppSession.self) private var session
    @State private var picking = false
    @State private var open: OpenPhoto?

    var body: some View {
        let g = l.gallery
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(l.kind == "SKILL" ? "Portfolio" : "Photos").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted(intro + " \(g.count) of 20.")
                    if m.busy { StudioBusyBar().padding(.top, 8) }
                }.padding(.bottom, 6)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                    if g.count < 20 {
                        Button { picking = true } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "camera.fill").foregroundStyle(BucksColor.primary); Text("Add photos").font(.bucks(.labelMedium)).foregroundStyle(BucksColor.onSurface)
                            }
                            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(m.busy)
                    }
                    ForEach(g, id: \.url) { p in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                            .overlay { StudioRemoteImage(url: p.url) }
                            .overlay(alignment: .topLeading) { if p.url == l.photoUrl { Pill("Cover", bg: BucksColor.primary, fg: BucksColor.onPrimary).padding(6) } }
                            .overlay(alignment: .bottom) {
                                if !p.caption.isEmpty {
                                    Text(p.caption).font(.bucks(.labelSmall)).foregroundStyle(.white).lineLimit(1).padding(.horizontal, 6).padding(.vertical, 3)
                                        .frame(maxWidth: .infinity, alignment: .leading).background(Color.black.opacity(0.45))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous))
                            .contentShape(Rectangle()).onTapGesture { open = OpenPhoto(photo: p) }
                    }
                }
            }.padding(Gutter)
        }
        .bucksPhotoPicker(isPresented: $picking, maxCount: 10) { files in
            let picked = files.compactMap(StudioPhoto.asListingPhoto)
            if !files.isEmpty && picked.isEmpty { session.toast("Couldn't read those images. Try JPG or PNG photos.") }
            if !picked.isEmpty { m.addGalleryPhotos(l.id, picked) }
        }
        .sheet(item: $open) { o in PhotoSheet(m: m, l: l, photo: o.photo) { open = nil }.presentationDetents([.large]).presentationDragIndicator(.visible) }
    }

    private var intro: String {
        switch l.kind {
        case "SKILL": "Photos of work you've done, with a line about each. Customers see them on your profile."
        case "ASSET": "Every room or angle, in daylight. The cover is the first thing people see."
        default: "The shop front, the inside, your best products. Tap a photo to caption it, reorder it or make it the cover."
        }
    }
}

private struct PhotoSheet: View {
    let m: ListingsStore
    let l: ListingRow
    let photo: MediaPhoto
    let close: () -> Void
    @State private var caption: String
    @State private var confirm = false

    init(m: ListingsStore, l: ListingRow, photo: MediaPhoto, close: @escaping () -> Void) {
        self.m = m; self.l = l; self.photo = photo; self.close = close; _caption = State(initialValue: photo.caption)
    }

    var body: some View {
        let i = l.gallery.firstIndex { $0.url == photo.url } ?? -1
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StudioRemoteImage(url: photo.url).frame(maxWidth: .infinity).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous))
                BucksField(Binding(get: { caption }, set: { caption = String($0.prefix(200)) }), label: l.kind == "SKILL" ? "What was the job?" : "Caption",
                           placeholder: l.kind == "SKILL" ? "Bathroom re-tiling, Koramangala" : "Optional").padding(.top, 12)
                PrimaryButton("Save caption", enabled: caption.trimmingCharacters(in: .whitespaces) != photo.caption) { m.setCaption(l.id, url: photo.url, caption: caption); close() }
                HStack(spacing: 8) {
                    SmallButton("Make cover", tonal: true, enabled: photo.url != l.photoUrl) { m.setCover(l.id, url: photo.url); close() }.frame(maxWidth: .infinity)
                    Button { m.moveGalleryPhoto(l.id, url: photo.url, by: -1); close() } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(i > 0 ? BucksColor.onSurface : BucksColor.onSurfaceVariant.opacity(0.4)).disabled(!(i > 0)).accessibilityLabel("Move earlier")
                    Button { m.moveGalleryPhoto(l.id, url: photo.url, by: 1); close() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(i >= 0 && i < l.gallery.count - 1 ? BucksColor.onSurface : BucksColor.onSurfaceVariant.opacity(0.4)).disabled(!(i >= 0 && i < l.gallery.count - 1)).accessibilityLabel("Move later")
                }.padding(.top, 8)
                BadButton("Remove photo") { confirm = true }.padding(.top, 4)
            }.padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28)
        }
        .background(BucksColor.surface)
        .bucksConfirm(isPresented: $confirm, title: "Remove this photo?", message: photo.url == l.photoUrl ? "It stays as the cover until you pick another." : "It's deleted from your listing.", confirmTitle: "Remove", destructive: true) {
            m.removeGalleryPhoto(l.id, url: photo.url); close()
        }
    }
}

// MARK: Feed

struct FeedManageTab: View {
    let m: ListingsStore
    let l: ListingRow
    @Environment(AppSession.self) private var session
    @State private var text = ""
    @State private var photo: Picked?
    @State private var picking = false
    @State private var deleting: PostRow?

    var body: some View {
        let posts = m.posts[l.id]
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                BucksCard {
                    Text("Post as \(l.title)").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted("Offers, new stock, finished work. People nearby and everyone synced with you see it in their feed.").padding(.bottom, 8)
                    BucksField(Binding(get: { text }, set: { text = String($0.prefix(1000)) }), placeholder: l.kind == "SKILL" ? "Just finished a kitchen rewiring in Jayanagar…" : "Fresh stock in today…", singleLine: false, minLines: 3)
                    HStack {
                        if let photo {
                            StudioPickedImage(picked: photo).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { self.photo = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(Circle().fill(Color.black.opacity(0.5))) }
                                        .buttonStyle(.plain).accessibilityLabel("Remove photo")
                                }
                        } else { SmallButton("Add photo", tonal: true) { picking = true } }
                        Spacer(minLength: 0)
                        SmallButton(m.busy ? "Posting…" : "Post", enabled: !m.busy && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photo != nil)) {
                            m.postAs(l.id, body: text, photo: photo) { text = ""; photo = nil }
                        }
                    }
                }.padding(Gutter)
                if posts == nil { CenteredLoading() }
                else if posts?.isEmpty == true { Muted("Nothing posted yet. Your first post shows here and on your profile.").padding(.horizontal, Gutter) }
                else {
                    ForEach(posts ?? []) { p in
                        postRow(p)
                        BucksDivider()
                    }
                }
            }.padding(.bottom, 24)
        }
        .task(id: l.id) { m.loadPosts(l.id) }
        .bucksPhotoPicker(isPresented: $picking, maxCount: 1) { files in
            guard let first = files.first else { return }
            if let ok = StudioPhoto.asListingPhoto(first) { photo = ok } else { session.toast("Couldn't read that image. Try a JPG or PNG photo.") }
        }
        .studioConfirm($deleting, title: { _ in "Delete this post?" }, message: { _ in "It leaves your profile and everyone's feed." }, confirm: "Delete") { m.deletePost($0) }
    }

    private func postRow(_ p: PostRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                let by = m.nameOf(p.authorId)
                Muted([Studio.ago(p.createdAt), by == "…" ? nil : "by \(by)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                Button { deleting = p } label: { Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 40, height: 40).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Delete post")
            }
            if !p.body.isEmpty { Text(p.body).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface) }
            if let path = p.media.first?["path"]?.string, !path.isEmpty {
                SignedImage(bucket: "posts", path: path).frame(maxWidth: .infinity).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous)).padding(.top, 8)
            }
            Muted("\(p.up) up · \(p.down) down · \(p.comments) comments").padding(.top, 6)
        }.padding(.horizontal, Gutter).padding(.vertical, 12)
    }
}

// MARK: Reviews and recommendations

struct ReviewsManageTab: View {
    let m: ListingsStore
    let l: ListingRow

    var body: some View {
        let rows = m.reviews[l.id], recs = m.recommendations[l.id] ?? 0
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    StatTile(value: Studio.trustPct(l.trustUp, l.trustDown), label: "Positive")
                    StatTile(value: "\(l.trustUp)", label: "Recommend")
                    StatTile(value: "\(l.trustDown)", label: "Don't")
                }
                BucksCard(tint: true) {
                    Text("\(recs) \(recs == 1 ? "person" : "people") nearby recommended you in person").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    Muted(l.status == "PENDING" ? "\(max(0, m.needed - recs)) more take you live. Show your code to people who know your work." : "Recommendations are how you went live. Reviews below come from completed orders and trips.")
                }
                Notice("Reviews come only from customers after a completed order, visit or trip. Nobody can add or remove them by hand, including you.")
                if rows == nil { CenteredLoading() }
                else if rows?.isEmpty == true { Muted("No reviews yet. They arrive as customers complete orders and trips with you.") }
                else {
                    ForEach(rows ?? []) { r in
                        let up = r.vote > 0
                        HStack(alignment: .top, spacing: 12) {
                            Avatar(initials: initials(m.nameOf(r.authorId)), size: 40)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(m.nameOf(r.authorId)).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                                Muted(Studio.ago(r.createdAt))
                                Text(r.comment).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 4)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: up ? "hand.thumbsup.fill" : "arrow.down").foregroundStyle(up ? BucksColor.good : BucksColor.bad)
                                .accessibilityLabel(up ? "Recommends" : "Doesn't recommend")
                        }
                    }
                }
            }.padding(Gutter)
        }
        .task(id: l.id) { m.loadReviews(l.id); m.loadCounts(l.id) }
    }
}
