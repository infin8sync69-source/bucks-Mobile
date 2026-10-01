import Foundation
import Observation

/// Port of the Android `Jobs` state holder: a listing's jobs, one job with its applications, my applications, my skill
/// profiles (to apply with) and jobs near me. Every action reports a failure as a toast.
@MainActor @Observable
public final class JobsStore {
    @ObservationIgnored public unowned let session: AppSession
    public init(session: AppSession) { self.session = session }

    // MARK: a listing's jobs (listingJobs)
    public private(set) var listing: ListingRow?
    public private(set) var jobs: [JobListRow] = []
    /// True when I own or administer the listing whose jobs are shown (or the listing of the open job).
    public private(set) var manager = false
    public private(set) var loadingJobs = false

    // MARK: one job (job)
    public private(set) var job: JobPageRow?
    /// The job id that was asked for but is not there (closed and not mine, or deleted).
    public private(set) var jobMissing: String?
    /// Every application on the job for a manager; only mine otherwise (row-level security).
    public private(set) var applications: [JobApplicationRow] = []
    /// Skill listing id -> listing, for the applicants' skill chips. Pending profiles of other people stay unresolved.
    public private(set) var skillProfiles: [String: ListingRow] = [:]
    public private(set) var loadingJob = false
    public var myApplication: JobApplicationRow? {
        guard let me = session.me?.id else { return nil }
        return applications.first { $0.applicantId == me }
    }

    // MARK: me as an applicant
    public private(set) var mySkills: [ListingRow] = []
    public private(set) var myApplications: [MyApplicationRow] = []
    public private(set) var loadingMine = false

    // MARK: jobs near me (jobsNear)
    public private(set) var near: [JobNearRow] = []
    public private(set) var loadingNear = false

    /// True while a write is in flight, so buttons can't be tapped twice.
    public private(set) var busy = false
    /// True while the chat with a business is being opened (the button is off, so a double tap can't open it twice).
    public private(set) var messaging = false

    // MARK: plumbing

