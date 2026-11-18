@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)

package com.bucks.app.ui.screens.pro

import com.bucks.app.R
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bucks.app.data.*
import com.bucks.app.ui.components.*
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate
import java.time.Month
import java.time.format.TextStyle
import java.util.Locale

/** Words and numbers the Pro profile shows. */
internal object ProText {
    val OPEN_TO get() = listOf("WORK" to Str.get(R.string.g5_pro_open_work), "GIGS" to Str.get(R.string.g5_pro_open_gigs), "HIRING" to Str.get(R.string.g5_pro_hiring))
    val JOB_TYPES get() = listOf("FULL_TIME" to Str.get(R.string.g5_job_full_time), "PART_TIME" to Str.get(R.string.g5_job_part_time), "CONTRACT" to Str.get(R.string.g5_job_contract), "GIG" to Str.get(R.string.g5_job_gigs), "INTERNSHIP" to Str.get(R.string.g5_job_internship), "APPRENTICESHIP" to Str.get(R.string.g5_job_apprenticeship))
    val LEVELS get() = listOf("BEGINNER" to Str.get(R.string.g5_level_beginner), "INTERMEDIATE" to Str.get(R.string.g5_level_intermediate), "EXPERT" to Str.get(R.string.g5_level_expert))
    val SECTIONS get() = listOf("EXPERIENCE" to Str.get(R.string.g5_sec_experience), "EDUCATION" to Str.get(R.string.g5_sec_education), "SKILLS" to Str.get(R.string.g5_sec_skills), "CERTIFICATIONS" to Str.get(R.string.g5_sec_certs), "SERVICES" to Str.get(R.string.g5_sec_services), "PREFERENCES" to Str.get(R.string.g5_sec_prefs))
    fun openTo(k: String) = OPEN_TO.firstOrNull { it.first == k }?.second ?: k
    fun level(k: String) = LEVELS.firstOrNull { it.first == k }?.second ?: k
    fun jobType(k: String) = JOB_TYPES.firstOrNull { it.first == k }?.second ?: k

    fun preferences(p: ProProfileRow): List<Pair<String, String>> = listOfNotNull(
        p.jobTypes.takeIf { it.isNotEmpty() }?.let { Str.get(R.string.g5_pref_job_types) to it.joinToString(", ") { k -> jobType(k) } },
        p.radiusKm?.let { Str.get(R.string.g5_pref_travel) to Str.get(R.string.g5_pref_up_to_km, it.toString()) },
        p.expectedPay.ifBlank { null }?.let { Str.get(R.string.g5_pref_pay) to it },
        p.availability.ifBlank { null }?.let { Str.get(R.string.g5_pref_available) to it },
        p.languages.takeIf { it.isNotEmpty() }?.let { Str.get(R.string.g5_pref_languages) to it.joinToString(", ") })

    /** How complete my profile is, and the next most useful thing to add. */
    fun completeness(p: ProProfileRow, d: ProBundle, hasPhoto: Boolean): Pair<Int, String?> {
        val steps = listOf(
            (p.headline.isNotBlank()) to (15 to Str.get(R.string.g5_tip_headline)),
            (p.summary.isNotBlank()) to (15 to Str.get(R.string.g5_tip_about)),
            (d.experience.isNotEmpty()) to (20 to Str.get(R.string.g5_tip_experience)),
            (d.skills.size >= 3) to (15 to Str.get(R.string.g5_tip_skills)),
            (d.education.isNotEmpty()) to (10 to Str.get(R.string.g5_tip_education)),
            hasPhoto to (10 to Str.get(R.string.g5_tip_photo)),
            (d.cvs.isNotEmpty()) to (10 to Str.get(R.string.g5_tip_cv)),
            (preferences(p).isNotEmpty()) to (5 to Str.get(R.string.g5_tip_prefs)))
        return steps.filter { it.first }.sumOf { it.second.first } to steps.firstOrNull { !it.first }?.second?.second
    }
}

