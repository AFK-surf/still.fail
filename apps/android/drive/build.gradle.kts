// A station's drive (fail.still.android.drive: its folders, the reader, the player), on :shared only, beside :settings
// and :chat (a file opened in the chat's viewer: screens/Elsewhere.kt) (2026-10-18).
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "fail.still.android.drive"
    compileSdk = 36
    lint {
        ignoreTestSources = true
        lintConfig = rootProject.file("lint.xml")
    }
    defaultConfig { minSdk = 29 }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    testImplementation(libs.junit)
    implementation(project(":core"))
    implementation(project(":shared"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.browser)
    implementation(libs.haze)
    // A drive played as it streams (Player.kt): ranged reads through the core, never the whole file first.
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.datasource)
    implementation(libs.androidx.media3.database)
}
