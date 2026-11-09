package com.bucks.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bucks.app.data.MapBackend
import com.bucks.app.data.MyMapPost
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import kotlinx.coroutines.launch

/**
 * Settings > Posts on the map: the one consent for the map, explained item by item, and every post of mine that has a place on it,
 * each with its own switch. Turning the main switch off takes every pin down at once.
 */
@Composable
fun MapPrivacyScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var allowed by remember { mutableStateOf<Boolean?>(null) }; var posts by remember { mutableStateOf<List<MyMapPost>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    val adult = vm.safety.band == "ADULT"
    fun load() = scope.launch { runCatching { allowed = MapBackend.consent(); posts = MapBackend.myPosts() }.onFailure { vm.toast("Couldn't load your map settings. Check your connection.") } }
    fun friendly(e: Throwable) = e.message?.let { m -> Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) } ?: "Something went wrong. Try again."
    LaunchedEffect(Unit) { if (vm.safety.state == null) vm.safety.refresh(); load() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Posts on the map", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            BucksCard {
                Text("What showing on the map means", style = MaterialTheme.typography.titleSmall)
                listOf(
                    "Your public and local posts can appear as part of a place on the Bucks map: the shop or page you tag, or else your locality.",
                    "Never your exact location, and never your name or photo on the map. People see the place and how many recommend it.",
                    "A post tagged to your locality shows 45 minutes after you post it, not right away.",
                    "Anyone signed in to Bucks can see the map. Posts for synced people only never show.",
                    "Turn this off any time: every pin of yours comes down at once. You can also remove single posts below.",
                    "Only for people 18 and over.",
                ).forEach { Text("• $it", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 6.dp)) }
            }
            Spacer(Modifier.height(12.dp))
            when {
                allowed == null -> LinearProgressIndicator(Modifier.fillMaxWidth())
                !adult -> Notice("Posts show on the map only for people 18 and over.")
                else -> ToggleRow("Show my posts on the map", if (allowed == true) "On. Your pins show as places, never as you." else "Off. None of your posts are on the map.", allowed == true) { on ->
                    if (busy) return@ToggleRow; busy = true
                    scope.launch { runCatching { MapBackend.setConsent(on) }.onSuccess { allowed = on; load() }.onFailure { vm.toast(friendly(it)) }; busy = false }
                }
            }
            if (posts.isNotEmpty()) {
                SectionTitle("Your posts with a place", Modifier.padding(top = 18.dp, bottom = 4.dp))
                posts.forEach { p ->
                    val status = when {
                        p.offBy == "REPORT" -> "Off the map: someone reported its location. Bucks is checking."
                        p.offBy == "STAFF" -> "Off the map: taken down by Bucks."
                        p.offBy == "AUTHOR" -> "Off the map: you removed it."
                        allowed != true -> "Not showing: the map switch above is off."
                        p.onMap -> "On the map"
                        else -> "Will show soon"
                    }
                    ToggleRow(p.body.ifBlank { "Photo or video post" }.take(60) + (p.place?.let { " · $it" } ?: ""), status, p.offBy == null && allowed == true) { on ->
                        if (p.offBy == "REPORT" || p.offBy == "STAFF") { vm.toast("Bucks took this one off the map; it can't be put back here."); return@ToggleRow }
                        scope.launch { runCatching { MapBackend.setPostOnMap(p.id, on) }.onSuccess { load() }.onFailure { vm.toast(friendly(it)) } }
                    }
                }
            } else if (allowed != null) Muted("None of your posts has a place on the map yet. Posts get one from a page you tag or the locality you post in.", Modifier.padding(top = 12.dp))
        }
    }
}
