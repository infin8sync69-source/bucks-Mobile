package com.bucks.app.ui

import com.bucks.app.data.Str
import com.bucks.app.R
import androidx.annotation.StringRes
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
data class PageGroup(val key: String, @StringRes val labelRes: Int, val icon: ImageVector, val services: List<String>) {
    val label: String get() = Str.get(labelRes)
}

/** What a page of this type shows and does. [itemKinds] are the items.kind values its catalogue holds. */
data class PageType(
    val key: String, val group: String, @StringRes val labelRes: Int, @StringRes val blurbRes: Int, val icon: ImageVector,
    /** Service row the page lives under; shop types derive it from the category instead (see serviceForCategory). */
    val service: String,
    val tabs: List<String>, @StringRes val catalogueLabelRes: Int?, val itemKinds: List<String>,
    val cta: String, @StringRes val ctaLabelRes: Int, val reviews: Boolean, val docs: List<String>,
) {
    val label: String get() = Str.get(labelRes)
    val blurb: String get() = Str.get(blurbRes)
    val catalogueLabel: String? get() = catalogueLabelRes?.let { Str.get(it) }
    val ctaLabel: String get() = Str.get(ctaLabelRes)
    val isShop get() = group == "SHOPS"
    val sellsProducts get() = "PRODUCT" in itemKinds
    /** Which tab shows the catalogue, if any. */
    val catalogueTab: String? get() = tabs.firstOrNull { it in setOf("products", "services", "programs", "events") }
    /** The noun for one catalogue entry: product, service, program, event. */
    val itemNoun: String get() = PageTypes.kindNoun(itemKinds.firstOrNull() ?: "SERVICE")
    /** The items.kind a new catalogue entry gets. */
    val newItemKind: String get() = itemKinds.firstOrNull() ?: "SERVICE"
}

