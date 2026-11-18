import Foundation
import Testing
@testable import BucksCore

/// Help's links and mail (Legal.swift), and when reviews and jobs can be reported (ReportTarget.review / .job).
@Suite struct LegalTests {
    @Test func pagesAreTheOnesDocsLegalPublishes() {
        #expect(Legal.url(.privacy).absoluteString == "https://infin8sync69-source.github.io/bucks-Mobile/legal/privacy")
        #expect(Legal.url(.guidelines).absoluteString.hasSuffix("/legal/community-guidelines"))
        #expect(Legal.url(.childSafety).absoluteString.hasSuffix("/legal/child-safety"))
        #expect(Legal.url(.deleteAccount).absoluteString.hasSuffix("/legal/delete-account"))
        #expect(Set(Legal.Page.allCases.map(\.rawValue)) == ["privacy", "terms", "grievance", "community-guidelines", "child-safety", "delete-account"])
    }

    @Test func mailtoEncodesTheSubjectAndBody() throws {
        let url = try #require(Legal.mailto(" help@bucks.test ", subject: "Help with Bucks", body: "a&b=c+d\n---"))
        #expect(url.absoluteString == "mailto:help@bucks.test?subject=Help%20with%20Bucks&body=a%26b%3Dc%2Bd%0A---")
        #expect(Legal.mailto("", subject: "x", body: "y") == nil)
        #expect(Legal.mailto("   ", subject: "x", body: "y") == nil)
    }

    @Test func supportMailNeedsAnAddress() {
        let saved = Legal.supportEmail
        defer { Legal.supportEmail = saved }
        Legal.supportEmail = ""
        #expect(Legal.supportMail(subject: "Problem report") == nil)
        Legal.supportEmail = "help@bucks.test"
        let mail = Legal.supportMail(subject: "Problem report")?.absoluteString ?? ""
        #expect(mail.hasPrefix("mailto:help@bucks.test?subject=Problem%20report&body="))
        #expect(mail.contains("Bucks%20"))
    }
}

@Suite struct ReportRulesTests {
    private func review(author: String = "u2", comment: String = "Rude on the phone") -> ReviewRow {
        ReviewRow(id: "r1", listingId: "l1", authorId: author, vote: -1, comment: comment, createdAt: "2026-11-14T10:00:00Z")
    }

    @Test func reviewsWithWordsBySomeoneElseOnALivePage() throws {
        let t = try #require(ReportTarget.review(review(), pageLive: true, me: "u1", authorName: "Asha"))
        #expect(t.kind == "REVIEW"); #expect(t.targetId == "r1"); #expect(t.ownerId == "u2"); #expect(t.ownerName == "Asha")
        #expect(t.title == "Report this recommendation")
        #expect(ReportTarget.review(review(author: "u1"), pageLive: true, me: "u1", authorName: "Me") == nil)      // my own
        #expect(ReportTarget.review(review(comment: " \n"), pageLive: true, me: "u1", authorName: "Asha") == nil)  // a vote, no words
        #expect(ReportTarget.review(review(), pageLive: false, me: "u1", authorName: "Asha") == nil)              // the server refuses
    }

    @Test func openJobsOfABusinessIDontRun() throws {
        let job = JobPageRow(id: "j1", listingId: "l1", listingTitle: "Sharma Stores", title: "Delivery helper")
        let t = try #require(ReportTarget.job(job, manager: false))
        #expect(t.kind == "JOB"); #expect(t.targetId == "j1"); #expect(t.ownerId == nil); #expect(t.ownerName == "Sharma Stores")
        #expect(t.title == "Report this job")
        #expect(ReportTarget.job(job, manager: true) == nil)
        var closed = job
        closed.open = false
        #expect(ReportTarget.job(closed, manager: false) == nil)
    }
}
