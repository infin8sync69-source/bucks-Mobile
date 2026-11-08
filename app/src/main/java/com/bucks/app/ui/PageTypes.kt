package com.bucks.app.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.ui.graphics.vector.ImageVector
import com.bucks.app.data.ListingRow
import com.bucks.app.data.SearchHit
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive

/*
 * Page types: what a BUSINESS listing is (shop, local service, company, NGO, school...). The type decides the catalogue tab, the
 * primary button, the tabs and the Home tile. The server holds the same registry (listing_types, migration page_types.sql) and
 * enforces it; this copy is what the app renders with, so screens work offline and old rows (no type) still get a sensible page.
 */

/**
 * The fourth tab of every profile: the page's catalogue. The owner names it ("Products", "Products & Services", "Courses & Events")
 * and picks what it holds, in Studio or when creating the page; both live in listings.details (catalogue_label, catalogue_kinds).
 * The server lets items in only of these kinds (listing_item_kinds, migration catalogue_tab.sql) and orders only when PRODUCT is one.
 */
data class Catalogue(val label: String, val kinds: List<String>, val custom: Boolean) {
    val sellsProducts get() = "PRODUCT" in kinds
    /** The items.kind a new entry gets by default. */
    val newItemKind get() = kinds.firstOrNull() ?: "SERVICE"
}

/** A group of types: one Home tile, one search chip. */
data class PageGroup(val key: String, val label: String, val icon: ImageVector, val services: List<String>)

/** What a page of this type shows and does. [itemKinds] are the items.kind values its catalogue holds. */
data class PageType(
    val key: String, val group: String, val label: String, val blurb: String, val icon: ImageVector,
    /** Service row the page lives under; shop types derive it from the category instead (see serviceForCategory). */
    val service: String,
    val tabs: List<String>, val catalogueLabel: String?, val itemKinds: List<String>,
    val cta: String, val ctaLabel: String, val reviews: Boolean, val docs: List<String>,
) {
    val isShop get() = group == "SHOPS"
    val sellsProducts get() = "PRODUCT" in itemKinds
    /** Which tab shows the catalogue, if any. */
    val catalogueTab: String? get() = tabs.firstOrNull { it in setOf("products", "services", "programs", "events") }
    /** The noun for one catalogue entry: product, service, program, event. */
    val itemNoun: String get() = when (itemKinds.firstOrNull()) { "PRODUCT" -> "product"; "PROGRAM" -> "program"; "EVENT" -> "event"; else -> "service" }
    /** The items.kind a new catalogue entry gets. */
    val newItemKind: String get() = itemKinds.firstOrNull() ?: "SERVICE"
}

