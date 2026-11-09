package com.bucks.app.ui.onboarding

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.data.AppLanguages
import com.bucks.app.data.Countries
import com.bucks.app.data.Country
import com.bucks.app.data.Prefs
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.findActivity
import com.bucks.app.ui.social.Legal
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/*
 * Onboarding v2 (research: docs/ONBOARDING.md). Four short screens and no progress bar: Language → Phone → Code → Name → Home.
 * Location is asked on Home (with the Play disclosure), notifications on a later visit; bio, interests and photo wait for Profile.
 */

/** The frame every onboarding screen shares: optional back, a title, one line under it, the content, and one primary action at the bottom. */
@Composable
private fun OnboardingFrame(title: String, hint: String?, onBack: (() -> Unit)?, topEnd: @Composable () -> Unit = {}, bottom: @Composable ColumnScope.() -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().systemBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp).heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
            if (onBack != null) IconButton(onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.cd_back)) } else Spacer(Modifier.width(16.dp))
            BucksWordmark(height = 22.dp, contentDescription = null)
            Spacer(Modifier.weight(1f)); topEnd()
        }
        Column(Modifier.weight(1f).padding(horizontal = Gutter)) {
            Text(title, style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.padding(top = 12.dp))
            if (hint != null) Text(hint, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp, bottom = 20.dp))
            else Spacer(Modifier.height(20.dp))
            content()
        }
        Column(Modifier.padding(horizontal = Gutter, vertical = 16.dp)) { bottom() }
    }
}

/** 1. Language: every language in its own script, the phone's preselected. Tapping one redraws the app in it at once. */
@Composable
fun LanguageScreen(onContinue: () -> Unit) {
    val current = remember { AppLanguages.current() }
    OnboardingFrame(stringResource(R.string.onb_language_title), stringResource(R.string.onb_language_hint), onBack = null,
        bottom = { PrimaryButton(stringResource(R.string.onb_continue)) { Prefs.chooseLanguage(current.tag); onContinue() } }) {
        LazyVerticalGrid(GridCells.Adaptive(150.dp), Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), contentPadding = PaddingValues(bottom = 12.dp)) {
            items(AppLanguages.all, key = { it.tag }) { l ->
                val on = l.tag == current.tag
                Surface(onClick = { if (!on) Prefs.chooseLanguage(l.tag) }, shape = MaterialTheme.shapes.medium,
                    color = if (on) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer,
                    border = if (on) BorderStroke(2.dp, MaterialTheme.colorScheme.primary) else null,
                    modifier = Modifier.heightIn(min = 72.dp).semantics { contentDescription = "${l.native}, ${l.english}" }) {
                    Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(l.native, style = MaterialTheme.typography.titleMedium, maxLines = 1)
                            if (l.native != l.english) Text(l.english, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                        }
                        if (on) Icon(Icons.Rounded.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
    }
}

/** 2. Phone: country (from the SIM) + number, and "I agree to the Terms". One button. */
@Composable
fun PhoneScreen(vm: BucksViewModel, onSent: () -> Unit, onLanguage: () -> Unit, onUseEmail: (() -> Unit)?) {
    val ctx = LocalContext.current
    var iso by rememberSaveable { mutableStateOf(Prefs.countryIso ?: Countries.detect(ctx).iso) }
    val country = remember(iso) { Countries.of(iso) }
    var number by rememberSaveable { mutableStateOf("") }; var adult by rememberSaveable { mutableStateOf(false) }
    var picking by remember { mutableStateOf(false) }; var tried by remember { mutableStateOf(false) }
    val e164 = remember(iso, number) { Countries.e164(country, number) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    if (Prefs.ageBlocked) { BlockedScreen(); return }
    val send = { tried = true; if (e164 != null && adult) { Prefs.countryIso = iso; Prefs.acceptedTerms = Legal.TERMS_VERSION; vm.setPhone(e164); onSent() } }
    OnboardingFrame(stringResource(R.string.onb_phone_title), stringResource(R.string.onb_phone_hint), onBack = null,
        topEnd = { TextButton(onLanguage) { Icon(Icons.Rounded.Language, null, Modifier.size(18.dp)); Text(" " + AppLanguages.current().native) } },
        bottom = {
            Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).toggleable(adult, role = Role.Checkbox) { adult = it }.padding(vertical = 6.dp), verticalAlignment = Alignment.Top) {
                Checkbox(adult, null, Modifier.padding(end = 10.dp))
                Text(stringResource(R.string.onb_agree_terms), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 2.dp))
            }
            Row(Modifier.padding(start = 34.dp)) {
                TextButton({ Legal.open(ctx, Legal.TERMS) }) { Text(stringResource(R.string.onb_terms)) }
                TextButton({ Legal.open(ctx, Legal.PRIVACY) }) { Text(stringResource(R.string.onb_privacy)) }
                TextButton({ Legal.open(ctx, Legal.GUIDELINES) }) { Text(stringResource(R.string.onb_guidelines)) }
            }
            PrimaryButton(stringResource(R.string.onb_get_code), Modifier.padding(top = 8.dp), enabled = e164 != null && adult) { send() }
            if (onUseEmail != null) TextButton(onUseEmail, Modifier.align(Alignment.CenterHorizontally)) { Text(stringResource(R.string.onb_use_email)) }
        }) {
        Row(verticalAlignment = Alignment.Top) {
            val change = stringResource(R.string.onb_country_change, country.name())
            Surface(onClick = { picking = true }, shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainer,
                modifier = Modifier.height(56.dp).semantics { contentDescription = change }) {
                Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(country.flag, style = MaterialTheme.typography.titleLarge); Text(" +${country.dialCode}", style = MaterialTheme.typography.titleMedium)
                    Icon(Icons.Rounded.ArrowDropDown, null)
                }
            }
            Spacer(Modifier.width(10.dp))
            OutlinedTextField(number, { number = it.filter { c -> c.isDigit() || c == ' ' }.take(17) }, Modifier.weight(1f).focusRequester(focus),
                label = { Text(stringResource(R.string.onb_phone_number)) }, placeholder = { Text(Countries.example(country)) }, singleLine = true,
                isError = tried && e164 == null, supportingText = if (tried && e164 == null) ({ Text(stringResource(R.string.onb_phone_invalid)) }) else null,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), shape = MaterialTheme.shapes.medium,
                textStyle = MaterialTheme.typography.titleMedium)
        }
    }
    if (picking) CountrySheet(onPick = { iso = it.iso; picking = false }, onDismiss = { picking = false })
}

