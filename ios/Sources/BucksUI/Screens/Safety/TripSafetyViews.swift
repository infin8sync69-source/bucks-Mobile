import SwiftUI
import BucksCore

// Trip safety (trip_safety.sql, docs/SAFETY.md), the same as Android's ui/safety/TripSafety.kt: the SOS sheet on every trip screen
// (riders and drivers), the live trip link, "Are you OK?", trusted contacts (Account → Safety) and the staff SOS list. SOS works
// without the server too: the phone dials 112 and Messages opens with the location, whether or not Bucks could be reached.

/// One message to several people, written in Messages (the person presses send).
@MainActor func textMany(_ phones: [String], body: String) {
    let to = phones.map { $0.filter { $0.isNumber || $0 == "+" } }.joined(separator: ",")
    let b = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    openSystemURL("sms://open?addresses=\(to)&body=\(b)")
}

/// The live-link text for my trip, or `fallback` without one (offline, demo).
@MainActor func liveTripText(_ taskId: String?, cloud: Bool, fallback: String, text: (String) -> String) async -> String {
    guard cloud, let taskId, let token = try? await Backend.shared.tripShareLink(taskId) else { return fallback }
    return text(TripSafety.tripURL(token))
}

/// "Share trip" that sends the live link (fetched when tapped).
struct LiveShareAction: View {
    let taskId: String?; let cloud: Bool; let fallback: String; let text: (String) -> String
    @State private var item: String?
    var body: some View {
        IconAction("square.and.arrow.up", "Share trip") { Task { item = await liveTripText(taskId, cloud: cloud, fallback: fallback, text: text) } }
            .sheet(item: Binding(get: { item.map(ShareItem.init) }, set: { item = $0?.text })) { s in ShareSheetView(text: s.text) }
    }
}
private struct ShareItem: Identifiable { let text: String; var id: String { text } }
private struct ShareSheetView: View {
    let text: String
    var body: some View {
        VStack(spacing: 16) {
            Text("Share your trip").bucks(.titleMedium)
            Text(text).bucks(.bodyMedium).multilineTextAlignment(.leading)
            ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
        }.padding(24).presentationDetents([.medium])
    }
}

/// The SOS button for a trip screen. `here` is read when it is pressed.
struct SosAction: View {
    let taskId: String?; let here: () -> LatLng?
    @State private var open = false
    var body: some View {
        IconAction("sos", "SOS") { open = true }
            .sheet(isPresented: $open) { SosSheet(taskId: taskId, at: here()) }
    }
}

struct SosSheet: View {
    let taskId: String?; let at: LatLng?
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var result: SosResult?
    @State private var failed = false

    private var message: String {
        if let m = result?.message, !m.isEmpty { return m }
        return "SOS: I need help." + (at.map { " My location: \(TripSafety.mapURL($0))" } ?? "") + " If you can't reach me, call 112."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Get help now").bucks(.headlineSmall).accessibilityAddTraits(.isHeader)
            Text(result != nil ? "Bucks staff have been alerted. Call 112 if you're in danger." : failed ? "Couldn't reach Bucks. Call 112, and text someone you trust." : "Alerting Bucks staff…")
                .bucks(.bodyMedium).foregroundStyle(failed ? BucksColor.bad : BucksColor.onSurfaceVariant)
            Button { dial("112") } label: {
                Text("Call 112").bucks(.titleMedium).frame(maxWidth: .infinity, minHeight: 56)
            }.buttonStyle(.borderedProminent).tint(BucksColor.bad)
            if let c = result?.contacts, !c.isEmpty {
                PrimaryButton("Text my trusted contacts (\(c.count))") { textMany(c.map(\.phone), body: message) }
            } else {
                ShareLink(item: message) { Text("Text someone").frame(maxWidth: .infinity, minHeight: 48) }.buttonStyle(.bordered)
                Muted("Add trusted contacts in Account → Safety, so one tap texts them your trip and location.")
            }
            if result?.shareToken != nil { ShareLink(item: message) { Text("Share live trip link").frame(maxWidth: .infinity, minHeight: 48) }.buttonStyle(.bordered) }
            HStack {
                if let r = result { GhostButton("I'm safe now") { Task { try? await Backend.shared.cancelSos(r.sosId); dismiss() } } }
                Spacer()
                GhostButton("Close") { dismiss() }
            }
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .task {
            guard session.cloud else { failed = true; return }
            do { result = try await Backend.shared.raiseSos(taskId: taskId, at: at) } catch { failed = true }
        }
    }
}

/// "Are you OK?" while a ride is in progress (ride_watch flags long stops, a drift off the route, a silent driver phone).
struct RideCheckCard: View {
    let taskId: String; let here: () -> LatLng?
    @Environment(AppSession.self) private var session
    @State private var alerts: [RideAlert] = []
    @State private var sos = false

