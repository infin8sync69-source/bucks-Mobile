import Foundation

// Port of ai/Intent.kt's rule engine. Android also runs an on-device model (FunctionGemma via LiteRT-LM) as Tier 1; iOS stays on the
// rules until LiteRT-LM's Swift API is stable (docs/PARITY.md). Engines only propose; the app validates.

/// One tool call the assistant wants to make.
public struct ParsedIntent: Equatable, Sendable {
    public var tool: String
    public var args: [String: String]
    public var confidence: Float
    public var source: String
    public init(tool: String, args: [String: String] = [:], confidence: Float = 1, source: String = "rules") {
        self.tool = tool; self.args = args; self.confidence = confidence; self.source = source
    }
}

/// The single tool catalogue every intent engine must produce.
public enum Tools {
    public static let ride = "request_ride", search = "search_marketplace", compare = "compare", sort = "sort_results"
    public static let activity = "show_activity", postRequest = "post_request", goOnline = "go_online", becomePro = "become_provider"
    public static let confirm = "confirm_pending", showMap = "show_map", cancel = "cancel_pending", help = "help"
    public static let all: Set<String> = [ride, search, compare, sort, activity, postRequest, goOnline, becomePro, confirm, showMap, cancel, help]
    /// JSON schema handed to the cloud model; keep in sync with the constants above.
    public static let schema = """
    {"tools":[
      {"name":"\(ride)","description":"Book a ride","args":{"vehicle":"BIKE|AUTO|CAB","destination":"place name or empty"}},
      {"name":"\(search)","description":"Find providers, shops, food or skilled people","args":{"query":"free text, e.g. sugar, plumber, biriyani"}},
      {"name":"\(compare)","description":"Compare providers for something","args":{"query":"free text"}},
      {"name":"\(sort)","description":"Change result ordering","args":{"by":"TRUST|NEAR|PRICE"}},
      {"name":"\(activity)","description":"Show my rides, orders and requests","args":{}},
      {"name":"\(postRequest)","description":"Ask the community for something not listed","args":{"what":"free text"}},
      {"name":"\(goOnline)","description":"Driver goes online","args":{}},
      {"name":"\(becomePro)","description":"Start provider onboarding","args":{}},
      {"name":"\(confirm)","description":"User confirms the pending action","args":{}},
      {"name":"\(cancel)","description":"User cancels the pending action","args":{}},
      {"name":"\(help)","description":"Anything else","args":{}}
    ]}
    """
}

/// The places the grammar and the cloud prompt know by name (Seed.PLACES on Android).
public enum IntentPlaces {
    public static let all = Geo.places.map(\.name)
}

public protocol IntentEngine: Sendable {
    func parse(_ text: String, context: String) async -> ParsedIntent?
}

private func rx(_ pattern: String) -> NSRegularExpression {
    // Patterns below are constants, so a failure here is a programming error caught by the tests.
    // swiftlint:disable:next force_try
    try! NSRegularExpression(pattern: pattern)
}
private extension NSRegularExpression {
    func matches(_ s: String) -> Bool { firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
    func removing(from s: String) -> String { stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "") }
}

/// Tier 0: deterministic grammar. Free, instant, offline; handles the common phrasings.
public struct RuleIntentEngine: IntentEngine {
    public init() {}

    private static let yes = rx("^(yes|confirm|ok|okay|book it|go ahead|haan|sari|yes, ring them)\\b")
    private static let no = rx("^(no|cancel|stop|nahi|beda|never mind)\\b")
    private static let bike = rx("\\b(bike|scooter|scooty|two wheeler)\\b")
    private static let auto = rx("\\b(auto|rickshaw)\\b")
    private static let cab = rx("\\b(cab|taxi|car)\\b")
    private static let rideWords = rx("\\b(ride|drop me|take me|pick me)\\b")
    private static let compareWords = rx("\\b(compare|cheapest|best|which is better)\\b")
    private static let compareNoise = rx("\\b(compare|cheapest|best|which is better|for|the|near me|me)\\b")
    private static let price = rx("price|cheap"), near = rx("near|close|distance")
    private static let activityWords = rx("\\b(my orders|my rides|my requests|history|activity)\\b")
    private static let postPrefix = try? NSRegularExpression(pattern: "post a request for", options: [.caseInsensitive])
    private static let onlineWords = rx("\\b(go online|start duty|i'm online)\\b")
    private static let proWords = rx("\\b(become|provider|pro profile|add (my )?(vehicle|skill|business)|earn)\\b")
    private static let fillers = rx("\\b(order|find|get|book|need|want|i|a|an|some|near|nearby|please|me|the|for)\\b")

