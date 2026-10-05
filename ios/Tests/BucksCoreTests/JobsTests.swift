import Foundation
import Testing
@testable import BucksCore

/// Part of DispatchTests so it runs serialized with every suite that scripts the shared FakeServer / Backend.shared.
/// The jobs state holder and its wire format: RPC names and `p_` parameters were checked against supabase/migrations/jobs.sql and Backend.kt / BackendJobs.kt.
extension DispatchTests {
    private func call(_ path: String) -> [(method: String, path: String, query: String, body: [String: Any])] { FakeServer.calls.filter { $0.path == path } }

    private func bootSession(_ handler: @escaping (String, String, [String: Any]) -> (Int, Any)) -> AppSession {
        RingAlert.enabled = false
        FakeServer.handler = handler; FakeServer.log = []; FakeServer.calls = []; FakeServer.prefer = [:]
        Backend.shared.configure(BackendConfig(url: "https://x.supabase.co", anonKey: "anon"), identity: FakeIdentity())
        Backend.shared.useProtocolClasses([FakeServer.self])
        let s = AppSession()
        s.me = ProfileRow(id: "me", shortCode: "ME0001", name: "Asha Rao")
        return s
    }
    private func job(open: Bool = true) -> [String: Any] {
        ["id": "j1", "listing_id": "L1", "listing_title": "Sri Tailors", "area": "Jayanagar", "title": "Tailor", "description": "", "pay": "", "job_type": "GIG", "open": open, "created_at": "2026-09-30T10:00:00+00:00"]
    }
    private func app(_ id: String, by who: String, status: String = "APPLIED", skills: [String] = [], at: String = "2026-09-30T10:00:00+00:00") -> [String: Any] {
        ["id": id, "job_id": "j1", "applicant_id": who, "skill_listing_ids": skills, "note": "", "status": status, "created_at": at]
    }
    private func skill(_ id: String, _ title: String, status: String = "LIVE", kind: String = "SKILL") -> [String: Any] {
        ["id": id, "kind": kind, "owner_id": "u1", "title": title, "status": status]
    }

    // MARK: labels

    @Test func labelsMatchAndroid() {
        #expect(JobsStore.typeLabel("FULL_TIME") == "Full time"); #expect(JobsStore.typeLabel("PART_TIME") == "Part time"); #expect(JobsStore.typeLabel("GIG") == "One-off")
        #expect(JobsStore.typeLabel("NIGHT_SHIFT") == "Night shift")
        #expect(JobsStore.statusLabel("REJECTED") == "Not selected"); #expect(JobsStore.statusLabel("WITHDRAWN") == "Withdrawn"); #expect(JobsStore.statusLabel("X") == "X")
        #expect(JobsStore.distance(450) == "450 m"); #expect(JobsStore.distance(949.9) == "949 m"); #expect(JobsStore.distance(950) == "1.0 km"); #expect(JobsStore.distance(2300) == "2.3 km")
        #expect(JobsStore.applicationsLine(0) == "No applications yet"); #expect(JobsStore.applicationsLine(1) == "1 application"); #expect(JobsStore.applicationsLine(7) == "7 applications")
        #expect(["WITHDRAWN", "HIRED", "REJECTED", "APPLIED", "SHORTLISTED"].sorted { JobsStore.statusRank($0) < JobsStore.statusRank($1) } == ["HIRED", "SHORTLISTED", "APPLIED", "REJECTED", "WITHDRAWN"])
    }

    @Test func timeSinceReadsLikeAVerbSuffix() {
        let now = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!
        #expect(JobsStore.timeSince("2026-10-01T11:59:40+00:00", now: now) == "just now")
        #expect(JobsStore.timeSince("2026-10-01T11:55:00+00:00", now: now) == "5m ago")
        #expect(JobsStore.timeSince("2026-10-01T09:00:00+00:00", now: now) == "3h ago")
        #expect(JobsStore.timeSince("2026-09-30T10:00:00.123456+00:00", now: now) == "yesterday")
        #expect(JobsStore.timeSince("2026-09-29T10:00:00+00:00", now: now).hasPrefix("on "))
        #expect(JobsStore.timeSince("2026-09-12 08:00:00+00", now: now) == JobsStore.timeSince("2026-09-12T08:00:00+00:00", now: now) || JobsStore.timeSince("2026-09-12 08:00:00+00", now: now) == "")
        #expect(JobsStore.timeSince("garbage", now: now) == "")
    }

