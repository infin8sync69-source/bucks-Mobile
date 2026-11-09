package com.bucks.app.ui

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.bucks.app.ui.components.*
import androidx.compose.ui.res.stringResource
import com.bucks.app.R
import com.bucks.app.data.Money

/**
 * The gate every money-moving action passes through. The agent (rules or cloud) can only propose;
 * this sheet is where the person says yes — and, above ₹500 or with a first-time counterparty,
 * proves it's them with BiometricPrompt (fingerprint/face/device PIN).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConfirmationSheet(vm: BucksViewModel, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val p = s.pending ?: return
    val ctx = LocalContext.current
    val speaker = remember { Speaker(ctx) }
    DisposableEffect(Unit) { onDispose { speaker.shutdown() } }
    // "Say confirm" only exists in the demo's assistant; the online build has no voice confirmation to offer.
    val spokenPlain = stringResource(R.string.g6_confirm_spoken, p.title, p.summary)
    val spokenVoice = stringResource(R.string.g6_confirm_spoken_voice, p.title, p.summary)
    val msgNeedLock = stringResource(R.string.g6_confirm_need_lock)
    val bioTitle = stringResource(R.string.g6_confirm_bio_title, Money.format(p.amount))
    LaunchedEffect(p) { speaker.say(if (vm.demoTools) spokenVoice else spokenPlain, s.voiceLang) }
    fun authenticateThenRun() {
        val activity = ctx as? FragmentActivity ?: return
        val can = BiometricManager.from(ctx).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL)
        if (can != BiometricManager.BIOMETRIC_SUCCESS) { showToast(msgNeedLock); return }
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(ctx), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) { vm.confirmPending(p) }
            override fun onAuthenticationError(code: Int, msg: CharSequence) { showToast(com.bucks.app.data.Str.get(R.string.g6_confirm_not_confirmed, msg.toString())) }
        })
        prompt.authenticate(BiometricPrompt.PromptInfo.Builder().setTitle(bioTitle).setSubtitle(p.title).setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL).build())
    }
    ModalBottomSheet(onDismissRequest = { vm.cancelPending() }) {
        Column(Modifier.padding(20.dp).padding(bottom = 28.dp)) {
            Text(p.title, style = MaterialTheme.typography.headlineSmall)
            Muted(p.summary, Modifier.padding(top = 6.dp))
            BucksCard(Modifier.padding(vertical = 16.dp), tint = true) {
                Row(verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Muted(stringResource(R.string.g6_confirm_amount)); Text(Money.format(p.amount), style = MaterialTheme.typography.headlineMedium) }; Column(horizontalAlignment = Alignment.End) { Muted(stringResource(R.string.g6_confirm_with)); Text(p.counterparty, style = MaterialTheme.typography.titleMedium) } }
                // The full badge on its own full-width row under the counterparty name, so it never has to share width with the amount.
                p.counterpartyTrust?.let { Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.End) { TrustBadge(it) } }
            }
            if (p.needsBiometric) Notice(stringResource(R.string.g6_confirm_needs_bio, Money.format(500)), Modifier.padding(bottom = 12.dp))
            PrimaryButton(if (p.needsBiometric) stringResource(R.string.g6_confirm_with_bio) else stringResource(R.string.g6_confirm)) { if (p.needsBiometric) authenticateThenRun() else vm.confirmPending(p) }
            GhostButton(stringResource(R.string.g6_cancel), Modifier.padding(top = 10.dp)) { vm.cancelPending() }
            Muted(stringResource(R.string.g6_confirm_footer), Modifier.padding(top = 12.dp).fillMaxWidth(), align = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}
