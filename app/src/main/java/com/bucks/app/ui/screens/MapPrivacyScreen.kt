package com.bucks.app.ui.screens

import com.bucks.app.data.Str
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
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
    fun load() = scope.launch { runCatching { allowed = MapBackend.consent(); posts = MapBackend.myPosts() }.onFailure { vm.toast(Str.get(R.string.g5_map_load_failed)) } }
    fun friendly(e: Throwable) = e.message?.let { m -> Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) } ?: Str.get(R.string.g5_something_wrong)
    LaunchedEffect(Unit) { if (vm.safety.state == null) vm.safety.refresh(); load() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g5_map_title), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            BucksCard {
                Text(stringResource(R.string.g5_map_means_title), style = MaterialTheme.typography.titleSmall)
                listOf(
                    stringResource(R.string.g5_map_b1),
                    stringResource(R.string.g5_map_b2),
                    stringResource(R.string.g5_map_b3),
                    stringResource(R.string.g5_map_b4),
                    stringResource(R.string.g5_map_b5),
                    stringResource(R.string.g5_map_b6),
                ).forEach { Text(stringResource(R.string.g5_bullet, it), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 6.dp)) }
            }
            Spacer(Modifier.height(12.dp))
            when {
                allowed == null -> LinearProgressIndicator(Modifier.fillMaxWidth())
                !adult -> Notice(stringResource(R.string.g5_map_adult_only))
                else -> ToggleRow(stringResource(R.string.g5_map_switch), stringResource(if (allowed == true) R.string.g5_map_switch_on else R.string.g5_map_switch_off), allowed == true) { on ->
                    if (busy) return@ToggleRow; busy = true
                    scope.launch { runCatching { MapBackend.setConsent(on) }.onSuccess { allowed = on; load() }.onFailure { vm.toast(friendly(it)) }; busy = false }
                }
            }
            if (posts.isNotEmpty()) {
                SectionTitle(stringResource(R.string.g5_map_your_posts), Modifier.padding(top = 18.dp, bottom = 4.dp))
                posts.forEach { p ->
                    val status = stringResource(when {
                        p.offBy == "REPORT" -> R.string.g5_map_st_reported
                        p.offBy == "STAFF" -> R.string.g5_map_st_staff
                        p.offBy == "AUTHOR" -> R.string.g5_map_st_author
                        allowed != true -> R.string.g5_map_st_switch_off
                        p.onMap -> R.string.g5_map_st_on
                        else -> R.string.g5_map_st_soon
                    })
                    ToggleRow(p.body.ifBlank { stringResource(R.string.g5_map_media_post) }.take(60) + (p.place?.let { " · $it" } ?: ""), status, p.offBy == null && allowed == true) { on ->
                        if (p.offBy == "REPORT" || p.offBy == "STAFF") { vm.toast(Str.get(R.string.g5_map_cant_restore)); return@ToggleRow }
                        scope.launch { runCatching { MapBackend.setPostOnMap(p.id, on) }.onSuccess { load() }.onFailure { vm.toast(friendly(it)) } }
                    }
                }
            } else if (allowed != null) Muted(stringResource(R.string.g5_map_none), Modifier.padding(top = 12.dp))
        }
    }
}
