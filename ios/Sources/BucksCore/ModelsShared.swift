import Foundation

// Row types shared by several areas, named as in supabase/schema.sql (Backend.kt "rows" section). The decoder maps snake_case to camelCase.
// Columns the Kotlin gives a default decode to the same default here, so a missing column never fails a whole list.

private extension KeyedDecodingContainer {
    func str(_ k: Key, _ d: String = "") -> String { (try? decodeIfPresent(String.self, forKey: k)) ?? d }
    func opt(_ k: Key) -> String? { (try? decodeIfPresent(String.self, forKey: k)) ?? nil }
    func int(_ k: Key, _ d: Int = 0) -> Int { (try? decodeIfPresent(Int.self, forKey: k)) ?? d }
    func dbl(_ k: Key, _ d: Double = 0) -> Double { (try? decodeIfPresent(Double.self, forKey: k)) ?? d }
    func bool(_ k: Key, _ d: Bool = false) -> Bool { (try? decodeIfPresent(Bool.self, forKey: k)) ?? d }
    func json(_ k: Key) -> JSONValue { (try? decodeIfPresent(JSONValue.self, forKey: k)) ?? .emptyObject }
}

/// A photo in a listing's gallery or a product's photos: a public listing-media URL and an optional caption.
public struct MediaPhoto: Codable, Hashable, Sendable {
    public var url: String
    public var caption: String
    public init(url: String, caption: String = "") { self.url = url; self.caption = caption }
    public init(from d: Decoder) throws { let c = try d.container(keyedBy: K.self); url = c.str(.url); caption = c.str(.caption) }
    private enum K: String, CodingKey { case url, caption }
}

public struct SyncRow: Codable, Hashable, Sendable { public var requesterId: String; public var addresseeId: String; public var status: String }

public struct ListingRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var ownerId: String
    public var title: String
    public var category: String
    public var description: String
    public var photoUrl: String?
    public var area: String
    public var details: JSONValue
    public var status: String
    public var online: Bool
    public var trustUp: Int
    public var trustDown: Int
    /// FOOD, GROCERY, … (services.sql); GIGS for skills, nil for drivers.
    public var service: String?
    public var complianceHold: Bool
    /// Up to 20 photos: the shop, a worker's portfolio, the rooms of a flat. The cover stays in `photoUrl`.
    public var gallery: [MediaPhoto]
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); kind = try c.decode(String.self, forKey: .kind); ownerId = try c.decode(String.self, forKey: .ownerId); title = try c.decode(String.self, forKey: .title)
        category = c.str(.category); description = c.str(.description); photoUrl = c.opt(.photoUrl); area = c.str(.area); details = c.json(.details)
        status = c.str(.status, "PENDING"); online = c.bool(.online); trustUp = c.int(.trustUp); trustDown = c.int(.trustDown); service = c.opt(.service)
        complianceHold = c.bool(.complianceHold); gallery = (try? c.decodeIfPresent([MediaPhoto].self, forKey: .gallery)) ?? []
    }
    private enum K: String, CodingKey { case id, kind, ownerId, title, category, description, photoUrl, area, details, status, online, trustUp, trustDown, service, complianceHold, gallery }
    public var trust: Trust { Trust(up: trustUp, down: trustDown) }
}

public struct SearchHit: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var title: String
    public var category: String
    public var description: String
    public var photoUrl: String?
    public var area: String
    public var online: Bool
    public var trustUp: Int
    public var trustDown: Int
    public var details: JSONValue
    public var distanceM: Double
    public var matchedItem: String?
    public var minPrice: Int?
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); kind = try c.decode(String.self, forKey: .kind); title = try c.decode(String.self, forKey: .title)
        category = c.str(.category); description = c.str(.description); photoUrl = c.opt(.photoUrl); area = c.str(.area); online = c.bool(.online)
        trustUp = c.int(.trustUp); trustDown = c.int(.trustDown); details = c.json(.details); distanceM = c.dbl(.distanceM); matchedItem = c.opt(.matchedItem)
        minPrice = (try? c.decodeIfPresent(Int.self, forKey: .minPrice)) ?? nil
    }
    private enum K: String, CodingKey { case id, kind, title, category, description, photoUrl, area, online, trustUp, trustDown, details, distanceM, matchedItem, minPrice }
    public var trust: Trust { Trust(up: trustUp, down: trustDown) }
}

