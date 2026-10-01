import SwiftUI
import BucksCore

/// Account tab. Opens on my profile; "Activity" and "Settings" share a tab row. `Router.accountTab` picks which one a link opens.
struct AccountScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.openBucksMenu) private var openMenu
    @State private var tab = "profile"
    @State private var model = AccountModel()

    private let tabs = [("activity", "Activity"), ("settings", "Settings")]

    var body: some View {
        Group {
            if tab == "profile" { AccountProfileView(model: model) }
            else {
                ContentColumn {
                    VStack(spacing: 0) {
                        BucksTopBar(title: "Account", onMenu: openMenu, unread: session.chat.unread, onChat: { router.push(.messages) })
                        tabRow
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if tab == "activity" { AccountActivityTab(model: model) } else { AccountSettingsHub(model: model) }
                            }.padding(Gutter)
                        }
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .bucksBackground().bucksHideNavigationBar()
        .onAppear { tab = router.accountTab }
        .onChange(of: router.accountTab) { _, new in tab = new }
    }

    private var tabRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.0) { key, label in
                    Button { tab = key; router.accountTab = key } label: {
                        VStack(spacing: 0) {
                            Text(label).bucks(.labelLarge).foregroundStyle(tab == key ? BucksColor.primary : BucksColor.onSurfaceVariant)
                                .frame(maxWidth: .infinity, minHeight: 46)
                            Rectangle().fill(tab == key ? BucksColor.primary : .clear).frame(height: 3)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(tab == key ? .isSelected : [])
                }
            }
            BucksDivider()
        }.background(BucksColor.surface)
    }
}

// MARK: Activity

private struct AccountActivityTab: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    let model: AccountModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Rides").padding(.bottom, 4)
            if model.rides.isEmpty { Muted("No rides yet. Tap Taxi in Services when you need to go somewhere.") }
            else {
                ForEach(model.rides) { r in
                    AccountCompactRow(systemImage: VehicleKind(serverValue: r.vehicleKind).systemImage, title: r.dropLabel,
                                      subtitle: "₹\(r.fare) · \(accountRideStatus(r.status))")
                }
            }
            SectionTitle("Orders", action: "See all", onAction: { router.push(.myOrders) }).padding(.top, 20).padding(.bottom, 4)
            if model.orders.isEmpty { Muted("No orders yet. Search for food, groceries or anything nearby.") }
            else {
                ForEach(model.orders.prefix(5)) { o in
                    AccountCompactRow(systemImage: "bag.fill", title: model.titleOf(o.listingId),
                                      subtitle: "₹\(o.subtotal + (o.feePaidBy == "BUYER" ? o.deliveryFee : 0)) · \(accountOrderStatus(o.status, mode: o.deliveryMode))") { router.push(.order(o.id)) }
                }
            }
            SectionTitle("Jobs").padding(.top, 20).padding(.bottom, 4)
            AccountCompactRow(systemImage: "briefcase.fill", title: "My applications", subtitle: "Jobs you applied to and where they stand") { router.push(.myApplications) }
            SectionTitle("Service requests").padding(.top, 20).padding(.bottom, 4)
            Muted("No service requests yet. Search for a plumber, tutor or any skill.")
        }
        .task(id: session.me?.id) { if let id = session.me?.id { await model.loadActivity(me: id) } }
    }
}

// MARK: Settings

private struct AccountSettingsHub: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    let model: AccountModel
    @State private var confirmDelete = false

    private static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Identity").padding(.bottom, 10)
            BucksIdCard(onSync: { router.push(.sync) })
            SectionTitle("Preferences").padding(.top, 22).padding(.bottom, 6)
            AccountSettingRow(icon: "person.fill", label: "Edit profile") { router.push(.editProfile) }
            AccountSettingRow(icon: "arrow.triangle.2.circlepath", label: "Sync", detail: "Requests, people you may know, synced people") { router.push(.sync) }
            AccountSettingRow(icon: "lock.fill", label: "Privacy", detail: "Who can message and sync with you, Moments audience, read receipts") { router.push(.settingsPrivacy) }
            AccountSettingRow(icon: "bell.fill", label: "Notifications", detail: "What Bucks tells you about, and quiet hours") { router.push(.settingsNotifications) }
            AccountSettingRow(icon: "paintpalette.fill", label: "Appearance and data", detail: "Theme, text size, motion, media on mobile data") { router.push(.settingsAppearance) }
            AccountSettingRow(icon: "nosign", label: "Blocked people") { router.push(.settingsBlocked) }
            AccountSettingRow(icon: "heart.fill", label: "Close friends", detail: "Who sees Moments you share with close friends") { router.push(.settingsCloseFriends) }
            if model.isStaff {
                AccountSettingRow(icon: "checklist", label: "Review documents", detail: "Bucks staff: shop and pro documents waiting for a check") { router.push(.staffReview) }
            }
            ListRow("Payment QR", subtitle: "How customers pay you by UPI: rides, deliveries and shop orders", onTap: { router.push(.paymentQr) },
                    leading: { Avatar(systemImage: "qrcode") }, trailing: { Image(systemName: "chevron.right").foregroundStyle(BucksColor.onSurfaceVariant) })
                .padding(.horizontal, -Gutter)
            SectionTitle("Voice and AI").padding(.top, 22).padding(.bottom, 10)
            BucksCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Voice language").font(.bucks(.titleSmall)).foregroundStyle(BucksColor.onSurface)
                    VoiceLanguageChips().padding(.top, 8)
                    BucksDivider().padding(.vertical, 10)
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Cloud understanding").font(.bucks(.titleSmall)).foregroundStyle(BucksColor.onSurface)
                            Muted(IntentRouter().cloudEnabled ? "Free-form commands are understood by Gemini. Only the command text is sent, never PINs, payments or documents." : "Off. The built-in rules work offline.")
                        }
                        Spacer(minLength: 8)
                        Image(systemName: IntentRouter().cloudEnabled ? "icloud.fill" : "icloud.slash").foregroundStyle(BucksColor.onSurfaceVariant)
                    }
                }
            }
            SectionTitle("About").padding(.top, 22).padding(.bottom, 6)
            AccountSettingRow(icon: "arrow.down.app.fill", label: "App version", detail: "Build \(Self.build)", chevron: false) {}
            AccountSettingRow(icon: "hammer.fill", label: "Community rules") {
                session.toast("Review only what you actually ordered or booked. Every review needs a reason. One account per person.")
            }
            SectionTitle("Account").padding(.top, 22).padding(.bottom, 6)
            AccountSettingRow(icon: "rectangle.portrait.and.arrow.right", label: "Log out") { Task { await session.logout() } }
            AccountSettingRow(icon: "trash", label: "Delete account") { confirmDelete = true }
        }
        .task { await model.loadStaff() }
        .bucksConfirm(isPresented: $confirmDelete, title: "Delete your account?",
                      message: "This removes your profile, phone number, payment QR, listings, posts, moments and messages, and your sign-in. Orders and trips stay in the other person's history without your name. It can't be undone.",
                      confirmTitle: "Delete", destructive: true) {
            Task { await session.deleteAccount() }
        }
    }
}
