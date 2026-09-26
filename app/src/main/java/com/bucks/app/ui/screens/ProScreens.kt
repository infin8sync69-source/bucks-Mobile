package com.bucks.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.ProKind
import com.bucks.app.ui.Role
import com.bucks.app.ui.components.*

@Composable
private fun Steps(step: Int) = Row(Modifier.fillMaxWidth().padding(bottom = 20.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { (1..3).forEach { i -> Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(if (i <= step) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHigh)) } }

@Composable
private fun OptionRow(icon: ImageVector, title: String, detail: String, selected: Boolean, onClick: () -> Unit) =
    Row(Modifier.fillMaxWidth().padding(bottom = 10.dp).clip(MaterialTheme.shapes.large).background(if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onClick).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface); Column(Modifier.padding(start = 14.dp)) { Text(title, style = MaterialTheme.typography.titleMedium); Muted(detail) } }

@Composable
fun ProCreateScreen(vm: BucksViewModel, onBack: () -> Unit, onHome: () -> Unit, onListings: (String) -> Unit, onVehicleForm: () -> Unit) {
    val s by vm.state.collectAsState()
    val edit = remember(s.editBiz) { s.editBiz?.let { s.businesses.getOrNull(it) } }
    var skillFilter by remember { mutableStateOf("") }; val skills = remember { mutableStateListOf<String>() }; var rate by remember { mutableStateOf("") }
    var bizName by remember(edit) { mutableStateOf(edit?.name ?: "") }; var bizCat by remember(edit) { mutableStateOf(edit?.category ?: "") }; var bizScope by remember(edit) { mutableStateOf(edit?.scope ?: Scope.LOCAL) }; var item by remember { mutableStateOf("") }; var price by remember { mutableStateOf("") }; var detail by remember { mutableStateOf("") }; var tag by remember { mutableStateOf("") }; val items = remember(edit) { mutableStateListOf<Item>().apply { edit?.let { addAll(it.items) } } }
    ContentColumn { BucksTopBar("Pro profile", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) {
            Steps(s.proStep)
            when {
                s.proStep == 1 -> {
                    Headline("How will you earn on Bucks?"); Muted("You can add more later.", Modifier.padding(top = 6.dp, bottom = 20.dp))
                    OptionRow(Icons.Rounded.TwoWheeler, "I have a vehicle", "Bike, auto or cab. Receive ride requests when online.", s.proKind == ProKind.VEHICLE) { vm.setProKind(ProKind.VEHICLE) }
                    OptionRow(Icons.Rounded.Handyman, "I have skills", "Plumber, doctor, developer. A to Z. Get service requests.", s.proKind == ProKind.SKILLS) { vm.setProKind(ProKind.SKILLS) }
                    OptionRow(Icons.Rounded.Storefront, "I run a business", "Grocery, restaurant, IT firm. Sell locally and globally.", s.proKind == ProKind.BUSINESS) { vm.setProKind(ProKind.BUSINESS) }
                    PrimaryButton("Continue", Modifier.padding(top = 10.dp), enabled = s.proKind != null) { if (s.proKind == ProKind.VEHICLE) onVehicleForm() else vm.setProStep(2) }
                }
                s.proStep == 2 && s.proKind == ProKind.SKILLS -> {
                    Headline("Add your skills"); Muted("Pick everything you can do. Each becomes searchable.", Modifier.padding(top = 6.dp))
                    BucksField(skillFilter, { skillFilter = it }, placeholder = "Filter skills", modifier = Modifier.padding(top = 14.dp))
                    FlowChips(Seed.SKILLS.filter { skillFilter.isBlank() || it.contains(skillFilter, true) }, skills.toSet()) { if (it in skills) skills.remove(it) else skills.add(it) }
                    BucksField(rate, { rate = it }, "Rate", "₹300 visit + parts", Modifier.padding(top = 16.dp))
                    PrimaryButton("Publish ${skills.size} skill${if (skills.size == 1) "" else "s"}", enabled = skills.isNotEmpty()) { vm.saveSkills(skills.toList(), rate.trim()) }
                }
                s.proStep == 2 && s.proKind == ProKind.BUSINESS -> {
                    Headline(if (edit != null) "Edit business profile" else "Create a business profile")
                    BucksField(bizName, { bizName = it }, "Business name", "Sri Lakshmi Stores", Modifier.padding(top = 14.dp))
                    Label("Category"); FlowChips(Seed.BIZ_CATS, setOf(bizCat)) { bizCat = it }
                    Spacer(Modifier.height(16.dp)); Label("Reach")
                    Row(Modifier.padding(bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { Chip("Local, within 5 km", selected = bizScope == Scope.LOCAL) { bizScope = Scope.LOCAL }; Chip("Global, ships anywhere", selected = bizScope == Scope.GLOBAL) { bizScope = Scope.GLOBAL } }
                    val variant = variantFor(bizCat)
                    Label(when (variant) { BusinessVariant.RESTAURANT -> "Menu items"; BusinessVariant.SUPERMARKET -> "Items and pack sizes"; BusinessVariant.FURNITURE -> "Catalogue"; BusinessVariant.ELECTRONICS -> "Products"; else -> "Items or services" })
                    items.forEachIndexed { i, it -> BucksCard(Modifier.padding(bottom = 8.dp), padding = 12) { Row(verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(it.name, style = MaterialTheme.typography.titleSmall); Muted(listOf("₹${it.price}", it.tag, it.detail).filter { d -> d.isNotBlank() }.joinToString(" · ")) }; IconButton(onClick = { items.removeAt(i) }) { Icon(Icons.Rounded.Close, "Remove") } } } }
                    Row(Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { OutlinedTextField(item, { item = it }, placeholder = { Text(when (variant) { BusinessVariant.RESTAURANT -> "Chicken biriyani"; BusinessVariant.SUPERMARKET -> "Sugar"; BusinessVariant.FURNITURE -> "Teak dining table"; BusinessVariant.ELECTRONICS -> "Wireless earbuds"; else -> "Item or service" }) }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, singleLine = true); OutlinedTextField(price, { price = it.filter { ch -> ch.isDigit() }.take(7) }, placeholder = { Text("₹") }, modifier = Modifier.width(96.dp), shape = MaterialTheme.shapes.medium, singleLine = true) }
                    if (variant == BusinessVariant.RESTAURANT) ChipRow(listOf("Veg", "Non-veg"), tag.ifBlank { null }, Modifier.padding(bottom = 8.dp)) { tag = it }
                    else OutlinedTextField(detail, { detail = it }, placeholder = { Text(when (variant) { BusinessVariant.SUPERMARKET -> "Pack size, e.g. 1 kg"; BusinessVariant.FURNITURE -> "Material and size"; BusinessVariant.ELECTRONICS -> "Brand and warranty"; else -> "Detail (optional)" }) }, modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp), shape = MaterialTheme.shapes.medium, singleLine = true)
                    SmallButton("Add item", Modifier.padding(bottom = 16.dp), tonal = true, enabled = item.isNotBlank() && (price.toIntOrNull() ?: 0) > 0) { items.add(Item(item.trim(), price.toInt(), tag, detail.trim(), "")); item = ""; price = ""; detail = ""; tag = "" }
                    PrimaryButton(if (edit != null) "Save business" else "Create business", enabled = items.isNotEmpty() || item.isNotBlank()) { if (item.isNotBlank() && (price.toIntOrNull() ?: 0) <= 0) { vm.toast("Enter a price for ${item.trim()}"); return@PrimaryButton }; val all = items.toList() + if (item.isNotBlank()) listOf(Item(item.trim(), price.toIntOrNull() ?: 0, tag, detail.trim())) else emptyList(); vm.saveBusiness(bizName.trim(), bizCat, bizScope, all) }
                }
                s.proStep == 3 -> Column(Modifier.fillMaxWidth().padding(top = 30.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Avatar(icon = Icons.Rounded.Check, size = 72); Headline("You're a provider now", Modifier.padding(top = 16.dp)); Muted(s.proMessage, Modifier.padding(top = 6.dp), TextAlign.Center)
                    Spacer(Modifier.height(24.dp))
                    PrimaryButton("Manage my listings") { val tab = if (s.proKind == ProKind.BUSINESS) "businesses" else "skills"; vm.startPro(null, 1); onListings(tab) }
                    TextButton(onClick = { vm.startPro(null, 1); onHome() }, modifier = Modifier.padding(top = 6.dp)) { Text("Back to home") }
                }
            }
        }
    }
}

@Composable
fun EarningsScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val s by vm.state.collectAsState()
    ContentColumn { BucksTopBar("Earnings", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) {
            BucksCard(tint = true) { Muted("Today"); Text("₹${animatedInt(s.earnings)}", style = MaterialTheme.typography.displaySmall); Muted("Bucks takes no cut in this build. The fee model is a product decision.") }
            Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) { BucksCard(Modifier.weight(1f)) { Text("${s.rides.size}", style = MaterialTheme.typography.titleLarge); Muted("Trips") }; BucksCard(Modifier.weight(1f)) { Text("${s.user?.up ?: 0}", style = MaterialTheme.typography.titleLarge); Muted("Recommend") }; BucksCard(Modifier.weight(1f)) { Text("${s.user?.down ?: 0}", style = MaterialTheme.typography.titleLarge); Muted("Not recommended") } }
            SectionTitle("Vehicle documents", Modifier.padding(top = 22.dp, bottom = 10.dp))
            listOf("Registration certificate" to true, "Insurance" to true, "Driving licence" to false, "Permit (autos and cabs)" to false).forEach { doc -> BucksCard(Modifier.padding(bottom = 10.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Description, null, tint = MaterialTheme.colorScheme.onSurfaceVariant); Text(doc.first, Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.bodyMedium); if (doc.second) PillGood("Approved") else PillWarn("Upload") } } }
        }
    }
}
