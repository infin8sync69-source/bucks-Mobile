import SwiftUI
import BucksCore

/// One line of the assistant conversation (AgentMessage on Android); `actions` are suggestion chips that submit as typed text.
public struct AgentMessage: Identifiable, Equatable {
    public let id = UUID()
    public var mine: Bool
    public var text: String
    public var actions: [String] = []
    public init(mine: Bool, text: String, actions: [String] = []) { self.mine = mine; self.text = text; self.actions = actions }
}

/// How the assistant ordered results the last time it was asked to (SortMode on Android).
public enum AssistantSort: String { case trust = "TRUST", near = "NEAR", price = "PRICE"
    public var label: String { switch self { case .trust: "Most recommended"; case .near: "Nearest"; case .price: "Lowest price" } }
}

/// What `submit` did with the text.
public enum AssistantOutcome: Equatable {
    /// Not a command: the caller should run a normal search for this text.
    case search(String)
    /// The assistant answered (the text is also appended to `messages`).
    case replied(AgentMessage)
}

/// Turns typed or spoken text into app actions: BucksViewModel.submitQuery + execute on Android.
/// The intent engine (rules, then optional Gemini) only proposes a tool; this validates it, proposes money-moving steps through the
/// confirmation gate (`session.confirmAction`/`requestRide`) and never books anything itself.
@MainActor @Observable
public final class AssistantRouter {
    public private(set) var thinking = false
    /// The conversation, newest last, capped at 14 lines like Android.
    public private(set) var messages: [AgentMessage] = []
    public var sort: AssistantSort = .trust
    /// What "post a request for …" asked for; the new-post screen can start from it.
    public var postDraft = ""
    public var cloudEnabled: Bool { intents.cloudEnabled }

    private unowned let session: AppSession
    private unowned let router: Router
    private let intents: IntentRouter
    private let openSearch: (String) -> Void

    /// - Parameter onSearch: runs a marketplace search for a term (Home's "Search shops, pros and drivers for …").
    public init(session: AppSession, router: Router, intents: IntentRouter = IntentRouter(), onSearch: @escaping (String) -> Void) {
        self.session = session; self.router = router; self.intents = intents; self.openSearch = onSearch
    }

    public func clear() { messages = [] }