    /// Runs `block`; a failure becomes a toast. The task is returned so callers (and tests) can wait for it.
    @discardableResult
    private func go(_ block: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            do { try await block() }
            catch is CancellationError {}
            catch { session.toast(Self.friendly(error)) }
        }
    }
    /// Our own database errors come back wrapped; show just the sentence we wrote.
    nonisolated static func friendly(_ e: Error) -> String {
        let msg = friendlyError(e)
        let lower = msg.lowercased()
        if lower.contains("duplicate key") { return "You already applied to this job." }
        if lower.contains("row-level security") { return "You're not allowed to do that." }
        return msg
    }
    private func write(_ block: () async throws -> Void) async throws {
        busy = true; defer { busy = false }
        try await block()
    }
    private func isManager(_ listingId: String) async throws -> Bool {
        guard let me = session.me?.id else { return false }
        let members: [MemberRow] = try await Backend.shared.select("listing_members", filters: [.eq("listing_id", listingId)])
        return members.contains { $0.profileId == me && Self.managerRoles.contains($0.role) }
    }
    public func nameOf(_ id: String) -> String { session.names[id] ?? "…" }
    private func namesFor(_ ids: [String]) async throws {
        var seen = Set<String>()
        let missing = ids.filter { session.names[$0] == nil && seen.insert($0).inserted }
        if missing.isEmpty { return }
        for p in try await Backend.shared.profiles(missing) { session.names[p.id] = p.name }
    }
    private func listingsByIds(_ ids: [String]) async throws -> [ListingRow] {
        ids.isEmpty ? [] : try await Backend.shared.select("listings", filters: [.isIn("id", ids)])
    }

    // MARK: a listing's jobs

    @discardableResult public func loadListingJobs(_ listingId: String) -> Task<Void, Never> {
        go { [self] in
            loadingJobs = true; defer { loadingJobs = false }
            if listing?.id != listingId { listing = nil; jobs = []; manager = false }
            listing = try await Backend.shared.selectOne("listings", filters: [.eq("id", listingId)])
            manager = try await isManager(listingId)
            jobs = try await Backend.shared.jobsWithCounts(listingId)
        }
    }
    @discardableResult public func postJob(listingId: String, title: String, description: String, pay: String, type: String, then: @escaping () -> Void) -> Task<Void, Never> {
        go { [self] in
            guard let me = session.me?.id else { return }
            try await write {
                try await Backend.shared.postJob(listingId: listingId, me: me, title: title.trimmed, description: description.trimmed, pay: pay.trimmed, type: type)
                session.toast("Job posted. People nearby can apply now.")
                jobs = try await Backend.shared.jobsWithCounts(listingId)
                then()
            }
        }
    }
    @discardableResult public func closeJob(_ jobId: String) -> Task<Void, Never> {
        go { [self] in try await write {
            try await Backend.shared.closeJob(jobId)
            session.toast("Job closed. No new applications will come in.")
            setOpen(jobId, false)
        } }
    }
    @discardableResult public func reopenJob(_ jobId: String) -> Task<Void, Never> {
        go { [self] in try await write {
            try await Backend.shared.reopenJob(jobId)
            session.toast("Job reopened. It shows up nearby again.")
            setOpen(jobId, true)
        } }
    }
    private func setOpen(_ jobId: String, _ open: Bool) {
        if job?.id == jobId { job?.open = open }
        jobs = jobs.map { var j = $0; if j.id == jobId { j.open = open }; return j }
    }

    // MARK: one job

    @discardableResult public func loadJob(_ jobId: String) -> Task<Void, Never> {
        go { [self] in
            loadingJob = true; defer { loadingJob = false }
            if job?.id != jobId { job = nil; applications = []; manager = false }
            jobMissing = nil
            guard let page = try await Backend.shared.jobPage(jobId) else { jobMissing = jobId; return }
            job = page
            manager = try await isManager(page.listingId)
            let apps = try await Backend.shared.jobApplications(jobId)
            applications = apps
            try await namesFor(apps.map(\.applicantId))
            var seen = Set<String>()
            let wanted = apps.flatMap(\.skillListingIds).filter { skillProfiles[$0] == nil && seen.insert($0).inserted }
            for l in try await listingsByIds(wanted) { skillProfiles[l.id] = l }
            if !manager { try await refreshMySkills() }
        }
    }
    @discardableResult public func apply(_ jobId: String, skillIds: [String], note: String) -> Task<Void, Never> {
        go { [self] in
            guard let me = session.me?.id else { return }
            try await write {
                try await Backend.shared.applyToJob(jobId, me: me, skillListingIds: skillIds, note: note.trimmed)
                session.toast("Applied. The business will see your application.")
                applications = try await Backend.shared.jobApplications(jobId)
            }
        }
    }
    @discardableResult public func withdraw(_ applicationId: String) -> Task<Void, Never> {
        go { [self] in try await write {
            try await Backend.shared.setApplicationStatus(applicationId, status: "WITHDRAWN")
            session.toast("Application withdrawn.")
            applications = applications.map { var a = $0; if a.id == applicationId { a.status = "WITHDRAWN" }; return a }
            myApplications = myApplications.map { var a = $0; if a.id == applicationId { a.status = "WITHDRAWN" }; return a }
        } }
    }
    @discardableResult public func setApplicationStatus(_ applicationId: String, _ status: String) -> Task<Void, Never> {
        go { [self] in try await write {
            try await Backend.shared.setApplicationStatus(applicationId, status: status)
            let who = applications.first { $0.id == applicationId }.map { nameOf($0.applicantId) } ?? "They"
            switch status {
            case "SHORTLISTED": session.toast("\(who) shortlisted. They can see it in their applications.")
            case "HIRED": session.toast("\(who) hired. Close the job when you've filled it.")
            case "REJECTED": session.toast("\(who) turned down.")
            default: session.toast("Updated.")
            }
            applications = applications.map { var a = $0; if a.id == applicationId { a.status = status }; return a }
            if let j = job {
                let fresh = applications.filter { $0.status == "APPLIED" }.count
                jobs = jobs.map { var r = $0; if r.id == j.id { r.newApplications = fresh }; return r }
            }
        } }
    }
    /// A manager opens (or reuses) a direct chat with an applicant. Applying lets the business reach them whatever their message setting; blocks still refuse.
    @discardableResult public func message(_ applicationId: String, onOpen: @escaping @MainActor (String) -> Void) -> Task<Void, Never> {
        go { onOpen(try await Backend.shared.startApplicantChat(applicationId)) }
    }
    /// An applicant (or anyone looking at the job) messages the business through its shared listing inbox.
    @discardableResult public func messageBusiness(_ listingId: String, onOpen: @escaping @MainActor (String) -> Void) -> Task<Void, Never> {
        if messaging { return Task {} }
        messaging = true   // set before the task starts, so the button is off the moment it is tapped
        return go { [self] in
            defer { messaging = false }
            let id: String = try await Backend.shared.rpc("start_listing_chat", ["p_listing": listingId])
            onOpen(id)
        }
    }

    // MARK: me as an applicant

    public func refreshMySkills() async throws {
        guard let me = session.me?.id else { return }
        let members: [MemberRow] = try await Backend.shared.select("listing_members", filters: [.eq("profile_id", me)])
        let ids = members.map(\.listingId)
        mySkills = ids.isEmpty ? [] : (try await listingsByIds(ids)).filter { $0.kind == "SKILL" }
    }
    @discardableResult public func loadMySkills() -> Task<Void, Never> { go { [self] in try await refreshMySkills() } }
    @discardableResult public func refreshMyApplications() -> Task<Void, Never> {
        go { [self] in loadingMine = true; defer { loadingMine = false }; myApplications = try await Backend.shared.myApplications() }
    }

    // MARK: jobs near me

    @discardableResult public func refreshNear() -> Task<Void, Never> {
        go { [self] in loadingNear = true; defer { loadingNear = false }; near = try await Backend.shared.jobsNear(session.here) }
    }

    public func signedOut() {
        listing = nil; jobs = []; manager = false; job = nil; jobMissing = nil; applications = []; skillProfiles = [:]; mySkills = []; myApplications = []; near = []
    }

    // MARK: labels

    public nonisolated static let managerRoles: Set<String> = ["OWNER", "ADMIN"]
    public nonisolated static let types: [(key: String, label: String)] = [("FULL_TIME", "Full time"), ("PART_TIME", "Part time"), ("GIG", "One-off")]
    public nonisolated static func typeLabel(_ type: String) -> String {
        if let t = types.first(where: { $0.key == type }) { return t.label }
        let s = type.lowercased().replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
    public nonisolated static func statusLabel(_ status: String) -> String {
        switch status {
        case "APPLIED": "Applied"
        case "SHORTLISTED": "Shortlisted"
        case "HIRED": "Hired"
        case "REJECTED": "Not selected"
        case "WITHDRAWN": "Withdrawn"
        default: status
        }
    }
    /// "450 m" or "2.3 km" (rounded half-up like Java's format, so 950 m reads "1.0 km").
    public nonisolated static func distance(_ m: Double) -> String {
        m < 950 ? "\(Int(m)) m" : String(format: "%.1f km", (m / 100).rounded(.toNearestOrAwayFromZero) / 10)
    }

    /// "just now", "5m ago", "3h ago", "yesterday", "on 12 Mar" from an ISO timestamp, to follow a verb ("Posted …", "Applied …").
    public nonisolated static func timeSince(_ iso: String, now: Date = Date()) -> String {
        let s = iso.replacingOccurrences(of: " ", with: "T")
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: s) ?? g.date(from: s) ?? g.date(from: s + "Z") else { return "" }
        let secs = max(Int(now.timeIntervalSince(d)), 0)
        switch secs {
        case ..<60: return "just now"
        case ..<3600: return "\(secs / 60)m ago"
        case ..<86400: return "\(secs / 3600)h ago"
        case ..<172800: return "yesterday"
        default:
            let out = DateFormatter(); out.dateFormat = "d MMM"; out.locale = Locale(identifier: "en_US_POSIX")
            return "on " + out.string(from: d)
        }
    }
    /// "No applications yet" / "1 application" / "N applications".
    public nonisolated static func applicationsLine(_ n: Int) -> String { n == 0 ? "No applications yet" : n == 1 ? "1 application" : "\(n) applications" }
    /// Order of applications on the manager's list: hired first, withdrawn last.
    public nonisolated static func statusRank(_ s: String) -> Int {
        switch s { case "HIRED": 0; case "SHORTLISTED": 1; case "APPLIED": 2; case "REJECTED": 3; default: 4 }
    }
}

private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