/// One line of the Notifications tab (notifications.sql). `route` is where a tap goes, checked by the push route allow-list.
public struct NotificationRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var title: String
    public var body: String
    public var route: String?
    public var createdAt: String
    public var readAt: String?
    public init(id: String, kind: String, title: String, body: String = "", route: String? = nil, createdAt: String = "", readAt: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.body = body; self.route = route; self.createdAt = createdAt; self.readAt = readAt
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); kind = c.str(.kind); title = c.str(.title); body = c.str(.body); route = c.opt(.route); createdAt = c.str(.createdAt); readAt = c.opt(.readAt)
    }
    private enum K: String, CodingKey { case id, kind, title, body, route, createdAt, readAt }
}

public struct MemberRow: Codable, Hashable, Sendable { public var listingId: String; public var profileId: String; public var role: String }

public struct ItemRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String?
    public var listingId: String
    public var kind: String
    public var name: String
    public var price: Int
    public var mrp: Int?
    public var unit: String
    public var groupName: String
    public var photoUrl: String?
    public var inStock: Bool
    public var sort: Int
    public var description: String
    /// How many are left; nil when the owner doesn't count stock. 0 means out of stock (the server switches it off).
    public var stock: Int?
    /// Up to 8 photos; the first one is also `photoUrl`, which search and older screens show.
    public var photos: [MediaPhoto]
    /// Service extras: duration, pricing (FIXED / HOURLY / VISIT / QUOTE); product extras: veg, brand.
    public var details: JSONValue
    public init(id: String? = nil, listingId: String, kind: String = "PRODUCT", name: String, price: Int, mrp: Int? = nil, unit: String = "", groupName: String = "", photoUrl: String? = nil, inStock: Bool = true, sort: Int = 0, description: String = "", stock: Int? = nil, photos: [MediaPhoto] = [], details: JSONValue = .emptyObject) {
        self.id = id; self.listingId = listingId; self.kind = kind; self.name = name; self.price = price; self.mrp = mrp; self.unit = unit; self.groupName = groupName; self.photoUrl = photoUrl
        self.inStock = inStock; self.sort = sort; self.description = description; self.stock = stock; self.photos = photos; self.details = details
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.opt(.id); listingId = try c.decode(String.self, forKey: .listingId); kind = c.str(.kind, "PRODUCT"); name = try c.decode(String.self, forKey: .name); price = c.int(.price)
        mrp = (try? c.decodeIfPresent(Int.self, forKey: .mrp)) ?? nil; unit = c.str(.unit); groupName = c.str(.groupName); photoUrl = c.opt(.photoUrl); inStock = c.bool(.inStock, true)
        sort = c.int(.sort); description = c.str(.description); stock = (try? c.decodeIfPresent(Int.self, forKey: .stock)) ?? nil
        photos = (try? c.decodeIfPresent([MediaPhoto].self, forKey: .photos)) ?? []; details = c.json(.details)
    }
    private enum K: String, CodingKey { case id, listingId, kind, name, price, mrp, unit, groupName, photoUrl, inStock, sort, description, stock, photos, details }
    /// The body for insert/update (snake_case column names).
    public var body: [String: Any?] {
        ["listing_id": listingId, "kind": kind, "name": name, "price": price, "mrp": mrp, "unit": unit, "group_name": groupName, "photo_url": photoUrl, "in_stock": inStock, "sort": sort,
         "description": description, "stock": stock, "photos": photos.map { ["url": $0.url, "caption": $0.caption] }, "details": details.any]
    }
}

