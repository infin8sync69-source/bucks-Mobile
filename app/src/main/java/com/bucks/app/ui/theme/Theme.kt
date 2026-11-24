package com.bucks.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.Shapes
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.bucks.app.R

val Purple = Color(0xFF811FF0)   // the logo's purple (branding/, app icon, splash)
val PurpleDeep = Color(0xFF4A0AA6)
val PurpleTint = Color(0xFFEFE6FE)
/** Vivid brand purple from the Home design: wordmark, badges, selected navigation. */
val Brand = Purple
val Ink = Color(0xFF15111C)
val Good = Color(0xFF117A47)
val GoodTint = Color(0xFFE6F4EC)
val Bad = Color(0xFFB42323)
val BadTint = Color(0xFFFBEAEA)
val Warn = Color(0xFF9A6A12)
val WarnTint = Color(0xFFFBF3E2)

/** Good / warn / bad for text and icons, and their tints for pill fills; dark mode gets deep tints with lighter foregrounds. */
@Immutable data class StatusColors(val good: Color, val goodTint: Color, val warn: Color, val warnTint: Color, val bad: Color, val badTint: Color)
private val LightStatus = StatusColors(Good, GoodTint, Warn, WarnTint, Bad, BadTint)
private val DarkStatus = StatusColors(Color(0xFF6FD39B), Color(0xFF12301F), Color(0xFFE8B962), Color(0xFF3A2E12), Color(0xFFF09393), Color(0xFF3A1717))
val LocalStatus = staticCompositionLocalOf { LightStatus }
val MaterialTheme.status: StatusColors @Composable @ReadOnlyComposable get() = LocalStatus.current

/** Manrope variable font; weight is selected through the wght axis. */
@OptIn(ExperimentalTextApi::class)
private fun manrope(weight: FontWeight) = Font(R.font.manrope, weight, variationSettings = FontVariation.Settings(FontVariation.weight(weight.weight)))
val Manrope = FontFamily(manrope(FontWeight.Normal), manrope(FontWeight.Medium), manrope(FontWeight.SemiBold), manrope(FontWeight.Bold), manrope(FontWeight.ExtraBold))

private val Light = lightColorScheme(
    primary = Purple, onPrimary = Color.White, primaryContainer = PurpleTint, onPrimaryContainer = PurpleDeep,
    secondary = Ink, onSecondary = Color.White, secondaryContainer = Color(0xFFEDEAF3), onSecondaryContainer = Ink,
    background = Color(0xFFFAF9FC), onBackground = Ink, surface = Color.White, onSurface = Ink,
    surfaceVariant = Color(0xFFF3F1F7), onSurfaceVariant = Color(0xFF5F586C), outline = Color(0xFFE4E0EB), outlineVariant = Color(0xFFEDEAF1),
    surfaceContainer = Color(0xFFF6F4F9), surfaceContainerHigh = Color(0xFFF0EDF4), surfaceContainerLow = Color(0xFFFBFAFD),
    error = Bad, onError = Color.White, errorContainer = BadTint, onErrorContainer = Bad,
)
private val Dark = darkColorScheme(
    primary = Color(0xFFA874FF), onPrimary = Color(0xFF23074F), primaryContainer = Color(0xFF2A1D45), onPrimaryContainer = Color(0xFFD2B8FF),
    secondary = Color(0xFFEFEBF6), onSecondary = Ink, secondaryContainer = Color(0xFF2A2533), onSecondaryContainer = Color(0xFFEFEBF6),
    background = Color(0xFF0F0C14), onBackground = Color(0xFFEFEBF6), surface = Color(0xFF15111C), onSurface = Color(0xFFEFEBF6),
    surfaceVariant = Color(0xFF1E1926), onSurfaceVariant = Color(0xFFB2ABBF), outline = Color(0xFF2E2838), outlineVariant = Color(0xFF241F2D),
    surfaceContainer = Color(0xFF1B1723), surfaceContainerHigh = Color(0xFF221D2C), surfaceContainerLow = Color(0xFF17131F),
    error = Color(0xFFF09393), onError = Ink, errorContainer = Color(0xFF3A1717), onErrorContainer = Color(0xFFF09393),
)

