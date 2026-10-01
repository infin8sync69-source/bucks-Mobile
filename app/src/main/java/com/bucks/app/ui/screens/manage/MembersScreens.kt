package com.bucks.app.ui.screens.manage

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.ago

private val ROLE_ORDER = mapOf("OWNER" to 0, "ADMIN" to 1, "STORE_RIDER" to 2)

/**
 * Who runs a listing (owner, admins, store riders) or drives a vehicle (owner, drivers).
 * Exactly one of [listingId] / [vehicleId] is set. The owner invites by Bucks ID and removes people;
 * anyone else can only leave.
 */
@Composable
fun MembersScreen(vm: BucksViewModel, listingId: String? = null, vehicleId: String? = null, onBack: () -> Unit) {
    val m = vm.myListings; val social = vm.social; val ctx = LocalContext.current; val meId = social.me?.id
    val vehicleMode = vehicleId != null
    LaunchedEffect(listingId, vehicleId) { if (!m.loaded) m.refresh(); m.refreshInvites(); if (listingId != null) m.loadMembers(listingId) else if (vehicleId != null) m.loadVehicleMembers(vehicleId) }
    val title = listingId?.let { m.listing(it)?.title } ?: vehicleId?.let { id -> m.vehicle(id)?.let { v -> "${v.model.ifBlank { vehicleKindLabel(v.kind) }} · ${v.plate}" } } ?: "…"
    val owner = if (listingId != null) m.isOwner(listingId) else vehicleId?.let { m.ownsVehicle(it) } ?: false
    val rows: List<Pair<String, String>>? = if (listingId != null) m.members[listingId]?.map { it.profileId to it.role } else vehicleId?.let { id -> m.vehicleMembers[id]?.map { it.profileId to it.role } }
    val pending = m.sentInvites.filter { if (listingId != null) it.listingId == listingId else it.vehicleId == vehicleId }
    var code by remember { mutableStateOf("") }; var role by remember { mutableStateOf("ADMIN") }
    var removeFor by remember { mutableStateOf<Pair<String, String>?>(null) }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(if (vehicleMode) "Drivers" else "Members", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Muted(if (vehicleMode) "The owner and the drivers who can go online with this vehicle." else "The owner, admins who help run it, and the store's own delivery riders.")
            SectionTitle("People", Modifier.padding(top = 20.dp, bottom = 4.dp))
            when {
                rows == null -> CenteredLoading()
                rows.isEmpty() -> Muted("Only you so far.")
                else -> rows.sortedWith(compareBy({ ROLE_ORDER[it.second] ?: 9 }, { social.nameOf(it.first).lowercase() })).forEach { (pid, r) ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(initials(social.nameOf(pid).ifBlank { "?" }), size = 40)
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            Text(social.nameOf(pid) + if (pid == meId) " (you)" else "", style = MaterialTheme.typography.titleMedium)
                            Muted(roleLabel(r, vehicleMode) + " · " + roleExplain(r, vehicleMode), maxLines = 2)
                        }
                        if (owner && r != "OWNER") IconButton(onClick = { removeFor = pid to r }) { Icon(Icons.Rounded.PersonRemove, "Remove") }
                        else if (pid == meId && r != "OWNER") SmallButton("Leave", tonal = true) { removeFor = pid to r }
                    }
                    Divider()
                }
            }
            if (owner) {
                SectionTitle(if (vehicleMode) "Invite a driver" else "Invite someone", Modifier.padding(top = 24.dp, bottom = 4.dp))
                Muted("Ask for their Bucks ID (Account > Your Bucks ID) or scan it. They get an invite to accept under My listings > Invites.", Modifier.padding(bottom = 10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(code, { code = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(8) }, placeholder = { Text("H6VF YWYF") }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, singleLine = true,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters))
                    Spacer(Modifier.width(8.dp))
                    FilledTonalIconButton(onClick = { scanQr(ctx, onResult = { raw -> when (val s = BucksQr.parse(raw)) { is BucksQr.Scanned.BucksId -> code = s.code; else -> vm.toast("That isn't a Bucks ID code.") } }, onError = { vm.toast(it) }) }) { Icon(Icons.Rounded.QrCodeScanner, "Scan a Bucks ID") }
                }
                Label("Role")
                if (vehicleMode) { Row { Chip("Driver", selected = true, icon = Icons.Rounded.DirectionsCar) {} }; Muted(roleExplain("ADMIN", true), Modifier.padding(top = 6.dp)) }
                else {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Chip("Admin", selected = role == "ADMIN") { role = "ADMIN" }; Chip("Store rider", selected = role == "STORE_RIDER") { role = "STORE_RIDER" } }
                    Muted(roleExplain(role, false), Modifier.padding(top = 6.dp))
                }
                PrimaryButton("Send invite", Modifier.padding(top = 14.dp), enabled = BucksQr.looksLikeBucksId(code)) { m.invite(listingId, vehicleId, code, if (vehicleMode) "ADMIN" else role); code = "" }
                if (pending.isNotEmpty()) {
                    SectionTitle("Invites sent", Modifier.padding(top = 24.dp, bottom = 4.dp))
                    pending.forEach { i ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Avatar(initials(social.nameOf(i.inviteeId).ifBlank { "?" }), size = 40)
                            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(social.nameOf(i.inviteeId), style = MaterialTheme.typography.titleMedium); Muted("Invited as ${roleLabel(i.role, vehicleMode).lowercase()} · waiting for their answer") }
                            TextButton({ m.revokeInvite(i.id) }) { Text("Cancel") }
                        }
                        Divider()
                    }
                }
            } else Notice("Only the owner can invite or remove people.", Modifier.padding(top = 20.dp))
            Spacer(Modifier.height(16.dp))
        }
    }
    removeFor?.let { (pid, r) ->
        val self = pid == meId; val name = social.nameOf(pid)
        ConfirmDialog(if (self) "Leave $title?" else "Remove $name?",
            if (self) "You'll no longer be able to ${if (vehicleMode) "go online with this vehicle" else "manage this listing or take its orders"}. The owner can invite you again."
            else "$name will no longer be ${roleLabel(r, vehicleMode).lowercase()} here. You can invite them again later.",
            if (self) "Leave" else "Remove",
            onConfirm = { if (listingId != null) m.removeMember(listingId, pid) else if (vehicleId != null) m.removeVehicleMember(vehicleId, pid); if (self) onBack() },
            onDismiss = { removeFor = null })
    }
}

