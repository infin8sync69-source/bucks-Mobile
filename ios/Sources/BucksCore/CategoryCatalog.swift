import Foundation

// What a business or a pro is, as a long searchable catalogue grouped by field, plus "add your own" (port of ui/screens/manage/Categories.kt).
// The category is free text on the listing (it feeds search); only the few food, grocery, fresh, meat and property names also decide the
// service on the server (service_for_category in supabase/migrations/services.sql and serviceForCategory in ServicesStore.swift must agree).

/// One field of the catalogue ("Food and drink") and the types under it.
public struct CategoryGroup: Hashable, Sendable {
    public var name: String
    public var items: [String]
    public init(_ name: String, _ items: [String]) { self.name = name; self.items = items }
}

/// Business types by field. Pharmacy is left out on purpose: selling medicines online needs its own licensing.
public let businessCategoryGroups: [CategoryGroup] = [
    CategoryGroup("Food and drink", ["Restaurant", "Cafe", "Bakery", "Sweets", "Cloud kitchen", "Tiffin", "Catering", "Juice bar", "Ice cream", "Street food", "Food truck"]),
    CategoryGroup("Grocery and daily needs", ["Grocery", "Supermarket", "Dairy", "Kirana", "Organic store"]),
    CategoryGroup("Fresh produce", ["Vegetables", "Fruits"]),
    CategoryGroup("Meat and fish", ["Chicken", "Mutton", "Fish", "Eggs"]),
    CategoryGroup("Fashion and lifestyle", ["Clothing", "Footwear", "Jewellery", "Bags and accessories", "Handloom and crafts", "Gifts", "Toys", "Books", "Stationery", "Cosmetics store", "Optical"]),
    CategoryGroup("Home and electronics", ["Electronics", "Mobile and accessories", "Appliances", "Furniture", "Hardware", "Paint and tiles", "Kitchenware", "Home decor", "Lighting"]),
    CategoryGroup("Beauty and wellness", ["Salon", "Spa", "Barber", "Beauty parlour", "Tattoo studio", "Gym", "Yoga studio", "Dance studio", "Meditation centre"]),
    CategoryGroup("Health and care", ["Clinic", "Dental clinic", "Diagnostic lab", "Physiotherapy", "Ayurveda", "Eye care", "Veterinary clinic", "Pet shop"]),
    CategoryGroup("Repair and home services", ["Mobile repair", "Appliance repair", "Computer repair", "Tailor", "Laundry and dry cleaning", "Cleaning service", "Pest control", "Packers and movers", "Interior design", "Construction", "Security services", "Courier", "Printing and xerox"]),
    CategoryGroup("IT and digital", ["IT services", "Software company", "Mobile app agency", "Web design agency", "Digital marketing", "Cloud and hosting", "Cybersecurity", "AI and data", "IT training", "Cyber cafe", "Computer sales"]),
    CategoryGroup("Professional services", ["Accounting and tax", "Legal", "Insurance", "Financial advisor", "Architect", "Consulting", "Recruitment", "Photography studio", "Event management", "Wedding planner", "Travel agency", "Notary"]),
    CategoryGroup("Education", ["School", "College", "Coaching centre", "Tuition centre", "Preschool", "Skill training", "Language institute", "Music school", "Driving school", "Library"]),
    CategoryGroup("Automotive", ["Garage", "Car wash", "Showroom", "Spare parts", "Tyre shop", "Bike repair"]),
    CategoryGroup("Property", ["Property owner", "Real estate agent", "Builder"]),
    CategoryGroup("Community and non-profit", ["NGO", "Charity trust", "Community group", "Resident association", "Religious place", "Club", "Foundation", "Self-help group", "Cooperative", "Alumni association"]),
    CategoryGroup("Farming and manufacturing", ["Farm produce", "Nursery and plants", "Manufacturing unit", "Wholesale trader", "Printing press", "Packaging", "Fabrication"]),
]

