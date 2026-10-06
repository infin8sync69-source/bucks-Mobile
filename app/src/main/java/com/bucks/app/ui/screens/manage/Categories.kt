package com.bucks.app.ui.screens.manage

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Backend
import com.bucks.app.data.categorySuggestions
import com.bucks.app.ui.components.*

/*
 * What a business or a pro is, as a long searchable catalogue grouped by field, plus "add your own". The category is free text on the
 * listing (it feeds search); only the few food, grocery, fresh, meat and property names also decide the service on the server
 * (service_for_category in supabase/migrations/services.sql and serviceForCategory in ui/Services.kt must agree).
 */

/** Business types by field. Pharmacy is left out on purpose: selling medicines online needs its own licensing. */
internal val BUSINESS_GROUPS: List<Pair<String, List<String>>> = listOf(
    "Food and drink" to listOf("Restaurant", "Cafe", "Bakery", "Sweets", "Cloud kitchen", "Tiffin", "Catering", "Juice bar", "Ice cream", "Street food", "Food truck"),
    "Grocery and daily needs" to listOf("Grocery", "Supermarket", "Dairy", "Kirana", "Organic store"),
    "Fresh produce" to listOf("Vegetables", "Fruits"),
    "Meat and fish" to listOf("Chicken", "Mutton", "Fish", "Eggs"),
    "Fashion and lifestyle" to listOf("Clothing", "Footwear", "Jewellery", "Bags and accessories", "Handloom and crafts", "Gifts", "Toys", "Books", "Stationery", "Cosmetics store", "Optical"),
    "Home and electronics" to listOf("Electronics", "Mobile and accessories", "Appliances", "Furniture", "Hardware", "Paint and tiles", "Kitchenware", "Home decor", "Lighting"),
    "Beauty and wellness" to listOf("Salon", "Spa", "Barber", "Beauty parlour", "Tattoo studio", "Gym", "Yoga studio", "Dance studio", "Meditation centre"),
    "Health and care" to listOf("Clinic", "Dental clinic", "Diagnostic lab", "Physiotherapy", "Ayurveda", "Eye care", "Veterinary clinic", "Pet shop"),
    "Repair and home services" to listOf("Mobile repair", "Appliance repair", "Computer repair", "Tailor", "Laundry and dry cleaning", "Cleaning service", "Pest control", "Packers and movers", "Interior design", "Construction", "Security services", "Courier", "Printing and xerox"),
    "IT and digital" to listOf("IT services", "Software company", "Mobile app agency", "Web design agency", "Digital marketing", "Cloud and hosting", "Cybersecurity", "AI and data", "IT training", "Cyber cafe", "Computer sales"),
    "Professional services" to listOf("Accounting and tax", "Legal", "Insurance", "Financial advisor", "Architect", "Consulting", "Recruitment", "Photography studio", "Event management", "Wedding planner", "Travel agency", "Notary"),
    "Education" to listOf("School", "College", "Coaching centre", "Tuition centre", "Preschool", "Skill training", "Language institute", "Music school", "Driving school", "Library"),
    "Automotive" to listOf("Garage", "Car wash", "Showroom", "Spare parts", "Tyre shop", "Bike repair"),
    "Property" to listOf("Property owner", "Real estate agent", "Builder"),
    "Community and non-profit" to listOf("NGO", "Charity trust", "Community group", "Resident association", "Religious place", "Club", "Foundation", "Self-help group", "Cooperative", "Alumni association"),
    "Farming and manufacturing" to listOf("Farm produce", "Nursery and plants", "Manufacturing unit", "Wholesale trader", "Printing press", "Packaging", "Fabrication"),
)

/** What a person does, by field. */
internal val SKILL_GROUPS: List<Pair<String, List<String>>> = listOf(
    "IT and software" to listOf("Software developer", "Web developer", "Mobile app developer", "UI/UX designer", "Data analyst", "Data scientist", "AI and ML engineer", "DevOps and cloud", "Cybersecurity", "QA tester", "Game developer", "IT support", "Network engineer", "Database admin", "Technical writer", "Digital marketer", "SEO specialist"),
    "Design and creative" to listOf("Designer", "Graphic designer", "Illustrator", "Video editor", "Animator", "Photographer", "Videographer", "Content writer", "Translator", "Voice artist", "Musician", "Singer", "DJ", "Dancer", "Makeup artist", "Mehendi artist"),
    "Teaching and training" to listOf("Tutor", "Maths tutor", "Science tutor", "English tutor", "Language teacher", "Music teacher", "Art teacher", "Yoga instructor", "Fitness trainer", "Coding instructor", "Exam coach", "Special educator"),
    "Home services" to listOf("Plumber", "Electrician", "Carpenter", "Painter", "Cleaner", "AC technician", "Appliance technician", "Mason", "Welder", "Gardener", "Pest control", "Handyman", "Interior designer", "Tile fitter", "Locksmith", "CCTV installer"),
    "Health and care" to listOf("Doctor", "Nurse", "Physiotherapist", "Dietitian", "Counsellor", "Caregiver", "Babysitter", "Ayurveda practitioner", "Lab technician", "Veterinarian", "Dog trainer"),
    "Business and professional" to listOf("Accountant", "Tax consultant", "Lawyer", "Architect", "Civil engineer", "Business consultant", "Recruiter", "Insurance agent", "Financial planner", "Notary"),
    "Food and events" to listOf("Chef", "Cook", "Caterer", "Baker", "Wedding planner", "Event host", "Decorator"),
    "Beauty and wellness" to listOf("Beautician", "Hair stylist", "Barber", "Massage therapist"),
    "Drivers and logistics" to listOf("Driver", "Delivery partner", "Mover"),
    "Other trades" to listOf("Tailor", "Cobbler", "Mechanic", "Bike mechanic", "Tow operator"),
)