// The other colour themes. Each keeps the purple theme's lightness steps and swaps the hue: its accent for the primary roles and a faint
// tint of it for the neutrals. Every text pair was checked at 4.5:1 or better in both light and dark (white on primary, primary on
// surface and on its container, onSurfaceVariant on surfaceVariant).
private val SapphireLight = Light.copy(
    primary = Color(0xFF1D4ED8), primaryContainer = Color(0xFFE4ECFE), onPrimaryContainer = Color(0xFF123A9E),
    secondary = Color(0xFF11141C), secondaryContainer = Color(0xFFEAEDF3), onSecondaryContainer = Color(0xFF11141C), background = Color(0xFFF9FAFC), onBackground = Color(0xFF11141C), onSurface = Color(0xFF11141C),
    surfaceVariant = Color(0xFFF1F3F7), onSurfaceVariant = Color(0xFF585E6C), outline = Color(0xFFE0E3EB), outlineVariant = Color(0xFFEAECF1), surfaceContainer = Color(0xFFF4F6F9), surfaceContainerHigh = Color(0xFFEDEFF4), surfaceContainerLow = Color(0xFFFAFBFD),
)
private val SapphireDark = Dark.copy(
    primary = Color(0xFF8FB0FF), onPrimary = Color(0xFF0A2463), primaryContainer = Color(0xFF172A52), onPrimaryContainer = Color(0xFFC3D5FF),
    secondary = Color(0xFFEBEEF6), onSecondary = Color(0xFF11141C), secondaryContainer = Color(0xFF252933), onSecondaryContainer = Color(0xFFEBEEF6), background = Color(0xFF0C0E14), onBackground = Color(0xFFEBEEF6), surface = Color(0xFF11141C), onSurface = Color(0xFFEBEEF6),
    surfaceVariant = Color(0xFF191D26), onSurfaceVariant = Color(0xFFABB1BF), outline = Color(0xFF282D38), outlineVariant = Color(0xFF1F232D), surfaceContainer = Color(0xFF171B23), surfaceContainerHigh = Color(0xFF1D212C), surfaceContainerLow = Color(0xFF13171F), onError = Color(0xFF11141C),
)
private val EmeraldLight = Light.copy(
    primary = Color(0xFF0A7A5A), primaryContainer = Color(0xFFDDF3EA), onPrimaryContainer = Color(0xFF07563F),
    secondary = Color(0xFF121B18), secondaryContainer = Color(0xFFEAF3F0), onSecondaryContainer = Color(0xFF121B18), background = Color(0xFFF9FCFB), onBackground = Color(0xFF121B18), onSurface = Color(0xFF121B18),
    surfaceVariant = Color(0xFFF1F7F5), onSurfaceVariant = Color(0xFF596B65), outline = Color(0xFFE1EAE7), outlineVariant = Color(0xFFEAF1EF), surfaceContainer = Color(0xFFF4F9F7), surfaceContainerHigh = Color(0xFFEDF4F2), surfaceContainerLow = Color(0xFFFAFDFC),
)
private val EmeraldDark = Dark.copy(
    primary = Color(0xFF5FD3A8), onPrimary = Color(0xFF033526), primaryContainer = Color(0xFF123528), onPrimaryContainer = Color(0xFFB4EBD4),
    secondary = Color(0xFFECF5F2), onSecondary = Color(0xFF121B18), secondaryContainer = Color(0xFF26322E), onSecondaryContainer = Color(0xFFECF5F2), background = Color(0xFF0C1411), onBackground = Color(0xFFECF5F2), surface = Color(0xFF121B18), onSurface = Color(0xFFECF5F2),
    surfaceVariant = Color(0xFF1A2521), onSurfaceVariant = Color(0xFFACBEB8), outline = Color(0xFF293732), outlineVariant = Color(0xFF202C28), surfaceContainer = Color(0xFF18221F), surfaceContainerHigh = Color(0xFF1E2B27), surfaceContainerLow = Color(0xFF141E1B), onError = Color(0xFF121B18),
)
private val RubyLight = Light.copy(
    primary = Color(0xFFBE185D), primaryContainer = Color(0xFFFCE4EE), onPrimaryContainer = Color(0xFF8A0F42),
    secondary = Color(0xFF1C1115), secondaryContainer = Color(0xFFF3EAED), onSecondaryContainer = Color(0xFF1C1115), background = Color(0xFFFCF9FA), onBackground = Color(0xFF1C1115), onSurface = Color(0xFF1C1115),
    surfaceVariant = Color(0xFFF7F1F3), onSurfaceVariant = Color(0xFF6C585F), outline = Color(0xFFEBE0E4), outlineVariant = Color(0xFFF1EAEC), surfaceContainer = Color(0xFFF9F4F6), surfaceContainerHigh = Color(0xFFF4EDEF), surfaceContainerLow = Color(0xFFFDFAFB),
)
private val RubyDark = Dark.copy(
    primary = Color(0xFFFF8FB8), onPrimary = Color(0xFF4F0625), primaryContainer = Color(0xFF46182B), onPrimaryContainer = Color(0xFFFFC4D9),
    secondary = Color(0xFFF6EBEF), onSecondary = Color(0xFF1C1115), secondaryContainer = Color(0xFF33252A), onSecondaryContainer = Color(0xFFF6EBEF), background = Color(0xFF140C0F), onBackground = Color(0xFFF6EBEF), surface = Color(0xFF1C1115), onSurface = Color(0xFFF6EBEF),
    surfaceVariant = Color(0xFF26191D), onSurfaceVariant = Color(0xFFBFABB2), outline = Color(0xFF38282D), outlineVariant = Color(0xFF2D1F24), surfaceContainer = Color(0xFF23171B), surfaceContainerHigh = Color(0xFF2C1D22), surfaceContainerLow = Color(0xFF1F1317), onError = Color(0xFF1C1115),
)
private val GraphiteLight = Light.copy(
    primary = Color(0xFF26262C), primaryContainer = Color(0xFFE9E9EC), onPrimaryContainer = Color(0xFF17171B),
    secondary = Color(0xFF151518), secondaryContainer = Color(0xFFEDEDF0), onSecondaryContainer = Color(0xFF151518), background = Color(0xFFFAFAFB), onBackground = Color(0xFF151518), onSurface = Color(0xFF151518),
    surfaceVariant = Color(0xFFF3F3F5), onSurfaceVariant = Color(0xFF606064), outline = Color(0xFFE4E4E7), outlineVariant = Color(0xFFEDEDEE), surfaceContainer = Color(0xFFF6F6F7), surfaceContainerHigh = Color(0xFFF0F0F1), surfaceContainerLow = Color(0xFFFBFBFC),
)
private val GraphiteDark = Dark.copy(
    primary = Color(0xFFD6D6DE), onPrimary = Color(0xFF1A1A1F), primaryContainer = Color(0xFF2B2B32), onPrimaryContainer = Color(0xFFE6E6EC),
    secondary = Color(0xFFEFEFF2), onSecondary = Color(0xFF151518), secondaryContainer = Color(0xFF2A2A2E), onSecondaryContainer = Color(0xFFEFEFF2), background = Color(0xFF0F0F11), onBackground = Color(0xFFEFEFF2), surface = Color(0xFF151518), onSurface = Color(0xFFEFEFF2),
    surfaceVariant = Color(0xFF1E1E21), onSurfaceVariant = Color(0xFFB2B2B7), outline = Color(0xFF2E2E32), outlineVariant = Color(0xFF242428), surfaceContainer = Color(0xFF1C1C1E), surfaceContainerHigh = Color(0xFF232326), surfaceContainerLow = Color(0xFF17171A), onError = Color(0xFF151518),
)

