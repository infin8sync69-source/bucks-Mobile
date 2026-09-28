package com.bucks.app.ui

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * The validity of a Bucks ID card: a year from when it was issued (profiles.id_issued_at, studio.sql).
 * [renewable] opens in the last 30 days; an [expired] card can't be used by others to sync until it's renewed.
 */
data class BucksIdCardInfo(val issued: LocalDate, val till: LocalDate, val daysLeft: Long) {
    val expired get() = daysLeft < 0
    val renewable get() = daysLeft <= 30
    val validFrom: String get() = issued.format(FMT)
    val validTill: String get() = till.format(FMT)

    companion object {
        private val FMT = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.ENGLISH)
        fun of(iso: String?, today: LocalDate = LocalDate.now()): BucksIdCardInfo? {
            if (iso.isNullOrBlank()) return null
            val issued = runCatching { java.time.OffsetDateTime.parse(iso).toLocalDate() }.getOrNull() ?: runCatching { LocalDate.parse(iso.take(10)) }.getOrNull() ?: return null
            val till = issued.plusYears(1)
            return BucksIdCardInfo(issued, till, ChronoUnit.DAYS.between(today, till))
        }
    }
}