    var body: some View {
        Group {
            if let a = alerts.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Are you OK?").bucks(.titleMedium)
                    Text(a.kind == "STOPPED" ? "Your ride has stopped for a while." : a.kind == "OFF_ROUTE" ? "Your ride looks off its route." : "We lost your driver's location.").bucks(.bodyMedium)
                    Text("If you don't answer within 5 minutes, Bucks staff are alerted.").bucks(.bodySmall)
                    HStack(spacing: 10) {
                        Button { Task { try? await Backend.shared.answerRideAlert(taskId, ok: true); alerts = [] } } label: { Text("I'm OK").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                        Button { Task { try? await Backend.shared.answerRideAlert(taskId, ok: false) }; alerts = []; sos = true } label: { Text("SOS").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).tint(BucksColor.bad)
                    }.padding(.top, 4)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(BucksColor.bad.opacity(0.14)))
                .padding(.vertical, 8)
                .accessibilityElement(children: .contain)
            }
        }
        .sheet(isPresented: $sos) { SosSheet(taskId: taskId, at: here()) }
        .task(id: taskId) {
            guard session.cloud else { return }
            while !Task.isCancelled {
                if let a = try? await Backend.shared.myRideAlerts(taskId) { alerts = a }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}

/// Account → Safety: trusted contacts (up to 5) and where to get help.
struct SafetyScreen: View {
    @Environment(Router.self) private var router
    @State private var list: [TrustedContact] = []
    @State private var name = ""
    @State private var phone = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Safety", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Trusted contacts").bucks(.titleMedium).accessibilityAddTraits(.isHeader)
                        Muted("Up to 5 people. SOS and Share trip text them your trip and location from your phone. They don't need Bucks.").padding(.top, 4)
                        ForEach(list) { c in
                            HStack {
                                VStack(alignment: .leading) { Text(c.name).bucks(.titleSmall); Muted(c.phone) }
                                Spacer()
                                Button { Task { try? await Backend.shared.removeTrustedContact(c.id); await reload() } } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("Remove \(c.name)")
                            }.padding(.top, 10)
                        }
                        if list.count >= 5 { Muted("You have 5 trusted contacts.").padding(.top, 10) } else {
                            BucksField(Binding(get: { name }, set: { name = String($0.prefix(60)) }), label: "Name", placeholder: "Name").padding(.top, 14)
                            BucksField(Binding(get: { phone }, set: { phone = String($0.filter { $0.isNumber || $0 == "+" }.prefix(13)) }), label: "Mobile number", placeholder: "98765 43210", keyboard: .phone).padding(.top, 8)
                            if let error { Text(error).bucks(.bodySmall).foregroundStyle(BucksColor.bad).padding(.top, 4) }
                            PrimaryButton(busy ? "Saving…" : "Add a trusted contact", enabled: !busy && !name.trimmingCharacters(in: .whitespaces).isEmpty && phone.filter(\.isNumber).count >= 10) { add() }.padding(.top, 10)
                        }
                        Text("If you're in danger").bucks(.titleMedium).padding(.top, 24).accessibilityAddTraits(.isHeader)
                        Muted("Call 112. Women's helpline 181. Childline 1098. Cyber crime 1930. On a trip, tap SOS: Bucks staff are alerted and you can text your trusted contacts in one tap.").padding(.top, 4)
                    }.padding(Gutter)
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task { await reload() }
    }

    private func reload() async { if let l = try? await Backend.shared.trustedContacts() { list = l } }
    private func add() {
        busy = true; error = nil
        Task {
            do { try await Backend.shared.addTrustedContact(name: name.trimmingCharacters(in: .whitespaces), phone: phone); name = ""; phone = ""; await reload() }
            catch { self.error = "\(error)".components(separatedBy: "\"message\":\"").dropFirst().first?.components(separatedBy: "\"").first ?? "Couldn't save. Check the number." }
            busy = false
        }
    }
}

/// Staff: open SOS alerts, refreshed every 20 seconds.
struct StaffSosScreen: View {
    @Environment(Router.self) private var router
    @State private var rows: [SosQueueRow]?

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "SOS alerts", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let rows, rows.isEmpty { Muted("No open SOS alerts.") }
                        ForEach(rows ?? []) { r in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(r.name ?? "Someone") · \(r.role)").bucks(.titleSmall)
                                Muted([String(r.createdAt.prefix(16)).replacingOccurrences(of: "T", with: " "), r.vehicle, r.otherName.map { "with \($0)" }, r.taskStatus].compactMap { $0 }.joined(separator: " · "))
                                HStack(spacing: 8) {
                                    if let p = r.phone { SmallButton("Call \(r.name?.components(separatedBy: " ").first ?? "them")") { dial(p) } }
                                    if let p = r.otherPhone { SmallButton("Call \(r.otherName?.components(separatedBy: " ").first ?? "other")") { dial(p) } }
                                }
                                HStack(spacing: 8) {
                                    if let l = r.tripLink { SmallButton("Open trip") { openSystemURL(l) } }
                                    if let la = r.lat, let ln = r.lng { SmallButton("Map") { openSystemURL(TripSafety.mapURL(LatLng(lat: la, lng: ln))) } }
                                    SmallButton("Close alert") { Task { try? await Backend.shared.closeSos(r.id, note: "Handled by staff"); rows = try? await Backend.shared.sosQueue() } }
                                }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 16).fill(BucksColor.bad.opacity(0.14)))
                        }
                    }.padding(Gutter)
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task { while !Task.isCancelled { rows = (try? await Backend.shared.sosQueue()) ?? rows ?? []; try? await Task.sleep(nanoseconds: 20_000_000_000) } }
    }
}
