package com.bucks.app.ui.screens.jobs

import androidx.compose.foundation.layout.*
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.ui.Jobs
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.ago

/* ---------- bits shared by the jobs screens ---------- */

/** "just now", "5m ago", "3h ago", "yesterday", "on 12 Mar" from an ISO timestamp, to follow a verb ("Posted …", "Applied …"). */
fun timeSince(iso: String): String = when (val a = ago(iso)) { "" -> ""; "now" -> "just now"; "Yesterday" -> "yesterday"; else -> if (a.last() == 'm' || a.last() == 'h') "$a ago" else "on $a" }

/** Application status as a coloured pill. */
@Composable
fun ApplicationStatusPill(status: String) {
    val label = Jobs.statusLabel(status)
    when (status) { "HIRED" -> PillGood(label); "SHORTLISTED" -> PillWarn(label); "REJECTED" -> PillBad(label); "WITHDRAWN" -> PillGrey(label); else -> PillPurple(label) }
}

@Composable fun JobTypePill(type: String) = PillGrey(Jobs.typeLabel(type))

/** Centred spinner with a line under it, for a screen that is still loading. */
@Composable
fun JobsLoading(text: String = "Loading…") = Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    BucksLoader(); Muted(text, Modifier.padding(top = 12.dp))
}

/** One job in a list: title, pay, type pill and a line of details (business, distance, posted time, counts). */
@Composable
fun JobCard(title: String, pay: String, type: String, createdAt: String, details: List<String>, closed: Boolean = false, badge: String? = null, onClick: () -> Unit) {
    BucksCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(pay.ifBlank { "Pay on request" }, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 2.dp))
            }
            Spacer(Modifier.width(10.dp))
            if (closed) PillGrey("Closed") else JobTypePill(type)
        }
        Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Muted((details + "Posted ${timeSince(createdAt)}").filter { it.isNotBlank() }.joinToString(" · "), Modifier.weight(1f), maxLines = 2)
            if (badge != null) { Spacer(Modifier.width(8.dp)); PillPurple(badge) }
        }
    }
}