/** A category the owner typed: spaces tidied, first letter capital, 2 to 40 characters of letters, digits and & / , ' . ( ) + -; null when it isn't usable. */
internal fun cleanCategory(raw: String): String? {
    val s = raw.trim().replace(Regex("\\s+"), " ")
    if (s.length !in 2..40 || !Regex("^[\\p{L}\\p{N} &/,'.()+-]+$").matches(s)) return null
    return s.replaceFirstChar { it.uppercase() }
}

/** The closed field that opens the picker: shows the chosen category or a hint. */
@Composable
internal fun CategoryField(value: String, hint: String, onClick: () -> Unit) {
    val shape = MaterialTheme.shapes.small
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).clip(shape).border(1.dp, MaterialTheme.colorScheme.outline, shape).clickable(onClickLabel = "Choose", onClick = onClick).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(value.ifBlank { hint }, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, color = if (value.isBlank()) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface)
        Icon(Icons.Rounded.ExpandMore, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * Searchable list of categories by field. Typing something that isn't in the list offers "Use “…” as my category", so nobody is stuck with
 * the wrong box; categories other owners already added (from the server) are listed too, so the catalogue grows by use.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CategoryPickerSheet(kind: String, selected: String, onPick: (String) -> Unit, onDismiss: () -> Unit) {
    val groups = if (kind == "SKILL") SKILL_GROUPS else BUSINESS_GROUPS
    var q by remember { mutableStateOf("") }
    var others by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(kind) { others = runCatching { Backend.categorySuggestions(kind).map { it.category } }.getOrDefault(emptyList()) }
    val builtIn = remember(groups) { groups.flatMap { it.second }.map { it.lowercase() }.toSet() }
    val extra = others.filter { it.lowercase() !in builtIn }
    val all = groups + (if (extra.isNotEmpty()) listOf("Added by others" to extra) else emptyList())
    val query = q.trim()
    val shown = if (query.isEmpty()) all else all.map { (g, items) -> g to items.filter { it.contains(query, ignoreCase = true) } }.filter { it.second.isNotEmpty() }
    val own = cleanCategory(query)
    val exact = own != null && all.any { (_, items) -> items.any { it.equals(own, ignoreCase = true) } }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxHeight(0.92f).padding(horizontal = Gutter).imePadding()) {
            Text(if (kind == "SKILL") "What do you do?" else "What kind of business?", style = MaterialTheme.typography.titleLarge)
            Muted("Pick the closest one, or type your own and add it.", Modifier.padding(top = 2.dp))
            OutlinedTextField(q, { q = it.take(40) }, Modifier.fillMaxWidth().padding(vertical = 10.dp), placeholder = { Text("Search or type your own") }, singleLine = true, leadingIcon = { Icon(Icons.Rounded.Search, null) })
            LazyColumn(Modifier.weight(1f)) {
                if (own != null && !exact) item(key = "own") {
                    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).clip(MaterialTheme.shapes.small).clickable { onPick(own) }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Add, null, tint = MaterialTheme.colorScheme.primary)
                        Column(Modifier.padding(start = 12.dp)) { Text("Use “$own” as my category", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary); Muted("Your own category. Others can find and pick it too.") }
                    }
                }
                shown.forEach { (g, list) ->
                    item(key = "h:$g") { Text(g, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 14.dp, bottom = 2.dp)) }
                    items(list, key = { "$g/$it" }) { c ->
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(MaterialTheme.shapes.small).clickable { onPick(c) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(c, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                            if (c.equals(selected, ignoreCase = true)) Icon(Icons.Rounded.Check, "Selected", tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
                if (shown.isEmpty() && own == null) item(key = "none") { Muted("Nothing matches. Type at least 2 letters to add your own.", Modifier.padding(top = 16.dp)) }
                item(key = "end") { Spacer(Modifier.height(24.dp)) }
            }
        }
    }
}
