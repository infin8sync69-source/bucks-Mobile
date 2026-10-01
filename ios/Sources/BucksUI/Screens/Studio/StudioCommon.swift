import SwiftUI
import BucksCore

// Shared widgets of the Studio and Manage screens (ports of ManageCommon.kt, StudioCommon.kt and the helpers in ListingScreens.kt).

/// Back arrow over a large title (Android `PageHeader`).
struct PageHeader: View {
    let title: String
    let onBack: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Back")
            Text(title).bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface).padding(.leading, 12).padding(.top, 6).padding(.bottom, 16)
        }
        .padding(.leading, 8).padding(.trailing, 20).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A square with an outline and a tinted icon (Android `ListingThumb`).
struct ListingThumb: View {
    let systemImage: String
    var size: CGFloat = 56
    var body: some View {
        Image(systemName: systemImage).font(.system(size: size * 0.5)).foregroundStyle(BucksColor.primary)
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
    }
}

/// A public-bucket photo URL (listing-media), cropped to fill.
struct StudioRemoteImage: View {
    let url: String
    var body: some View {
        ZStack {
            BucksColor.surfaceContainer
            if let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: Image(systemName: "photo").foregroundStyle(BucksColor.onSurfaceVariant)
                    default: ProgressView().controlSize(.small)
                    }
                }
            }
        }.clipped()
    }
}

/// A picked photo before it is uploaded.
struct StudioPickedImage: View {
    let picked: Picked
    var body: some View {
        ZStack {
            BucksColor.surfaceContainer
            if let img = StudioPhoto.image(picked) { img.resizable().scaledToFill() } else { Image(systemName: "photo").foregroundStyle(BucksColor.onSurfaceVariant) }
        }.clipped()
    }
}

/// A photo from a public bucket, or an icon on a tinted square when there is none.
struct PhotoOrIcon: View {
    let url: String?
    let systemImage: String
    var size: CGFloat = 56
    var radius: CGFloat = BucksRadius.medium
    var body: some View {
        Group {
            if let url, !url.isEmpty { StudioRemoteImage(url: url) }
            else { BucksColor.primaryContainer.overlay(Image(systemName: systemImage).font(.system(size: size * 0.5)).foregroundStyle(BucksColor.onPrimaryContainer)) }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A listing's cover: its photo, or a soft brand gradient with the kind's icon when it has none.
struct ListingCover: View {
    let listing: ListingRow
    let height: CGFloat
    var body: some View {
        let photo = (listing.photoUrl ?? "").isEmpty ? listing.gallery.first?.url : listing.photoUrl
        Group {
            if let photo { StudioRemoteImage(url: photo) }
            else {
                LinearGradient(colors: [BucksColor.primaryContainer, BucksColor.surfaceContainerHigh], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: Studio.icon(listing)).font(.system(size: 40)).foregroundStyle(BucksColor.onPrimaryContainer))
            }
        }
        .frame(maxWidth: .infinity).frame(height: height).clipped()
    }
}

/// Status pill used on cards and the dashboard.
struct ListingStatusPill: View {
    let listing: ListingRow
    let recs: Int
    @Environment(AppSession.self) private var session
    var body: some View {
        switch listing.status {
        case "LIVE":
            if listing.online { PillGood(listing.kind == "ASSET" ? "Live · available" : "Live · \(Studio.onlineLabel(listing.kind, true).lowercased())") }
            else { PillGrey("Live · \(Studio.onlineLabel(listing.kind, false).lowercased())") }
        case "SUSPENDED": PillBad(listing.complianceHold ? "Paused: documents" : "Suspended")
        default: PillWarn("Not live · \(recs) of \(session.listings.needed) recommendations")
        }
    }
}

/// A labelled switch row used in the edit forms.
struct SwitchRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface)
                if let detail { Muted(detail) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: $isOn).labelsHidden().tint(BucksColor.primary)
        }.padding(.vertical, 6)
    }
}

/// A short explanation with a title and an icon, for empty states and rules.
struct InfoRow: View {
    let systemImage: String, title: String, detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(systemImage: systemImage, size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                Muted(detail)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 8)
    }
}

struct CenteredLoading: View {
    var body: some View { BucksLoader().frame(maxWidth: .infinity).padding(40) }
}

/// The hub could not load (no network, expired session): say so and offer a retry, never an empty state that invites a duplicate listing.
struct ListingsLoadError: View {
    let message: String
    let retry: () -> Void
    var body: some View { LoadError(message, title: "Couldn't load your listings", retry: retry) }
}

/// Current photo (or the newly picked one) with Add / Change / Remove.
struct PhotoField: View {
    let label: String
    let url: String?
    let preview: Picked?
    let systemImage: String
    let onPick: () -> Void
    var onClear: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(label)
            HStack(spacing: 14) {
                Button(action: onPick) {
                    Group {
                        if let preview { StudioPickedImage(picked: preview) }
                        else if let url, !url.isEmpty { StudioRemoteImage(url: url) }
                        else { BucksColor.surfaceContainerHigh.overlay(Image(systemName: systemImage).font(.system(size: 30)).foregroundStyle(BucksColor.onSurfaceVariant)) }
                    }.frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous))
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    SmallButton(preview == nil && (url ?? "").isEmpty ? "Add photo" : "Change photo", tonal: true, action: onPick)
                    if preview != nil, let onClear {
                        Button("Remove", action: onClear).buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary)
                    }
                }
                Spacer(minLength: 0)
            }
        }.padding(.bottom, 14)
    }
}