    @Test func friendlyMessagesForOurOwnDatabaseErrors() {
        let dup = BackendError.http(status: 409, body: #"{"message":"duplicate key value violates unique constraint \"applications_job_id_applicant_id_key\""}"#)
        #expect(JobsStore.friendly(dup) == "You already applied to this job.")
        let rls = BackendError.http(status: 403, body: #"{"message":"new row violates row-level security policy for table \"jobs\""}"#)
        #expect(JobsStore.friendly(rls) == "You're not allowed to do that.")
        let own = BackendError.http(status: 400, body: #"{"message":"You can't apply to your own job."}"#)
        #expect(JobsStore.friendly(own) == "You can't apply to your own job.")
        #expect(JobsStore.friendly(BackendError.transport("offline")) == "Couldn't reach Bucks. Check your connection and try again.")
    }

    // MARK: decoding

    @Test func rowsDecodeWithDefaultsForMissingColumns() throws {
        let d = Backend.decoder
        let list = try d.decode(JobListRow.self, from: Data(#"{"id":"j","listing_id":"L","title":"T","created_by":"u","created_at":"x"}"#.utf8))
        #expect(list.jobType == "FULL_TIME"); #expect(list.open); #expect(list.applications == 0); #expect(list.pay == "")
        let near = try d.decode(JobNearRow.self, from: Data(#"{"id":"j","listing_id":"L","listing_title":"B","title":"T","created_at":"x","distance_m":812.5}"#.utf8))
        #expect(near.distanceM == 812.5); #expect(near.area == "")
        let mine = try d.decode(MyApplicationRow.self, from: Data(#"{"id":"a","job_id":"j","status":"HIRED","created_at":"x","job_title":"T","listing_id":"L","listing_title":"B"}"#.utf8))
        #expect(mine.jobOpen); #expect(mine.note == "")
        let a = try d.decode(JobApplicationRow.self, from: Data(#"{"id":"a","job_id":"j","applicant_id":"u","status":"APPLIED","created_at":"x"}"#.utf8))
        #expect(a.skillListingIds.isEmpty)
    }

    // MARK: a listing's jobs

    @Test func listingJobsLoadsListingRoleAndCountsAndPostsJobs() async throws {
        var posted = false
        let s = bootSession { path, query, params in
            switch path {
            case "/rest/v1/listings": return (200, [["id": "L1", "kind": "SHOP", "owner_id": "me", "title": "Sri Tailors", "status": "LIVE"]])
            case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "me", "role": "OWNER"], ["listing_id": "L1", "profile_id": "u2", "role": "STAFF"]])
            case "/rest/v1/jobs_with_counts":
                return (200, posted ? [["id": "j2", "listing_id": "L1", "title": "Cutter", "created_by": "me", "created_at": "2026-09-30T10:00:00+00:00", "applications": 0, "new_applications": 0]]
                                    : [["id": "j1", "listing_id": "L1", "title": "Tailor", "created_by": "me", "created_at": "2026-09-30T10:00:00+00:00", "applications": 3, "new_applications": 2]])
            case "/rest/v1/jobs": posted = true; return (201, [:])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        await s.jobs.loadListingJobs("L1").value
        #expect(s.jobs.listing?.title == "Sri Tailors"); #expect(s.jobs.manager); #expect(s.jobs.jobs.first?.newApplications == 2); #expect(!s.jobs.loadingJobs)
        let counts = try #require(call("/rest/v1/jobs_with_counts").first)
        #expect(counts.query.contains("listing_id=eq.L1")); #expect(counts.query.contains("order=created_at.desc"))
        #expect(call("/rest/v1/listing_members").first?.query.contains("listing_id=eq.L1") == true)

        var thenRan = false
        await s.jobs.postJob(listingId: "L1", title: "  Cutter ", description: " Fast hands\n", pay: " Rs 500/day ", type: "GIG") { thenRan = true }.value
        let body = try #require(call("/rest/v1/jobs").first)
        #expect(body.method == "POST"); #expect(FakeServer.prefer["POST /rest/v1/jobs"] == "return=minimal")
        #expect(Set(body.body.keys) == ["listing_id", "created_by", "title", "description", "pay", "job_type"])
        #expect(body.body["title"] as? String == "Cutter"); #expect(body.body["description"] as? String == "Fast hands"); #expect(body.body["pay"] as? String == "Rs 500/day")
        #expect(body.body["created_by"] as? String == "me"); #expect(body.body["job_type"] as? String == "GIG")
        #expect(thenRan); #expect(s.jobs.jobs.map(\.id) == ["j2"]); #expect(!s.jobs.busy)
    }

    @Test func adminRoleManagesButStaffAndStrangersDoNot() async {
        for (role, expected) in [("ADMIN", true), ("STAFF", false), ("DRIVER", false)] {
            let s = bootSession { path, _, _ in
                switch path {
                case "/rest/v1/listings": return (200, [["id": "L1", "kind": "SHOP", "owner_id": "u9", "title": "B"]])
                case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "me", "role": role]])
                default: return (200, [])
                }
            }
            await s.jobs.loadListingJobs("L1").value
            #expect(s.jobs.manager == expected)
        }
    }

    @Test func switchingListingClearsTheOldJobsBeforeTheNewOnesLoad() async {
        let s = bootSession { path, _, _ in
            switch path {
            case "/rest/v1/listings": return (200, [["id": "L1", "kind": "SHOP", "owner_id": "me", "title": "A"]])
            case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "me", "role": "OWNER"]])
            default: return (200, [["id": "j1", "listing_id": "L1", "title": "Tailor", "created_by": "me", "created_at": "x"]])
            }
        }
        await s.jobs.loadListingJobs("L1").value
        #expect(s.jobs.manager); #expect(s.jobs.jobs.count == 1)
        FakeServer.handler = { _, _, _ in (500, ["message": "down"]) }
        await s.jobs.loadListingJobs("L2").value
        #expect(s.jobs.listing == nil); #expect(s.jobs.jobs.isEmpty); #expect(!s.jobs.manager)
    }

    @Test func closeAndReopenPatchTheOpenFlagAndUpdateBothLists() async throws {
        let s = bootSession { path, _, _ in
            switch path {
            case "/rest/v1/jobs_with_counts": return (200, [["id": "j1", "listing_id": "L1", "title": "Tailor", "created_by": "me", "created_at": "x"]])
            case "/rest/v1/listings": return (200, [["id": "L1", "kind": "SHOP", "owner_id": "me", "title": "A"]])
            case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "me", "role": "OWNER"]])
            case "/rest/v1/rpc/job_page": return (200, [job()])
            case "/rest/v1/applications": return (200, [])
            case "/rest/v1/jobs": return (204, [:])
            default: return (404, ["message": "no stub"])
            }
        }
        var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        await s.jobs.loadListingJobs("L1").value; await s.jobs.loadJob("j1").value
        await s.jobs.closeJob("j1").value
        var patch = try #require(call("/rest/v1/jobs").last)
        #expect(patch.method == "PATCH"); #expect(patch.query.contains("id=eq.j1")); #expect(patch.body as NSDictionary == ["open": false] as NSDictionary)
        #expect(s.jobs.job?.open == false); #expect(s.jobs.jobs.first?.open == false)
        await s.jobs.reopenJob("j1").value
        patch = try #require(call("/rest/v1/jobs").last)
        #expect(patch.body as NSDictionary == ["open": true] as NSDictionary)
        #expect(s.jobs.job?.open == true); #expect(s.jobs.jobs.first?.open == true)
        #expect(toasts == ["Job closed. No new applications will come in.", "Job reopened. It shows up nearby again."])
    }

    // MARK: one job

    @Test func managerSeesEveryApplicationWithNamesAndSkillProfiles() async throws {
        let s = bootSession { path, query, _ in
            switch path {
            case "/rest/v1/rpc/job_page": return (200, [self.job()])
            case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "me", "role": "ADMIN"]])
            case "/rest/v1/applications": return (200, [self.app("a1", by: "u1", skills: ["S1", "S2"]), self.app("a2", by: "u2", skills: ["S1"])])
            case "/rest/v1/profiles": return (200, [["id": "u1", "short_code": "U1", "name": "Ravi Kumar"], ["id": "u2", "short_code": "U2", "name": "Meera Shah"]])
            case "/rest/v1/listings": return (200, [self.skill("S1", "Tailor"), self.skill("S2", "Cutter", status: "PENDING")])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        await s.jobs.loadJob("j1").value
        #expect(call("/rest/v1/rpc/job_page").first?.body as NSDictionary? == ["p_job": "j1"] as NSDictionary)
        #expect(s.jobs.job?.id == "j1"); #expect(s.jobs.manager); #expect(s.jobs.jobMissing == nil); #expect(s.jobs.applications.count == 2)
        #expect(s.jobs.nameOf("u1") == "Ravi Kumar"); #expect(s.jobs.nameOf("zz") == "…")
        // Skill profiles are fetched once for the union of ids, in one `in.(…)` call; a manager does not load their own skills.
        let skillCall = try #require(call("/rest/v1/listings").first)
        #expect(skillCall.query.contains("id=in.(S1,S2)"))
        #expect(s.jobs.skillProfiles["S2"]?.status == "PENDING"); #expect(s.jobs.skillProfiles.count == 2)
        #expect(call("/rest/v1/listings").count == 1)
        #expect(call("/rest/v1/applications").first?.query.contains("order=created_at.asc") == true)
        #expect(call("/rest/v1/applications").first?.query.contains("job_id=eq.j1") == true)
        #expect(s.jobs.myApplication == nil)
    }

