package com.bucks.app.ui.social

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Backend
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.Purple
import com.bucks.app.ui.theme.PurpleDeep
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** First screen for someone signed out: the wordmark entrance, what Bucks is for, and the way in. */
@Composable
fun WelcomeScreen(onStart: () -> Unit) {
    val reduced = rememberReducedMotion(); val ctx = LocalContext.current
    val entrance = remember { WordmarkEntrance() }; val settle = remember { Animatable(0f) }; val copy = remember { Animatable(0f) }
    LightSystemBars()
    LaunchedEffect(Unit) {
        if (reduced) { entrance.snapIn(); settle.snapTo(1f); copy.snapTo(1f); return@LaunchedEffect }
        entrance.play()
        settle.animateTo(1f, tween(620, easing = Motion.Emphasized))
        copy.animateTo(1f, tween(460, easing = Motion.Emphasized))
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(Purple).systemBarsPadding()) {
        val lift = with(LocalDensity.current) { (maxHeight * 0.2f).toPx() }
        BucksWordmark(Modifier.align(Alignment.Center).graphicsLayer { translationY = -lift * settle.value; val z = 1f - 0.12f * settle.value; scaleX = z; scaleY = z },
            height = 72.dp, color = Color.White, sheen = { entrance.sheen.value }, pose = entrance::pose)
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 28.dp, vertical = 28.dp)
            .graphicsLayer { alpha = copy.value; translationY = (1f - copy.value) * 48f }) {
            Text("Your people, close by.", style = MaterialTheme.typography.headlineMedium, color = Color.White)
            Spacer(Modifier.height(16.dp))
            WelcomePoint(Icons.Rounded.AutoAwesome, "Share Moments and posts with the people you sync with")
            WelcomePoint(Icons.Rounded.ChatBubble, "Chat one-to-one or in groups")
            WelcomePoint(Icons.Rounded.Shield, "You choose who sees what. Report anything that isn't okay.")
            Spacer(Modifier.height(24.dp))
            Button(onClick = onStart, enabled = copy.value > 0.3f, modifier = Modifier.fillMaxWidth().height(56.dp), shape = MaterialTheme.shapes.large,
                colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = PurpleDeep, disabledContainerColor = Color.White, disabledContentColor = PurpleDeep)) { Text("Get started", style = MaterialTheme.typography.titleMedium) }
            Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                Text("By continuing you agree to the", style = MaterialTheme.typography.bodySmall, color = Color.White.copy(alpha = .8f))
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                TextButton({ Legal.open(ctx, Legal.TERMS) }) { Text("Terms", color = Color.White) }
                TextButton({ Legal.open(ctx, Legal.PRIVACY) }) { Text("Privacy Policy", color = Color.White) }
                TextButton({ Legal.open(ctx, Legal.GUIDELINES) }) { Text("Community Guidelines", color = Color.White) }
            }
        }
    }
}

@Composable
private fun WelcomePoint(icon: ImageVector, text: String) = Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
    Box(Modifier.size(36.dp).clip(CircleShape).background(Color.White.copy(alpha = .16f)), contentAlignment = Alignment.Center) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(20.dp)) }
    Text(text, style = MaterialTheme.typography.bodyLarge, color = Color.White, modifier = Modifier.padding(start = 14.dp))
}

/**
 * Date of birth, asked of everyone right after sign-in. It sets the person's age band on the server (once), which decides the
 * protections that apply to them. The date is never shown on the profile.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgeScreen(vm: BucksViewModel, onDone: (String) -> Unit, onSignOut: () -> Unit) {
    val social = vm.social; val safety = vm.safety
    var date by remember { mutableStateOf<LocalDate?>(null) }; var picking by remember { mutableStateOf(false) }; var confirm by remember { mutableStateOf(false) }
    // Demo builds have no server to ask; a returning person who already gave a date goes straight on.
    LaunchedEffect(Unit) { if (!Backend.enabled) onDone("ADULT") }
    LaunchedEffect(social.me?.id) { if (social.me != null) safety.refresh { safety.state?.takeIf { it.birthDateSet }?.let { st -> onDone(if (st.guardianConsent == false) "TEEN" else "ADULT") } } }
    val fmt = remember { DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG) }
    OnboardingFrame(step = 1, icon = Icons.Rounded.Cake, title = "When's your birthday?",
        body = "We ask everyone. People under 18 get extra privacy and safety settings, and your birthday is never shown on your profile.",
        onSignOut = onSignOut) {
        OutlinedCard(onClick = { picking = true }, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large) {
            Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.CalendarMonth, null, tint = MaterialTheme.colorScheme.primary)
                Column(Modifier.padding(start = 14.dp).weight(1f)) {
                    Text("Date of birth", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(date?.format(fmt) ?: "Choose a date", style = MaterialTheme.typography.titleMedium)
                }
                Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.weight(1f))
        PrimaryButton(when { safety.busy -> "Saving…"; social.me == null -> "Getting ready…"; else -> "Continue" }, Modifier.padding(top = 24.dp), enabled = date != null && social.me != null && !safety.busy) { confirm = true }
    }
    if (picking) {
        val today = LocalDate.now()
        val state = rememberDatePickerState(
            initialSelectedDateMillis = date?.atStartOfDay(ZoneOffset.UTC)?.toInstant()?.toEpochMilli(),
            initialDisplayedMonthMillis = (date ?: today.minusYears(18)).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            yearRange = 1920..today.year,
            selectableDates = object : SelectableDates { override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= System.currentTimeMillis() })
        DatePickerDialog(onDismissRequest = { picking = false },
            confirmButton = { TextButton({ state.selectedDateMillis?.let { date = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }; picking = false }, enabled = state.selectedDateMillis != null) { Text("OK") } },
            dismissButton = { TextButton({ picking = false }) { Text("Cancel") } }) { DatePicker(state, showModeToggle = true) }
    }
    if (confirm) date?.let { d -> AlertDialog(onDismissRequest = { confirm = false },
        title = { Text("Is ${d.format(fmt)} right?") },
        text = { Text("You can't change your date of birth later without contacting support, so please check it.") },
        confirmButton = { TextButton({ confirm = false; safety.setBirthDate(d.toString(), onDone) }) { Text("Yes, that's right") } },
        dismissButton = { TextButton({ confirm = false }) { Text("Change it") } }) }
}

/**
 * Under 18: a parent or guardian agrees before the app opens up (India's DPDP Act). The teen hands the phone over; the parent fills
 * this in. Recorded on the server with the time; verification by OTP to the parent's phone follows in a later release.
 */