/// The rows' tab strip: scrolls sideways, an underline under the selected tab (Android `ScrollableTabRow`).
struct StudioScrollTabs<ID: Hashable>: View {
    let tabs: [(id: ID, label: String)]
    @Binding var selected: ID
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { _, t in
                        Button { selected = t.id } label: {
                            Text(t.label).bucks(.labelLarge).foregroundStyle(selected == t.id ? BucksColor.primary : BucksColor.onSurfaceVariant)
                                .padding(.horizontal, 16).frame(height: 48)
                                .overlay(alignment: .bottom) { if selected == t.id { Rectangle().fill(BucksColor.primary).frame(height: 2) } }
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, Gutter - 16)
            }
            BucksDivider()
        }.background(BucksColor.surface)
    }
}

/// A thin determinate bar (Android `LinearProgressIndicator(progress)`).
struct StudioProgress: View {
    let value: Double
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(BucksColor.primaryContainer)
                Capsule().fill(BucksColor.primary).frame(width: g.size.width * min(1, max(0, value)))
            }
        }.frame(height: height)
    }
}

/// An indeterminate bar for work in flight.
struct StudioBusyBar: View {
    var body: some View { ProgressView().progressViewStyle(.linear).tint(BucksColor.primary) }
}

/// One step of the go-live checklist: a tick, a clock or an empty circle with the step, and its action.
struct GoLiveRow: View {
    let step: GoLiveStep
    let onAction: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: step.done ? "checkmark" : step.waiting ? "clock" : "circle").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(step.done ? BucksColor.good : step.waiting ? BucksColor.warn : BucksColor.onSurfaceVariant)
                .frame(width: 28, height: 28).background(Circle().fill(step.done ? BucksColor.goodTint : step.waiting ? BucksColor.warnTint : BucksColor.surfaceContainerHigh))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(step.title).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    if step.required && !step.done { PillPurple("Needed to go live").fixedSize() }
                }
                Muted(step.detail)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !step.done, let action = step.action { SmallButton(action, tonal: true, action: onAction) }
        }.padding(.vertical, 8)
    }
}

/// Number over a label on a tinted tile.
struct StatTile: View {
    let value: String, label: String
    var body: some View {
        VStack(spacing: 0) {
            Text(value).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
            Muted(label, align: .center, maxLines: 1)
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surfaceContainer))
    }
}

/// Card from the manage listings design: thumbnail and details, an optional pill, and a switch / Edit row (Android `ListingCard`).
struct ListingCard<Thumb: View, Details: View>: View {
    let title: String
    var pill: String?
    var online: Binding<Bool>?
    let onEdit: () -> Void
    let thumb: Thumb
    let details: Details
    init(title: String, pill: String? = nil, online: Binding<Bool>? = nil, onEdit: @escaping () -> Void, @ViewBuilder thumb: () -> Thumb, @ViewBuilder details: () -> Details) {
        self.title = title; self.pill = pill; self.online = online; self.onEdit = onEdit; self.thumb = thumb(); self.details = details()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                thumb
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                    details
                }.padding(.top, 4).frame(maxWidth: .infinity, alignment: .leading)
                if let pill { BrandPill(pill) }
            }
            HStack(alignment: .bottom) {
                if let online { VStack(alignment: .leading, spacing: 0) { ListingSwitch(online); Muted(online.wrappedValue ? "Go offline" : "Go online") } }
                Spacer(minLength: 0)
                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil").font(.system(size: 14)); Text("Edit").bucks(.labelLarge)
                    }.foregroundStyle(BucksColor.onSurfaceVariant).padding(6)
                }.buttonStyle(.plain)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surface))
        .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
    }
}

/// A switch bound to a value that is saved elsewhere: shows `value`, reports a change through `onChange`.
func studioSwitchBinding(_ value: Bool, _ onChange: @escaping (Bool) -> Void) -> Binding<Bool> {
    Binding(get: { value }, set: { onChange($0) })
}

extension View {
    /// A confirmation alert for the item bound to `item` (set it to ask, it clears on dismissal); `onConfirm` gets the item that was asked about.
    func studioConfirm<T>(_ item: Binding<T?>, title: @escaping (T) -> String, message: @escaping (T) -> String, confirm: String, onConfirm: @escaping (T) -> Void) -> some View {
        alert(item.wrappedValue.map(title) ?? "", isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }), presenting: item.wrappedValue) { v in
            Button("Cancel", role: .cancel) {}
            Button(confirm, role: .destructive) { onConfirm(v) }
        } message: { v in Text(message(v)) }
    }
}
