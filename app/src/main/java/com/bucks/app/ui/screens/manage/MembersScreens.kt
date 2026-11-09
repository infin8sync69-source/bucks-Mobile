package com.bucks.app.ui.screens.manage

import androidx.compose.ui.res.stringResource
import com.bucks.app.R
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
    val notBucksId = stringResource(R.string.g8_not_bucks_id)
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(if (vehicleMode) stringResource(R.string.g8_drivers) else stringResource(R.string.g8_members), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Muted(if (vehicleMode) stringResource(R.string.g8_members_sub_vehicle) else stringResource(R.string.g8_members_sub_listing))
            SectionTitle(stringResource(R.string.g8_people), Modifier.padding(top = 20.dp, bottom = 4.dp))
            when {
                rows == null -> CenteredLoading()
                rows.isEmpty() -> Muted(stringResource(R.string.g8_only_you))
                else -> rows.sortedWith(compareBy({ ROLE_ORDER[it.second] ?: 9 }, { social.nameOf(it.first).lowercase() })).forEach { (pid, r) ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(initials(social.nameOf(pid).ifBlank { "?" }), size = 40)
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            Text(if (pid == meId) stringResource(R.string.g8_name_you, social.nameOf(pid)) else social.nameOf(pid), style = MaterialTheme.typography.titleMedium)
                            Muted(roleLabel(r, vehicleMode) + " · " + roleExplain(r, vehicleMode), maxLines = 2)
                        }
                        if (owner && r != "OWNER") IconButton(onClick = { removeFor = pid to r }) { Icon(Icons.Rounded.PersonRemove, stringResource(R.string.g8_remove)) }
                        else if (pid == meId && r != "OWNER") SmallButton(stringResource(R.string.g8_leave), tonal = true) { removeFor = pid to r }
                    }
                    Divider()
                }
            }
            if (owner) {
                SectionTitle(if (vehicleMode) stringResource(R.string.g8_invite_driver) else stringResource(R.string.g8_invite_someone), Modifier.padding(top = 24.dp, bottom = 4.dp))
                Muted(stringResource(R.string.g8_invite_how), Modifier.padding(bottom = 10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(code, { code = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(8) }, placeholder = { Text("H6VF YWYF") }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, singleLine = true,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters))
                    Spacer(Modifier.width(8.dp))
                    FilledTonalIconButton(onClick = { scanQr(ctx, onResult = { raw -> when (val s = BucksQr.parse(raw)) { is BucksQr.Scanned.BucksId -> code = s.code; else -> vm.toast(notBucksId) } }, onError = { vm.toast(it) }) }) { Icon(Icons.Rounded.QrCodeScanner, stringResource(R.string.g8_cd_scan_bucks_id)) }
                }
                Label(stringResource(R.string.g8_role))
                if (vehicleMode) { Row { Chip(stringResource(R.string.g8_driver), selected = true, icon = Icons.Rounded.DirectionsCar) {} }; Muted(roleExplain("ADMIN", true), Modifier.padding(top = 6.dp)) }
                else {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Chip(stringResource(R.string.g8_admin), selected = role == "ADMIN") { role = "ADMIN" }; Chip(stringResource(R.string.g8_store_rider), selected = role == "STORE_RIDER") { role = "STORE_RIDER" } }
                    Muted(roleExplain(role, false), Modifier.padding(top = 6.dp))
                }
                PrimaryButton(stringResource(R.string.g8_send_invite), Modifier.padding(top = 14.dp), enabled = BucksQr.looksLikeBucksId(code)) { m.invite(listingId, vehicleId, code, if (vehicleMode) "ADMIN" else role); code = "" }
                if (pending.isNotEmpty()) {
                    SectionTitle(stringResource(R.string.g8_invites_sent), Modifier.padding(top = 24.dp, bottom = 4.dp))
                    pending.forEach { i ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Avatar(initials(social.nameOf(i.inviteeId).ifBlank { "?" }), size = 40)
                            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(social.nameOf(i.inviteeId), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g8_invited_as_waiting, roleLabel(i.role, vehicleMode).lowercase())) }
                            TextButton({ m.revokeInvite(i.id) }) { Text(stringResource(R.string.g8_cancel)) }
                        }
                        Divider()
                    }
                }
            } else Notice(stringResource(R.string.g8_only_owner_invites), Modifier.padding(top = 20.dp))
            Spacer(Modifier.height(16.dp))
        }
    }
    removeFor?.let { (pid, r) ->
        val self = pid == meId; val name = social.nameOf(pid)
        ConfirmDialog(if (self) stringResource(R.string.g8_leave_q, title) else stringResource(R.string.g8_remove_name_q, name),
            if (self) (if (vehicleMode) stringResource(R.string.g8_leave_body_vehicle) else stringResource(R.string.g8_leave_body_listing))
            else stringResource(R.string.g8_remove_member_body, name, roleLabel(r, vehicleMode).lowercase()),
            if (self) stringResource(R.string.g8_leave) else stringResource(R.string.g8_remove),
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
        BucksTopBar(stringResource(R.string.g8_invites), onBack = onBack)
        LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (m.invites.isEmpty()) item {
                BucksCard {
                    Text(stringResource(R.string.g8_no_invites), style = MaterialTheme.typography.titleMedium)
                    Muted(stringResource(R.string.g8_no_invites_sub), Modifier.padding(top = 4.dp))
                }
            }
            items(m.invites, key = { it.id }) { i ->
                val vehicle = i.kind == "VEHICLE"
                BucksCard {
                    Row(verticalAlignment = Alignment.Top) {
                        Avatar(icon = if (vehicle) Icons.Rounded.LocalTaxi else listingIcon(i.kind, ""), size = 48)
                        Column(Modifier.weight(1f).padding(start = 12.dp)) {
                            Text(i.title, style = MaterialTheme.typography.titleMedium)
                            Muted(listOfNotNull(stringResource(R.string.g8_invited_you_as, i.inviterName.ifBlank { stringResource(R.string.g8_someone) }, roleLabel(i.role, vehicle).lowercase()), i.createdAt.takeIf { it.isNotBlank() }?.let { ago(it) }).joinToString(" · "))
                        }
                    }
                    Muted(roleExplain(i.role, vehicle), Modifier.padding(top = 10.dp))
                    Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SmallButton(stringResource(R.string.g8_accept), Modifier.weight(1f)) { m.respondInvite(i, true) }
                        SmallButton(stringResource(R.string.g8_decline), Modifier.weight(1f), tonal = true) { m.respondInvite(i, false) }
                    }
                }
            }
        }
    }
}