/** Dates as the database keeps them: experience by month (YYYY-MM-01), certificates by day. */
internal object ProDates {
    fun month(iso: String): String = runCatching { LocalDate.parse(iso.take(10)).let { Str.get(R.string.g5_month_year, it.month.getDisplayName(TextStyle.SHORT, Locale.getDefault()), it.year.toString()) } }.getOrDefault(iso)
    fun expired(iso: String) = runCatching { LocalDate.parse(iso.take(10)).isBefore(LocalDate.now()) }.getOrDefault(false)
    /** "Jun 2021 – Present · 3 yrs 5 mos". */
    fun range(start: String, end: String?): String {
        val s = runCatching { LocalDate.parse(start.take(10)) }.getOrNull() ?: return start
        val e = end?.let { runCatching { LocalDate.parse(it.take(10)) }.getOrNull() }
        val months = ((e ?: LocalDate.now().withDayOfMonth(1)).let { (it.year - s.year) * 12 + (it.monthValue - s.monthValue) } + 1).coerceAtLeast(1)
        val span = listOfNotNull((months / 12).takeIf { it > 0 }?.let { Str.plural(R.plurals.g5_pro_yrs, it) }, (months % 12).takeIf { it > 0 }?.let { Str.plural(R.plurals.g5_pro_mos, it) }).joinToString(" ")
        return Str.get(R.string.g5_date_range_span, month(start), e?.let { month(end!!) } ?: Str.get(R.string.g5_present), span)
    }
}

// ---------------------------------------------------------------- the intro, preferences and visibility

@Composable
internal fun IntroSheet(p: ProProfileRow?, busy: Boolean, onDismiss: () -> Unit, onSave: (JsonObject) -> Unit) {
    var headline by remember { mutableStateOf(p?.headline.orEmpty()) }; var summary by remember { mutableStateOf(p?.summary.orEmpty()) }
    var years by remember { mutableStateOf(p?.years?.toString().orEmpty()) }; var open by remember { mutableStateOf(p?.openTo?.toSet() ?: emptySet()) }
    EditorSheet(stringResource(if (p == null) R.string.g5_pro_your_profile else R.string.g5_pro_intro), busy, onDismiss, canSave = headline.isNotBlank(), onSave = {
        onSave(buildJsonObject { put("headline", headline.trim()); put("summary", summary.trim()); put("years_experience", years.toIntOrNull()?.coerceIn(0, 60))
            put("open_to", buildJsonArray { ProText.OPEN_TO.map { it.first }.filter { it in open }.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } }) })
    }) {
        BucksField(headline, { headline = it.take(120) }, stringResource(R.string.g5_f_headline), stringResource(R.string.g5_f_headline_hint))
        BucksField(summary, { summary = it.take(2000) }, stringResource(R.string.g5_f_about), stringResource(R.string.g5_f_about_hint), Modifier.padding(top = 12.dp), singleLine = false, minLines = 4)
        BucksField(years, { years = it.filter(Char::isDigit).take(2) }, stringResource(R.string.g5_f_years_exp), "6", Modifier.padding(top = 12.dp), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
        Label(stringResource(R.string.g5_open_to)); FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ProText.OPEN_TO.forEach { (k, l) -> FilterChip(k in open, { open = if (k in open) open - k else open + k }, label = { Text(l) }) } }
    }
}

@Composable
internal fun PreferencesSheet(p: ProProfileRow, busy: Boolean, onDismiss: () -> Unit, onSave: (JsonObject) -> Unit) {
    var types by remember { mutableStateOf(p.jobTypes.toSet()) }; var radius by remember { mutableStateOf(p.radiusKm?.toString().orEmpty()) }
    var pay by remember { mutableStateOf(p.expectedPay) }; var avail by remember { mutableStateOf(p.availability) }; var langs by remember { mutableStateOf(p.languages.joinToString(", ")) }
    EditorSheet(stringResource(R.string.g5_sec_prefs), busy, onDismiss, canSave = true, onSave = {
        onSave(buildJsonObject {
            put("job_types", buildJsonArray { ProText.JOB_TYPES.map { it.first }.filter { it in types }.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } })
            put("work_radius_km", radius.toIntOrNull()?.coerceIn(1, 500)); put("expected_pay", pay.trim().take(60)); put("availability", avail.trim().take(60))
            put("languages", buildJsonArray { langs.split(',').map { it.trim().take(30) }.filter { it.isNotEmpty() }.distinctBy { it.lowercase() }.take(10).forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } })
        })
    }) {
        Label(stringResource(R.string.g5_pref_job_types)); FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ProText.JOB_TYPES.forEach { (k, l) -> FilterChip(k in types, { types = if (k in types) types - k else types + k }, label = { Text(l) }) } }
        BucksField(radius, { radius = it.filter(Char::isDigit).take(3) }, stringResource(R.string.g5_f_radius), "15", Modifier.padding(top = 12.dp), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
        BucksField(pay, { pay = it.take(60) }, stringResource(R.string.g5_pref_pay), stringResource(R.string.g5_f_pay_hint, Money.format(25_000), Money.format(600)), Modifier.padding(top = 12.dp))
        BucksField(avail, { avail = it.take(60) }, stringResource(R.string.g5_f_avail), stringResource(R.string.g5_f_avail_hint), Modifier.padding(top = 12.dp))
        BucksField(langs, { langs = it.take(200) }, stringResource(R.string.g5_pref_languages), stringResource(R.string.g5_pref_languages_hint), Modifier.padding(top = 12.dp))
    }
}

