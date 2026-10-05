import Foundation

// Jobs: reads that need more than the plain tables give (supabase/migrations/jobs.sql), plus the job writes of Backend.kt.
// Row decoding uses the shared snake-case strategy, so `listing_id` arrives as `listingId`.

private extension KeyedDecodingContainer {
    func str(_ k: Key, _ d: String = "") -> String { (try? decodeIfPresent(String.self, forKey: k)) ?? d }
    func int(_ k: Key, _ d: Int = 0) -> Int { (try? decodeIfPresent(Int.self, forKey: k)) ?? d }
    func dbl(_ k: Key, _ d: Double = 0) -> Double { (try? decodeIfPresent(Double.self, forKey: k)) ?? d }
    func bool(_ k: Key, _ d: Bool = true) -> Bool { (try? decodeIfPresent(Bool.self, forKey: k)) ?? d }
}

/// A job with its application counts (view jobs_with_counts). Counts follow row-level security: only managers see everyone's.
public struct JobListRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listingId: String
    public var title: String
    public var description: String
    public var pay: String
    public var jobType: String
    public var open: Bool
    public var createdBy: String
    public var createdAt: String
    public var applications: Int
    public var newApplications: Int
    public init(id: String, listingId: String, title: String, description: String = "", pay: String = "", jobType: String = "FULL_TIME", open: Bool = true,
                createdBy: String = "", createdAt: String = "", applications: Int = 0, newApplications: Int = 0) {
        self.id = id; self.listingId = listingId; self.title = title; self.description = description; self.pay = pay; self.jobType = jobType; self.open = open
        self.createdBy = createdBy; self.createdAt = createdAt; self.applications = applications; self.newApplications = newApplications
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); listingId = try c.decode(String.self, forKey: .listingId); title = try c.decode(String.self, forKey: .title)
        description = c.str(.description); pay = c.str(.pay); jobType = c.str(.jobType, "FULL_TIME"); open = c.bool(.open)
        createdBy = c.str(.createdBy); createdAt = c.str(.createdAt); applications = c.int(.applications); newApplications = c.int(.newApplications)
    }
    private enum K: String, CodingKey { case id, listingId, title, description, pay, jobType, open, createdBy, createdAt, applications, newApplications }
}

/// One job with its business (function job_page).
public struct JobPageRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listingId: String
    public var listingTitle: String
    public var area: String
    public var title: String
    public var description: String
    public var pay: String
    public var jobType: String
    public var open: Bool
    public var createdAt: String
    public init(id: String, listingId: String, listingTitle: String, area: String = "", title: String, description: String = "", pay: String = "",
                jobType: String = "FULL_TIME", open: Bool = true, createdAt: String = "") {
        self.id = id; self.listingId = listingId; self.listingTitle = listingTitle; self.area = area; self.title = title; self.description = description
        self.pay = pay; self.jobType = jobType; self.open = open; self.createdAt = createdAt
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); listingId = try c.decode(String.self, forKey: .listingId); listingTitle = try c.decode(String.self, forKey: .listingTitle)
        area = c.str(.area); title = try c.decode(String.self, forKey: .title); description = c.str(.description); pay = c.str(.pay)
        jobType = c.str(.jobType, "FULL_TIME"); open = c.bool(.open); createdAt = c.str(.createdAt)
    }
    private enum K: String, CodingKey { case id, listingId, listingTitle, area, title, description, pay, jobType, open, createdAt }
}

/// An open job near a point (function jobs_near).
public struct JobNearRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listingId: String
    public var listingTitle: String
    public var area: String
    public var title: String
    public var pay: String
    public var jobType: String
    public var createdAt: String
    public var distanceM: Double
    public init(id: String, listingId: String, listingTitle: String, area: String = "", title: String, pay: String = "", jobType: String = "FULL_TIME", createdAt: String = "", distanceM: Double = 0) {
        self.id = id; self.listingId = listingId; self.listingTitle = listingTitle; self.area = area; self.title = title; self.pay = pay
        self.jobType = jobType; self.createdAt = createdAt; self.distanceM = distanceM
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); listingId = try c.decode(String.self, forKey: .listingId); listingTitle = try c.decode(String.self, forKey: .listingTitle)
        area = c.str(.area); title = try c.decode(String.self, forKey: .title); pay = c.str(.pay); jobType = c.str(.jobType, "FULL_TIME")
        createdAt = c.str(.createdAt); distanceM = c.dbl(.distanceM)
    }
    private enum K: String, CodingKey { case id, listingId, listingTitle, area, title, pay, jobType, createdAt, distanceM }
}

