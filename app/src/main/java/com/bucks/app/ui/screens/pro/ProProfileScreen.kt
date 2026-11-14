@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.bucks.app.ui.screens.pro

import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.bucks.app.R
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.FileOpener
import com.bucks.app.ui.MediaViewer
import com.bucks.app.ui.ViewerMedia
import com.bucks.app.ui.components.*
import com.bucks.app.ui.shareText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The Pro profile: a person's professional side (Bucks Pro menu > Pro profile). My own opens editable: intro, experience, education,
 * skills, certifications, services I offer (my skill pages), work preferences, visibility and my CV files. Someone else's is read-only
 * and shows only what their visibility settings let me see (the server decides: pro_profile.sql). [profileId] null: mine.
 */
@Composable
fun ProProfileScreen(vm: BucksViewModel, profileId: String?, onBack: () -> Unit, onOpenListing: (String) -> Unit, onAddService: () -> Unit, onOpenChat: (String) -> Unit) {
    val social = vm.social; val me = social.me; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    val id = profileId ?: me?.id
    val mine = id != null && id == me?.id
    var data by remember(id) { mutableStateOf<ProBundle?>(null) }
    var person by remember(id) { mutableStateOf<ProfileRow?>(null) }
    var failed by remember(id) { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var sheet by remember { mutableStateOf<ProSheet?>(null) }
    var viewing by remember { mutableStateOf<ProCv?>(null) }

    fun reload() { val pid = id ?: return; scope.launch {
        failed = false
        try { data = ProBackend.load(pid, mine); if (!mine && person == null) person = Backend.profiles(listOf(pid)).firstOrNull() }
        catch (e: CancellationException) { throw e } catch (e: Exception) { failed = true; vm.toast(friendlyError(e)) }
    } }
    /** Runs a change, then reads the profile again so the screen shows what the server kept. */
    fun change(done: String? = null, block: suspend () -> Unit) { if (busy) return; scope.launch {
        busy = true
        try { block(); done?.let { vm.toast(it) }; sheet = null; data = ProBackend.load(id ?: return@launch, mine) }
        catch (e: CancellationException) { throw e } catch (e: Exception) { vm.toast(friendlyError(e)) }
        finally { busy = false }
    } }
    LaunchedEffect(id) { reload() }

    val pickCv = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val meId = me?.id ?: return@rememberLauncherForActivityResult
        if (uri != null) change(Str.get(R.string.g7_pp_cv_uploaded)) {
            val picked = withContext(Dispatchers.IO) { Upload.read(ctx, uri, maxPx = 2400, quality = 85) } ?: error(Str.get(R.string.g7_pp_cv_unreadable))
            ProBackend.uploadCv(meId, picked, primary = false, hasOthers = data?.cvs?.isNotEmpty() == true)
        }
    }

    val p = data?.profile
    val name = if (mine) me?.name.orEmpty() else person?.name.orEmpty()
    val photo = if (mine) me?.photoUrl else person?.photoUrl
    val area = if (mine) me?.area.orEmpty() else person?.area.orEmpty()

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(if (mine) stringResource(R.string.g7_pp_my_title) else stringResource(R.string.g7_pp_title), onBack = onBack, actions = {
            if (mine && p != null) IconButton({ sheet = ProSheet.Visibility }) { Icon(Icons.Rounded.Visibility, stringResource(R.string.g7_cd_pp_who_sees)) }
            if (p != null) IconButton({ shareText(ctx, proShareText(name, p, area)) }) { Icon(Icons.Rounded.IosShare, stringResource(R.string.g7_cd_share)) }
        })
        val d = data
        when {
            id == null -> Muted(stringResource(R.string.g7_pp_sign_in), Modifier.padding(Gutter))
            d == null && failed -> Column(Modifier.padding(Gutter)) { Muted(stringResource(R.string.g7_pp_load_failed)); SmallButton(stringResource(R.string.g7_pp_try_again), Modifier.padding(top = 10.dp)) { reload() } }
            d == null -> Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            mine && vm.safety.isMinor -> Notice(stringResource(R.string.g7_pp_adults_only), Modifier.padding(Gutter))
            p == null && mine -> StartCard(name, photo) { sheet = ProSheet.Intro }
            p == null -> Column(Modifier.padding(Gutter)) { Text(name.ifBlank { stringResource(R.string.g7_pp_this_person) }, style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g7_pp_not_shared), Modifier.padding(top = 4.dp)) }
            else -> Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 32.dp)) {
                Header(name, photo, area, p, mine, d, onEditIntro = { sheet = ProSheet.Intro }, onMessage = { if (id != null) social.openDirect(id, onOpenChat) })
                val hidden = p.hidden.toSet()
                fun shown(key: String) = mine || key !in hidden

                if (p.summary.isNotBlank() || mine) SectionCard(stringResource(R.string.g7_pp_about), Icons.Rounded.Notes, if (mine) ({ sheet = ProSheet.Intro }) else null, actionIcon = Icons.Rounded.Edit) {
                    if (p.summary.isBlank()) Muted(stringResource(R.string.g7_pp_about_empty)) else Text(p.summary, style = MaterialTheme.typography.bodyMedium)
                }
                if (shown("EXPERIENCE") && (mine || d.experience.isNotEmpty())) SectionCard(stringResource(R.string.g7_pp_experience), Icons.Rounded.Work, if (mine) ({ sheet = ProSheet.Experience(null) }) else null, hiddenNote = mine && "EXPERIENCE" in hidden) {
                    if (d.experience.isEmpty()) Muted(stringResource(R.string.g7_pp_experience_empty))
                    d.experience.forEachIndexed { i, x -> if (i > 0) HorizontalDivider(Modifier.padding(vertical = 10.dp))
                        ItemRow(mine, onClick = { sheet = ProSheet.Experience(x) }) {
                            Text(x.title, style = MaterialTheme.typography.titleSmall)
                            Muted(listOf(x.org, x.location).filter { it.isNotBlank() }.joinToString(" · "))
                            Muted(ProDates.range(x.start, x.end))
                            if (x.description.isNotBlank()) Text(x.description, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp))
                        } }
                }
                if (shown("EDUCATION") && (mine || d.education.isNotEmpty())) SectionCard(stringResource(R.string.g7_pp_education), Icons.Rounded.School, if (mine) ({ sheet = ProSheet.Education(null) }) else null, hiddenNote = mine && "EDUCATION" in hidden) {
                    if (d.education.isEmpty()) Muted(stringResource(R.string.g7_pp_education_empty))
                    d.education.forEachIndexed { i, x -> if (i > 0) HorizontalDivider(Modifier.padding(vertical = 10.dp))
                        ItemRow(mine, onClick = { sheet = ProSheet.Education(x) }) {
                            Text(x.course, style = MaterialTheme.typography.titleSmall)
                            if (x.institute.isNotBlank()) Muted(x.institute)
                            Muted(listOfNotNull(listOfNotNull(x.startYear, x.endYear).joinToString(" – ").ifBlank { null }, x.grade.ifBlank { null }).joinToString(" · "))
                        } }
                }
                if (shown("SKILLS") && (mine || d.skills.isNotEmpty())) SectionCard(stringResource(R.string.g7_pp_skills), Icons.Rounded.Construction, if (mine) ({ sheet = ProSheet.Skill(null) }) else null, hiddenNote = mine && "SKILLS" in hidden) {
                    if (d.skills.isEmpty()) Muted(stringResource(R.string.g7_pp_skills_empty))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        d.skills.forEach { s -> AssistChip(onClick = { if (mine) sheet = ProSheet.Skill(s) }, enabled = true,
                            label = { Text(s.years?.let { stringResource(R.string.g7_pp_skill_years, s.name, it.toString()) } ?: s.name) },
                            leadingIcon = { Icon(when (s.level) { "EXPERT" -> Icons.Rounded.Star; "INTERMEDIATE" -> Icons.Rounded.StarHalf; else -> Icons.Rounded.StarOutline }, ProText.level(s.level), Modifier.size(18.dp)) }) }
                    }
                }
                if (shown("CERTIFICATIONS") && (mine || d.certifications.isNotEmpty())) SectionCard(stringResource(R.string.g7_pp_certs), Icons.Rounded.WorkspacePremium, if (mine) ({ sheet = ProSheet.Certification(null) }) else null, hiddenNote = mine && "CERTIFICATIONS" in hidden) {
                    if (d.certifications.isEmpty()) Muted(stringResource(R.string.g7_pp_certs_empty))
                    d.certifications.forEachIndexed { i, x -> if (i > 0) HorizontalDivider(Modifier.padding(vertical = 10.dp))
                        ItemRow(mine, onClick = { sheet = ProSheet.Certification(x) }) {
                            Text(x.name, style = MaterialTheme.typography.titleSmall)
                            Muted(listOfNotNull(x.issuer.ifBlank { null }, x.issuedOn?.let { stringResource(R.string.g7_pp_issued, ProDates.month(it)) }, x.expiresOn?.let { if (ProDates.expired(it)) stringResource(R.string.g7_pp_expired, ProDates.month(it)) else stringResource(R.string.g7_pp_valid_till, ProDates.month(it)) }).joinToString(" · "))
                            if (x.credentialId.isNotBlank()) Muted(stringResource(R.string.g7_pp_credential_id, x.credentialId))
                        } }
                }
                if (shown("SERVICES") && (mine || d.services.isNotEmpty())) SectionCard(stringResource(R.string.g7_pp_services), Icons.Rounded.Handyman, if (mine) onAddService else null, hiddenNote = mine && "SERVICES" in hidden) {
                    if (d.services.isEmpty()) Muted(stringResource(R.string.g7_pp_services_empty))
                    d.services.forEach { l -> Row(Modifier.fillMaxWidth().clickable { onOpenListing(l.id) }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(initials(l.title), icon = Icons.Rounded.Handyman, size = 40, photoUrl = Backend.listingPhoto(l.photoUrl))
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(l.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis); Muted(listOf(l.category, l.area).filter { it.isNotBlank() }.joinToString(" · "), maxLines = 1) }
                        if (l.status != "LIVE") PillWarn(stringResource(R.string.g7_pp_not_live)) else TrustBadge(Trust(l.trustUp, l.trustDown), compact = true)
                    } }
                }
                if (shown("PREFERENCES")) {
                    val prefs = ProText.preferences(p)
                    if (prefs.isNotEmpty() || mine) SectionCard(stringResource(R.string.g7_pp_prefs), Icons.Rounded.Tune, if (mine) ({ sheet = ProSheet.Preferences }) else null, actionIcon = Icons.Rounded.Edit, hiddenNote = mine && "PREFERENCES" in hidden) {
                        if (prefs.isEmpty()) Muted(stringResource(R.string.g7_pp_prefs_empty))
                        prefs.forEach { (k, v) -> Row(Modifier.padding(vertical = 3.dp)) { Text(k, style = MaterialTheme.typography.labelLarge, modifier = Modifier.width(110.dp)); Text(v, style = MaterialTheme.typography.bodyMedium) } }
                    }
                }
                if (mine) SectionCard(stringResource(R.string.g7_pp_my_cv), Icons.Rounded.Description, { pickCv.launch(ProBackend.CV_MIMES) }, actionIcon = Icons.Rounded.Upload, actionLabel = stringResource(R.string.g7_pp_upload_cv)) {
                    Muted(stringResource(R.string.g7_pp_cv_note))
                    d.cvs.forEach { cv -> CvRow(cv, busy, onOpen = { if (cv.mime.startsWith("image/")) viewing = cv else scope.launch { if (!FileOpener.open(ctx, social, "docs", cv.path, cv.fileName, cv.mime)) vm.toast(Str.get(R.string.g7_pp_no_app)) } },
                        onShare = { scope.launch { if (!FileOpener.share(ctx, social, "docs", cv.path, cv.mime)) vm.toast(Str.get(R.string.g7_pp_share_failed)) } },
                        onPrimary = { change(Str.get(R.string.g7_pp_main_set)) { ProBackend.setPrimaryCv(me!!.id, cv.id) } },
                        onDelete = { change(Str.get(R.string.g7_pp_cv_deleted)) { ProBackend.deleteCv(cv) } }) }
                    if (d.cvs.isEmpty()) PrimaryButton(stringResource(R.string.g7_pp_upload_my_cv), Modifier.padding(top = 12.dp), enabled = !busy) { pickCv.launch(ProBackend.CV_MIMES) }
                }
                if (!mine) Muted(stringResource(R.string.g7_pp_updated, p.updatedAt?.take(10) ?: ""), Modifier.padding(top = 16.dp))
            }
        }
    }

    val meId = me?.id
    if (meId != null) when (val s = sheet) {
        null -> {}
        ProSheet.Intro -> IntroSheet(data?.profile, busy, onDismiss = { sheet = null }) { fields -> change(if (data?.profile == null) Str.get(R.string.g7_pp_ready) else Str.get(R.string.g7_pp_saved)) { ProBackend.saveProfile(meId, fields) } }
        ProSheet.Preferences -> PreferencesSheet(data?.profile ?: return, busy, onDismiss = { sheet = null }) { fields -> change(Str.get(R.string.g7_pp_saved)) { ProBackend.saveProfile(meId, fields) } }
        ProSheet.Visibility -> VisibilitySheet(data?.profile ?: return, busy, onDismiss = { sheet = null }) { fields -> change(Str.get(R.string.g7_pp_saved)) { ProBackend.saveProfile(meId, fields) } }
        is ProSheet.Experience -> ExperienceSheet(s.item, busy, onDismiss = { sheet = null },
            onSave = { f -> change(Str.get(R.string.g7_pp_saved)) { if (s.item == null) ProBackend.add(ProBackend.EXPERIENCE, meId, f) else ProBackend.edit(ProBackend.EXPERIENCE, s.item.id, f) } },
            onDelete = { change(Str.get(R.string.g7_pp_removed)) { ProBackend.remove(ProBackend.EXPERIENCE, s.item!!.id) } })
        is ProSheet.Education -> EducationSheet(s.item, busy, onDismiss = { sheet = null },
            onSave = { f -> change(Str.get(R.string.g7_pp_saved)) { if (s.item == null) ProBackend.add(ProBackend.EDUCATION, meId, f) else ProBackend.edit(ProBackend.EDUCATION, s.item.id, f) } },
            onDelete = { change(Str.get(R.string.g7_pp_removed)) { ProBackend.remove(ProBackend.EDUCATION, s.item!!.id) } })
        is ProSheet.Skill -> SkillSheet(s.item, busy, onDismiss = { sheet = null },
            onSave = { f -> change(Str.get(R.string.g7_pp_saved)) { if (s.item == null) ProBackend.add(ProBackend.SKILLS, meId, f) else ProBackend.edit(ProBackend.SKILLS, s.item.id, f) } },
            onDelete = { change(Str.get(R.string.g7_pp_removed)) { ProBackend.remove(ProBackend.SKILLS, s.item!!.id) } })
        is ProSheet.Certification -> CertificationSheet(s.item, busy, onDismiss = { sheet = null },
            onSave = { f -> change(Str.get(R.string.g7_pp_saved)) { if (s.item == null) ProBackend.add(ProBackend.CERTIFICATIONS, meId, f) else ProBackend.edit(ProBackend.CERTIFICATIONS, s.item.id, f) } },
            onDelete = { change(Str.get(R.string.g7_pp_removed)) { ProBackend.remove(ProBackend.CERTIFICATIONS, s.item!!.id) } })
    }
    viewing?.let { cv -> MediaViewer(vm, listOf(ViewerMedia.Stored("docs", cv.path, cv.mime)), title = cv.fileName) { viewing = null } }
}

