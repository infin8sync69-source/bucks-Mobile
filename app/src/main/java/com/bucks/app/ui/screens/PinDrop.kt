package com.bucks.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.bucks.app.data.Backend
import com.bucks.app.data.LatLng
import com.bucks.app.data.MapServices
import com.bucks.app.data.addPlace
import com.bucks.app.ui.components.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * "Can't find it? Drop a pin": move the map under the pin to the place, name it, save. The place is saved for everyone (places.sql:
 * add_place), so the next person searching that name finds it. [start] is where the map opens (the phone, or the last search area);
 * [name] prefills what was searched. [onPick] gets the name and the point.
 */
@Composable
fun PinDropDialog(start: LatLng, name: String, onPick: (String, LatLng) -> Unit, onDismiss: () -> Unit) {
    val cmds = remember { MapCommands() }; val scope = rememberCoroutineScope()
    var center by remember { mutableStateOf(start) }
    var placeName by remember { mutableStateOf(name.trim()) }
    // The area under the pin (from the map, when it knows it) goes with the place, to tell same-named places apart.
    var area by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }; var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { delay(300); cmds.moveTo(start, 16.0) }
    LaunchedEffect(center) { delay(700); area = MapServices.label(center)?.let { areaOf(it) ?: it }.orEmpty().take(60) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().systemBarsPadding().imePadding()) {
                BucksTopBar("Drop a pin", onBack = onDismiss)
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    BucksMap(Modifier.fillMaxSize(), emptyList(), zoom = 16.0, commands = cmds, onCenter = { center = it })
                    // The pin stays in the middle; the map moves under it.
                    Icon(Icons.Rounded.LocationOn, "Pin", Modifier.align(Alignment.Center).offset(y = (-20).dp).size(44.dp), tint = MaterialTheme.colorScheme.primary)
                    MapAttribution(Modifier.align(Alignment.BottomStart).padding(8.dp))
                }
                Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp)) {
                    Muted("Move the map until the pin sits on the place." + (if (area.isNotBlank()) " Near $area." else ""), Modifier.padding(bottom = 8.dp))
                    BucksField(placeName, { placeName = it.take(60); error = null }, "Name of the place", "e.g. Sai Baba Temple, Ward 12")
                    error?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(bottom = 6.dp)) }
                    Muted("Saved on Bucks so neighbours can find it too.", Modifier.padding(bottom = 8.dp))
                    PrimaryButton(if (saving) "Saving…" else "Use this place", enabled = !saving && placeName.trim().length >= 2) {
                        saving = true
                        scope.launch {
                            val n = placeName.trim(); val at = center
                            // Even if saving fails (offline), the pick itself still works for this person.
                            val e = runCatching { Backend.addPlace(n, at, area) }.exceptionOrNull()
                            saving = false
                            val msg = e?.message?.let { m -> Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) }
                            if (msg != null && ("India" in msg || "name" in msg)) error = msg.replaceFirstChar { it.uppercase() } else onPick(n, at)
                        }
                    }
                }
            }
        }
    }
}