/** Searchable list of every country, in the app's language, with flag and dial code. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CountrySheet(onPick: (Country) -> Unit, onDismiss: () -> Unit) {
    val all = remember { Countries.all() }
    var q by remember { mutableStateOf("") }
    val shown = remember(q) { if (q.isBlank()) all else all.filter { it.name().contains(q, true) || "+${it.dialCode}".contains(q.trim()) || it.iso.equals(q.trim(), true) } }
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Text(stringResource(R.string.onb_country_title), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = Gutter))
        OutlinedTextField(q, { q = it }, Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 12.dp), placeholder = { Text(stringResource(R.string.onb_country_search)) },
            leadingIcon = { Icon(Icons.Rounded.Search, null) }, singleLine = true, shape = MaterialTheme.shapes.medium)
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp)) {
            items(shown, key = { it.iso }) { c ->
                Row(Modifier.fillMaxWidth().clickable { onPick(c) }.padding(horizontal = Gutter, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(c.flag, style = MaterialTheme.typography.titleLarge); Text(c.name(), Modifier.weight(1f).padding(horizontal = 14.dp), style = MaterialTheme.typography.bodyLarge)
                    Text("+${c.dialCode}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** 3. Code: one box per digit, verifies on its own when full, resend after 30 s, edit the number. Many phones fill it in themselves. */
@Composable
fun CodeScreen(vm: BucksViewModel, phone: String, onEdit: () -> Unit, onVerified: () -> Unit) {
    val length = if (vm.cloud) 6 else 4
    val activity = LocalContext.current.findActivity()
    var code by rememberSaveable { mutableStateOf("") }; var busy by remember { mutableStateOf(false) }; var wrong by remember { mutableIntStateOf(0) }
    var sent by rememberSaveable { mutableStateOf(false) }; var wait by rememberSaveable { mutableIntStateOf(30) }
    LaunchedEffect(Unit) { if (!sent && activity != null) { sent = true; vm.sendOtp(activity, onSignedIn = onVerified) } }
    LaunchedEffect(wait > 0) { while (wait > 0) { delay(1_000); wait-- } }
    val verify = { if (!busy && code.length == length) { busy = true; vm.verifyOtp(code) { ok -> busy = false; if (ok) onVerified() else { wrong++; code = "" } } } }
    LaunchedEffect(code) { if (code.length == length) verify() }
    val status by vm.otpStatus.collectAsState()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    OnboardingFrame(stringResource(R.string.onb_code_title), null, onBack = onEdit,
        bottom = { PrimaryButton(if (busy) stringResource(R.string.onb_code_checking) else stringResource(R.string.onb_code_verify), enabled = !busy && code.length == length) { verify() } }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.onb_code_sent_to, Countries.pretty(phone)), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onEdit) { Text(stringResource(R.string.onb_code_edit)) }
        }
        val label = stringResource(R.string.onb_code_field)
        BasicTextField(code, { code = it.filter(Char::isDigit).take(length) }, Modifier.padding(top = 16.dp).focusRequester(focus).shakeOn(wrong).semantics { contentDescription = label },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            decorationBox = { _ ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    repeat(length) { i ->
                        val ch = code.getOrNull(i)?.toString() ?: ""; val active = i == code.length
                        Box(Modifier.size(width = 46.dp, height = 56.dp).border(if (active) 2.dp else 1.dp, if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline, MaterialTheme.shapes.medium)
                            .background(MaterialTheme.colorScheme.surface, MaterialTheme.shapes.medium), contentAlignment = Alignment.Center) {
                            Text(ch, style = MaterialTheme.typography.headlineSmall)
                        }
                    }
                }
            })
        if (status.isNotBlank()) Text(status, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 12.dp))
        if (!vm.cloud) Muted(stringResource(R.string.onb_code_demo), Modifier.padding(top = 12.dp))
        Box(Modifier.padding(top = 8.dp)) {
            if (wait > 0) Text(stringResource(R.string.onb_code_resend_in, wait), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 12.dp))
            else TextButton({ wait = 30; if (vm.cloud) activity?.let { vm.sendOtp(it, resend = true, onSignedIn = onVerified) } }) { Text(stringResource(R.string.onb_code_resend)) }
        }
    }
}

