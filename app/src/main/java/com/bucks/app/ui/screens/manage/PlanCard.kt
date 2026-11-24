package com.bucks.app.ui.screens.manage

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.data.Backend
import com.bucks.app.data.LicenceRow
import com.bucks.app.data.myLicences
import com.bucks.app.ui.components.BucksCard
import com.bucks.app.ui.components.Muted
import com.bucks.app.ui.components.PillBad
import com.bucks.app.ui.components.PillGood
import com.bucks.app.ui.components.PillGrey
import com.bucks.app.ui.components.PillWarn
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * The owner's licence for one listing or vehicle: code, state and VALID TILL (supabase/migrations/billing.sql, my_licences).
 * Per Google Play's payments policy this never shows a price, a pay button or a payment link; the SMS carries those.
 */

/** My licences, loaded once per [key]; null while loading or when the server has none (billing switched off, or an error). */
@Composable
fun rememberMyLicences(key: Any? = Unit): List<LicenceRow>? {
    var rows by remember { mutableStateOf<List<LicenceRow>?>(null) }
    LaunchedEffect(key) { rows = runCatching { Backend.myLicences() }.getOrNull() }
    return rows
}

private val IST: ZoneId = ZoneId.of("Asia/Kolkata")
private fun parse(iso: String?): OffsetDateTime? = iso?.let { runCatching { OffsetDateTime.parse(it.replace(" ", "T")) }.getOrNull() }

/** "10 Apr 2027" in India time, or "–". */
fun licenceDay(iso: String?): String =
    parse(iso)?.atZoneSameInstant(IST)?.format(DateTimeFormatter.ofPattern("d MMM yyyy", Locale.getDefault())) ?: "–"

/** Whole days until [iso], counted in India dates (0 on the day itself, negative after). */
fun licenceDaysLeft(iso: String?): Long? =
    parse(iso)?.let { ChronoUnit.DAYS.between(java.time.LocalDate.now(IST), it.atZoneSameInstant(IST).toLocalDate()) }

/** "TX7K Q2MP": the code in two groups of four, easier to read out and type. */
fun prettyLicenceCode(code: String): String = if (code.length == 8) code.substring(0, 4) + " " + code.substring(4) else code

@Composable
fun LicencePill(row: LicenceRow) {
    val left = licenceDaysLeft(row.validTill) ?: 0
    when (row.state) {
        "FOUNDING" -> PillGood(stringResource(R.string.lic_pill_founding))
        "TRIAL" -> PillGrey(stringResource(R.string.lic_pill_free))
        "ACTIVE" -> if (left <= 7) PillWarn(stringResource(R.string.lic_pill_renew_soon)) else PillGood(stringResource(R.string.lic_pill_active))
        "GRACE" -> PillWarn(stringResource(R.string.lic_pill_expired_grace))
        "EXPIRED" -> PillBad(stringResource(R.string.lic_pill_paused))
    }
}

/** The licence card; draws nothing when there is no licence for this subject. [vehicle] changes the paused wording. */
@Composable
fun PlanCard(row: LicenceRow?, vehicle: Boolean = false, modifier: Modifier = Modifier) {
    if (row == null) return
    BucksCard(modifier) { PlanStatus(row, vehicle) }
}

/** The licence's status lines without a card, for places that already sit in one (the vehicles list). */
@Composable
fun PlanStatus(row: LicenceRow, vehicle: Boolean = false, modifier: Modifier = Modifier) {
    Column(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.lic_title, row.planLabel), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f, fill = false))
            LicencePill(row)
        }
        Text(stringResource(R.string.lic_code, prettyLicenceCode(row.code)), style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace), modifier = Modifier.padding(top = 6.dp))
        Muted(licenceLine(row, vehicle), Modifier.padding(top = 2.dp))
        if (row.state != "EXPIRED") Muted(pluralStringResource(R.plurals.lic_enquiries_30d, row.enquiries30d, row.enquiries30d), Modifier.padding(top = 2.dp))
    }
}

/** One sentence on where the licence stands and what happens next. */
@Composable
fun licenceLine(row: LicenceRow, vehicle: Boolean): String {
    val left = (licenceDaysLeft(row.validTill) ?: 0).toInt().coerceAtLeast(0)
    return when (row.state) {
        "FOUNDING", "TRIAL" -> stringResource(R.string.lic_free_till, licenceDay(row.validTill))
        "ACTIVE" -> if (left <= 7) pluralStringResource(R.plurals.lic_renew_in_days, left, licenceDay(row.validTill), left)
                    else stringResource(R.string.lic_valid_till, licenceDay(row.validTill))
        "GRACE" -> stringResource(R.string.lic_grace_till, licenceDay(row.graceUntil))
        "EXPIRED" -> stringResource(if (vehicle) R.string.lic_paused_vehicle else R.string.lic_paused_listing)
        else -> ""
    }
}
