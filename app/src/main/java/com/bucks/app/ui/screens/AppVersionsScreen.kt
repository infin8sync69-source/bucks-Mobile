package com.bucks.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.SystemUpdate
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import com.bucks.app.BuildConfig
import com.bucks.app.R
import com.bucks.app.data.AppUpdate
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*

/**
 * App versions (test builds): which build is installed, and every recent build CI has published, of every branch, newest first,
 * with what changed. Any newer build installs with one tap, so a tester can switch to the latest build of any branch. Older builds
 * are listed but can't go on top (Android refuses a downgrade). Play builds update through the Play Store and only show their version.
 */
@Composable
fun AppVersionsScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val u = vm.updates; val ctx = LocalContext.current
    LaunchedEffect(Unit) { u.loadVersions() }
    val current = AppUpdate.currentBuild
    val branch = BuildConfig.BUILD_BRANCH.ifBlank { null }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g1_versions_title), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            BucksCard(Modifier.fillMaxWidth(), tint = true) {
                Text(stringResource(R.string.g1_versions_current, current.toString()), style = MaterialTheme.typography.titleMedium)
                Muted(if (branch != null) stringResource(R.string.g1_versions_name_branch, BuildConfig.VERSION_NAME, branch) else "Bucks ${BuildConfig.VERSION_NAME}")
            }
            if (!AppUpdate.enabled) {
                Muted(stringResource(R.string.g1_versions_play), Modifier.padding(top = 16.dp)); return@Column
            }
            Row(Modifier.padding(top = 20.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Published builds", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                IconButton({ u.loadVersions() }, enabled = !u.checking) { Icon(Icons.Rounded.Refresh, "Check again") }
            }
            val list = u.versions
            when {
                list == null && u.checking -> com.bucks.app.ui.screens.manage.CenteredLoading()
                u.versionsFailed -> Muted("Couldn't reach GitHub. Check your connection and tap the refresh button.")
                list.isNullOrEmpty() -> Muted("No builds are published yet.")
                else -> {
                    val newest = list.first().build
                    // The newest build of each branch is marked, so switching to the latest of a branch is one look.
                    val branchHeads = list.groupBy { it.branch }.mapValues { (_, v) -> v.maxOf { it.build } }
                    list.forEach { r -> VersionRow(r, current, newest = r.build == newest, branchHead = branchHeads[r.branch] == r.build,
                        installing = u.installing == r.build, progress = u.progress, busy = u.progress != null) { u.install(ctx, r) } }
                }
            }
            Muted("Builds come from GitHub Releases. A build only installs over this one when it's newer and signed with the same test key.",
                Modifier.padding(top = 16.dp))
        }
    }
}

@Composable
private fun VersionRow(r: AppUpdate.Release, current: Int, newest: Boolean, branchHead: Boolean, installing: Boolean, progress: Float?, busy: Boolean, onInstall: () -> Unit) {
    BucksCard(Modifier.fillMaxWidth().padding(top = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Build ${r.build}", style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold))
                    if (newest) PillGood("Latest") else if (branchHead) PillGrey("Latest of branch")
                }
                Muted(listOfNotNull(r.branch.ifBlank { null }, r.publishedAt.take(10).ifBlank { null }, r.size.takeIf { it > 0 }?.let { "${it / 1_048_576} MB" }).joinToString(" · "), maxLines = 1)
            }
            when {
                r.build == current -> Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.CheckCircle, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary); Text(" Installed", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary) }
                r.build > current -> FilledTonalButton(onInstall, enabled = !busy) { Icon(Icons.Rounded.SystemUpdate, null, Modifier.size(18.dp)); Text(if (installing) " Downloading…" else " Install") }
                else -> Muted("Older")
            }
        }
        if (installing && progress != null) LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp))
        val notes = r.notes.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.take(3).joinToString("\n")
        if (notes.isNotBlank()) Text(notes, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 4, modifier = Modifier.padding(top = 8.dp))
    }
}
