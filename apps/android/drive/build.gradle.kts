// A station's drive (fail.still.android.drive: its folders, the reader, the player), built on the chats' pages (:chat:
// a file's preview) and the settings' (:settings) (2026-10-17).
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "fail.still.android.drive"
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
    implementation(project(":chat"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.browser)
    implementation(libs.commonmark)
    implementation(libs.haze)
    // A drive played as it streams (Player.kt): ranged reads through the core, never the whole file first.
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.datasource)
    implementation(libs.androidx.media3.database)
}
