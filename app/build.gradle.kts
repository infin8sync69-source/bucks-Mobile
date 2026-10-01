import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}
// Firebase (phone sign-in, live rides) switches on when app/google-services.json exists; without it the app runs its on-device demo.
if (file("google-services.json").exists()) apply(plugin = "com.google.gms.google-services")

android {
    namespace = "com.bucks.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.bucks.app"
        minSdk = 26
        targetSdk = 36
        // CI passes the GitHub run number, so every test build is newer than the last and installs over it; a local build is 1.
        val buildNumber = System.getenv("BUILD_NUMBER")?.toIntOrNull() ?: 1
        versionCode = buildNumber
        versionName = "0.2.$buildNumber"
        buildConfigField("int", "BUILD_NUMBER", "$buildNumber")
        // Where test builds are published (GitHub Releases "build-N"), and which branch this one came from: the in-app
        // updater only offers newer builds of the same branch.
        buildConfigField("String", "UPDATE_REPO", "\"infin8sync69-source/bucks-Mobile\"")
        buildConfigField("String", "BUILD_BRANCH", "\"${System.getenv("BUILD_BRANCH") ?: ""}\"")
        // Put GEMINI_API_KEY=... in local.properties to enable the cloud intent engine. Without it the app uses the on-device rule engine only.
        val props = Properties().apply { val f = rootProject.file("local.properties"); if (f.exists()) f.inputStream().use { load(it) } }
        buildConfigField("String", "GEMINI_API_KEY", "\"${props.getProperty("GEMINI_API_KEY", "")}\"")
        // Supabase project (see SUPABASE_SETUP.md): from local.properties, or environment variables on CI.
        fun cfg(k: String) = props.getProperty(k) ?: System.getenv(k) ?: ""
        buildConfigField("String", "SUPABASE_URL", "\"${cfg("SUPABASE_URL")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${cfg("SUPABASE_ANON_KEY")}\"")
        // Mapbox public token (pk.*, made to ship inside apps): map tiles, place search and routes. Override with MAPBOX_TOKEN in local.properties or CI; empty falls back to OpenStreetMap servers.
        buildConfigField("String", "MAPBOX_TOKEN", "\"${props.getProperty("MAPBOX_TOKEN") ?: System.getenv("MAPBOX_TOKEN") ?: ""}\"")
    }
    // The pilot key (a CI secret, see scripts/setup-pilot-signing.sh). Every test build must carry the same signature, or Android
    // refuses to install it over the previous one. Without the secret, builds fall back to a throwaway debug key.
    val pilotKeystore = System.getenv("PILOT_KEYSTORE_FILE")?.let { file(it) }?.takeIf { it.exists() }
    signingConfigs {
        if (pilotKeystore != null) create("pilot") {
            storeFile = pilotKeystore; storePassword = System.getenv("PILOT_KEYSTORE_PASSWORD"); keyAlias = "pilot"; keyPassword = System.getenv("PILOT_KEYSTORE_PASSWORD")
        }
    }
    buildTypes {
        debug {
            if (pilotKeystore != null) signingConfig = signingConfigs.getByName("pilot")
            // Test builds update themselves from GitHub Releases (data/AppUpdate.kt). Never in a Play build: Play forbids self-updating.
            buildConfigField("boolean", "SELF_UPDATE", "true")
        }
        release {
            buildConfigField("boolean", "SELF_UPDATE", "false")
            // R8 shrinks and optimises the release build; Compose is several times faster than in a debug build.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.core.splashscreen)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.material3.window)
    implementation(libs.coil.compose)
    implementation(libs.androidx.biometric)
    implementation(libs.androidx.fragment.ktx)
    implementation(libs.play.services.location)
    implementation(libs.play.services.code.scanner)
    implementation(libs.osmdroid)
    implementation(libs.zxing.core)
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.messaging)
    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.postgrest)
    implementation(libs.supabase.realtime)
    implementation(libs.supabase.storage)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.kotlinx.coroutines.play.services)
    debugImplementation(libs.androidx.ui.tooling)
}