object PageTypes {
    val groups = listOf(
        PageGroup("SHOPS", "Shops", Icons.Rounded.Storefront, listOf("FOOD", "GROCERY", "VEGETABLES", "MEAT", "SHOPPING")),
        PageGroup("LOCAL_SERVICES", "Local services", Icons.Rounded.ContentCut, listOf("LOCAL_SERVICES")),
        PageGroup("COMPANIES", "Companies", Icons.Rounded.Code, listOf("BIZ_PRO")),
        PageGroup("COMMUNITY", "NGOs and groups", Icons.Rounded.Groups, listOf("COMMUNITY")),
        PageGroup("INSTITUTIONS", "Institutions", Icons.Rounded.Apartment, listOf("INSTITUTIONS")),
    )
    val all = listOf(
        PageType("RETAIL_SHOP", "SHOPS", "Shop", "Restaurant, grocery, store. Products with prices, orders and delivery nearby.", Icons.Rounded.Storefront, "SHOPPING",
            listOf("products", "feed", "about", "jobs", "reviews"), "Products", listOf("PRODUCT"), "CART", "Add to cart", true, listOf("OWNER_ID", "GSTIN", "FSSAI", "SHOP_EST", "TRADE_LICENCE")),
        PageType("D2C_STORE", "SHOPS", "Online store", "Ships across India by courier. Products, orders, tracking.", Icons.Rounded.LocalShipping, "SHOPPING",
            listOf("products", "about", "feed", "reviews"), "Products", listOf("PRODUCT"), "CART", "Add to cart", true, listOf("OWNER_ID", "GSTIN", "UDYAM")),
        PageType("LOCAL_SERVICE", "LOCAL_SERVICES", "Local service", "Salon, clinic, repair, coaching, gym. Services with prices; people book.", Icons.Rounded.ContentCut, "LOCAL_SERVICES",
            listOf("services", "photos", "about", "feed", "reviews"), "Services", listOf("SERVICE"), "BOOK", "Book", true, listOf("OWNER_ID", "GSTIN", "TRADE_LICENCE", "SHOP_EST")),
        PageType("IT_COMPANY", "COMPANIES", "IT company", "Software, apps, design, digital marketing. Services from a price or on quote.", Icons.Rounded.Code, "BIZ_PRO",
            listOf("services", "photos", "about", "team", "jobs", "reviews", "feed"), "Services", listOf("SERVICE"), "QUOTE", "Get a quote", true, listOf("OWNER_ID", "GSTIN", "UDYAM")),
        PageType("COLLECTIVE", "COMPANIES", "Freelancer collective", "A few pros working together. People, then services.", Icons.Rounded.Group, "BIZ_PRO",
            listOf("team", "services", "photos", "about", "reviews", "feed"), "Services", listOf("SERVICE"), "HIRE", "Hire us", true, listOf("OWNER_ID", "GSTIN")),
        PageType("PRO_FIRM", "COMPANIES", "Professional firm", "Accounting, legal, architecture, consulting.", Icons.Rounded.Gavel, "BIZ_PRO",
            listOf("services", "about", "team", "reviews", "feed"), "Services", listOf("SERVICE"), "ENQUIRE", "Enquire", true, listOf("OWNER_ID", "GSTIN", "UDYAM")),
        PageType("MANUFACTURER", "COMPANIES", "Manufacturer / wholesaler", "A catalogue with per-unit prices; buyers ask for a quote, no cart.", Icons.Rounded.Inventory2, "BIZ_PRO",
            listOf("services", "about", "jobs", "reviews", "feed"), "Catalogue", listOf("SERVICE"), "QUOTE", "Get a quote", true, listOf("OWNER_ID", "GSTIN", "UDYAM")),
        PageType("NGO_CHARITY", "COMMUNITY", "NGO / charity", "Programs people can join or support. Volunteers, team, updates.", Icons.Rounded.Favorite, "COMMUNITY",
            listOf("about", "programs", "jobs", "team", "feed", "reviews"), "Programs", listOf("PROGRAM"), "VOLUNTEER", "Volunteer", true, listOf("OWNER_ID", "NGO_REG")),
        PageType("COMMUNITY_GROUP", "COMMUNITY", "Community group", "Neighbours doing things together. Events and updates.", Icons.Rounded.Groups, "COMMUNITY",
            listOf("about", "events", "feed", "team"), "Events", listOf("EVENT", "SERVICE"), "JOIN", "Join", false, listOf("OWNER_ID")),
        PageType("SCHOOL_COLLEGE", "INSTITUTIONS", "School / college", "Courses and classes, admissions, campus, staff openings.", Icons.Rounded.Apartment, "INSTITUTIONS",
            listOf("about", "programs", "photos", "team", "jobs", "feed", "reviews"), "Programs", listOf("PROGRAM"), "ENQUIRE", "Admission enquiry", true, listOf("OWNER_ID", "NGO_REG", "AFFILIATION")),
        PageType("HOSPITAL", "INSTITUTIONS", "Hospital", "Departments and services; people book a visit.", Icons.Rounded.MedicalServices, "INSTITUTIONS",
            listOf("about", "services", "team", "feed", "reviews"), "Services", listOf("SERVICE"), "BOOK", "Book a visit", true, listOf("OWNER_ID", "GSTIN")),
        PageType("WORSHIP_PLACE", "INSTITUTIONS", "Place of worship", "Timings, events and updates. No reviews.", Icons.Rounded.Place, "INSTITUTIONS",
            listOf("about", "events", "photos", "feed"), "Events", listOf("EVENT"), "DIRECTIONS", "Directions", false, listOf("OWNER_ID", "NGO_REG")),
        PageType("ASSOCIATION", "INSTITUTIONS", "Association / society", "Residents, alumni, trade or welfare association. Members, events, notices.", Icons.Rounded.HowToReg, "INSTITUTIONS",
            listOf("about", "events", "team", "jobs", "feed"), "Events", listOf("EVENT", "SERVICE"), "JOIN", "Join", false, listOf("OWNER_ID", "NGO_REG")),
    )
    fun byKey(key: String?): PageType? = all.firstOrNull { it.key == key }
    fun group(key: String?): PageGroup? = groups.firstOrNull { it.key == key }
    fun inGroup(group: String) = all.filter { it.group == group }