/// One of my applications with the job and business names (function my_applications).
public struct MyApplicationRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var jobId: String
    public var status: String
    public var note: String
    public var createdAt: String
    public var jobTitle: String
    public var jobOpen: Bool
    public var pay: String
    public var jobType: String
    public var listingId: String
    public var listingTitle: String
    public var area: String
    public init(id: String, jobId: String, status: String, note: String = "", createdAt: String = "", jobTitle: String, jobOpen: Bool = true, pay: String = "",
                jobType: String = "FULL_TIME", listingId: String, listingTitle: String, area: String = "") {
        self.id = id; self.jobId = jobId; self.status = status; self.note = note; self.createdAt = createdAt; self.jobTitle = jobTitle; self.jobOpen = jobOpen
        self.pay = pay; self.jobType = jobType; self.listingId = listingId; self.listingTitle = listingTitle; self.area = area
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); jobId = try c.decode(String.self, forKey: .jobId); status = try c.decode(String.self, forKey: .status)
        note = c.str(.note); createdAt = c.str(.createdAt); jobTitle = try c.decode(String.self, forKey: .jobTitle); jobOpen = c.bool(.jobOpen); pay = c.str(.pay)
        jobType = c.str(.jobType, "FULL_TIME"); listingId = try c.decode(String.self, forKey: .listingId); listingTitle = try c.decode(String.self, forKey: .listingTitle); area = c.str(.area)
    }
    private enum K: String, CodingKey { case id, jobId, status, note, createdAt, jobTitle, jobOpen, pay, jobType, listingId, listingTitle, area }
}

/// An application row with its date (table applications; the shared ApplicationRow has no created_at).
public struct JobApplicationRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var jobId: String
    public var applicantId: String
    public var skillListingIds: [String]
    public var note: String
    public var status: String
    public var createdAt: String
    public init(id: String, jobId: String, applicantId: String, skillListingIds: [String] = [], note: String = "", status: String, createdAt: String = "") {
        self.id = id; self.jobId = jobId; self.applicantId = applicantId; self.skillListingIds = skillListingIds; self.note = note; self.status = status; self.createdAt = createdAt
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); jobId = try c.decode(String.self, forKey: .jobId); applicantId = try c.decode(String.self, forKey: .applicantId)
        skillListingIds = (try? c.decodeIfPresent([String].self, forKey: .skillListingIds)) ?? []; note = c.str(.note); status = try c.decode(String.self, forKey: .status); createdAt = c.str(.createdAt)
    }
    private enum K: String, CodingKey { case id, jobId, applicantId, skillListingIds, note, status, createdAt }
}

public extension Backend {
    func jobsWithCounts(_ listingId: String) async throws -> [JobListRow] {
        try await select("jobs_with_counts", filters: [.eq("listing_id", listingId)], order: "created_at", ascending: false)
    }
    func jobPage(_ jobId: String) async throws -> JobPageRow? { (try await rpcList("job_page", ["p_job": jobId]) as [JobPageRow]).first }
    func jobsNear(_ at: LatLng, radiusM: Int = 15_000) async throws -> [JobNearRow] {
        try await rpcList("jobs_near", ["lat": at.lat, "lng": at.lng, "radius_m": radiusM])
    }
    func myApplications() async throws -> [MyApplicationRow] { try await rpcList("my_applications") }
    /// Applications on a job, oldest first. Row-level security returns them all to a manager and only mine otherwise.
    func jobApplications(_ jobId: String) async throws -> [JobApplicationRow] {
        try await select("applications", filters: [.eq("job_id", jobId)], order: "created_at", ascending: true)
    }
    func postJob(listingId: String, me: String, title: String, description: String, pay: String, type: String) async throws {
        try await insertVoid("jobs", ["listing_id": listingId, "created_by": me, "title": title, "description": description, "pay": pay, "job_type": type])
    }
    func closeJob(_ id: String) async throws { try await update("jobs", ["open": false], filters: [.eq("id", id)]) }
    func reopenJob(_ id: String) async throws { try await update("jobs", ["open": true], filters: [.eq("id", id)]) }
    func applyToJob(_ jobId: String, me: String, skillListingIds: [String], note: String) async throws {
        try await insertVoid("applications", ["job_id": jobId, "applicant_id": me, "note": note, "skill_listing_ids": skillListingIds])
    }
    func setApplicationStatus(_ id: String, status: String) async throws { try await update("applications", ["status": status], filters: [.eq("id", id)]) }
    /// A manager opens (or reuses) a direct chat with someone who applied, whatever their message setting; returns the conversation id.
    func startApplicantChat(_ applicationId: String) async throws -> String { try await rpc("start_applicant_chat", ["p_application": applicationId]) }
}
