package com.bucks.app.ui.screens

import androidx.compose.ui.res.stringResource
import com.bucks.app.R
import com.bucks.app.data.Cloud
import com.bucks.app.data.LatLng
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.findActivity
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.Purple
import com.bucks.app.ui.theme.PurpleDeep

/**
 * Welcome screen for people who are not signed in. The wordmark plays its entrance in the middle of the purple field
 * (letters spring up one after another, a light sweeps across), glides up into place, then the promise and the button
 * rise in. With reduced motion everything is simply there.
 */
@Composable
fun SplashScreen(onStart: () -> Unit) {
    val reduced = rememberReducedMotion()
    val entrance = remember { WordmarkEntrance() }; val settle = remember { Animatable(0f) }; val copy = remember { Animatable(0f) }
    LightSystemBars()
    LaunchedEffect(Unit) {
        if (reduced) { entrance.snapIn(); settle.snapTo(1f); copy.snapTo(1f); return@LaunchedEffect }
        entrance.play()
        settle.animateTo(1f, tween(620, easing = Motion.Emphasized))
        copy.animateTo(1f, tween(460, easing = Motion.Emphasized))
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(Purple).systemBarsPadding()) {
        val lift = with(LocalDensity.current) { (maxHeight * 0.16f).toPx() }
        BucksWordmark(Modifier.align(Alignment.Center).graphicsLayer { translationY = -lift * settle.value; val z = 1f - 0.12f * settle.value; scaleX = z; scaleY = z },
            height = 72.dp, color = Color.White, sheen = { entrance.sheen.value }, pose = entrance::pose)
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 32.dp, vertical = 32.dp)
            .graphicsLayer { alpha = copy.value; translationY = (1f - copy.value) * 48f }, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.g8_splash_promise), style = MaterialTheme.typography.bodyLarge, color = Color.White.copy(alpha = .88f), textAlign = TextAlign.Center, modifier = Modifier.padding(bottom = 32.dp))
            Button(onClick = onStart, enabled = copy.value > 0.3f, modifier = Modifier.fillMaxWidth().height(52.dp), shape = MaterialTheme.shapes.medium, colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = PurpleDeep, disabledContainerColor = Color.White, disabledContentColor = PurpleDeep)) { Text(stringResource(R.string.g8_get_started), style = MaterialTheme.typography.labelLarge) }
        }
    }
}

@Composable
fun PasswordField(value: String, onChange: (String) -> Unit, label: String, placeholder: String = stringResource(R.string.g8_pw_placeholder_min)) {
    var show by remember { mutableStateOf(false) }
    val hideCd = stringResource(R.string.g8_cd_hide_password); val showCd = stringResource(R.string.g8_cd_show_password)
    Column(Modifier.fillMaxWidth().padding(bottom = 14.dp)) { Label(label)
        OutlinedTextField(value, onChange, placeholder = { Text(placeholder) }, singleLine = true, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium, visualTransformation = if (show) VisualTransformation.None else PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            trailingIcon = { IconButton(onClick = { show = !show }) { Icon(if (show) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility, if (show) hideCd else showCd) } }) }
}