@Composable
internal fun VisibilitySheet(p: ProProfileRow, busy: Boolean, onDismiss: () -> Unit, onSave: (JsonObject) -> Unit) {
    var who by remember { mutableStateOf(p.visibility) }; var hidden by remember { mutableStateOf(p.hidden.toSet()) }
    EditorSheet(stringResource(R.string.g5_vis_title), busy, onDismiss, canSave = true, onSave = {
        onSave(buildJsonObject { put("visibility", who); put("hidden_sections", buildJsonArray { hidden.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } }) })
    }) {
        listOf("EVERYONE" to (stringResource(R.string.g5_vis_everyone) to stringResource(R.string.g5_vis_everyone_sub)), "SYNCED" to (stringResource(R.string.g5_vis_synced) to stringResource(R.string.g5_vis_synced_sub)), "ONLY_ME" to (stringResource(R.string.g5_vis_me) to stringResource(R.string.g5_vis_me_sub))).forEach { (k, t) ->
            Row(Modifier.fillMaxWidth().clickable(role = Role.RadioButton) { who = k }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                RadioButton(who == k, { who = k }); Column(Modifier.padding(start = 8.dp)) { Text(t.first, style = MaterialTheme.typography.bodyLarge); Muted(t.second) } } }
        Label(stringResource(R.string.g5_vis_sections)); Muted(stringResource(R.string.g5_vis_cv_private), Modifier.padding(bottom = 6.dp))
        ProText.SECTIONS.forEach { (k, l) -> Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(l, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f)); Switch(k !in hidden, { on -> hidden = if (on) hidden - k else hidden + k }) } }
    }
}

// ---------------------------------------------------------------- one item of a section

@Composable
internal fun ExperienceSheet(x: ProExperience?, busy: Boolean, onDismiss: () -> Unit, onSave: (JsonObject) -> Unit, onDelete: () -> Unit) {
    var title by remember { mutableStateOf(x?.title.orEmpty()) }; var org by remember { mutableStateOf(x?.org.orEmpty()) }; var place by remember { mutableStateOf(x?.location.orEmpty()) }
    var start by remember { mutableStateOf(MonthValue.of(x?.start)) }; var end by remember { mutableStateOf(MonthValue.of(x?.end)) }; var current by remember { mutableStateOf(x != null && x.end == null) }
    var about by remember { mutableStateOf(x?.description.orEmpty()) }
    val endOk = current || (end != null && start != null && end!!.date >= start!!.date)
    EditorSheet(stringResource(if (x == null) R.string.g5_exp_add else R.string.g5_exp_edit), busy, onDismiss, canSave = title.isNotBlank() && start != null && endOk, onDelete = x?.let { onDelete },
        hint = if (start != null && !endOk) stringResource(R.string.g5_exp_end_after) else null, onSave = {
            onSave(buildJsonObject { put("title", title.trim()); put("org", org.trim()); put("location", place.trim()); put("start_month", start!!.iso)
                if (current) put("end_month", JsonNull) else put("end_month", end!!.iso); put("description", about.trim()) })
        }) {
        BucksField(title, { title = it.take(100) }, stringResource(R.string.g5_f_role), stringResource(R.string.g5_f_role_hint))
        BucksField(org, { org = it.take(100) }, stringResource(R.string.g5_f_where), stringResource(R.string.g5_f_where_hint), Modifier.padding(top = 12.dp))
        BucksField(place, { place = it.take(80) }, stringResource(R.string.g5_f_place), stringResource(R.string.g5_f_place_hint), Modifier.padding(top = 12.dp))
        MonthField(stringResource(R.string.g5_started), start, Modifier.padding(top = 12.dp)) { start = it }
        Row(Modifier.fillMaxWidth().padding(top = 8.dp).clickable(role = Role.Checkbox) { current = !current }, verticalAlignment = Alignment.CenterVertically) {
            Checkbox(current, { current = it }); Text(stringResource(R.string.g5_still_work_here), style = MaterialTheme.typography.bodyLarge) }
        if (!current) MonthField(stringResource(R.string.g5_ended), end) { end = it }
        BucksField(about, { about = it.take(1000) }, stringResource(R.string.g5_f_what_did), stringResource(R.string.g5_f_what_did_hint), Modifier.padding(top = 12.dp), singleLine = false, minLines = 3)
    }
}

