@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.bucks.app.ui.screens.pro

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
        if (uri != null) change("CV uploaded.") {
            val picked = withContext(Dispatchers.IO) { Upload.read(ctx, uri, maxPx = 2400, quality = 85) } ?: error("Couldn't open that file. Try another one.")
            ProBackend.uploadCv(meId, picked, primary = false, hasOthers = data?.cvs?.isNotEmpty() == true)
        }
    }

    val p = data?.profile
    val name = if (mine) me?.name.orEmpty() else person?.name.orEmpty()
    val photo = if (mine) me?.photoUrl else person?.photoUrl
    val area = if (mine) me?.area.orEmpty() else person?.area.orEmpty()

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(if (mine) "My Pro profile" else "Pro profile", onBack = onBack, actions = {
            if (mine && p != null) IconButton({ sheet = ProSheet.Visibility }) { Icon(Icons.Rounded.Visibility, "Who can see it") }
            if (p != null) IconButton({ shareText(ctx, proShareText(name, p, area)) }) { Icon(Icons.Rounded.IosShare, "Share") }
        })
        val d = data
        when {
            id == null -> Muted("Sign in to set up your Pro profile.", Modifier.padding(Gutter))
            d == null && failed -> Column(Modifier.padding(Gutter)) { Muted("Couldn't load this Pro profile."); SmallButton("Try again", Modifier.padding(top = 10.dp)) { reload() } }
            d == null -> Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            mine && vm.safety.isMinor -> Notice("Pro profiles are for people aged 18 and over.", Modifier.padding(Gutter))
            p == null && mine -> StartCard(name, photo) { sheet = ProSheet.Intro }
            p == null -> Column(Modifier.padding(Gutter)) { Text(name.ifBlank { "This person" }, style = MaterialTheme.typography.titleLarge); Muted("hasn't shared a Pro profile with you.", Modifier.padding(top = 4.dp)) }
            else -> Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 32.dp)) {
                Header(name, photo, area, p, mine, d, onEditIntro = { sheet = ProSheet.Intro }, onMessage = { if (id != null) social.openDirect(id, onOpenChat) })
                val hidden = p.hidden.toSet()
                fun shown(key: String) = mine || key !in hidden

                if (p.summary.isNotBlank() || mine) SectionCard("About", Icons.Rounded.Notes, if (mine) ({ sheet = ProSheet.Intro }) else null, actionIcon = Icons.Rounded.Edit) {
                    if (p.summary.isBlank()) Muted("Say what you do, who you do it for and what you're good at.") else Text(p.summary, style = MaterialTheme.typography.bodyMedium)
                }
                if (shown("EXPERIENCE") && (mine || d.experience.isNotEmpty())) SectionCard("Experience", Icons.Rounded.Work, if (mine) ({ sheet = ProSheet.Experience(null) }) else null, hiddenNote = mine && "EXPERIENCE" in hidden) {
                    if (d.experience.isEmpty()) Muted("Add the jobs and work you've done.")
                    d.experience.forEachIndexed { i, x -> if (i > 0) HorizontalDivider(Modifier.padding(vertical = 10.dp))
                        ItemRow(mine, onClick = { sheet = ProSheet.Experience(x) }) {
                            Text(x.title, style = MaterialTheme.typography.titleSmall)
                            Muted(listOf(x.org, x.location).filter { it.isNotBlank() }.joinToString(" · "))
                            Muted(ProDates.range(x.start, x.end))
                            if (x.description.isNotBlank()) Text(x.description, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp))
                        } }
                }
                if (shown("EDUCATION") && (mine || d.education.isNotEmpty())) SectionCard("Education", Icons.Rounded.School, if (mine) ({ sheet = ProSheet.Education(null) }) else null, hiddenNote = mine && "EDUCATION" in hidden) {
                    if (d.education.isEmpty()) Muted("Add a course, a degree, an ITI or an apprenticeship.")
                    d.education.forEachIndexed { i, x -> if (i > 0) HorizontalDivider(Modifier.padding(vertical = 10.dp))
                        ItemRow(mine, onClick = { sheet = ProSheet.Education(x) }) {
                            Text(x.course, style = MaterialTheme.typography.titleSmall)
                            if (x.institute.isNotBlank()) Muted(x.institute)
                            Muted(listOfNotNull(listOfNotNull(x.startYear, x.endYear).joinToString(" – ").ifBlank { null }, x.grade.ifBlank { null }).joinToString(" · "))
                        } }
                }
                if (shown("SKILLS") && (mine || d.skills.isNotEmpty())) SectionCard("Skills", Icons.Rounded.Construction, if (mine) ({ sheet = ProSheet.Skill(null) }) else null, hiddenNote = mine && "SKILLS" in hidden) {
                    if (d.skills.isEmpty()) Muted("Add what you're good at. People search by skill.")
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        d.skills.forEach { s -> AssistChip(onClick = { if (mine) sheet = ProSheet.Skill(s) }, enabled = true,
                            label = { Text(s.name + (s.years?.let { " · ${it}y" } ?: "")) },
                            leadingIcon = { Icon(when (s.level) { "EXPERT" -> Icons.Rounded.Star; "INTERMEDIATE" -> Icons.Rounded.StarHalf; else -> Icons.Rounded.StarOutline }, ProText.level(s.level), Modifier.size(18.dp)) }) }
                    }
                }
                if (shown("CERTIFICATIONS") && (mine || d.certifications.isNotEmpty())) SectionCard("Licences and certificates", Icons.Rounded.WorkspacePremium, if (mine) ({ sheet = ProSheet.Certification(null) }) else null, hiddenNote = mine && "CERTIFICATIONS" in hidden) {
                    if (d.certifications.isEmpty()) Muted("A driving licence, a trade licence, a course certificate.")
                    d.certifications.forEachIndexed { i, x -> if (i > 0) HorizontalDivider(Modifier.padding(vertical = 10.dp))
                        ItemRow(mine, onClick = { sheet = ProSheet.Certification(x) }) {
                            Text(x.name, style = MaterialTheme.typography.titleSmall)
                            Muted(listOfNotNull(x.issuer.ifBlank { null }, x.issuedOn?.let { "Issued " + ProDates.month(it) }, x.expiresOn?.let { (if (ProDates.expired(it)) "Expired " else "Valid till ") + ProDates.month(it) }).joinToString(" · "))
                            if (x.credentialId.isNotBlank()) Muted("ID ${x.credentialId}")
                        } }
                }
                if (shown("SERVICES") && (mine || d.services.isNotEmpty())) SectionCard("Services I offer", Icons.Rounded.Handyman, if (mine) onAddService else null, hiddenNote = mine && "SERVICES" in hidden) {
                    if (d.services.isEmpty()) Muted("A skill page lets people nearby book you, recommend you and find you in Services.")
                    d.services.forEach { l -> Row(Modifier.fillMaxWidth().clickable { onOpenListing(l.id) }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(initials(l.title), icon = Icons.Rounded.Handyman, size = 40, photoUrl = Backend.listingPhoto(l.photoUrl))
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(l.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis); Muted(listOf(l.category, l.area).filter { it.isNotBlank() }.joinToString(" · "), maxLines = 1) }
                        if (l.status != "LIVE") PillWarn("Not live yet") else TrustBadge(Trust(l.trustUp, l.trustDown), compact = true)
                    } }
                }
                if (shown("PREFERENCES")) {
                    val prefs = ProText.preferences(p)
                    if (prefs.isNotEmpty() || mine) SectionCard("Work preferences", Icons.Rounded.Tune, if (mine) ({ sheet = ProSheet.Preferences }) else null, actionIcon = Icons.Rounded.Edit, hiddenNote = mine && "PREFERENCES" in hidden) {
                        if (prefs.isEmpty()) Muted("Job types, how far you'll travel, expected pay, when you're free, languages.")
                        prefs.forEach { (k, v) -> Row(Modifier.padding(vertical = 3.dp)) { Text(k, style = MaterialTheme.typography.labelLarge, modifier = Modifier.width(110.dp)); Text(v, style = MaterialTheme.typography.bodyMedium) } }
                    }
                }
                if (mine) SectionCard("My CV", Icons.Rounded.Description, { pickCv.launch(ProBackend.CV_MIMES) }, actionIcon = Icons.Rounded.Upload, actionLabel = "Upload a CV") {
                    Muted("Only you can see these. PDF, Word (.docx) or a photo, up to 10 MB; keep up to 5.")
                    d.cvs.forEach { cv -> CvRow(cv, busy, onOpen = { if (cv.mime.startsWith("image/")) viewing = cv else scope.launch { if (!FileOpener.open(ctx, social, "docs", cv.path, cv.fileName, cv.mime)) vm.toast("No app on this phone opens that file.") } },
                        onShare = { scope.launch { if (!FileOpener.share(ctx, social, "docs", cv.path, cv.mime)) vm.toast("Couldn't share that. Check your connection.") } },
                        onPrimary = { change("Main CV set.") { ProBackend.setPrimaryCv(me!!.id, cv.id) } },
                        onDelete = { change("CV deleted.") { ProBackend.deleteCv(cv) } }) }
                    if (d.cvs.isEmpty()) PrimaryButton("Upload my CV", Modifier.padding(top = 12.dp), enabled = !busy) { pickCv.launch(ProBackend.CV_MIMES) }
                }
                if (!mine) Muted("Updated ${p.updatedAt?.take(10) ?: ""}", Modifier.padding(top = 16.dp))
            }
        }
    }

    val meId = me?.id
    if (meId != null) when (val s = sheet) {
        null -> {}
        ProSheet.Intro -> IntroSheet(data?.profile, busy, onDismiss = { sheet = null }) { fields -> change(if (data?.profile == null) "Your Pro profile is ready. Add your experience and skills." else "Saved.") { ProBackend.saveProfile(meId, fields) } }
        ProSheet.Preferences -> PreferencesSheet(data?.profile ?: return, busy, onDismiss = { sheet = null }) { fields -> change("Saved.") { ProBackend.saveProfile(meId, fields) } }
        ProSheet.Visibility -> VisibilitySheet(data?.profile ?: return, busy, onDismiss = { sheet = null }) { fields -> change("Saved.") { ProBackend.saveProfile(meId, fields) } }
        is ProSheet.Experience -> ExperienceSheet(s.item, busy, onDismiss = { sheet = null },
            onSave = { f -> change("Saved.") { if (s.item == null) ProBackend.add(ProBackend.EXPERIENCE, meId, f) else ProBackend.edit(ProBackend.EXPERIENCE, s.item.id, f) } },
            onDelete = { change("Removed.") { ProBackend.remove(ProBackend.EXPERIENCE, s.item!!.id) } })
        is ProSheet.Education -> EducationSheet(s.item, busy, onDismiss = { sheet = null },
            onSave = { f -> change("Saved.") { if (s.item == null) ProBackend.add(ProBackend.EDUCATION, meId, f) else ProBackend.edit(ProBackend.EDUCATION, s.item.id, f) } },
            onDelete = { change("Removed.") { ProBackend.remove(ProBackend.EDUCATION, s.item!!.id) } })
        is ProSheet.Skill -> SkillSheet(s.item, busy, onDismiss = { sheet = null },
            onSave = { f -> change("Saved.") { if (s.item == null) ProBackend.add(ProBackend.SKILLS, meId, f) else ProBackend.edit(ProBackend.SKILLS, s.item.id, f) } },
            onDelete = { change("Removed.") { ProBackend.remove(ProBackend.SKILLS, s.item!!.id) } })
        is ProSheet.Certification -> CertificationSheet(s.item, busy, onDismiss = { sheet = null },
            onSave = { f -> change("Saved.") { if (s.item == null) ProBackend.add(ProBackend.CERTIFICATIONS, meId, f) else ProBackend.edit(ProBackend.CERTIFICATIONS, s.item.id, f) } },
            onDelete = { change("Removed.") { ProBackend.remove(ProBackend.CERTIFICATIONS, s.item!!.id) } })
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
            Column(Modifier.padding(start = 14.dp)) { Text("Set up your Pro profile", style = MaterialTheme.typography.titleMedium); Muted("Your work, skills and CV in one place.") }
        }
        Muted("People nearby and employers see what you do, where you've worked and what you're good at. You choose who sees it, and you can hide any part.", Modifier.padding(top = 12.dp))
        PrimaryButton("Start", Modifier.padding(top = 14.dp), onClick = onStart)
    }
}