/** Sign-in with either a mobile number (OTP) or email + password; links to email sign-up. */
@Composable
fun LoginScreen(vm: BucksViewModel, onSent: () -> Unit, onSignedIn: () -> Unit, onSignUp: () -> Unit, showToast: (String) -> Unit) {
    var mode by remember { mutableStateOf("Mobile number") }
    var phone by remember { mutableStateOf("") }; var email by remember { mutableStateOf("") }; var password by remember { mutableStateOf("") }
    val tenDigits = stringResource(R.string.g8_enter_10_digits); val email0 = email
    val resetSent = stringResource(R.string.g8_reset_link_sent, email0)
    ContentColumn { BucksTopBar()
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) {
            Headline(stringResource(R.string.g8_sign_in))
            // With Firebase on, sign-in is by mobile number only: the email accounts live on this device and can't book real rides.
            Muted(if (vm.cloud) stringResource(R.string.g8_login_sub_cloud) else stringResource(R.string.g8_login_sub_demo), Modifier.padding(top = 8.dp, bottom = 20.dp))
            if (!vm.cloud) Row(Modifier.padding(bottom = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { Chip(stringResource(R.string.g8_mobile_number), selected = mode == "Mobile number") { mode = "Mobile number" }; Chip(stringResource(R.string.g8_email), selected = mode == "Email") { mode = "Email" } }
            if (mode == "Mobile number") {
                Label(stringResource(R.string.g8_mobile_number))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField("+91", {}, readOnly = true, modifier = Modifier.width(80.dp), shape = MaterialTheme.shapes.medium)
                    Spacer(Modifier.width(10.dp))
                    OutlinedTextField(phone, { phone = it.filter { ch -> ch.isDigit() }.take(10) }, placeholder = { Text("98765 43210") }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone))
                }
                PrimaryButton(stringResource(R.string.g8_send_code), Modifier.padding(top = 20.dp)) { if (phone.length < 10) showToast(tenDigits) else { vm.setPhone(phone); onSent() } }
            } else {
                BucksField(email, { email = it }, stringResource(R.string.g8_email), "you@example.com", keyboard = KeyboardOptions(keyboardType = KeyboardType.Email))
                PasswordField(password, { password = it }, stringResource(R.string.g8_password), stringResource(R.string.g8_your_password))
                PrimaryButton(stringResource(R.string.g8_sign_in), Modifier.padding(top = 6.dp)) { if (vm.signInEmail(email, password)) { if (vm.isLoggedIn) onSignedIn() else onSent() } }
                TextButton(onClick = { showToast(resetSent) }, modifier = Modifier.align(Alignment.CenterHorizontally)) { Text(stringResource(R.string.g8_forgot_password)) }
            }
            if (!vm.cloud) Row(Modifier.fillMaxWidth().padding(top = 20.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { Muted(stringResource(R.string.g8_new_to_bucks)); TextButton(onClick = onSignUp) { Text(stringResource(R.string.g8_create_account)) } }
            // Play's UGC policy: people accept the terms before they can post. The links open the published pages (docs/legal).
            val legalCtx = LocalContext.current
            Muted(stringResource(R.string.g8_legal_agree), Modifier.padding(top = 8.dp).fillMaxWidth(), TextAlign.Center)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                TextButton({ com.bucks.app.ui.social.Legal.open(legalCtx, com.bucks.app.ui.social.Legal.TERMS) }) { Text(stringResource(R.string.g8_terms)) }
                TextButton({ com.bucks.app.ui.social.Legal.open(legalCtx, com.bucks.app.ui.social.Legal.GUIDELINES) }) { Text(stringResource(R.string.g8_guidelines)) }
                TextButton({ com.bucks.app.ui.social.Legal.open(legalCtx, com.bucks.app.ui.social.Legal.PRIVACY) }) { Text(stringResource(R.string.g8_privacy)) } }
        }
    }
}

@Composable
fun SignUpEmailScreen(vm: BucksViewModel, onBack: () -> Unit, onCreated: () -> Unit, onUseMobile: () -> Unit) {
    var email by remember { mutableStateOf("") }; var pw by remember { mutableStateOf("") }; var confirm by remember { mutableStateOf("") }
    ContentColumn { BucksTopBar(onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) {
            Headline(stringResource(R.string.g8_create_account))
            Muted(stringResource(R.string.g8_signup_sub), Modifier.padding(top = 8.dp, bottom = 24.dp))
            BucksField(email, { email = it }, stringResource(R.string.g8_email), "you@example.com", keyboard = KeyboardOptions(keyboardType = KeyboardType.Email))
            PasswordField(pw, { pw = it }, stringResource(R.string.g8_password))
            PasswordField(confirm, { confirm = it }, stringResource(R.string.g8_confirm_password), stringResource(R.string.g8_type_again))
            PrimaryButton(stringResource(R.string.g8_continue)) { if (vm.signUpEmail(email, pw, confirm)) onCreated() }
            TextButton(onClick = onUseMobile, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp)) { Text(stringResource(R.string.g8_use_mobile_instead)) }
        }
    }
}

