package com.bucks.app

import android.content.Intent
import android.os.Bundle
import androidx.fragment.app.FragmentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.bucks.app.data.Push
import com.bucks.app.ui.BucksAppUi
import com.bucks.app.ui.BucksViewModel

class MainActivity : FragmentActivity() {
    override fun onResume() { super.onResume(); com.bucks.app.data.Push.appVisible = true }
    override fun onPause() { com.bucks.app.data.Push.appVisible = false; super.onPause() }

    private val vm: BucksViewModel by viewModels { BucksViewModel.Factory((application as BucksApp).repository) }
    /** Screen a tapped notification asked for ("chat/<id>", "cloud-order/<id>", ...). BucksAppUi opens it once the person is signed in, then clears it. */
    private var startRoute by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()   // purple launch field (Theme.Bucks.Starting), then Theme.Bucks
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Only a fresh launch takes the route from the intent; after a rotation the screen is already where it should be.
        if (savedInstanceState == null) startRoute = Push.routeFrom(intent)
        setContent { BucksAppUi(vm, startRoute = startRoute, onStartRouteHandled = { startRoute = null }) }
    }

    /** A notification tapped while the app is already open (the tap intent carries FLAG_ACTIVITY_SINGLE_TOP). */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Push.routeFrom(intent)?.let { startRoute = it }
    }
}
