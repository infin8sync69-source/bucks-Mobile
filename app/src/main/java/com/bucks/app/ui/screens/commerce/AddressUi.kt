package com.bucks.app.ui.screens.commerce

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bucks.app.data.AddressRow
import com.bucks.app.data.Pincode
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*

/** The address a shipped order goes to: who, the number the courier calls, the lines, with a Change button. */
@Composable
fun AddressCard(a: AddressRow?, onChange: () -> Unit) = BucksCard(onClick = onChange) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.LocationOn, null, tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            if (a == null) { Text("Add a delivery address", style = MaterialTheme.typography.titleMedium); Muted("Shops that ship need your name, number and full address.") }
            else { Text(listOfNotNull(a.name, a.label.ifBlank { null }).joinToString(" · "), style = MaterialTheme.typography.titleMedium); Muted(a.oneLine); Muted("Mobile ${a.phone}") }
        }
        Text(if (a == null) "Add" else "Change", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
    }
}

/**
 * The address book in a sheet: pick one for this order, edit or delete saved ones, or add a new one (pincode fills city and state).
 * Also the place to manage addresses on their own, so it works without a cart ([onPick] null hides the radio buttons).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AddressSheet(vm: BucksViewModel, selectedId: String?, startNew: Boolean = false, onPick: ((AddressRow) -> Unit)?, onDismiss: () -> Unit) {
    val commerce = vm.commerce
    LaunchedEffect(Unit) { commerce.loadAddresses() }
    var editing by remember { mutableStateOf<AddressRow?>(null) }; var adding by remember { mutableStateOf(startNew) }
    var confirmDelete by remember { mutableStateOf<AddressRow?>(null) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            if (adding || editing != null) {
                AddressForm(editing, first = commerce.addresses.isEmpty(), onCancel = { adding = false; editing = null }) { saved ->
                    commerce.saveAddress(saved) { r -> adding = false; editing = null; onPick?.invoke(r); if (onPick != null) onDismiss() }
                }
            } else {
                Text(if (onPick != null) "Deliver to" else "My addresses", style = MaterialTheme.typography.titleLarge)
                if (!commerce.addressesLoaded) SkeletonLines(3, Modifier.padding(top = 16.dp))
                else if (commerce.addresses.isEmpty()) Muted("No saved addresses yet.", Modifier.padding(top = 10.dp))
                commerce.addresses.forEach { a ->
                    Row(Modifier.fillMaxWidth().padding(top = 10.dp).then(if (onPick != null) Modifier.selectable(a.id == selectedId, role = Role.RadioButton, onClick = { onPick(a); onDismiss() }) else Modifier), verticalAlignment = Alignment.Top) {
                        if (onPick != null) RadioButton(a.id == selectedId, null, Modifier.padding(top = 2.dp, end = 8.dp))
                        Column(Modifier.weight(1f)) {
                            Text(listOfNotNull(a.name, a.label.ifBlank { null }, if (a.isDefault) "Default" else null).joinToString(" · "), style = MaterialTheme.typography.titleSmall)
                            Muted(a.oneLine); Muted("Mobile ${a.phone}")
                        }
                        IconButton({ editing = a }) { Icon(Icons.Rounded.Edit, "Edit address for ${a.name}") }
                        IconButton({ confirmDelete = a }) { Icon(Icons.Rounded.DeleteOutline, "Delete address for ${a.name}", tint = MaterialTheme.colorScheme.error) }
                    }
                    HorizontalDivider(Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.outlineVariant)
                }
                OutlinedButton({ adding = true }, Modifier.padding(top = 14.dp).fillMaxWidth().heightIn(min = 48.dp)) { Icon(Icons.Rounded.Add, null); Spacer(Modifier.width(8.dp)); Text("Add a new address") }
            }
        }
    }
    confirmDelete?.let { a -> AlertDialog(onDismissRequest = { confirmDelete = null }, title = { Text("Delete this address?") }, text = { Text("${a.name}, ${a.oneLine}") },
        confirmButton = { TextButton({ a.id?.let { commerce.deleteAddress(it) }; confirmDelete = null }) { Text("Delete", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmDelete = null }) { Text("Keep") } }) }
}

/** Add or edit one address. Checks what the server checks (10-digit mobile, 6-digit pincode) and says what is wrong next to the field. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AddressForm(existing: AddressRow?, first: Boolean, onCancel: () -> Unit, onSave: (AddressRow) -> Unit) {
    var label by remember { mutableStateOf(existing?.label ?: "") }; var name by remember { mutableStateOf(existing?.name ?: "") }; var phone by remember { mutableStateOf(existing?.phone ?: "") }
    var pin by remember { mutableStateOf(existing?.pincode ?: "") }; var line1 by remember { mutableStateOf(existing?.line1 ?: "") }; var line2 by remember { mutableStateOf(existing?.line2 ?: "") }
    var city by remember { mutableStateOf(existing?.city ?: "") }; var state by remember { mutableStateOf(existing?.state ?: "") }; var default by remember { mutableStateOf(existing?.isDefault ?: first) }
    var tried by remember { mutableStateOf(false) }; var looking by remember { mutableStateOf(false) }
    // A full pincode fills the city and state (the person can still change them).
    LaunchedEffect(pin) { if (pin.length == 6 && existing?.pincode != pin) { looking = true; Pincode.lookup(pin)?.let { (c, s) -> city = c; state = s }; looking = false } }
    val phoneOk = Regex("[6-9][0-9]{9}").matches(phone); val pinOk = Regex("[1-9][0-9]{5}").matches(pin)
    val valid = name.isNotBlank() && phoneOk && pinOk && line1.trim().length >= 3 && city.isNotBlank() && state.isNotBlank()
    Text(if (existing == null) "New address" else "Edit address", style = MaterialTheme.typography.titleLarge)
    Label("Save as")
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf("Home", "Work", "Other").forEach { l -> Chip(l, selected = label == l) { label = if (label == l) "" else l } } }
    Spacer(Modifier.height(12.dp))
    BucksField(name, { name = it.take(80) }, "Full name", "Who receives it")
    if (tried && name.isBlank()) Muted("Enter the name of the person receiving it.", Modifier.padding(bottom = 8.dp))
    BucksField(phone, { phone = it.filter { c -> c.isDigit() }.take(10) }, "Mobile number", "10 digits, the courier may call it", keyboard = KeyboardOptions(keyboardType = KeyboardType.Phone))
    if (tried && !phoneOk) Muted("Enter a 10-digit mobile number starting with 6, 7, 8 or 9.", Modifier.padding(bottom = 8.dp))
    BucksField(pin, { pin = it.filter { c -> c.isDigit() }.take(6) }, "Pincode", "6 digits", keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
    if (looking) Muted("Looking up the city…", Modifier.padding(bottom = 8.dp)) else if (tried && !pinOk) Muted("Enter a 6-digit pincode.", Modifier.padding(bottom = 8.dp))
    BucksField(line1, { line1 = it.take(150) }, "House or flat number and street", "e.g. 12, 4th Cross, MG Road")
    if (tried && line1.trim().length < 3) Muted("Enter the house or flat number and street.", Modifier.padding(bottom = 8.dp))
    BucksField(line2, { line2 = it.take(150) }, "Area or landmark (optional)", "e.g. near the park")
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f)) { BucksField(city, { city = it.take(60) }, "City", "") }
        Column(Modifier.weight(1f)) { BucksField(state, { state = it.take(60) }, "State", "") }
    }
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).selectable(default, role = Role.Switch, onClick = { default = !default }), verticalAlignment = Alignment.CenterVertically) {
        Text("Make this my default address", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge); Switch(default, null)
    }
    Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        OutlinedButton(onCancel, Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Cancel") }
        Button({ tried = true; if (valid) onSave(AddressRow(existing?.id, label, name.trim(), phone, line1.trim(), line2.trim(), city.trim(), state.trim(), pin, default)) }, Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Save address") }
    }
}
