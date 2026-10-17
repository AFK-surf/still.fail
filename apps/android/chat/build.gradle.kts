// The chats' pages (fail.still.android.screens: home, a chat, its composer, files, previews, history, decisions…),
// built on the settings' (:settings) and :shared (2026-10-17).
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "fail.still.android.chat"
    compileSdk = 36
    lint { ignoreTestSources = true }
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
    implementation(project(":settings"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.browser)
    implementation(libs.commonmark)
    implementation(libs.haze)
    // Videos and songs in a chat (VideoViewer.kt), played as they stream.
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.datasource)
}
