#if os(macOS)
import Foundation
import BucksCore

/// Discover's part of the in-process server: services, search results and three listing profiles (a shop, a pro, a driver).
enum DiscoverFakes {
    static func hit(_ id: String, _ kind: String, _ title: String, _ category: String, _ area: String, up: Int, down: Int, dist: Double, online: Bool = true, details: [String: Any] = [:], matched: String? = nil, min: Int? = nil) -> [String: Any] {
        var h: [String: Any] = ["id": id, "kind": kind, "title": title, "category": category, "description": "", "area": area, "online": online, "trust_up": up, "trust_down": down, "details": details, "distance_m": dist]
        if let matched { h["matched_item"] = matched }
        if let min { h["min_price"] = min }
        return h
    }
    static var hits: [[String: Any]] {
        [hit("L-shop", "BUSINESS", "Fresh Mart", "Grocery", "Jayanagar 4th block", up: 42, down: 3, dist: 650, matched: "Sugar", min: 5),
         hit("L-pro", "SKILL", "Ravi Plumbing", "Plumber", "Jayanagar", up: 18, down: 1, dist: 1800, details: ["rate": "₹300 per visit"]),
         hit("L-drv", "DRIVER", "Imran S", "Auto", "BTM Layout", up: 12, down: 0, dist: 2400, details: ["vehicle_kind": "AUTO", "model": "TVS King"]),
         hit("L-flat", "ASSET", "2 BHK near Cool Joe's", "Flat", "Jayanagar 7th block", up: 0, down: 0, dist: 3100, online: false)]
    }
    static func listing(_ id: String) -> [String: Any]? {
        switch id {
        case "L-shop": return ["id": id, "kind": "BUSINESS", "owner_id": "o1", "title": "Fresh Mart", "category": "Grocery", "description": "Daily groceries, fruit and vegetables. Free delivery above ₹300.", "area": "Jayanagar 4th block",
                               "details": ["hours": "7 am to 10 pm", "free_delivery": true, "delivery_radius_km": 3, "gst_note": "Registered"], "status": "LIVE", "online": true, "trust_up": 42, "trust_down": 3, "service": "GROCERY"]
        case "L-pro": return ["id": id, "kind": "SKILL", "owner_id": "o2", "title": "Ravi Plumbing", "category": "Plumber", "description": "Leaks, taps and bathroom fittings. 8 years of experience.", "area": "Jayanagar",
                              "details": ["rate": "₹300 per visit", "level": "EXPERT", "languages": ["Kannada", "Hindi"]], "status": "LIVE", "online": true, "trust_up": 18, "trust_down": 1, "service": "GIGS"]
        case "L-drv": return ["id": id, "kind": "DRIVER", "owner_id": "o3", "title": "Imran S", "category": "Auto", "description": "", "area": "BTM Layout", "details": ["vehicle_kind": "AUTO", "model": "TVS King", "languages": "Kannada, Urdu"],
                              "status": "LIVE", "online": true, "trust_up": 12, "trust_down": 0]
        default: return nil
        }
    }
    static func items(_ id: String) -> [[String: Any]] {
        switch id {
        case "L-shop": return [["id": "i1", "listing_id": id, "kind": "PRODUCT", "name": "Sugar", "price": 48, "mrp": 55, "unit": "1 kg", "group_name": "Staples", "in_stock": true, "sort": 1, "stock": 4],
                               ["id": "i2", "listing_id": id, "kind": "PRODUCT", "name": "Toor dal", "price": 165, "unit": "1 kg", "group_name": "Staples", "in_stock": true, "sort": 2],
                               ["id": "i3", "listing_id": id, "kind": "PRODUCT", "name": "Tomato", "price": 36, "unit": "500 g", "group_name": "Vegetables", "in_stock": false, "sort": 3]]
        case "L-pro": return [["id": "s1", "listing_id": id, "kind": "SERVICE", "name": "Tap repair", "price": 300, "unit": "", "description": "Includes small parts.", "sort": 1, "details": ["pricing": "VISIT", "duration": "1 hour"]],
                              ["id": "s2", "listing_id": id, "kind": "SERVICE", "name": "Bathroom fitting", "price": 2500, "sort": 2, "details": ["pricing": "FROM"]]]
        default: return []
        }
    }
    static func services() -> [[String: Any]] {
        func s(_ key: String, _ label: String, _ state: String, supply: Int = 0, min: Int = 0, noun: String = "", interested: Int = 0, mine: Bool = false, minOnline: Int = 0, delivery: Bool = false) -> [String: Any] {
            ["key": key, "label": label, "mode": "AUTO", "state": state, "supply": supply, "min_supply": min, "online": 3, "min_online": minOnline, "supply_noun": noun, "radius_m": 3000, "delivery": delivery, "delivery_now": false, "interested": interested, "mine": mine]
        }
        return [s("TAXI", "Taxi", "OPEN"), s("AUTO", "Auto", "OPEN"), s("PARCEL", "Parcel", "LOCKED", supply: 2, min: 5, noun: "bike riders", interested: 7),
                s("FOOD", "Food", "QUIET", minOnline: 2, delivery: true), s("GROCERY", "Grocery", "OPEN"), s("VEGETABLES", "Vegetables", "LOCKED", supply: 4, min: 5, noun: "stalls"),
                s("MEAT", "Meat", "SOON"), s("SHOPPING", "Shopping", "OPEN"), s("GIGS", "Gigs", "OPEN"), s("JOBS", "Jobs", "OPEN"), s("PROPERTIES", "Properties", "LOCKED", supply: 1, min: 3, noun: "agents", interested: 1, mine: true)]
    }
}

