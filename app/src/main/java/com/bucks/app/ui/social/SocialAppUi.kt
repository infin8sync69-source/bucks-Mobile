package com.bucks.app.ui.social

import androidx.compose.runtime.staticCompositionLocalOf

// The social-only shell (Home · Discover · Create · Chats · Profile) was retired: the app has one shell, the super-app layout in
// ui/BucksAppUi.kt, which hosts the social screens of this package (onboarding gate, people, Discover, reporting, settings, help).

/** Open someone's profile from anywhere (post author, comment, search result). Provided by BucksAppUi. */
val LocalOpenPerson = staticCompositionLocalOf<(String) -> Unit> { {} }