    /// The first known place whose first word appears in the (lower-cased) command.
    static func placeIn(_ l: String) -> String? {
        IntentPlaces.all.first { p in
            let head = p.components(separatedBy: ",")[0].lowercased().components(separatedBy: " ")[0]
            return l.contains(head)
        }
    }

    public func parse(_ text: String, context: String) async -> ParsedIntent? { Self.parseNow(text) }

    /// Synchronous form of `parse`, used by the tests and by anything that needs the answer immediately.
    public static func parseNow(_ text: String) -> ParsedIntent? {
        let l = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if l.isEmpty { return nil }
        if yes.matches(l) { return ParsedIntent(tool: Tools.confirm) }
        if no.matches(l) { return ParsedIntent(tool: Tools.cancel) }
        if l.contains("show the map") { return ParsedIntent(tool: Tools.showMap) }
        let kind: VehicleKind? = bike.matches(l) ? .bike : auto.matches(l) ? .auto : cab.matches(l) ? .cab : nil
        if kind != nil || rideWords.matches(l) {
            return ParsedIntent(tool: Tools.ride, args: ["vehicle": (kind ?? .auto).rawValue, "destination": placeIn(l) ?? ""])
        }
        if compareWords.matches(l) {
            return ParsedIntent(tool: Tools.compare, args: ["query": compareNoise.removing(from: l).trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        if l.hasPrefix("sort") {
            return ParsedIntent(tool: Tools.sort, args: ["by": price.matches(l) ? "PRICE" : near.matches(l) ? "NEAR" : "TRUST"])
        }
        if activityWords.matches(l) { return ParsedIntent(tool: Tools.activity) }
        if l.hasPrefix("post a request") {
            let what = postPrefix?.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "") ?? text
            return ParsedIntent(tool: Tools.postRequest, args: ["what": what.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        if onlineWords.matches(l) { return ParsedIntent(tool: Tools.goOnline) }
        if proWords.matches(l) { return ParsedIntent(tool: Tools.becomePro) }
        let q = fillers.removing(from: l).trimmingCharacters(in: .whitespacesAndNewlines)
        return q.count >= 3 ? ParsedIntent(tool: Tools.search, args: ["query": q], confidence: 0.6) : nil
    }
}

/// The rules alone (Android puts its on-device model between the rules and help).
public struct IntentRouter: Sendable {
    private let rules: any IntentEngine
    public init(rules: any IntentEngine = RuleIntentEngine()) { self.rules = rules }
    public func parse(_ text: String, context: String) async -> ParsedIntent {
        await rules.parse(text, context: context) ?? ParsedIntent(tool: Tools.help)
    }
}

/// Typed or spoken text that should go to the assistant rather than straight to search (BucksViewModel.isAgentQuery).
public func isAgentQuery(_ q: String) -> Bool {
    let l = q.lowercased()
    let r = rx("\\b(bike|scooter|taxi|cab|auto|ride|car|compare|cheapest|best|sort|my orders|my rides|history|post a request|go online|become|provider|pro profile|yes|confirm|cancel|show the map|book|take me|drop me)\\b")
    return r.matches(l)
}

/// A money-moving step the person confirms before it runs (PendingAction in Models.kt). The assistant can only propose one of these.
public struct PendingAction: Identifiable {
    public let id: UUID
    public var title: String
    public var summary: String
    public var amount: Int
    public var counterparty: String
    public var counterpartyTrust: Trust?
    public var needsBiometric: Bool
    public var run: @MainActor () -> Void
    public init(id: UUID = UUID(), title: String, summary: String, amount: Int, counterparty: String, counterpartyTrust: Trust? = nil, needsBiometric: Bool, run: @escaping @MainActor () -> Void) {
        self.id = id; self.title = title; self.summary = summary; self.amount = amount; self.counterparty = counterparty
        self.counterpartyTrust = counterpartyTrust; self.needsBiometric = needsBiometric; self.run = run
    }
    /// The gate's rule for orders: from ₹500 up, or a first-time provider, needs the person to prove it is them.
    public static func needsBiometric(amount: Int, firstTimeWithCounterparty: Bool) -> Bool { amount >= 500 || firstTimeWithCounterparty }
    /// The ride booking sheet: never needs biometrics (the fare is paid after the trip).
    public init(booking b: PendingBooking) {
        self.init(id: b.id, title: b.title, summary: b.summary, amount: b.amount, counterparty: "Nearest online rider", counterpartyTrust: nil, needsBiometric: false, run: b.run)
    }
}