    /** The type of a listing. A business saved before types existed is a shop (an online store when it ships). Other kinds have none. */
    fun of(l: ListingRow): PageType? = if (l.kind != "BUSINESS") null else byKey(l.typeKey) ?: legacyShop(l.details.str("ships_india") == "true")
    fun of(h: SearchHit): PageType? = if (h.kind != "BUSINESS") null else byKey(h.typeKey) ?: legacyShop(h.details.str("ships_india") == "true")
    private fun legacyShop(ships: Boolean) = byKey(if (ships) "D2C_STORE" else "RETAIL_SHOP")!!

    /** The kinds a catalogue can hold, in the order the tab shows them. */
    val itemKinds = listOf("PRODUCT", "SERVICE", "PROGRAM", "EVENT")
    fun kindPlural(k: String) = when (k) { "PRODUCT" -> "Products"; "PROGRAM" -> "Programs"; "EVENT" -> "Events"; else -> "Services" }
    fun kindNoun(k: String) = when (k) { "PRODUCT" -> "product"; "PROGRAM" -> "program"; "EVENT" -> "event"; else -> "service" }
    const val CATALOGUE_LABEL_MAX = 24

    /** What a page's catalogue holds before the owner changes it: its type's kinds, services for a pro, nothing for an asset or a driver. */
    fun defaultKinds(kind: String, type: PageType?): List<String> = type?.itemKinds ?: if (kind == "SKILL") listOf("SERVICE") else emptyList()
    /** The tab's name before the owner renames it. */
    fun defaultLabel(kind: String, type: PageType?, kinds: List<String>): String = when {
        kind == "ASSET" -> "Pricing"
        kind == "DRIVER" -> "Rides"
        type != null && kinds == type.itemKinds && type.catalogueLabel != null -> type.catalogueLabel
        kinds.isEmpty() -> "Services"
        else -> kinds.map { kindPlural(it) }.let { if (it.size <= 2) it.joinToString(" & ") else it.dropLast(1).joinToString(", ") + " & " + it.last() }
    }
    fun catalogue(l: ListingRow): Catalogue {
        val type = of(l)
        val chosen = (l.details["catalogue_kinds"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }?.filter { it in itemKinds }?.takeIf { it.isNotEmpty() }
        val kinds = chosen?.let { c -> itemKinds.filter { it in c } } ?: defaultKinds(l.kind, type)
        val label = l.details.str("catalogue_label")?.take(CATALOGUE_LABEL_MAX)
        return Catalogue(label ?: defaultLabel(l.kind, type, kinds), kinds, chosen != null || label != null)
    }

    /** Short label for a card or header: the type for a business ("NGO / charity"), else the kind. */
    fun badge(kind: String, typeKey: String?, ships: Boolean = false): String = if (kind == "BUSINESS") (byKey(typeKey) ?: legacyShop(ships)).label else kindLabel(kind)
    fun badgeIcon(kind: String, typeKey: String?, ships: Boolean = false): ImageVector = if (kind == "BUSINESS") (byKey(typeKey) ?: legacyShop(ships)).icon else kindIcon(kind)

    /** What the primary button says to the page, when it opens a chat (until requests become their own object). */
    fun ctaMessage(t: PageType, title: String): String = when (t.cta) {
        "BOOK" -> "Hi, I'd like to book with $title. When are you free?"
        "QUOTE" -> "Hi $title, could you send me a quote? Here is what I need: "
        "ENQUIRE" -> if (t.key == "SCHOOL_COLLEGE") "Hi, I'd like to enquire about admission at $title. " else "Hi $title, I have an enquiry: "
        "VOLUNTEER" -> "Hi, I'd like to volunteer with $title. How can I help?"
        "JOIN" -> "Hi, I'd like to join $title. What are the next steps?"
        "HIRE" -> "Hi $title, I'd like to hire you for a project: "
        else -> "Hi $title, "
    }
}