public struct PostRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var authorId: String
    public var listingId: String?
    public var body: String
    public var media: [JSONValue]
    public var visibility: String
    public var up: Int
    public var down: Int
    public var comments: Int
    public var createdAt: String
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); authorId = try c.decode(String.self, forKey: .authorId); listingId = c.opt(.listingId); body = c.str(.body)
        media = (try? c.decodeIfPresent([JSONValue].self, forKey: .media)) ?? []; visibility = c.str(.visibility, "LOCAL"); up = c.int(.up); down = c.int(.down); comments = c.int(.comments); createdAt = c.str(.createdAt)
    }
    private enum K: String, CodingKey { case id, authorId, listingId, body, media, visibility, up, down, comments, createdAt }
}

public struct InviteRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listingId: String?
    public var vehicleId: String?
    public var inviterId: String
    public var inviteeId: String
    public var role: String
    public var status: String
}

public struct OrderRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listingId: String
    public var buyerId: String
    public var subtotal: Int
    public var deliveryFee: Int
    public var feePaidBy: String
    public var deliveryMode: String
    public var payment: String
    public var dropLabel: String
    public var status: String
    public var acceptBy: String
    public var createdAt: String
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); listingId = try c.decode(String.self, forKey: .listingId); buyerId = try c.decode(String.self, forKey: .buyerId); subtotal = c.int(.subtotal)
        deliveryFee = c.int(.deliveryFee); feePaidBy = c.str(.feePaidBy, "BUYER"); deliveryMode = c.str(.deliveryMode, "MARKETPLACE"); payment = c.str(.payment, "UPI"); dropLabel = c.str(.dropLabel)
        status = c.str(.status); acceptBy = c.str(.acceptBy); createdAt = c.str(.createdAt)
    }
    private enum K: String, CodingKey { case id, listingId, buyerId, subtotal, deliveryFee, feePaidBy, deliveryMode, payment, dropLabel, status, acceptBy, createdAt }
}

public struct ReviewRow: Codable, Hashable, Sendable, Identifiable { public var id: String; public var listingId: String; public var authorId: String; public var vote: Int; public var comment: String; public var createdAt: String }

public struct JobRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listingId: String
    public var title: String
    public var description: String
    public var pay: String
    public var jobType: String
    public var open: Bool
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); listingId = try c.decode(String.self, forKey: .listingId); title = try c.decode(String.self, forKey: .title); description = c.str(.description)
        pay = c.str(.pay); jobType = c.str(.jobType, "FULL_TIME"); open = c.bool(.open, true)
    }
    private enum K: String, CodingKey { case id, listingId, title, description, pay, jobType, open }
}

public struct ApplicationRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var jobId: String
    public var applicantId: String
    public var skillListingIds: [String]
    public var note: String
    public var status: String
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); jobId = try c.decode(String.self, forKey: .jobId); applicantId = try c.decode(String.self, forKey: .applicantId)
        skillListingIds = (try? c.decodeIfPresent([String].self, forKey: .skillListingIds)) ?? []; note = c.str(.note); status = c.str(.status)
    }
    private enum K: String, CodingKey { case id, jobId, applicantId, skillListingIds, note, status }
}

/// A file already uploaded to the "chat" bucket at `path`.
public struct FileRef: Hashable, Sendable { public var path: String, name: String, mime: String, size: Int
    public init(path: String, name: String, mime: String, size: Int) { self.path = path; self.name = name; self.mime = mime; self.size = size } }