/** Which editor is open. */
internal sealed interface ProSheet {
    data object Intro : ProSheet
    data object Preferences : ProSheet
    data object Visibility : ProSheet
    data class Experience(val item: ProExperience?) : ProSheet
    data class Education(val item: ProEducation?) : ProSheet
    data class Skill(val item: ProSkill?) : ProSheet
    data class Certification(val item: ProCertification?) : ProSheet
}

@Composable
private fun StartCard(name: String, photo: String?, onStart: () -> Unit) = Column(Modifier.padding(Gutter)) {
    BucksCard(Modifier.fillMaxWidth(), tint = true) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(initials(name.ifBlank { "?" }), size = 56, photoUrl = photo)
            Column(Modifier.padding(start = 14.dp)) { Text(stringResource(R.string.g7_pp_setup), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g7_pp_setup_sub)) }
        }
        Muted(stringResource(R.string.g7_pp_setup_note), Modifier.padding(top = 12.dp))
        PrimaryButton(stringResource(R.string.g7_pp_start), Modifier.padding(top = 14.dp), onClick = onStart)
    }
}

@Composable
private fun Header(name: String, photo: String?, area: String, p: ProProfileRow, mine: Boolean, d: ProBundle, onEditIntro: () -> Unit, onMessage: () -> Unit) {
    Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(initials(name.ifBlank { "?" }), size = 72, photoUrl = photo)
        Column(Modifier.padding(start = 14.dp).weight(1f)) {
            Text(name.ifBlank { " " }, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.semantics { heading() })
            if (p.headline.isNotBlank()) Text(p.headline, style = MaterialTheme.typography.bodyLarge)
            Muted(listOfNotNull(area.ifBlank { null }, p.years?.let { pluralStringResource(R.plurals.g7_pp_years, it, it) }).joinToString(" · "))
        }
    }
    if (p.openTo.isNotEmpty()) FlowRow(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        p.openTo.forEach { PillGood(ProText.openTo(it)) } }
    if (mine) {
        val (pct, tip) = ProText.completeness(p, d, photo != null)
        Column(Modifier.padding(top = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) { Text(stringResource(R.string.g7_pp_complete, pct), style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f)); TextButton(onEditIntro) { Text(stringResource(R.string.g7_pp_edit_intro)) } }
            LinearProgressIndicator(progress = { pct / 100f }, modifier = Modifier.fillMaxWidth())
            tip?.let { Muted(it, Modifier.padding(top = 6.dp)) }
        }
    } else Row(Modifier.padding(top = 12.dp)) { SmallButton(stringResource(R.string.g7_pp_message), tonal = true, onClick = onMessage) }
}