    @Test func missingJobIsRemembered() async {
        let s = bootSession { path, _, _ in
            if path == "/rest/v1/rpc/job_page" { return (200, [] as [Any]) }
            return (404, ["message": "no stub"])
        }
        await s.jobs.loadJob("gone").value
        #expect(s.jobs.job == nil); #expect(s.jobs.jobMissing == "gone"); #expect(!s.jobs.loadingJob)
    }

    @Test func applicantSeesOnlyTheirOwnApplicationAndLoadsTheirSkills() async throws {
        let s = bootSession { path, query, _ in
            switch path {
            case "/rest/v1/rpc/job_page": return (200, [self.job()])
            case "/rest/v1/listing_members":
                return query.contains("profile_id=eq.me") ? (200, [["listing_id": "S1", "profile_id": "me", "role": "OWNER"], ["listing_id": "S3", "profile_id": "me", "role": "OWNER"]])
                                                          : (200, [["listing_id": "L1", "profile_id": "u9", "role": "OWNER"]])
            case "/rest/v1/applications": return (200, [self.app("a1", by: "me", skills: ["S1"])])
            case "/rest/v1/profiles": return (200, [["id": "me", "short_code": "ME", "name": "Asha Rao"]])
            case "/rest/v1/listings": return (200, [self.skill("S1", "Tailor"), self.skill("S3", "Shop", kind: "SHOP")])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        await s.jobs.loadJob("j1").value
        #expect(!s.jobs.manager); #expect(s.jobs.myApplication?.id == "a1")
        #expect(s.jobs.mySkills.map(\.id) == ["S1"])   // only SKILL listings, from the memberships of mine
    }

    // MARK: applying

    @Test func applyInsertsTheApplicationAndRefreshesIt() async throws {
        // The insert carries a body; the read that follows does not.
        let s = bootSession { path, _, params in
            if path == "/rest/v1/applications" { return params.isEmpty ? (200, [self.app("a1", by: "me", skills: ["S1"])]) : (201, [:] as [String: Any]) }
            return (404, ["message": "no stub"])
        }
        var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        let task = s.jobs.apply("j1", skillIds: ["S1"], note: "  Can start Monday ")
        await task.value
        let post = try #require(call("/rest/v1/applications").first(where: { $0.method == "POST" }))
        #expect(FakeServer.prefer["POST /rest/v1/applications"] == "return=minimal")
        #expect(Set(post.body.keys) == ["job_id", "applicant_id", "note", "skill_listing_ids"])
        #expect(post.body["job_id"] as? String == "j1"); #expect(post.body["applicant_id"] as? String == "me")
        #expect(post.body["note"] as? String == "Can start Monday"); #expect(post.body["skill_listing_ids"] as? [String] == ["S1"])
        #expect(toasts == ["Applied. The business will see your application."])
        #expect(s.jobs.applications.map(\.id) == ["a1"]); #expect(s.jobs.myApplication?.id == "a1")
        #expect(!s.jobs.busy)
    }

    @Test func applyingTwiceToasts_AlreadyApplied() async {
        let s = bootSession { _, _, _ in (409, ["message": "duplicate key value violates unique constraint \"applications_job_id_applicant_id_key\""]) }
        var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        await s.jobs.apply("j1", skillIds: [], note: "hi").value
        #expect(toasts == ["You already applied to this job."]); #expect(!s.jobs.busy)
    }

    @Test func applyNeedsASignedInProfile() async {
        let s = bootSession { _, _, _ in (500, ["message": "should not be called"]) }
        s.me = nil
        await s.jobs.apply("j1", skillIds: [], note: "x").value
        await s.jobs.postJob(listingId: "L1", title: "x", description: "", pay: "", type: "GIG") {}.value
        #expect(FakeServer.calls.isEmpty)
    }

    @Test func withdrawMarksBothTheJobPageAndMyApplications() async throws {
        let s = bootSession { path, _, _ in
            switch path {
            case "/rest/v1/rpc/my_applications": return (200, [["id": "a1", "job_id": "j1", "status": "APPLIED", "created_at": "x", "job_title": "Tailor", "listing_id": "L1", "listing_title": "Sri"]])
            case "/rest/v1/applications": return (204, [:])
            default: return (404, ["message": "no stub"])
            }
        }
        var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        await s.jobs.refreshMyApplications().value
        #expect(s.jobs.myApplications.first?.status == "APPLIED"); #expect(!s.jobs.loadingMine)
        await s.jobs.withdraw("a1").value
        let patch = try #require(call("/rest/v1/applications").first)
        #expect(patch.method == "PATCH"); #expect(patch.query.contains("id=eq.a1")); #expect(patch.body as NSDictionary == ["status": "WITHDRAWN"] as NSDictionary)
        #expect(s.jobs.myApplications.first?.status == "WITHDRAWN"); #expect(toasts == ["Application withdrawn."])
    }

    @Test func deciderToastsNameThePerson() async throws {
        let s = bootSession { path, _, _ in
            switch path {
            case "/rest/v1/rpc/job_page": return (200, [self.job()])
            case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "me", "role": "OWNER"]])
            case "/rest/v1/applications": return (200, [self.app("a1", by: "u1"), self.app("a2", by: "u2")])
            case "/rest/v1/profiles": return (200, [["id": "u1", "short_code": "U1", "name": "Ravi Kumar"], ["id": "u2", "short_code": "U2", "name": "Meera Shah"]])
            case "/rest/v1/jobs_with_counts": return (200, [["id": "j1", "listing_id": "L1", "title": "Tailor", "created_by": "me", "created_at": "x", "applications": 2, "new_applications": 2]])
            case "/rest/v1/listings": return (200, [["id": "L1", "kind": "SHOP", "owner_id": "me", "title": "A"]])
            default: return (404, ["message": "no stub"])
            }
        }
        var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        await s.jobs.loadListingJobs("L1").value; await s.jobs.loadJob("j1").value
        FakeServer.handler = { path, _, _ in (path == "/rest/v1/applications" ? (204, [:]) : (404, ["message": "x"])) }
        await s.jobs.setApplicationStatus("a1", "SHORTLISTED").value
        await s.jobs.setApplicationStatus("a1", "HIRED").value
        await s.jobs.setApplicationStatus("a2", "REJECTED").value
        await s.jobs.setApplicationStatus("a2", "APPLIED").value
        #expect(toasts == ["Ravi Kumar shortlisted. They can see it in their applications.", "Ravi Kumar hired. Close the job when you've filled it.", "Meera Shah turned down.", "Updated."])
        #expect(s.jobs.applications.map(\.status) == ["HIRED", "APPLIED"])
        // The list's "new" badge follows the applications still waiting for a decision.
        #expect(s.jobs.jobs.first?.newApplications == 1)
        #expect(call("/rest/v1/applications").filter { $0.method == "PATCH" }.map { $0.body["status"] as? String } == ["SHORTLISTED", "HIRED", "REJECTED", "APPLIED"])
    }

    // MARK: chats

    @Test func messagingUsesTheRightRpcsAndGuardsDoubleTaps() async throws {
        let s = bootSession { path, _, _ in
            switch path {
            case "/rest/v1/rpc/start_applicant_chat": return (200, "c-app")
            case "/rest/v1/rpc/start_listing_chat": return (200, "c-biz")
            default: return (404, ["message": "no stub"])
            }
        }
        var opened: [String] = []
        await s.jobs.message("a1") { opened.append($0) }.value
        #expect(call("/rest/v1/rpc/start_applicant_chat").first?.body as NSDictionary? == ["p_application": "a1"] as NSDictionary)
        let first = s.jobs.messageBusiness("L1") { opened.append($0) }
        #expect(s.jobs.messaging)
        let second = s.jobs.messageBusiness("L1") { opened.append($0) }
        await first.value; await second.value
        #expect(call("/rest/v1/rpc/start_listing_chat").count == 1)
        #expect(call("/rest/v1/rpc/start_listing_chat").first?.body as NSDictionary? == ["p_listing": "L1"] as NSDictionary)
        #expect(opened == ["c-app", "c-biz"]); #expect(!s.jobs.messaging)
    }

    @Test func aFailedChatOpenToastsAndReleasesTheButton() async {
        let s = bootSession { _, _, _ in (400, ["message": "They have blocked you."]) }
        var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        await s.jobs.messageBusiness("L1") { _ in }.value
        #expect(toasts == ["They have blocked you."]); #expect(!s.jobs.messaging)
    }

    // MARK: near me

    @Test func jobsNearSendsMyPositionAndFifteenKm() async throws {
        let s = bootSession { path, _, _ in
            if path == "/rest/v1/rpc/jobs_near" {
                return (200, [["id": "j1", "listing_id": "L1", "listing_title": "Sri", "area": "Jayanagar", "title": "Tailor", "pay": "Rs 500/day", "job_type": "GIG", "created_at": "x", "distance_m": 1234.0]])
            }
            return (404, ["message": "no stub"])
        }
        await s.jobs.refreshNear().value
        let c = try #require(call("/rest/v1/rpc/jobs_near").first)
        #expect(Set(c.body.keys) == ["lat", "lng", "radius_m"]); #expect(c.body["radius_m"] as? Int == 15_000)
        #expect(c.body["lat"] as? Double == s.here.lat); #expect(c.body["lng"] as? Double == s.here.lng)
        #expect(s.jobs.near.first?.distanceM == 1234.0); #expect(!s.jobs.loadingNear)
    }

    @Test func failuresToastAndSignOutClearsEverything() async {
        let s = bootSession { _, _, _ in (500, ["message": "boom"]) }
        var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        await s.jobs.refreshNear().value
        #expect(toasts == ["Couldn't reach Bucks. Check your connection and try again."]); #expect(!s.jobs.loadingNear)
        FakeServer.handler = { path, _, _ in path.hasSuffix("jobs_near") ? (200, [["id": "j1", "listing_id": "L1", "listing_title": "Sri", "title": "Tailor", "created_at": "x"]]) : (200, []) }
        await s.jobs.refreshNear().value
        #expect(s.jobs.near.count == 1)
        s.jobs.signedOut()
        #expect(s.jobs.near.isEmpty); #expect(s.jobs.job == nil); #expect(s.jobs.applications.isEmpty); #expect(s.jobs.skillProfiles.isEmpty); #expect(!s.jobs.manager)
    }
}