public struct SettingsRow: Codable, Hashable, Sendable {
    public var profileId: String
    public var whoCanMessage: String
    public var whoCanSync: String
    public var momentsAudience: String
    public var readReceipts: Bool
    public var showOnline: Bool
    public var discoverable: Bool
    public var notify: JSONValue
    public var quietHours: JSONValue?
    public var app: JSONValue
    public init(profileId: String) { self.init(profileId: profileId, whoCanMessage: "SYNCED", whoCanSync: "EVERYONE", momentsAudience: "SYNCED", readReceipts: true, showOnline: true, discoverable: true, notify: .emptyObject, quietHours: nil, app: .emptyObject) }
    public init(profileId: String, whoCanMessage: String, whoCanSync: String, momentsAudience: String, readReceipts: Bool, showOnline: Bool, discoverable: Bool, notify: JSONValue, quietHours: JSONValue?, app: JSONValue) {
        self.profileId = profileId; self.whoCanMessage = whoCanMessage; self.whoCanSync = whoCanSync; self.momentsAudience = momentsAudience; self.readReceipts = readReceipts
        self.showOnline = showOnline; self.discoverable = discoverable; self.notify = notify; self.quietHours = quietHours; self.app = app
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        profileId = try c.decode(String.self, forKey: .profileId); whoCanMessage = c.str(.whoCanMessage, "SYNCED"); whoCanSync = c.str(.whoCanSync, "EVERYONE"); momentsAudience = c.str(.momentsAudience, "SYNCED")
        readReceipts = c.bool(.readReceipts, true); showOnline = c.bool(.showOnline, true); discoverable = c.bool(.discoverable, true); notify = c.json(.notify)
        quietHours = (try? c.decodeIfPresent(JSONValue.self, forKey: .quietHours)).flatMap { $0 == .null ? nil : $0 }; app = c.json(.app)
    }
    private enum K: String, CodingKey { case profileId, whoCanMessage, whoCanSync, momentsAudience, readReceipts, showOnline, discoverable, notify, quietHours, app }
    /// The body for upsert (snake_case column names).
    public var body: [String: Any?] {
        ["profile_id": profileId, "who_can_message": whoCanMessage, "who_can_sync": whoCanSync, "moments_audience": momentsAudience, "read_receipts": readReceipts, "show_online": showOnline,
         "discoverable": discoverable, "notify": notify.any, "quiet_hours": quietHours?.any, "app": app.any]
    }
}

public struct BlockRow: Codable, Hashable, Sendable { public var blockerId: String; public var blockedId: String }
public struct CloseFriendRow: Codable, Hashable, Sendable { public var profileId: String; public var friendId: String }

public struct InboxRow: Codable, Hashable, Sendable, Identifiable {
    public var conversationId: String
    public var kind: String
    public var title: String?
    public var otherId: String?
    public var otherName: String?
    public var otherCode: String?
    public var lastBody: String?
    public var lastAt: String
    public var unread: Int
    public var muted: Bool
    public var archived: Bool
    public var id: String { conversationId }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        conversationId = try c.decode(String.self, forKey: .conversationId); kind = c.str(.kind); title = c.opt(.title); otherId = c.opt(.otherId); otherName = c.opt(.otherName); otherCode = c.opt(.otherCode)
        lastBody = c.opt(.lastBody); lastAt = c.str(.lastAt); unread = c.int(.unread); muted = c.bool(.muted); archived = c.bool(.archived)
    }
    private enum K: String, CodingKey { case conversationId, kind, title, otherId, otherName, otherCode, lastBody, lastAt, unread, muted, archived }
}

public struct MessageRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var conversationId: String
    public var senderId: String
    public var body: String
    public var attachment: JSONValue?
    public var replyTo: String?
    public var momentId: String?
    public var createdAt: String
    public var editedAt: String?
    public var deletedAt: String?
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); conversationId = try c.decode(String.self, forKey: .conversationId); senderId = try c.decode(String.self, forKey: .senderId); body = c.str(.body)
        attachment = (try? c.decodeIfPresent(JSONValue.self, forKey: .attachment)).flatMap { $0 == .null ? nil : $0 }; replyTo = c.opt(.replyTo); momentId = c.opt(.momentId)
        createdAt = c.str(.createdAt); editedAt = c.opt(.editedAt); deletedAt = c.opt(.deletedAt)
    }
    private enum K: String, CodingKey { case id, conversationId, senderId, body, attachment, replyTo, momentId, createdAt, editedAt, deletedAt }
}

