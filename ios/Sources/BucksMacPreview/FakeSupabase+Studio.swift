#if os(macOS)
import Foundation

/// Fake listings I run (a live shop, a pending skill, a driver profile) for the Studio screens in the Mac preview harness.
enum StudioFakes {
    static func listing(_ id: String, kind: String, title: String, category: String, status: String, online: Bool, service: String? = nil, photo: String? = nil, details: [String: Any] = [:], description: String = "") -> [String: Any] {
        var r: [String: Any] = ["id": id, "kind": kind, "owner_id": "me", "title": title, "category": category, "description": description, "area": "Jayanagar", "details": details,
                                "status": status, "online": online, "trust_up": kind == "BUSINESS" ? 14 : 0, "trust_down": kind == "BUSINESS" ? 2 : 0, "gallery": [[String: Any]]()]
        if let service { r["service"] = service }
        if let photo { r["photo_url"] = photo }
        return r
    }
    static let all: [[String: Any]] = [
        listing("S-shop", kind: "BUSINESS", title: "Sri Lakshmi Stores", category: "Grocery", status: "LIVE", online: true, service: "GROCERY",
                details: ["hours": "9 am - 9 pm", "free_delivery": true, "delivery_radius_km": 3, "cod": false], description: "Daily groceries, fresh vegetables and dairy since 1998."),
        listing("S-skill", kind: "SKILL", title: "Plumber", category: "Plumber", status: "PENDING", online: false, details: ["level": "Expert", "rate": "₹300 per visit", "languages": ["Kannada", "English"]]),
        listing("S-asset", kind: "ASSET", title: "2BHK flat in 4th Block", category: "Flat", status: "PENDING", online: false, details: ["mode": "RENT", "price": 28000, "price_unit": "MONTH", "bedrooms": 2, "furnishing": "Semi-furnished"], description: "East facing, near the park."),
    ]
    static func items(_ id: String) -> [[String: Any]] {
        guard id == "S-shop" else { return [] }
        func i(_ n: String, _ name: String, _ price: Int, _ group: String, stock: Int? = nil, inStock: Bool = true, mrp: Int? = nil) -> [String: Any] {
            var r: [String: Any] = ["id": n, "listing_id": id, "kind": "PRODUCT", "name": name, "price": price, "unit": "1 kg", "group_name": group, "in_stock": inStock, "sort": 0, "description": "", "photos": [[String: Any]](), "details": [String: Any]()]
            if let stock { r["stock"] = stock }
            if let mrp { r["mrp"] = mrp }
            return r
        }
        return [i("i1", "Sona masoori rice", 62, "Rice and grains", stock: 25, mrp: 70), i("i2", "Toor dal", 148, "Dals", stock: 0, inStock: false), i("i3", "Sugar", 45, "")]
    }
}

func fakeStudio(_ method: String, _ path: String, _ query: String, _ params: [String: Any]) -> (Int, Any)? {
    func eq(_ col: String) -> String? { query.components(separatedBy: "&").first { $0.hasPrefix(col + "=eq.") }.map { String($0.dropFirst(col.count + 4)) } }
    switch (method, path) {
    case ("GET", "/rest/v1/listing_members") where eq("profile_id") == "me":
        return (200, StudioFakes.all.map { ["listing_id": $0["id"] as? String ?? "", "profile_id": "me", "role": "OWNER"] })
    case ("GET", "/rest/v1/listings") where query.contains("id=in.") && query.contains("S-"): return (200, StudioFakes.all)
    case ("GET", "/rest/v1/recommendations"): return (200, ["a", "b", "c"].map { ["listing_id": "S-skill", "recommender_id": $0] })
    case ("GET", "/rest/v1/settings") where eq("key") == "min_recommendations": return (200, [["key": "min_recommendations", "value": 7]])
    case ("GET", "/rest/v1/items") where eq("listing_id")?.hasPrefix("S-") == true: return (200, StudioFakes.items(eq("listing_id") ?? ""))
    case ("GET", "/rest/v1/invites"): return (200, [])
    case ("POST", "/rest/v1/rpc/my_invites"): return (200, [["id": "inv1", "listing_id": "L-x", "inviter_id": "u9", "inviter_name": "Meera Shah", "role": "ADMIN", "title": "Chai Point", "kind": "BUSINESS"]])
    case ("POST", "/rest/v1/rpc/listing_compliance"):
        return (200, [["doc_type": "FSSAI", "label": "FSSAI licence", "required": true, "status": "PENDING"], ["doc_type": "GST", "label": "GST certificate", "required": false, "status": "MISSING"]])
    case ("GET", "/rest/v1/posts") where eq("listing_id")?.hasPrefix("S-") == true:
        return (200, [["id": "p1", "author_id": "me", "listing_id": "S-shop", "body": "Fresh stock in today: mangoes from Ramanagara.", "created_at": "2026-09-30T08:00:00+00:00", "up": 6, "down": 0, "comments": 2]])
    case ("GET", "/rest/v1/reviews") where eq("listing_id")?.hasPrefix("S-") == true:
        return (200, [["id": "r1", "listing_id": "S-shop", "author_id": "u9", "vote": 1, "comment": "Quick and honest. Delivered in 20 minutes.", "created_at": "2026-09-28T10:00:00+00:00"]])
    default: return nil
    }
}
#endif