@Composable
fun OtpScreen(vm: BucksViewModel, phone: String, onBack: () -> Unit, onVerified: () -> Unit, showToast: (String) -> Unit) {
    var code by remember { mutableStateOf("") }; var busy by remember { mutableStateOf(false) }; var wrong by remember { mutableIntStateOf(0) }
    val length = if (vm.cloud) 6 else 4
    val activity = LocalContext.current.findActivity()
    // Send the SMS once per visit, not again on rotation.
    var sent by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) { if (!sent && activity != null) { sent = true; vm.sendOtp(activity, onSignedIn = onVerified) } }
    val codeResent = stringResource(R.string.g8_code_resent)
    ContentColumn { BucksTopBar(onBack = onBack)
        Column(Modifier.padding(20.dp)) {
            Headline(stringResource(R.string.g8_enter_code))
            Muted(if (vm.cloud) stringResource(R.string.g8_otp_sent_cloud, length, "+91 $phone") else stringResource(R.string.g8_otp_sent_demo, "+91 $phone"), Modifier.padding(top = 8.dp, bottom = 28.dp))
            OutlinedTextField(code, { code = it.filter { ch -> ch.isDigit() }.take(length) }, modifier = Modifier.fillMaxWidth().shakeOn(wrong), shape = MaterialTheme.shapes.medium, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), textStyle = MaterialTheme.typography.headlineMedium.copy(textAlign = TextAlign.Center, letterSpacing = androidx.compose.ui.unit.TextUnit(8f, androidx.compose.ui.unit.TextUnitType.Sp)))
            PrimaryButton(if (busy) stringResource(R.string.g8_checking) else stringResource(R.string.g8_verify), Modifier.padding(top = 20.dp), enabled = !busy && code.length == length) { busy = true; vm.verifyOtp(code) { ok -> busy = false; if (ok) onVerified() else wrong++ } }
            TextButton(onClick = { if (vm.cloud) activity?.let { vm.sendOtp(it, resend = true, onSignedIn = onVerified) } else showToast(codeResent) }, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp)) { Text(stringResource(R.string.g8_resend_code)) }
            if (vm.cloud) {
                val status by vm.otpStatus.collectAsState()
                if (activity == null) Muted(stringResource(R.string.g8_otp_no_activity), Modifier.padding(top = 12.dp))
                if (status.isNotBlank()) Muted(status, Modifier.padding(top = 12.dp).fillMaxWidth(), TextAlign.Center)
                if (com.bucks.app.BuildConfig.SELF_UPDATE) Muted("Build ${com.bucks.app.BuildConfig.BUILD_NUMBER} · ${Cloud.project ?: "no Firebase"}", Modifier.padding(top = 6.dp).fillMaxWidth(), TextAlign.Center)
            }
        }
    }
}

/** Stored values (saved on the profile as-is); [interestLabel] gives what people read. */
private val INTERESTS = listOf("Food", "Rides", "Home services", "Fitness", "Tech", "Design", "Jobs", "Kids", "Pets", "Shopping", "Events", "Health")
@Composable private fun interestLabel(v: String): String = when (v) {
    "Food" -> stringResource(R.string.g8_interest_food); "Rides" -> stringResource(R.string.g8_interest_rides); "Home services" -> stringResource(R.string.g8_interest_home)
    "Fitness" -> stringResource(R.string.g8_interest_fitness); "Tech" -> stringResource(R.string.g8_interest_tech); "Design" -> stringResource(R.string.g8_interest_design)
    "Jobs" -> stringResource(R.string.g8_interest_jobs); "Kids" -> stringResource(R.string.g8_interest_kids); "Pets" -> stringResource(R.string.g8_interest_pets)
    "Shopping" -> stringResource(R.string.g8_interest_shopping); "Events" -> stringResource(R.string.g8_interest_events); "Health" -> stringResource(R.string.g8_interest_health)
    else -> v }

