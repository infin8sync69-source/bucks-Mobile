package com.bucks.app.ui

import androidx.annotation.StringRes
import com.bucks.app.R
import com.bucks.app.data.Str
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The delivery time a shop promises its customers, chosen in the listing form (and changed there any time): one preset in
 * details.delivery_time, and an optional preferred time of day in details.delivery_slot ("6 pm to 9 pm"). It is the shop's own
 * promise, shown as "usually": nothing on the server enforces it, and a Bucks delivery agent still has to be free to carry the order.
 * Same keys on iOS (BucksCore/DeliveryTimes.swift).
 */
object DeliveryTimes {
    enum class Option(val key: String, @StringRes val labelRes: Int) {
        MIN_10("10M", R.string.g7_dtime_10m), MIN_30("30M", R.string.g7_dtime_30m), HOUR_1("1H", R.string.g7_dtime_1h),
        HOUR_2("2H", R.string.g7_dtime_2h), SAME_DAY("SAME_DAY", R.string.g7_dtime_same_day), HOUR_24("24H", R.string.g7_dtime_24h),
        DAY_2("2D", R.string.g7_dtime_2d);
        val label: String get() = Str.get(labelRes)
    }
    const val SLOT_MAX = 40

    fun option(key: String?): Option? = Option.entries.firstOrNull { it.key == key }
    private fun JsonObject.text(k: String) = (this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()?.ifBlank { null }
    /** The preset a shop chose, or null (not set, or a key this version doesn't know). */
    fun of(details: JsonObject): Option? = option(details.text("delivery_time"))
    fun slotOf(details: JsonObject): String? = details.text("delivery_slot")?.take(SLOT_MAX)
    /** "Within 30 min · 6 pm to 9 pm", or null when the shop set neither. */
    fun summary(details: JsonObject): String? = listOfNotNull(of(details)?.label, slotOf(details)?.let { Str.get(R.string.g7_dtime_slot_short, it) }).joinToString(" · ").ifBlank { null }
}