/// What a person does, by field.
public let skillCategoryGroups: [CategoryGroup] = [
    CategoryGroup("IT and software", ["Software developer", "Web developer", "Mobile app developer", "UI/UX designer", "Data analyst", "Data scientist", "AI and ML engineer", "DevOps and cloud", "Cybersecurity", "QA tester", "Game developer", "IT support", "Network engineer", "Database admin", "Technical writer", "Digital marketer", "SEO specialist"]),
    CategoryGroup("Design and creative", ["Designer", "Graphic designer", "Illustrator", "Video editor", "Animator", "Photographer", "Videographer", "Content writer", "Translator", "Voice artist", "Musician", "Singer", "DJ", "Dancer", "Makeup artist", "Mehendi artist"]),
    CategoryGroup("Teaching and training", ["Tutor", "Maths tutor", "Science tutor", "English tutor", "Language teacher", "Music teacher", "Art teacher", "Yoga instructor", "Fitness trainer", "Coding instructor", "Exam coach", "Special educator"]),
    CategoryGroup("Home services", ["Plumber", "Electrician", "Carpenter", "Painter", "Cleaner", "AC technician", "Appliance technician", "Mason", "Welder", "Gardener", "Pest control", "Handyman", "Interior designer", "Tile fitter", "Locksmith", "CCTV installer"]),
    CategoryGroup("Health and care", ["Doctor", "Nurse", "Physiotherapist", "Dietitian", "Counsellor", "Caregiver", "Babysitter", "Ayurveda practitioner", "Lab technician", "Veterinarian", "Dog trainer"]),
    CategoryGroup("Business and professional", ["Accountant", "Tax consultant", "Lawyer", "Architect", "Civil engineer", "Business consultant", "Recruiter", "Insurance agent", "Financial planner", "Notary"]),
    CategoryGroup("Food and events", ["Chef", "Cook", "Caterer", "Baker", "Wedding planner", "Event host", "Decorator"]),
    CategoryGroup("Beauty and wellness", ["Beautician", "Hair stylist", "Barber", "Massage therapist"]),
    CategoryGroup("Drivers and logistics", ["Driver", "Delivery partner", "Mover"]),
    CategoryGroup("Other trades", ["Tailor", "Cobbler", "Mechanic", "Bike mechanic", "Tow operator"]),
]

/// The group of categories other owners added (from the server), shown after the built-in ones.
public let addedByOthersGroup = "Added by others"

/// A category the owner typed: spaces tidied, first letter capital, 2 to 40 characters of letters, digits and & / , ' . ( ) + -; nil when it isn't usable.
public func cleanCategory(_ raw: String) -> String? {
    let s = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    guard (2...40).contains(s.count), s.allSatisfy({ $0.isLetter || $0.isNumber || " &/,'.()+-".contains($0) }) else { return nil }
    return s.prefix(1).uppercased() + String(s.dropFirst())
}

/// What the category picker shows for one search text: the groups that still match, and whether to offer "Use “…” as my category".
public struct CategoryPickerModel: Sendable {
    /// Built-in groups plus "Added by others", filtered by the search text (all of them while it is empty).
    public let groups: [CategoryGroup]
    /// The typed text as a usable category of its own (nil when it is empty or not allowed).
    public let own: String?
    /// True when `own` is already in the list (same letters, any case), so no "Use ..." row is needed.
    public let exact: Bool
    /// Show the "Use “…” as my category" row.
    public var offersOwn: Bool { own != nil && !exact }

    /// `others` are the server's suggestions; the ones already built in (any case) are dropped.
    public init(kind: String, others: [String], query: String) {
        let builtIn = kind == "SKILL" ? skillCategoryGroups : businessCategoryGroups
        let known = Set(builtIn.flatMap(\.items).map { $0.lowercased() })
        var seen = Set<String>()
        let extra = others.filter { known.contains($0.lowercased()) ? false : seen.insert($0.lowercased()).inserted }
        let all = builtIn + (extra.isEmpty ? [] : [CategoryGroup(addedByOthersGroup, extra)])
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { groups = all }
        else { groups = all.compactMap { (g: CategoryGroup) -> CategoryGroup? in
            let hit = g.items.filter { $0.range(of: q, options: .caseInsensitive) != nil }
            return hit.isEmpty ? nil : CategoryGroup(g.name, hit)
        } }
        let own = cleanCategory(q)
        self.own = own
        exact = own.map { o in all.contains { g in g.items.contains { $0.caseInsensitiveCompare(o) == .orderedSame } } } ?? false
    }
}