@Composable
private fun Header(name: String, photo: String?, area: String, p: ProProfileRow, mine: Boolean, d: ProBundle, onEditIntro: () -> Unit, onMessage: () -> Unit) {
    Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(initials(name.ifBlank { "?" }), size = 72, photoUrl = photo)
        Column(Modifier.padding(start = 14.dp).weight(1f)) {
            Text(name.ifBlank { " " }, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.semantics { heading() })
            if (p.headline.isNotBlank()) Text(p.headline, style = MaterialTheme.typography.bodyLarge)
            Muted(listOfNotNull(area.ifBlank { null }, p.years?.let { if (it == 1) "1 year" else "$it years" }).joinToString(" · "))
        }
    }
    if (p.openTo.isNotEmpty()) FlowRow(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        p.openTo.forEach { PillGood(ProText.openTo(it)) } }
    if (mine) {
        val (pct, tip) = ProText.completeness(p, d, photo != null)
        Column(Modifier.padding(top = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) { Text("$pct% complete", style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f)); TextButton(onEditIntro) { Text("Edit intro") } }
            LinearProgressIndicator(progress = { pct / 100f }, modifier = Modifier.fillMaxWidth())
            tip?.let { Muted(it, Modifier.padding(top = 6.dp)) }
        }
    } else Row(Modifier.padding(top = 12.dp)) { SmallButton("Message", tonal = true, onClick = onMessage) }
}