/** Three-step profile setup, matching Figma's Profile Step 1–3. Editing an existing profile starts on step 1 with values filled in. */
@Composable
fun CreateProfileScreen(vm: BucksViewModel, onDone: () -> Unit, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val u = s.user
    var step by remember { mutableIntStateOf(1) }
    var name by remember { mutableStateOf(u?.name ?: "") }; var bio by remember { mutableStateOf(u?.bio ?: "") }
    // Where you are based: chosen anywhere (current location or a searched place). The point chosen becomes your home, which decides who can recommend you.
    var area by remember { mutableStateOf(u?.area.orEmpty()) }; var homeAt by remember { mutableStateOf<LatLng?>(null) }
    LaunchedEffect(s.hereLabel, s.me) { if (u == null && area.isBlank() && homeAt == null) { val here = s.me; val a = areaOf(s.hereLabel); if (here != null && a != null) { area = a; homeAt = here } } }
    var gender by remember { mutableStateOf(u?.gender ?: "") }; val interests = remember { mutableStateListOf<String>().apply { addAll(u?.interests ?: emptyList()) } }
    val addName = stringResource(R.string.g8_add_name); val chooseBase = stringResource(R.string.g8_choose_base)
    val genders = listOf("Woman", "Man", "Non-binary", "Prefer not to say")
    val genderLabels = listOf(stringResource(R.string.g8_gender_woman), stringResource(R.string.g8_gender_man), stringResource(R.string.g8_gender_nonbinary), stringResource(R.string.g8_gender_no_say))
    val interestLabels = INTERESTS.map { interestLabel(it) }
    ContentColumn { BucksTopBar(onBack = if (step > 1) ({ step -= 1 }) else null)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) {
            // Signing up, this continues the bar the age check started (step 1 of 4); editing, it's just these three.
            if (u == null) SetupProgress(step + 1, 3, Modifier.padding(bottom = 20.dp)) else SetupProgress(step, 3, Modifier.padding(bottom = 20.dp))
            when (step) {
                1 -> {
                    Headline(if (u == null) stringResource(R.string.g8_profile_name_title) else stringResource(R.string.g8_edit_profile)); Muted(stringResource(R.string.g8_profile_name_sub), Modifier.padding(top = 8.dp, bottom = 24.dp))
                    Box(Modifier.fillMaxWidth().padding(bottom = 20.dp), contentAlignment = Alignment.Center) { Avatar(if (name.isBlank()) "?" else initials(name), size = 84) }
                    BucksField(name, { name = it }, stringResource(R.string.g8_full_name), stringResource(R.string.g8_full_name_hint))
                    PrimaryButton(stringResource(R.string.g8_continue)) { if (name.isBlank()) showToast(addName) else step = 2 }
                }
                2 -> {
                    Headline(stringResource(R.string.g8_profile_base_title)); Muted(stringResource(R.string.g8_profile_base_sub), Modifier.padding(top = 8.dp, bottom = 24.dp))
                    LocationPicker(area, s.me, s.hereLabel) { label, at -> area = label; homeAt = at }
                    Spacer(Modifier.height(20.dp)); Label(stringResource(R.string.g8_gender_optional)); ChipRow(genderLabels, genders.indexOf(gender).takeIf { it >= 0 }?.let { genderLabels[it] }) { gender = genders[genderLabels.indexOf(it)] }
                    // Signing up ends here: a line about you and interests can wait for Edit profile (fewer steps before the app).
                    PrimaryButton(if (u == null) stringResource(R.string.g8_finish) else stringResource(R.string.g8_continue), Modifier.padding(top = 24.dp)) {
                        when {
                            area.isBlank() -> showToast(chooseBase)
                            u == null -> { vm.createProfile(name.trim(), area, "", gender, emptyList(), homeAt ?: s.me); onDone() }
                            else -> step = 3
                        }
                    }
                }
                else -> {
                    Headline(stringResource(R.string.g8_profile_about_title)); Muted(stringResource(R.string.g8_profile_about_sub), Modifier.padding(top = 8.dp, bottom = 24.dp))
                    BucksField(bio, { bio = it }, stringResource(R.string.g8_bio_label), stringResource(R.string.g8_bio_hint))
                    Label(stringResource(R.string.g8_interests)); FlowChips(interestLabels, interests.mapNotNull { v -> INTERESTS.indexOf(v).takeIf { it >= 0 }?.let { interestLabels[it] } }.toSet()) { l -> val v = INTERESTS[interestLabels.indexOf(l)]; if (v in interests) interests.remove(v) else interests.add(v) }
                    PrimaryButton(if (u == null) stringResource(R.string.g8_finish) else stringResource(R.string.g8_save_changes), Modifier.padding(top = 24.dp)) { vm.createProfile(name.trim(), area, bio.trim(), gender, interests.toList(), homeAt ?: if (u == null) s.me else null); onDone() }
                }
            }
        }
    }
}