    /// Every typed or spoken command enters here. Plain words that aren't a command are handed back as `.search`.
    @discardableResult
    public func submit(_ raw: String) async -> AssistantOutcome {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return .search("") }
        if !isAgentQuery(q) && session.pendingAction == nil { openSearch(q); return .search(q) }
        append(AgentMessage(mine: true, text: q))
        thinking = true
        let ctx = "user area=\(session.me?.area ?? ""); pending=\(session.pendingAction?.title ?? "none"); online riders=\(session.dispatch.drivers.filter(\.online).count)"
        let intent = await intents.parse(q, context: ctx)
        let (reply, then) = execute(intent, raw: q)
        thinking = false
        append(reply)
        if let then { try? await Task.sleep(nanoseconds: 700_000_000); then() }
        return .replied(reply)
    }

    /// Fire-and-forget form for button handlers.
    public func send(_ raw: String) { Task { await submit(raw) } }

    private func append(_ m: AgentMessage) { messages = Array((messages + [m]).suffix(14)) }

    /// The known place a destination word names: the whole name, or one that contains its first word.
    static func place(named d: String) -> (name: String, at: LatLng)? {
        let head = d.lowercased().components(separatedBy: " ")[0]
        return Geo.places.first { $0.name.caseInsensitiveCompare(d) == .orderedSame || $0.name.lowercased().contains(head) }
    }

    private func execute(_ i: ParsedIntent, raw: String) -> (AgentMessage, (() -> Void)?) {
        let via = i.source == "gemini" ? " (understood by cloud AI)" : ""
        func say(_ t: String, _ actions: [String] = []) -> AgentMessage { AgentMessage(mine: false, text: t, actions: actions) }
        switch i.tool {
        case Tools.confirm:
            guard let p = session.pendingAction else { return (say("Nothing is waiting for confirmation."), nil) }
            if p.needsBiometric { return (say("This one needs your fingerprint or PIN — tap Confirm on the card."), nil) }
            return (say("Confirmed. \(p.title)."), { [session] in session.confirmPendingAction(p) })
        case Tools.cancel:
            session.cancelPendingAction()
            return (say("Cancelled."), nil)
        case Tools.showMap:
            return (say("Opening the ride screen."), { [session, router] in session.cancelPendingAction(); router.push(.chooseRide) })
        case Tools.ride:
            return rideReply(i, via: via)
        case Tools.compare, Tools.search:
            let q = (i.args["query"]).flatMap { $0.isEmpty ? nil : $0 } ?? raw
            let lead = i.tool == Tools.compare ? "Ranked by community trust, then price for" : "Here's who people nearby recommend for"
            return (say("\(lead) “\(q)”:\(via)"), { [openSearch] in openSearch(q) })
        case Tools.sort:
            sort = AssistantSort(rawValue: i.args["by"] ?? "TRUST") ?? .trust
            return (say("Sorted by \(sort.label.lowercased()). Type a search term and I'll show results that way."), nil)
        case Tools.activity:
            return (say("Opening your orders and rides."), { [router] in router.select(.account, accountTab: "activity") })
        case Tools.postRequest:
            let what = (i.args["what"]).flatMap { $0.isEmpty ? nil : $0 } ?? raw
            postDraft = "Looking for \(what) near \(session.me?.area ?? ""). Any recommendations?"
            return (say("Let's post that to your neighbourhood feed."), { [router] in router.push(.createPost) })
        case Tools.goOnline:
            return (say("Putting you online with your checked vehicle."), { [session, router] in router.select(.home); Task { await session.setOnline(true) } })
        case Tools.becomePro:
            return (say("Let's set up your pro profile."), { [router] in router.push(.myListings) })
        default:
            let tries = ["Auto to MG Road", "Order sugar", "Find a doctor", "Compare biriyani", "Show my orders"]
            return cloudEnabled ? (say("I didn't get that. Try 'auto to MG Road', 'order sugar' or 'compare biriyani'.", tries), nil)
                : (say("I didn't get that. Try one of these (add a Gemini key to understand free-form commands):", tries), nil)
        }
    }

    private func rideReply(_ i: ParsedIntent, via: String) -> (AgentMessage, (() -> Void)?) {
        func say(_ t: String, _ actions: [String] = []) -> AgentMessage { AgentMessage(mine: false, text: t, actions: actions) }
        // The model may say anything; only a passenger vehicle is booked, and an unknown word means an auto.
        let kind = VehicleKind(rawValue: i.args["vehicle"] ?? "AUTO").flatMap { $0.carriesPassengers ? $0 : nil } ?? .auto
        session.rideKind = kind
        if session.mockLocation { return (say("Mock location is on, so I can't book a ride. Turn it off in developer settings."), nil) }
        let n = session.onlineCount(kind), noun = "\(kind.label.lowercased()) rider\(n == 1 ? "" : "s")"
        guard let d = i.args["destination"], !d.isEmpty, let p = Self.place(named: d) else {
            return (say("Where to? \(n) \(kind.label.lowercased()) riders are online near you.", Geo.places.prefix(3).map { "\(kind.label) to \($0.name.components(separatedBy: ",")[0])" }), nil)
        }
        session.chooseDestPlace(p.name, at: p.at)
        let km = session.rideDest?.km ?? 0
        session.requestRide()
        return (say("\(n) \(noun) within 5 km. \(kind.label) to \(p.name), about ₹\(session.fare(kind, km: km)), cash or UPI after the trip. Confirm?\(via)", ["Yes, ring them", "Show the map first", "Cancel"]), nil)
    }
}