@Composable
private fun SectionCard(title: String, icon: ImageVector, onAction: (() -> Unit)?, actionIcon: ImageVector = Icons.Rounded.Add, actionLabel: String = "Add to $title", hiddenNote: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    BucksCard(Modifier.fillMaxWidth().padding(top = 14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
            Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 8.dp).weight(1f).semantics { heading() })
            if (hiddenNote) PillGrey("Hidden")
            if (onAction != null) IconButton(onAction) { Icon(actionIcon, actionLabel) }
        }
        Column(Modifier.padding(top = 6.dp), content = content)
    }
}

@Composable
private fun ItemRow(editable: Boolean, onClick: () -> Unit, content: @Composable ColumnScope.() -> Unit) =
    Row(Modifier.fillMaxWidth().then(if (editable) Modifier.clickable(onClickLabel = "Edit", onClick = onClick) else Modifier), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f), content = content)
        if (editable) Icon(Icons.Rounded.Edit, null, Modifier.padding(start = 8.dp).size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }

@Composable
private fun CvRow(cv: ProCv, busy: Boolean, onOpen: () -> Unit, onShare: () -> Unit, onPrimary: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }; var confirm by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().clickable(onClickLabel = "Open", onClick = onOpen).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(if (cv.mime.startsWith("image/")) Icons.Rounded.Image else Icons.Rounded.Description, null, tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Text(cv.fileName, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Muted(listOfNotNull(cv.uploadedAt.take(10).ifBlank { null }, "${(cv.size + 1023) / 1024} KB").joinToString(" · "))
        }
        if (cv.primary) PillGood("Main")
        Box { IconButton({ menu = true }, enabled = !busy) { Icon(Icons.Rounded.MoreVert, "More for ${cv.fileName}") }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text("Open") }, { menu = false; onOpen() }, leadingIcon = { Icon(Icons.Rounded.OpenInNew, null) })
                DropdownMenuItem({ Text("Share") }, { menu = false; onShare() }, leadingIcon = { Icon(Icons.Rounded.Share, null) })
                if (!cv.primary) DropdownMenuItem({ Text("Make it my main CV") }, { menu = false; onPrimary() }, leadingIcon = { Icon(Icons.Rounded.Star, null) })
                DropdownMenuItem({ Text("Delete", color = MaterialTheme.colorScheme.error) }, { menu = false; confirm = true }, leadingIcon = { Icon(Icons.Rounded.DeleteOutline, null, tint = MaterialTheme.colorScheme.error) })
            } }
    }
    if (confirm) AlertDialog(onDismissRequest = { confirm = false }, title = { Text("Delete this CV?") }, text = { Text("${cv.fileName} is removed from Bucks.") },
        confirmButton = { TextButton({ confirm = false; onDelete() }) { Text("Delete", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirm = false }) { Text("Cancel") } })
}

private fun proShareText(name: String, p: ProProfileRow, area: String) =
    "$name on Bucks" + (if (p.headline.isNotBlank()) ": ${p.headline}" else "") + (if (area.isNotBlank()) " · $area" else "") + ". Open Bucks and search \"$name\"."