/**
 * 4. Name and date of birth, then Home. Bucks is for 18 and over; the date is checked on the server (set_birth_date), and the screen
 * doesn't say where the line is (a neutral age gate). People who signed up before dates of birth only see the birthday part.
 */
@Composable
fun NameScreen(vm: BucksViewModel, onDone: () -> Unit, onBlocked: () -> Unit) {
    val s by vm.state.collectAsState()
    val existing = s.user != null
    var name by rememberSaveable { mutableStateOf(s.user?.name.orEmpty()) }
    var dd by rememberSaveable { mutableStateOf("") }; var mm by rememberSaveable { mutableStateOf("") }; var yyyy by rememberSaveable { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }; var tried by remember { mutableStateOf(false) }; var error by remember { mutableStateOf<String?>(null) }
    val date = remember(dd, mm, yyyy) { runCatching { java.time.LocalDate.of(yyyy.toInt(), mm.toInt(), dd.toInt()) }.getOrNull()?.takeIf { yyyy.length == 4 && it.isBefore(java.time.LocalDate.now()) && it.year >= 1900 } }
    val ready = (existing || name.isNotBlank()) && date != null && !busy
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val done: () -> Unit = done@{
        tried = true; val d = date ?: return@done
        if (!existing && name.isBlank()) return@done
        busy = true; error = null
        scope.launch {
            val r = if (com.bucks.app.data.Backend.enabled) runCatching { com.bucks.app.data.BackendSafety.setBirthDate(d.toString()) } else Result.success("ADULT")
            busy = false
            r.onSuccess { vm.safety.refresh(); if (!existing) vm.createProfile(name.trim(), "", "", home = s.me); onDone() }
                .onFailure { e -> if (e.message?.contains("not eligible") == true) { Prefs.ageBlocked = true; onBlocked() } else error = e.message?.substringAfter("message\":\"")?.substringBefore("\"")?.take(140) ?: "Try again." }
        }
    }
    OnboardingFrame(stringResource(if (existing) R.string.onb_dob_title else R.string.onb_name_title), stringResource(if (existing) R.string.onb_dob_hint else R.string.onb_name_hint), onBack = null,
        bottom = { PrimaryButton(stringResource(R.string.onb_name_cta), enabled = ready) { done() } }) {
        if (!existing) OutlinedTextField(name, { name = it.take(60) }, Modifier.fillMaxWidth().focusRequester(focus), label = { Text(stringResource(R.string.onb_name_label)) },
            singleLine = true, shape = MaterialTheme.shapes.medium, textStyle = MaterialTheme.typography.titleMedium,
            keyboardOptions = KeyboardOptions(capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Words))
        Text(stringResource(R.string.onb_dob_label), style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = if (existing) 0.dp else 20.dp, bottom = 8.dp))
        // Free entry, no default and no picker limited to "allowed" years: the neutral way to ask.
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val num = KeyboardOptions(keyboardType = KeyboardType.Number)
            OutlinedTextField(dd, { dd = it.filter(Char::isDigit).take(2) }, Modifier.width(76.dp).then(if (existing) Modifier.focusRequester(focus) else Modifier), placeholder = { Text(stringResource(R.string.onb_dob_day)) }, singleLine = true, keyboardOptions = num, shape = MaterialTheme.shapes.medium)
            OutlinedTextField(mm, { mm = it.filter(Char::isDigit).take(2) }, Modifier.width(76.dp), placeholder = { Text(stringResource(R.string.onb_dob_month)) }, singleLine = true, keyboardOptions = num, shape = MaterialTheme.shapes.medium)
            OutlinedTextField(yyyy, { yyyy = it.filter(Char::isDigit).take(4) }, Modifier.width(104.dp), placeholder = { Text(stringResource(R.string.onb_dob_year)) }, singleLine = true, keyboardOptions = num, shape = MaterialTheme.shapes.medium)
        }
        if (tried && date == null) Text(stringResource(R.string.onb_dob_invalid), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 8.dp))
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 8.dp)) }
    }
}

/** Shown after a date of birth under 18, and on every later visit from this phone: neutral, no way round it. */
@Composable
fun BlockedScreen() {
    OnboardingFrame(stringResource(R.string.onb_blocked_title), stringResource(R.string.onb_blocked_hint), onBack = null, bottom = {}) {}
}
