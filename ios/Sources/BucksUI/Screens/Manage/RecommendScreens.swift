import SwiftUI
import BucksCore

/// The owner's side of the community cap: a QR code that neighbours scan in person. The token behind it lasts 2 minutes on the
/// server, so a new one is fetched every 90 seconds while open; the count refreshes on its own too.
struct RecommendShowScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var store = ManageStore()

    private var listing: ListingRow? { store.listings[id] }
    private var count: Int { store.recommendations[id] ?? 0 }
    private var needed: Int { store.needed }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Get recommended", onBack: { router.pop() })
                ScrollView {
                    VStack(spacing: 0) {
                        Text(listing?.title ?? "Your listing").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).multilineTextAlignment(.center)
                        if let l = listing, l.status == "LIVE" { live(l) } else { waiting }
                    }.padding(Gutter).padding(.bottom, 16)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task {
            await store.loadListing(id)
            while !Task.isCancelled {
                await store.refreshToken(id, toast: session.toast)
                for _ in 0..<9 { // a new code every 90 s; the count every 10 s in between
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if Task.isCancelled { return }
                    await store.refreshCount(id)
                }
            }
        }
        .task { for await _ in Backend.shared.changes(table: "recommendations", filter: "listing_id=eq.\(id)") { await store.refreshCount(id) } }
        .onDisappear { store.clearToken() }
        // Going live here must reach the hub and dashboard too (Android keeps one MyListings).
        .onChange(of: listing?.status) { _, status in if status == "LIVE" { session.listings.refresh() } }
    }

    private func live(_ l: ListingRow) -> some View {
        VStack(spacing: 0) {
            Avatar(systemImage: "checkmark", size: 72).padding(.top, 24)
            Text("You're live").bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 14)
            Muted("\(count) people nearby recommended \(l.title). Customers nearby can find it now. Switch it on from My listings to start taking work.", align: .center).padding(.top, 6)
            SmallButton("Back to my listings") { router.pop() }.padding(.top, 20)
        }
    }

    private var waiting: some View {
        VStack(spacing: 0) {
            Muted("Ask someone nearby to open Bucks and scan this", align: .center).padding(.top, 4).padding(.bottom, 16)
            if let t = store.token { QRBox(text: BucksQr.forRecommendation(t), side: 260, label: "Recommendation QR code", bordered: false) }
            else { BucksLoader().frame(width: 260, height: 260) }
            Text("\(count) of \(needed)").bucks(.headlineMedium).fontWeight(.heavy).foregroundStyle(BucksColor.onSurface).padding(.top, 16)
            Muted(count == 0 ? "No recommendations yet" : "people nearby have recommended you", align: .center)
            ProgressView(value: min(max(Double(count) / Double(max(needed, 1)), 0), 1)).tint(BucksColor.primary).padding(.top, 10)
            Muted("The code changes every 90 seconds. Keep this screen open while they scan; the count updates on its own.", align: .center).padding(.top, 10)
            HStack(spacing: 8) {
                ShareLink(item: "I've listed \(listing?.title ?? "my work") on Bucks and need \(needed) people nearby to recommend it before it goes live. If you live within 3 km and have had Bucks for over 2 weeks, come by and scan the code on my phone: open Bucks, My listings, Recommend a local. Thank you!") {
                    Text("Share how to help").font(.bucks(.labelMedium)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(BucksColor.onPrimary).background(Capsule().fill(BucksColor.primary))
                }.buttonStyle(.plain)
                SmallButton("New code", tonal: true) { Task { await store.refreshToken(id, toast: session.toast) } }
            }.padding(.top, 16)
            SectionTitle("Who can recommend you").padding(.top, 24).padding(.bottom, 4)
            RecommendRules()
            Notice("Ask regular customers and people nearby who know your work. When \(needed) have scanned, the listing goes live on its own and you'll see it under My listings.").padding(.top, 12)
        }
    }
}

/// The neighbour's side: scan the code an owner shows and recommend them, if the server's rules allow.
struct RecommendScanScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var store = ManageStore()
    @State private var result: Int?
    @State private var scanning = false

    // The scanner needs a real location fix: the server's "in person" check compares where the scanner stands with the listing,
    // and the map's default centre would pass it for every listing near it, photo of the code or not.
    private var haveFix: Bool { session.hereKnown }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Recommend a local", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(spacing: 0) {
                            Avatar(systemImage: "qrcode.viewfinder", size: 72)
                            Text("Scan their code").bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 14)
                            Muted("Ask the shop owner, driver or worker to open Get recommended on their phone, then scan the code it shows. Your recommendation helps them go live for everyone nearby.", align: .center).padding(.top, 6)
                        }.frame(maxWidth: .infinity)
                        if !session.locationGranted { Notice("Turn on location for Bucks first. Recommendations only count when you scan in person, near their shop.").padding(.top, 14) }
                        else if !haveFix { Notice("Waiting for your location… The scanner opens once Bucks knows where you are, so the recommendation counts as in person.").padding(.top, 14) }
                        PrimaryButton("Open the scanner", enabled: haveFix) { scan() }.padding(.top, 16)
                        if let n = result { resultCard(n).padding(.top, 14) }
                        SectionTitle("Who can recommend").padding(.top, 24).padding(.bottom, 4)
                        RecommendRules()
                        Notice("Recommend only people whose work you know. One recommendation per listing; it's how your neighbourhood decides who gets listed.").padding(.top, 12)
                    }.padding(Gutter).padding(.bottom, 16)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task { await store.loadNeeded() }
        .manageQrScanner(isPresented: $scanning, onResult: handle, onError: { session.toast($0) })
    }

    private func scan() {
        guard haveFix else { session.toast("Turn on location first. Recommendations only count when you scan in person, near their shop."); return }
        scanning = true
    }

    private func handle(_ raw: String) {
        switch BucksQr.parse(raw) {
        case .recommendation(let token):
            let at = session.here
            Task { if let n = await store.recommend(token: token, lat: at.lat, lng: at.lng, toast: session.toast) { result = n } }
        case .bucksId: session.toast("That's someone's Bucks ID for syncing, not a recommendation code. Ask them to open Get recommended.")
        default: session.toast("That isn't a Bucks recommendation code.")
        }
    }

    private func resultCard(_ n: Int) -> some View {
        BucksCard(tint: true) {
            HStack(spacing: 8) {
                Image(systemName: "hand.thumbsup.fill").foregroundStyle(BucksColor.onPrimaryContainer)
                Text("Thanks, that's \(n) of \(store.needed)").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            }
            Muted(n >= store.needed ? "They're live on Bucks now. Neighbours can find and order from them." : "They need \(store.needed - n) more. Know someone else nearby who rates them? Tell them.").padding(.top, 4)
        }
    }
}