@Composable
fun GuardianScreen(vm: BucksViewModel, onDone: () -> Unit, onSignOut: () -> Unit) {
    val safety = vm.safety; val ctx = LocalContext.current
    var name by remember { mutableStateOf("") }; var phone by remember { mutableStateOf("") }; var relation by remember { mutableStateOf("PARENT") }; var agree by remember { mutableStateOf(false) }
    val ok = name.trim().length >= 2 && phone.length == 10 && agree
    OnboardingFrame(step = 2, icon = Icons.Rounded.FamilyRestroom, title = "Ask a parent or guardian",
        body = "Because you're under 18, a parent or guardian needs to agree before you use Bucks. Hand your phone to them for this step.",
        onSignOut = onSignOut, scroll = true) {
        Surface(color = MaterialTheme.colorScheme.surfaceContainer, shape = MaterialTheme.shapes.large, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text("For parents: how Bucks protects teens", style = MaterialTheme.typography.titleSmall)
                TeenRule("Their profile is private, and adults they aren't connected to can't find them in search or suggestions.")
                TeenRule("Only people they've synced with can message them.")
                TeenRule("Their exact location is never stored. Nearby posts use an area of about 2 km.")
                TeenRule("Anyone can report a post, message or account, and our team reviews every report.")
            }
        }
        Spacer(Modifier.height(18.dp))
        BucksField(name, { name = it.take(80) }, "Parent or guardian's full name", "Name")
        Label("Their mobile number")
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField("+91", {}, readOnly = true, modifier = Modifier.width(80.dp), shape = MaterialTheme.shapes.medium)
            Spacer(Modifier.width(10.dp))
            OutlinedTextField(phone, { phone = it.filter(Char::isDigit).take(10) }, placeholder = { Text("98765 43210") }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone))
        }
        Label("You are their")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Chip("Parent", selected = relation == "PARENT") { relation = "PARENT" }; Chip("Legal guardian", selected = relation == "GUARDIAN") { relation = "GUARDIAN" } }
        Row(Modifier.fillMaxWidth().padding(top = 16.dp).clip(MaterialTheme.shapes.small).toggleable(agree, role = Role.Checkbox) { agree = it }.padding(vertical = 6.dp), verticalAlignment = Alignment.Top) {
            Checkbox(checked = agree, onCheckedChange = null)
            Text("I'm this person's parent or legal guardian. I agree to them using Bucks and to Bucks processing their data as the Privacy Policy describes.", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 12.dp))
        }
        TextButton({ Legal.open(ctx, Legal.PRIVACY) }) { Text("Read the Privacy Policy") }
        PrimaryButton(if (safety.busy) "Saving…" else "Agree and continue", Modifier.padding(top = 8.dp), enabled = ok && !safety.busy) { safety.recordConsent(name.trim(), "+91$phone", relation, onDone) }
    }
}

@Composable
private fun TeenRule(text: String) = Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.Top) {
    Icon(Icons.Rounded.CheckCircle, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp).padding(top = 2.dp))
    Text(text, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 10.dp))
}

/** Shared layout for the onboarding steps: progress, a large icon, title and explanation, then the step's content. */
@Composable
private fun OnboardingFrame(step: Int, icon: ImageVector, title: String, body: String, onSignOut: () -> Unit, scroll: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    ContentColumn(Modifier.fillMaxSize().systemBarsPadding().imePadding()) {
        Column(Modifier.fillMaxSize().then(if (scroll) Modifier.verticalScroll(rememberScrollState()) else Modifier).padding(horizontal = 24.dp, vertical = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                // The age check (and a guardian, for minors) is the first of the three sign-up steps; name and area are the other two.
                SetupProgress(1, 3, Modifier.weight(1f))
                TextButton(onSignOut) { Text("Sign out") }
            }
            Box(Modifier.padding(top = 28.dp).size(64.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(32.dp))
            }
            Text(title, style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = 20.dp))
            Text(body, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp, bottom = 24.dp))
            content()
        }
    }
}