@Composable
private fun SectionCard(title: String, icon: ImageVector, onAction: (() -> Unit)?, actionIcon: ImageVector = Icons.Rounded.Add, actionLabel: String = stringResource(R.string.g7_cd_pp_add_to, title), hiddenNote: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    BucksCard(Modifier.fillMaxWidth().padding(top = 14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
            Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 8.dp).weight(1f).semantics { heading() })
            if (hiddenNote) PillGrey(stringResource(R.string.g7_pp_hidden))
            if (onAction != null) IconButton(onAction) { Icon(actionIcon, actionLabel) }
        }
        Column(Modifier.padding(top = 6.dp), content = content)
    }
}

@Composable
private fun ItemRow(editable: Boolean, onClick: () -> Unit, content: @Composable ColumnScope.() -> Unit) =
    Row(Modifier.fillMaxWidth().then(if (editable) Modifier.clickable(onClickLabel = stringResource(R.string.g7_pp_edit), onClick = onClick) else Modifier), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f), content = content)
        if (editable) Icon(Icons.Rounded.Edit, null, Modifier.padding(start = 8.dp).size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }

@Composable
private fun CvRow(cv: ProCv, busy: Boolean, onOpen: () -> Unit, onShare: () -> Unit, onPrimary: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }; var confirm by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().clickable(onClickLabel = stringResource(R.string.g7_pp_open), onClick = onOpen).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(if (cv.mime.startsWith("image/")) Icons.Rounded.Image else Icons.Rounded.Description, null, tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Text(cv.fileName, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Muted(listOfNotNull(cv.uploadedAt.take(10).ifBlank { null }, stringResource(R.string.g7_pp_kb, ((cv.size + 1023) / 1024).toString())).joinToString(" · "))
        }
        if (cv.primary) PillGood(stringResource(R.string.g7_pp_main))
        Box { IconButton({ menu = true }, enabled = !busy) { Icon(Icons.Rounded.MoreVert, stringResource(R.string.g7_cd_pp_more_for, cv.fileName)) }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text(stringResource(R.string.g7_pp_open)) }, { menu = false; onOpen() }, leadingIcon = { Icon(Icons.Rounded.OpenInNew, null) })
                DropdownMenuItem({ Text(stringResource(R.string.g7_cd_share)) }, { menu = false; onShare() }, leadingIcon = { Icon(Icons.Rounded.Share, null) })
                if (!cv.primary) DropdownMenuItem({ Text(stringResource(R.string.g7_pp_make_main)) }, { menu = false; onPrimary() }, leadingIcon = { Icon(Icons.Rounded.Star, null) })
                DropdownMenuItem({ Text(stringResource(R.string.g7_pp_delete), color = MaterialTheme.colorScheme.error) }, { menu = false; confirm = true }, leadingIcon = { Icon(Icons.Rounded.DeleteOutline, null, tint = MaterialTheme.colorScheme.error) })
            } }
    }
    if (confirm) AlertDialog(onDismissRequest = { confirm = false }, title = { Text(stringResource(R.string.g7_pp_delete_cv_title)) }, text = { Text(stringResource(R.string.g7_pp_delete_cv_body, cv.fileName)) },
        confirmButton = { TextButton({ confirm = false; onDelete() }) { Text(stringResource(R.string.g7_pp_delete), color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirm = false }) { Text(stringResource(R.string.g7_pp_cancel)) } })
}

private fun proShareText(name: String, p: ProProfileRow, area: String) =
    when {
        p.headline.isNotBlank() && area.isNotBlank() -> Str.get(R.string.g7_pp_share_headline_area, name, p.headline, area)
        p.headline.isNotBlank() -> Str.get(R.string.g7_pp_share_headline, name, p.headline)
        area.isNotBlank() -> Str.get(R.string.g7_pp_share_area, name, area)
        else -> Str.get(R.string.g7_pp_share, name)
    }