func fakeDiscover(_ method: String, _ path: String, _ query: String, _ params: [String: Any]) -> (Int, Any)? {
    func eq(_ col: String) -> String? { query.components(separatedBy: "&").first { $0.hasPrefix(col + "=eq.") }.map { String($0.dropFirst(col.count + 4)) } }
    switch (method, path) {
    case ("POST", "/rest/v1/rpc/services_near"): return (200, DiscoverFakes.services())
    case ("POST", "/rest/v1/rpc/toggle_service_interest"): return (200, true)
    case ("POST", "/rest/v1/rpc/search_listings"):
        let kinds = params["kinds"] as? [String]
        let q = (params["q"] as? String ?? "").lowercased()
        return (200, DiscoverFakes.hits.filter { h in (kinds == nil || kinds!.contains(h["kind"] as? String ?? "")) && (q.isEmpty || (h["title"] as? String ?? "").lowercased().contains(q) || (h["matched_item"] as? String ?? "").lowercased().contains(q)) })
    case ("GET", "/rest/v1/listings"):
        guard let id = eq("id"), id.hasPrefix("L-") else { return nil }
        return (200, DiscoverFakes.listing(id).map { [$0] } ?? [])
    case ("GET", "/rest/v1/items"): return eq("listing_id").map { (200, DiscoverFakes.items($0)) }
    case ("GET", "/rest/v1/reviews"):
        guard let id = eq("listing_id"), id.hasPrefix("L-") else { return nil }
        return (200, [["id": "r1", "listing_id": id, "author_id": "u9", "vote": 1, "comment": "Quick and honest. Delivered in 20 minutes.", "created_at": "2026-09-28T10:00:00+00:00"],
                      ["id": "r2", "listing_id": id, "author_id": "me", "vote": -1, "comment": "Out of stock on two items.", "created_at": "2026-09-20T10:00:00+00:00"]])
    case ("GET", "/rest/v1/listing_members"): return eq("listing_id")?.hasPrefix("L-") == true ? (200, [["listing_id": "L-shop", "profile_id": "o1", "role": "OWNER"]]) : nil
    case ("POST", "/rest/v1/rpc/listing_counts"): return (200, [["recommendations": 14, "syncs": 36, "members": 2, "open_jobs": 1]])
    case ("GET", "/rest/v1/listing_points"): return (200, [["id": eq("id") ?? "", "lat": 12.9301, "lng": 77.5832]])
    case ("GET", "/rest/v1/listing_syncs"): return (200, [])
    case ("GET", "/rest/v1/posts"): return eq("listing_id")?.hasPrefix("L-") == true ? (200, [["id": "p1", "author_id": "o2", "listing_id": "L-pro", "body": "Fixed a leaking mixer in Jayanagar today.", "created_at": "2026-09-30T08:00:00+00:00", "up": 6, "down": 0, "comments": 2]]) : nil
    case ("POST", "/rest/v1/rpc/listing_badges"): return (200, [["doc_type": "FSSAI", "label": "FSSAI licence", "number": "11224999000123", "expires_on": "2027-03-12"]])
    case ("POST", "/rest/v1/rpc/suggest_people"): return (200, [["id": "u9", "name": "Meera Shah", "short_code": "CU0009", "area": "Jayanagar", "mutual": 3], ["id": "u8", "name": "Karthik R", "short_code": "CU0008", "area": "", "mutual": 0, "distance_m": 1400.0]])
    case ("POST", "/rest/v1/rpc/start_listing_chat"): return (200, "c1")
    default: return nil
    }
}
#endif