/**
 * The app's colour theme, chosen in Settings > Appearance. PURPLE is the brand and the default; the launch and welcome screens stay
 * purple whatever is chosen here (they are the logo).
 */
enum class Accent(private val light: androidx.compose.material3.ColorScheme, private val dark: androidx.compose.material3.ColorScheme) {
    PURPLE(Light, Dark),
    SAPPHIRE(SapphireLight, SapphireDark),
    EMERALD(EmeraldLight, EmeraldDark),
    RUBY(RubyLight, RubyDark),
    GRAPHITE(GraphiteLight, GraphiteDark);
    fun scheme(isDark: Boolean) = if (isDark) dark else light
}

val BucksType = Typography(
    displaySmall = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.ExtraBold, fontSize = 34.sp, lineHeight = 38.sp, letterSpacing = (-1).sp),
    headlineMedium = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Bold, fontSize = 26.sp, lineHeight = 31.sp, letterSpacing = (-0.6).sp),
    headlineSmall = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Bold, fontSize = 22.sp, lineHeight = 27.sp, letterSpacing = (-0.4).sp),
    titleLarge = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Bold, fontSize = 18.sp, lineHeight = 23.sp, letterSpacing = (-0.2).sp),
    titleMedium = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, lineHeight = 20.sp),
    titleSmall = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, lineHeight = 18.sp),
    bodyLarge = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp),
    labelLarge = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Bold, fontSize = 15.sp),
    labelMedium = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.SemiBold, fontSize = 12.sp),
    labelSmall = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.SemiBold, fontSize = 11.sp),
)

/** three radii: 10 controls and menus, 14 fields and buttons, 20 cards; 28 sheets */
val BucksShapes = Shapes(extraSmall = RoundedCornerShape(10.dp), small = RoundedCornerShape(10.dp), medium = RoundedCornerShape(14.dp), large = RoundedCornerShape(20.dp), extraLarge = RoundedCornerShape(28.dp))

@Composable
fun BucksTheme(dark: Boolean = isSystemInDarkTheme(), textScale: Float = 1f, accent: Accent = Accent.PURPLE, content: @Composable () -> Unit) {
    val d = LocalDensity.current
    CompositionLocalProvider(LocalStatus provides if (dark) DarkStatus else LightStatus, LocalDensity provides Density(d.density, d.fontScale * textScale)) { MaterialTheme(colorScheme = accent.scheme(dark), typography = BucksType, shapes = BucksShapes, content = content) }
}
