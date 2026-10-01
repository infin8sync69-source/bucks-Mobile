import Foundation
import Testing
@testable import BucksCore

@Suite struct IntentGrammarTests {
    private func p(_ s: String) -> ParsedIntent? { RuleIntentEngine.parseNow(s) }

    @Test func confirmAndCancelWords() {
        for s in ["yes", "Confirm", "ok", "okay", "book it", "go ahead", "haan", "sari", "Yes, ring them", "yes please"] { #expect(p(s)?.tool == Tools.confirm, "\(s)") }
        for s in ["no", "cancel", "stop", "nahi", "beda", "never mind", "Cancel it"] { #expect(p(s)?.tool == Tools.cancel, "\(s)") }
        #expect(p("yesterday") == nil || p("yesterday")?.tool != Tools.confirm)
    }
    @Test func showTheMap() { #expect(p("Show the map first")?.tool == Tools.showMap) }

    @Test func ridePhrasesFromTheReadmeAndSuggestions() {
        let a = p("auto to MG Road")
        #expect(a?.tool == Tools.ride); #expect(a?.args["vehicle"] == "AUTO"); #expect(a?.args["destination"] == "MG Road")
        let b = p("Bike to Koramangala")
        #expect(b?.args["vehicle"] == "BIKE"); #expect(b?.args["destination"] == "Koramangala, Bengaluru")
        #expect(p("cab to the airport")?.args["destination"] == "")  // "airport" is not the first word of Kempegowda airport
        #expect(p("taxi to kempegowda")?.args["vehicle"] == "CAB"); #expect(p("taxi to kempegowda")?.args["destination"] == "Kempegowda airport")
        #expect(p("scooty to Indiranagar")?.args["vehicle"] == "BIKE")
        #expect(p("two wheeler to whitefield")?.args["destination"] == "Whitefield, ITPL")
        #expect(p("rickshaw please")?.args["vehicle"] == "AUTO")
        #expect(p("Auto to Jayanagar")?.args["destination"] == "Jayanagar 4th block")
        #expect(p("Cab to Majestic")?.args["destination"] == "Majestic bus stand")
        #expect(p("drop me at nexus mall")?.args["destination"] == "Nexus Mall, Koramangala")
        let r = p("take me home")
        #expect(r?.tool == Tools.ride); #expect(r?.args["vehicle"] == "AUTO"); #expect(r?.args["destination"] == "")
        #expect(p("pick me up")?.tool == Tools.ride)
        #expect(p("Auto to MG Road")?.confidence == 1)
    }
    @Test func compare() {
        let c = p("Compare grocery for sugar")
        #expect(c?.tool == Tools.compare); #expect(c?.args["query"] == "grocery  sugar")
        #expect(p("Compare biriyani")?.args["query"] == "biriyani")
        #expect(p("cheapest plumber near me")?.args["query"] == "plumber")
        #expect(p("which is better chicken biriyani")?.tool == Tools.compare)
    }
    @Test func sort() {
        #expect(p("sort by price")?.args["by"] == "PRICE"); #expect(p("sort cheapest")?.tool == Tools.compare)  // "cheapest" is checked before "sort", as on Android
        #expect(p("sort nearest")?.args["by"] == "NEAR"); #expect(p("sort by distance")?.args["by"] == "NEAR")
        #expect(p("sort by trust")?.args["by"] == "TRUST"); #expect(p("sort")?.args["by"] == "TRUST")
    }
    @Test func activityPostGoOnlineBecomePro() {
        for s in ["Show my orders", "my rides", "my requests", "history", "activity"] { #expect(p(s)?.tool == Tools.activity, "\(s)") }
        let post = p("Post a request for a plumber")
        #expect(post?.tool == Tools.postRequest); #expect(post?.args["what"] == "a plumber")
        #expect(p("POST A REQUEST FOR tutor")?.args["what"] == "tutor")
        for s in ["go online", "start duty", "i'm online"] { #expect(p(s)?.tool == Tools.goOnline, "\(s)") }
        for s in ["become a driver", "provider", "pro profile", "add my vehicle", "add skill", "add business", "earn money"] { #expect(p(s)?.tool == Tools.becomePro, "\(s)") }
    }
    @Test func searchFallbackAndHelp() {
        let s = p("order sugar")
        #expect(s?.tool == Tools.search); #expect(s?.args["query"] == "sugar"); #expect(s?.confidence == 0.6)
        #expect(p("Find a doctor")?.args["query"] == "doctor")
        #expect(p("Biriyani")?.args["query"] == "biriyani")
        #expect(p("plumber")?.tool == Tools.search)
        #expect(p("   ") == nil); #expect(p("") == nil)
        #expect(p("get a") == nil)  // everything is filler: under 3 letters left
    }
    @Test func agentQueryDetection() {
        for s in ["Bike to Koramangala", "auto to MG Road", "yes", "Show my orders", "compare sugar", "post a request for x", "go online", "take me home", "book a table", "sort price", "cancel"] { #expect(isAgentQuery(s), "\(s)") }
        for s in ["sugar", "biriyani", "plumber", "doctor", "Find a doctor"] { #expect(!isAgentQuery(s), "\(s)") }
    }
    @Test func routerFallsBackToHelpAndNeverCallsCloudWithoutAKey() async {
        let r = IntentRouter(cloud: GeminiIntentEngine(apiKey: ""))
        #expect(!r.cloudEnabled)
        #expect(await r.parse("Auto to MG Road", context: "").tool == Tools.ride)
        #expect(await r.parse("order sugar", context: "").tool == Tools.search)
        #expect(await r.parse("hi", context: "").tool == Tools.help)
    }
}

@Suite struct GeminiIntentTests {
    private func reply(_ text: String) -> Data {
        let body: [String: Any] = ["candidates": [["content": ["parts": [["text": text]]]]]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
    @Test func parsesPlainAndFencedJson() {
        let a = GeminiIntentEngine.parseReply(reply(#"{"tool":"request_ride","args":{"vehicle":"CAB","destination":"MG Road"},"confidence":0.95}"#))
        #expect(a?.tool == Tools.ride); #expect(a?.args["vehicle"] == "CAB"); #expect(a?.source == "gemini"); #expect(a?.confidence == 0.95)
        let b = GeminiIntentEngine.parseReply(reply("```json\n{\"tool\":\"search_marketplace\",\"args\":{\"query\":\"sugar\"}}\n```"))
        #expect(b?.tool == Tools.search); #expect(b?.confidence == 0.8)
    }
    @Test func rejectsUnknownToolsAndGarbage() {
        #expect(GeminiIntentEngine.parseReply(reply(#"{"tool":"transfer_money","args":{"to":"x"}}"#)) == nil)
        #expect(GeminiIntentEngine.parseReply(reply("sorry I can't")) == nil)
        #expect(GeminiIntentEngine.parseReply(Data("{}".utf8)) == nil)
    }
    @Test func clampsConfidenceAndStringifiesArgs() {
        let c = GeminiIntentEngine.parseReply(reply(#"{"tool":"help","args":{"n":5,"z":null},"confidence":7}"#))
        #expect(c?.confidence == 1); #expect(c?.args["n"] == "5"); #expect(c?.args["z"] == "")
    }
    @Test func disabledWithoutAKeyAndPromptCarriesTheCatalogue() async {
        let e = GeminiIntentEngine(apiKey: "")
        #expect(!e.enabled); #expect(await e.parse("auto", context: "") == nil)
        let p = GeminiIntentEngine(apiKey: "k").prompt("auto to mg road", context: "user area=X")
        #expect(p.contains("request_ride")); #expect(p.contains("Context: user area=X")); #expect(p.contains("Known places: Koramangala, Bengaluru, Nexus Mall, Koramangala"))
        #expect(p.hasSuffix("Command: \"auto to mg road\""))
        #expect(GeminiIntentEngine(apiKey: "k").model == "gemini-2.5-flash-lite")
    }
}

@Suite struct IdentityTests {
    @Test func userIdIsStableAndDerivedFromThePublicKey() {
        let id = IdentityService(store: MemoryKeyStore(), useSecureEnclave: false)
        let a = id.userId()
        #expect(a.count == 32); #expect(a == id.userId())
        let der = Data(base64Encoded: id.publicKeyBase64()) ?? Data()
        #expect(a == String(IdentityService.sha256(der).prefix(32)))
    }
    @Test func keyPersistsInTheStoreAndDeleteMakesANewOne() {
        let store = MemoryKeyStore()
        let first = IdentityService(store: store, useSecureEnclave: false)
        let id1 = first.userId()
        #expect(IdentityService(store: store, useSecureEnclave: false).userId() == id1)
        first.deleteKey()
        #expect(first.userId() != id1)
    }
    @Test func signAndVerifyRoundTrip() {
        let id = IdentityService(store: MemoryKeyStore(), useSecureEnclave: false)
        let payload = Identity.txnPayload(type: "ride", txnId: "r1", actor: id.userId(), counterparty: "", amount: 82, at: 1_700_000_000_000)
        #expect(payload == "ride|r1|\(id.userId())||82|1700000000000")
        let sig = id.sign(payload)
        #expect(!sig.isEmpty)
        #expect(id.verify(payload, signature: sig))
        #expect(!id.verify(payload + "x", signature: sig))
        #expect(!id.verify(payload, signature: "AAAA")); #expect(!id.verify(payload, signature: "not base64!"))
        #expect(IdentityService.verify(payload, signature: sig, publicKeyBase64: id.publicKeyBase64()))
        let other = IdentityService(store: MemoryKeyStore(), useSecureEnclave: false)
        #expect(!IdentityService.verify(payload, signature: sig, publicKeyBase64: other.publicKeyBase64()))
        #expect(!IdentityService.verify(payload, signature: sig, publicKeyBase64: "junk"))
    }
    @Test func txnPayloadMatchesAndroid() {
        #expect(Identity.txnPayload(type: "vote", txnId: "t", actor: "u", counterparty: "p", amount: -1, at: 5) == "vote|t|u|p|-1|5")
    }
    @Test func sha256Hex() { #expect(IdentityService.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") }
    @Test func softwareKeySurvivesTheSecureEnclaveFlagWhenNoHardware() {
        // On a Mac/CI without an Enclave the default flag still yields a working key.
        let id = IdentityService(store: MemoryKeyStore())
        #expect(id.verify("x", signature: id.sign("x")))
    }
}

@Suite struct ConfirmationRuleTests {
    @Test func biometricsFromFiveHundredOrFirstTime() {
        #expect(!PendingAction.needsBiometric(amount: 499, firstTimeWithCounterparty: false))
        #expect(PendingAction.needsBiometric(amount: 500, firstTimeWithCounterparty: false))
        #expect(PendingAction.needsBiometric(amount: 10, firstTimeWithCounterparty: true))
    }
    @MainActor @Test func rideBookingNeverNeedsBiometrics() {
        let b = PendingBooking(title: "Book an auto", summary: "A → B", amount: 82) {}
        let a = PendingAction(booking: b)
        #expect(!a.needsBiometric); #expect(a.id == b.id); #expect(a.counterparty == "Nearest online rider"); #expect(a.counterpartyTrust == nil)
        #expect(a.title == "Book an auto"); #expect(a.amount == 82)
    }
}

@Suite struct InviteTests {
    @Test func shareTextAppendsTheLink() {
        let t = Invite.shareText("Join me")
        #expect(t.hasPrefix("Join me\n\nGet Bucks for iPhone: ")); #expect(t.contains(Invite.link))
        #expect(Invite.contactText(firstName: "Anitha").hasPrefix("Hi Anitha, I'm on Bucks: rides, food, shops, skills and homes near you, run by locals. Join here: "))
    }
    @Test func lockedServiceCopyMatchesAndroid() {
        #expect(Invite.forService(label: "Plumbers", supplyNoun: "plumbers") == "I want Plumbers on Bucks near me, but it needs more plumbers here first. If you're one (or know one), join Bucks and get recommended by locals so it opens for all of us.")
    }
}