@Composable
internal fun EducationSheet(x: ProEducation?, busy: Boolean, onDismiss: () -> Unit, onSave: (JsonObject) -> Unit, onDelete: () -> Unit) {
    var course by remember { mutableStateOf(x?.course.orEmpty()) }; var inst by remember { mutableStateOf(x?.institute.orEmpty()) }
    var from by remember { mutableStateOf(x?.startYear?.toString().orEmpty()) }; var to by remember { mutableStateOf(x?.endYear?.toString().orEmpty()) }; var grade by remember { mutableStateOf(x?.grade.orEmpty()) }
    val f = from.toIntOrNull(); val t = to.toIntOrNull()
    val yearsOk = listOfNotNull(f, t).all { it in 1950..2100 } && (f == null || t == null || t >= f)
    EditorSheet(stringResource(if (x == null) R.string.g5_edu_add else R.string.g5_edu_edit), busy, onDismiss, canSave = course.isNotBlank() && yearsOk, onDelete = x?.let { onDelete },
        hint = if (!yearsOk) stringResource(R.string.g5_check_years) else null, onSave = {
            onSave(buildJsonObject { put("course", course.trim()); put("institute", inst.trim()); put("start_year", f); put("end_year", t); put("grade", grade.trim()) })
        }) {
        BucksField(course, { course = it.take(120) }, stringResource(R.string.g5_f_course), stringResource(R.string.g5_f_course_hint))
        BucksField(inst, { inst = it.take(120) }, stringResource(R.string.g5_f_where), stringResource(R.string.g5_f_where_hint2), Modifier.padding(top = 12.dp))
        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            BucksField(from, { from = it.filter(Char::isDigit).take(4) }, stringResource(R.string.g5_f_from_year), "2016", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
            BucksField(to, { to = it.filter(Char::isDigit).take(4) }, stringResource(R.string.g5_f_to_year), "2018", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number)) }
        BucksField(grade, { grade = it.take(40) }, stringResource(R.string.g5_f_grade), stringResource(R.string.g5_f_grade_hint), Modifier.padding(top = 12.dp))
    }
}

@Composable
internal fun SkillSheet(x: ProSkill?, busy: Boolean, onDismiss: () -> Unit, onSave: (JsonObject) -> Unit, onDelete: () -> Unit) {
    var name by remember { mutableStateOf(x?.name.orEmpty()) }; var level by remember { mutableStateOf(x?.level ?: "INTERMEDIATE") }; var years by remember { mutableStateOf(x?.years?.toString().orEmpty()) }
    EditorSheet(stringResource(if (x == null) R.string.g5_skill_add else R.string.g5_skill_edit), busy, onDismiss, canSave = name.isNotBlank(), onDelete = x?.let { onDelete }, onSave = {
        onSave(buildJsonObject { put("name", name.trim()); put("level", level); put("years", years.toIntOrNull()?.coerceIn(0, 60)) })
    }) {
        BucksField(name, { name = it.take(60) }, stringResource(R.string.g5_f_skill), stringResource(R.string.g5_f_skill_hint))
        Label(stringResource(R.string.g5_level)); FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { ProText.LEVELS.forEach { (k, l) -> FilterChip(level == k, { level = k }, label = { Text(l) }) } }
        BucksField(years, { years = it.filter(Char::isDigit).take(2) }, stringResource(R.string.g5_f_years_opt), "4", Modifier.padding(top = 12.dp), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
    }
}

@Composable
internal fun CertificationSheet(x: ProCertification?, busy: Boolean, onDismiss: () -> Unit, onSave: (JsonObject) -> Unit, onDelete: () -> Unit) {
    var name by remember { mutableStateOf(x?.name.orEmpty()) }; var issuer by remember { mutableStateOf(x?.issuer.orEmpty()) }
    var issued by remember { mutableStateOf(MonthValue.of(x?.issuedOn)) }; var expires by remember { mutableStateOf(MonthValue.of(x?.expiresOn)) }; var cid by remember { mutableStateOf(x?.credentialId.orEmpty()) }
    val datesOk = issued == null || expires == null || expires!!.date >= issued!!.date
    EditorSheet(stringResource(if (x == null) R.string.g5_cert_add else R.string.g5_cert_edit), busy, onDismiss, canSave = name.isNotBlank() && datesOk, onDelete = x?.let { onDelete },
        hint = if (!datesOk) stringResource(R.string.g5_cert_dates) else null, onSave = {
            onSave(buildJsonObject { put("name", name.trim()); put("issuer", issuer.trim()); put("issued_on", issued?.iso); put("expires_on", expires?.iso); put("credential_id", cid.trim()) })
        }) {
        BucksField(name, { name = it.take(120) }, stringResource(R.string.g5_f_name), stringResource(R.string.g5_f_name_hint))
        BucksField(issuer, { issuer = it.take(120) }, stringResource(R.string.g5_f_issuer), stringResource(R.string.g5_f_issuer_hint), Modifier.padding(top = 12.dp))
        MonthField(stringResource(R.string.g5_issued_opt), issued, Modifier.padding(top = 12.dp), clearable = true) { issued = it }
        MonthField(stringResource(R.string.g5_valid_till_opt), expires, Modifier.padding(top = 8.dp), clearable = true, futureYears = 20) { expires = it }
        BucksField(cid, { cid = it.take(80) }, stringResource(R.string.g5_f_cert_number), "", Modifier.padding(top = 12.dp))
        Muted(stringResource(R.string.g5_cert_number_note), Modifier.padding(top = 6.dp))
    }
}

// ---------------------------------------------------------------- shared pieces

/** A bottom sheet with a title, the fields, Save and (when editing) Remove. */
@Composable
private fun EditorSheet(title: String, busy: Boolean, onDismiss: () -> Unit, canSave: Boolean, onSave: () -> Unit, onDelete: (() -> Unit)? = null, hint: String? = null, content: @Composable ColumnScope.() -> Unit) {
    var confirm by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.verticalScroll(rememberScrollState()).imePadding().padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 14.dp))
            content()
            hint?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 10.dp)) }
            PrimaryButton(stringResource(if (busy) R.string.g5_saving else R.string.g5_save), Modifier.padding(top = 18.dp), enabled = canSave && !busy, onClick = onSave)
            if (onDelete != null) BadButton(stringResource(R.string.g5_remove), Modifier.padding(top = 4.dp), enabled = !busy) { confirm = true }
        }
    }
    if (confirm && onDelete != null) AlertDialog(onDismissRequest = { confirm = false }, title = { Text(stringResource(R.string.g5_remove_this)) }, text = { Text(stringResource(R.string.g5_remove_this_body)) },
        confirmButton = { TextButton({ confirm = false; onDelete() }) { Text(stringResource(R.string.g5_remove), color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirm = false }) { Text(stringResource(R.string.g5_cancel)) } })
}