/** Invites waiting for my answer: help run a listing, or drive a vehicle. */
@Composable
fun InvitesScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(Unit) { m.refreshInvites() }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Invites", onBack = onBack)
        LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (m.invites.isEmpty()) item {
                BucksCard {
                    Text("No invites", style = MaterialTheme.typography.titleMedium)
                    Muted("When a shop owner asks you to help run their listing or deliver their orders, or a vehicle owner asks you to drive for them, the invite shows up here. They need your Bucks ID to send one.", Modifier.padding(top = 4.dp))
                }
            }
            items(m.invites, key = { it.id }) { i ->
                val vehicle = i.kind == "VEHICLE"
                BucksCard {
                    Row(verticalAlignment = Alignment.Top) {
                        Avatar(icon = if (vehicle) Icons.Rounded.LocalTaxi else listingIcon(i.kind, ""), size = 48)
                        Column(Modifier.weight(1f).padding(start = 12.dp)) {
                            Text(i.title, style = MaterialTheme.typography.titleMedium)
                            Muted(listOfNotNull("${i.inviterName.ifBlank { "Someone" }} invited you as ${roleLabel(i.role, vehicle).lowercase()}", i.createdAt.takeIf { it.isNotBlank() }?.let { ago(it) }).joinToString(" · "))
                        }
                    }
                    Muted(roleExplain(i.role, vehicle), Modifier.padding(top = 10.dp))
                    Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SmallButton("Accept", Modifier.weight(1f)) { m.respondInvite(i, true) }
                        SmallButton("Decline", Modifier.weight(1f), tonal = true) { m.respondInvite(i, false) }
                    }
                }
            }
        }
    }
}
