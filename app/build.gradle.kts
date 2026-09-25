import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.bucks.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.bucks.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.2.0"
        // Put GEMINI_API_KEY=... in local.properties to enable the cloud intent engine. Without it the app uses the on-device rule engine only.
        val props = Properties().apply { val f = rootProject.file("local.properties"); if (f.exists()) f.inputStream().use { load(it) } }
        buildConfigField("String", "GEMINI_API_KEY", "\"${props.getProperty("GEMINI_API_KEY", "")}\"")
    }
    buildTypes {
        release {
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
    implementation(libs.osmdroid)
    implementation(libs.zxing.core)
    debugImplementation(libs.androidx.ui.tooling)
}