object PageTypes {
    val groups = listOf(
        PageGroup("SHOPS", R.string.g5_pt_group_shops, Icons.Rounded.Storefront, listOf("FOOD", "GROCERY", "VEGETABLES", "MEAT", "SHOPPING")),
        PageGroup("LOCAL_SERVICES", R.string.g5_pt_group_local_services, Icons.Rounded.ContentCut, listOf("LOCAL_SERVICES")),
        PageGroup("COMPANIES", R.string.g5_pt_group_companies, Icons.Rounded.Code, listOf("BIZ_PRO")),
        PageGroup("COMMUNITY", R.string.g5_pt_group_community, Icons.Rounded.Groups, listOf("COMMUNITY")),
        PageGroup("INSTITUTIONS", R.string.g5_pt_group_institutions, Icons.Rounded.Apartment, listOf("INSTITUTIONS")),
    )
    val all = listOf(
        PageType("RETAIL_SHOP", "SHOPS", R.string.g5_pt_retail_shop_label, R.string.g5_pt_retail_shop_blurb, Icons.Rounded.Storefront, "SHOPPING",
            listOf("products", "feed", "about", "jobs", "reviews"), R.string.g5_kind_products, listOf("PRODUCT"), "CART", R.string.g5_cta_add_to_cart, true, listOf("OWNER_ID", "GSTIN", "FSSAI", "SHOP_EST", "TRADE_LICENCE")),
        PageType("D2C_STORE", "SHOPS", R.string.g5_pt_d2c_store_label, R.string.g5_pt_d2c_store_blurb, Icons.Rounded.LocalShipping, "SHOPPING",
            listOf("products", "about", "feed", "reviews"), R.string.g5_kind_products, listOf("PRODUCT"), "CART", R.string.g5_cta_add_to_cart, true, listOf("OWNER_ID", "GSTIN", "UDYAM")),
        PageType("LOCAL_SERVICE", "LOCAL_SERVICES", R.string.g5_pt_local_service_label, R.string.g5_pt_local_service_blurb, Icons.Rounded.ContentCut, "LOCAL_SERVICES",
            listOf("services", "photos", "about", "feed", "reviews"), R.string.g5_kind_services, listOf("SERVICE"), "BOOK", R.string.g5_cta_book, true, listOf("OWNER_ID", "GSTIN", "TRADE_LICENCE", "SHOP_EST")),
        PageType("IT_COMPANY", "COMPANIES", R.string.g5_pt_it_company_label, R.string.g5_pt_it_company_blurb, Icons.Rounded.Code, "BIZ_PRO",
            listOf("services", "photos", "about", "team", "jobs", "reviews", "feed"), R.string.g5_kind_services, listOf("SERVICE"), "QUOTE", R.string.g5_cta_get_quote, true, listOf("OWNER_ID", "GSTIN", "UDYAM")),
        PageType("COLLECTIVE", "COMPANIES", R.string.g5_pt_collective_label, R.string.g5_pt_collective_blurb, Icons.Rounded.Group, "BIZ_PRO",
            listOf("team", "services", "photos", "about", "reviews", "feed"), R.string.g5_kind_services, listOf("SERVICE"), "HIRE", R.string.g5_cta_hire_us, true, listOf("OWNER_ID", "GSTIN")),
        PageType("PRO_FIRM", "COMPANIES", R.string.g5_pt_pro_firm_label, R.string.g5_pt_pro_firm_blurb, Icons.Rounded.Gavel, "BIZ_PRO",
            listOf("services", "about", "team", "reviews", "feed"), R.string.g5_kind_services, listOf("SERVICE"), "ENQUIRE", R.string.g5_cta_enquire, true, listOf("OWNER_ID", "GSTIN", "UDYAM")),
        PageType("MANUFACTURER", "COMPANIES", R.string.g5_pt_manufacturer_label, R.string.g5_pt_manufacturer_blurb, Icons.Rounded.Inventory2, "BIZ_PRO",
            listOf("services", "about", "jobs", "reviews", "feed"), R.string.g5_kind_catalogue, listOf("SERVICE"), "QUOTE", R.string.g5_cta_get_quote, true, listOf("OWNER_ID", "GSTIN", "UDYAM")),
        PageType("NGO_CHARITY", "COMMUNITY", R.string.g5_pt_ngo_charity_label, R.string.g5_pt_ngo_charity_blurb, Icons.Rounded.Favorite, "COMMUNITY",
            listOf("about", "programs", "jobs", "team", "feed", "reviews"), R.string.g5_kind_programs, listOf("PROGRAM"), "VOLUNTEER", R.string.g5_cta_volunteer, true, listOf("OWNER_ID", "NGO_REG")),
        PageType("COMMUNITY_GROUP", "COMMUNITY", R.string.g5_pt_community_group_label, R.string.g5_pt_community_group_blurb, Icons.Rounded.Groups, "COMMUNITY",
            listOf("about", "events", "feed", "team"), R.string.g5_kind_events, listOf("EVENT", "SERVICE"), "JOIN", R.string.g5_cta_join, false, listOf("OWNER_ID")),
        PageType("SCHOOL_COLLEGE", "INSTITUTIONS", R.string.g5_pt_school_college_label, R.string.g5_pt_school_college_blurb, Icons.Rounded.Apartment, "INSTITUTIONS",
            listOf("about", "programs", "photos", "team", "jobs", "feed", "reviews"), R.string.g5_kind_programs, listOf("PROGRAM"), "ENQUIRE", R.string.g5_cta_admission_enquiry, true, listOf("OWNER_ID", "NGO_REG", "AFFILIATION")),
        PageType("HOSPITAL", "INSTITUTIONS", R.string.g5_pt_hospital_label, R.string.g5_pt_hospital_blurb, Icons.Rounded.MedicalServices, "INSTITUTIONS",
            listOf("about", "services", "team", "feed", "reviews"), R.string.g5_kind_services, listOf("SERVICE"), "BOOK", R.string.g5_cta_book_visit, true, listOf("OWNER_ID", "GSTIN")),
        PageType("WORSHIP_PLACE", "INSTITUTIONS", R.string.g5_pt_worship_place_label, R.string.g5_pt_worship_place_blurb, Icons.Rounded.Place, "INSTITUTIONS",
            listOf("about", "events", "photos", "feed"), R.string.g5_kind_events, listOf("EVENT"), "DIRECTIONS", R.string.g5_cta_directions, false, listOf("OWNER_ID", "NGO_REG")),
        PageType("ASSOCIATION", "INSTITUTIONS", R.string.g5_pt_association_label, R.string.g5_pt_association_blurb, Icons.Rounded.HowToReg, "INSTITUTIONS",
            listOf("about", "events", "team", "jobs", "feed"), R.string.g5_kind_events, listOf("EVENT", "SERVICE"), "JOIN", R.string.g5_cta_join, false, listOf("OWNER_ID", "NGO_REG")),
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
    fun kindPlural(k: String) = Str.get(when (k) { "PRODUCT" -> R.string.g5_kind_products; "PROGRAM" -> R.string.g5_kind_programs; "EVENT" -> R.string.g5_kind_events; else -> R.string.g5_kind_services })
    fun kindNoun(k: String) = Str.get(when (k) { "PRODUCT" -> R.string.g5_noun_product; "PROGRAM" -> R.string.g5_noun_program; "EVENT" -> R.string.g5_noun_event; else -> R.string.g5_noun_service })
    const val CATALOGUE_LABEL_MAX = 24

    /** What a page's catalogue holds before the owner changes it: its type's kinds, services for a pro, nothing for an asset or a driver. */
    fun defaultKinds(kind: String, type: PageType?): List<String> = type?.itemKinds ?: if (kind == "SKILL") listOf("SERVICE") else emptyList()
    /** The tab's name before the owner renames it. */
    fun defaultLabel(kind: String, type: PageType?, kinds: List<String>): String = when {
        kind == "ASSET" -> Str.get(R.string.g5_tab_pricing)
        kind == "DRIVER" -> Str.get(R.string.g5_tab_rides)
        type != null && kinds == type.itemKinds && type.catalogueLabelRes != null -> Str.get(type.catalogueLabelRes)
        kinds.isEmpty() -> Str.get(R.string.g5_kind_services)
        else -> kinds.map { kindPlural(it) }.let { when (it.size) { 1 -> it[0]; 2 -> Str.get(R.string.g5_list_two, it[0], it[1]); 3 -> Str.get(R.string.g5_list_three, it[0], it[1], it[2]); else -> Str.get(R.string.g5_list_four, it[0], it[1], it[2], it[3]) } }
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
        "BOOK" -> Str.get(R.string.g5_cta_msg_book, title)
        "QUOTE" -> Str.get(R.string.g5_cta_msg_quote, title)
        "ENQUIRE" -> if (t.key == "SCHOOL_COLLEGE") Str.get(R.string.g5_cta_msg_admission, title) else Str.get(R.string.g5_cta_msg_enquire, title)
        "VOLUNTEER" -> Str.get(R.string.g5_cta_msg_volunteer, title)
        "JOIN" -> Str.get(R.string.g5_cta_msg_join, title)
        "HIRE" -> Str.get(R.string.g5_cta_msg_hire, title)
        else -> Str.get(R.string.g5_cta_msg_hi, title)
    }
}