public struct FeedRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var authorId: String
    public var authorName: String
    public var authorCode: String
    public var listingId: String?
    public var listingTitle: String?
    public var body: String
    public var media: [JSONValue]
    public var visibility: String
    public var area: String
    public var up: Int
    public var down: Int
    public var comments: Int
    public var myVote: Int?
    public var createdAt: String
    public var synced: Bool
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); authorId = try c.decode(String.self, forKey: .authorId); authorName = c.str(.authorName); authorCode = c.str(.authorCode); listingId = c.opt(.listingId)
        listingTitle = c.opt(.listingTitle); body = c.str(.body); media = (try? c.decodeIfPresent([JSONValue].self, forKey: .media)) ?? []; visibility = c.str(.visibility, "LOCAL"); area = c.str(.area)
        up = c.int(.up); down = c.int(.down); comments = c.int(.comments); myVote = (try? c.decodeIfPresent(Int.self, forKey: .myVote)) ?? nil; createdAt = c.str(.createdAt); synced = c.bool(.synced)
    }
    private enum K: String, CodingKey { case id, authorId, authorName, authorCode, listingId, listingTitle, body, media, visibility, area, up, down, comments, myVote, createdAt, synced }
}

public struct CommentRow: Codable, Hashable, Sendable, Identifiable { public var id: String; public var postId: String; public var authorId: String; public var body: String; public var createdAt: String }

public struct TrayRow: Codable, Hashable, Sendable, Identifiable {
    public var authorId: String
    public var authorName: String
    public var authorCode: String
    public var listingTitle: String?
    public var moments: Int
    public var unseen: Int
    public var latestAt: String
    public var isMe: Bool
    public var id: String { authorId }
}

public struct MomentRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var authorId: String
    public var mediaPath: String
    public var mediaType: String
    public var caption: String
    public var audience: String
    public var createdAt: String
    public var expiresAt: String
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); authorId = try c.decode(String.self, forKey: .authorId); mediaPath = c.str(.mediaPath); mediaType = c.str(.mediaType); caption = c.str(.caption)
        audience = c.str(.audience); createdAt = c.str(.createdAt); expiresAt = c.str(.expiresAt)
    }
    private enum K: String, CodingKey { case id, authorId, mediaPath, mediaType, caption, audience, createdAt, expiresAt }
}

public struct ViewerRow: Codable, Hashable, Sendable { public var viewerId: String; public var name: String; public var reaction: String?; public var viewedAt: String }

public struct PersonSuggestion: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var shortCode: String
    public var area: String
    public var mutual: Int
    public var distanceM: Double?
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); name = c.str(.name); shortCode = c.str(.shortCode); area = c.str(.area); mutual = c.int(.mutual); distanceM = (try? c.decodeIfPresent(Double.self, forKey: .distanceM)) ?? nil
    }
    private enum K: String, CodingKey { case id, name, shortCode, area, mutual, distanceM }
}

public struct ListingSuggestion: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var title: String
    public var category: String
    public var area: String
    public var syncedRecommenders: Int
    public var distanceM: Double?
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); kind = c.str(.kind); title = c.str(.title); category = c.str(.category); area = c.str(.area); syncedRecommenders = c.int(.syncedRecommenders)
        distanceM = (try? c.decodeIfPresent(Double.self, forKey: .distanceM)) ?? nil
    }
    private enum K: String, CodingKey { case id, kind, title, category, area, syncedRecommenders, distanceM }
}

/// A file picked on the phone, ready to upload: bytes, a display name and its type (Upload.kt `Picked`).
public struct Picked: Hashable, Sendable {
    public var data: Data
    public var name: String
    public var mime: String
    public init(data: Data, name: String, mime: String) { self.data = data; self.name = name; self.mime = mime }
    public var isImage: Bool { mime.hasPrefix("image/") }
    public var isVideo: Bool { mime.hasPrefix("video/") }
    /// Unique object name inside a storage folder; keeps the extension so previews and downloads know the type.
    public func objectName() -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + "." + (ext.isEmpty ? (isImage ? "jpg" : "bin") : ext)
    }
}