/** A month and year, kept as the first of the month. */
internal data class MonthValue(val year: Int, val month: Int) {
    val date: LocalDate get() = LocalDate.of(year, month, 1)
    val iso: String get() = date.toString()
    companion object { fun of(iso: String?): MonthValue? = iso?.let { runCatching { LocalDate.parse(it.take(10)).let { d -> MonthValue(d.year, d.monthValue) } }.getOrNull() } }
}

/** Month and year pickers; [clearable] offers "Not set". Years run from 1960 to this year (+[futureYears]). */
@Composable
private fun MonthField(label: String, value: MonthValue?, modifier: Modifier = Modifier, clearable: Boolean = false, futureYears: Int = 0, onChange: (MonthValue?) -> Unit) {
    val now = LocalDate.now()
    Column(modifier) {
        Label(label)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Picker(value?.let { Month.of(it.month).getDisplayName(TextStyle.FULL, Locale.getDefault()) } ?: stringResource(R.string.g5_month), Modifier.weight(1f),
                (if (clearable) listOf(stringResource(R.string.g5_not_set) to null) else emptyList()) + (1..12).map { Month.of(it).getDisplayName(TextStyle.FULL, Locale.getDefault()) to it }) { m ->
                onChange(m?.let { MonthValue(value?.year ?: now.year, it) }) }
            Picker(value?.year?.toString() ?: stringResource(R.string.g5_year), Modifier.weight(1f),
                (if (clearable) listOf(stringResource(R.string.g5_not_set) to null) else emptyList()) + (now.year + futureYears downTo 1960).map { it.toString() to it }) { y ->
                onChange(y?.let { MonthValue(it, value?.month ?: 1) }) }
        }
    }
}

@Composable
private fun <T> Picker(shown: String, modifier: Modifier, options: List<Pair<String, T?>>, onPick: (T?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        OutlinedButton({ open = true }, Modifier.fillMaxWidth().heightIn(min = 48.dp), shape = MaterialTheme.shapes.small) {
            Text(shown, Modifier.weight(1f)); Icon(Icons.Rounded.ArrowDropDown, null) }
        DropdownMenu(open, { open = false }, Modifier.heightIn(max = 320.dp)) {
            options.forEach { (l, v) -> DropdownMenuItem({ Text(l) }, { open = false; onPick(v) }) } }
    }
}
