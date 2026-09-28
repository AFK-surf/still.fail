plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// The build's number: -PemberBuild=<n>, or the commits in the history (scripts/release.sh publishes by it). Each
// release is higher than the one before it, so the app sees it as newer (Updates.kt) and Android installs it over.
val emberBuild = providers.gradleProperty("emberBuild")
    .orElse(providers.exec { commandLine("git", "rev-list", "--count", "HEAD"); isIgnoreExitValue = true }.standardOutput.asText.map { it.trim() })
    .get().toIntOrNull() ?: 1

android {
    namespace = "dev.ember.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.ember.android"
        minSdk = 29
        targetSdk = 36
        versionCode = emberBuild
        versionName = "0.1.$emberBuild"
        ndk { abiFilters += "arm64-v8a" }
        // Where the core finds ember cloud: -PemberCloud=http://127.0.0.1:8787 for a dev cloud (adb reverse its ports).
        buildConfigField("String", "CLOUD_ORIGIN", "\"${providers.gradleProperty("emberCloud").getOrElse("https://ember.3720.org")}\"")
    }
    buildTypes {
        // What goes on a phone: optimized (R8), signed with the debug key for now so it installs over a debug build.
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":core"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.browser)
    // Markdown as the web reads it (GFM: tables, strikethrough, autolinks, task lists).
    implementation(libs.commonmark)
    implementation(libs.commonmark.ext.gfm.tables)
    implementation(libs.commonmark.ext.gfm.strikethrough)
    implementation(libs.commonmark.ext.autolink)
    implementation(libs.commonmark.ext.task.list.items)
    // Frosted bars: what scrolls under them shows through, blurred (Android 12+; tinted glass before).
    implementation(libs.haze)
}
