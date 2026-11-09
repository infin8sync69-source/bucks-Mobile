package com.bucks.app.data

import android.content.Context
import android.telephony.TelephonyManager
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import io.michaelrocks.libphonenumber.android.NumberParseException
import io.michaelrocks.libphonenumber.android.PhoneNumberUtil
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/** A language the app is translated into. [tag] is a BCP-47 tag with a matching res/values-* folder. */
data class AppLanguage(val tag: String, val native: String, val english: String)

/**
 * The app's language. Applied with AppCompatDelegate (Android 13+ also shows it in the phone's per-app language settings; below that,
 * AppCompat stores it, see AppLocalesMetadataHolderService in the manifest). Changing it recreates the activity, so every screen
 * redraws in the new language.
 */
object AppLanguages {
    val all = listOf(
        AppLanguage("en", "English", "English"),
        AppLanguage("hi", "हिन्दी", "Hindi"),
        AppLanguage("bn", "বাংলা", "Bengali"),
        AppLanguage("mr", "मराठी", "Marathi"),
        AppLanguage("te", "తెలుగు", "Telugu"),
        AppLanguage("ta", "தமிழ்", "Tamil"),
        AppLanguage("gu", "ગુજરાતી", "Gujarati"),
        AppLanguage("kn", "ಕನ್ನಡ", "Kannada"),
        AppLanguage("ml", "മലയാളം", "Malayalam"),
        AppLanguage("or", "ଓଡ଼ିଆ", "Odia"),
        AppLanguage("pa", "ਪੰਜਾਬੀ", "Punjabi"),
        AppLanguage("as", "অসমীয়া", "Assamese"),
        AppLanguage("ur", "اردو", "Urdu"),
        AppLanguage("es", "Español", "Spanish"),
        AppLanguage("fr", "Français", "French"),
        AppLanguage("pt-BR", "Português", "Portuguese"),
        AppLanguage("de", "Deutsch", "German"),
        AppLanguage("ar", "العربية", "Arabic"),
        AppLanguage("id", "Bahasa Indonesia", "Indonesian"),
        AppLanguage("zh-CN", "简体中文", "Chinese"),
        AppLanguage("ja", "日本語", "Japanese"),
        AppLanguage("ru", "Русский", "Russian"),
    )

    /** The language in use: the one chosen in the app, else the phone's if Bucks has it, else English. */
    fun current(): AppLanguage {
        val chosen = AppCompatDelegate.getApplicationLocales().get(0) ?: LocaleListCompat.getAdjustedDefault().get(0)
        return match(chosen) ?: all.first()
    }
    /** The phone's language when Bucks is translated into it (preselected on the language screen). */
    fun device(): AppLanguage? = match(LocaleListCompat.getAdjustedDefault().get(0))

    private fun match(l: Locale?): AppLanguage? {
        l ?: return null
        val lang = if (l.language == "in") "id" else l.language     // Java's old code for Indonesian
        return all.firstOrNull { it.tag.equals("${lang}-${l.country}", true) } ?: all.firstOrNull { it.tag.substringBefore('-') == lang }
    }

    fun apply(tag: String) = AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(tag))
}

/** A country people can sign up from. Names come from the system in the app's language; numbers from libphonenumber. */
data class Country(val iso: String, val dialCode: Int) {
    val flag: String get() = iso.uppercase().map { Character.toChars(0x1F1E6 + (it - 'A')).concatToString() }.joinToString("")
    fun name(locale: Locale = Locale.getDefault()): String = Locale("", iso).getDisplayCountry(locale).ifBlank { iso }
    val currency: Currency? get() = runCatching { Currency.getInstance(Locale("", iso)) }.getOrNull()
    /** UPI only exists in India; elsewhere payments are cash or the provider's own way. */
    val hasUpi: Boolean get() = iso == "IN"
}

object Countries {
    private lateinit var util: PhoneNumberUtil
    fun init(ctx: Context) { util = PhoneNumberUtil.createInstance(ctx.applicationContext) }

    /** Every region libphonenumber knows, sorted by name in the app's language. */
    fun all(locale: Locale = Locale.getDefault()): List<Country> =
        util.supportedRegions.map { Country(it, util.getCountryCodeForRegion(it)) }.sortedBy { it.name(locale) }

    fun of(iso: String): Country = Country(iso.uppercase(), util.getCountryCodeForRegion(iso.uppercase()).takeIf { it > 0 } ?: 91)

    /** SIM country, then the network's, then the phone's region; India if none is known. Roaming can make SIM and network differ. */
    fun detect(ctx: Context): Country {
        val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        val iso = listOfNotNull(tm?.simCountryIso, tm?.networkCountryIso, Locale.getDefault().country)
            .map { it.uppercase() }.firstOrNull { it.length == 2 && util.getCountryCodeForRegion(it) > 0 } ?: "IN"
        return of(iso)
    }

    /** A sample national number for the hint, e.g. "81234 56789" for India. */
    fun example(c: Country): String = runCatching {
        val n = util.getExampleNumberForType(c.iso, PhoneNumberUtil.PhoneNumberType.MOBILE)
        util.format(n, PhoneNumberUtil.PhoneNumberFormat.NATIONAL).trimStart('0')
    }.getOrDefault("")

    /** E.164 ("+919876543210") when [national] is a valid number for [c], else null. */
    fun e164(c: Country, national: String): String? = try {
        val n = util.parse(national, c.iso)
        if (util.isValidNumberForRegion(n, c.iso)) util.format(n, PhoneNumberUtil.PhoneNumberFormat.E164) else null
    } catch (_: NumberParseException) { null }

    /** "+91 98765 43210" for display. */
    fun pretty(e164: String): String = runCatching { util.format(util.parse(e164, null), PhoneNumberUtil.PhoneNumberFormat.INTERNATIONAL) }.getOrDefault(e164)
}

/** Amounts in the person's country currency, written the way their language writes money (₹1,500 · $15 · 1.500 €). Whole units only. */
object Money {
    var country: Country = Country("IN", 91)
    fun format(amount: Number): String {
        val f = NumberFormat.getCurrencyInstance(Locale.getDefault())
        country.currency?.let { f.currency = it }
        f.maximumFractionDigits = 0; f.minimumFractionDigits = 0
        return f.format(amount)
    }
    val symbol: String get() = country.currency?.getSymbol(Locale.getDefault()) ?: "₹"
}
