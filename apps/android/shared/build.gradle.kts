// What the app's pages are built on: the core's data and its calls (fail.still.android.data, with the shapes and
// operations made from the core's), and the design (fail.still.android.ui, with the icons made from design/icons).
// A module of its own so that lint, which reads a module whole on one thread, reads it only when it changes, and the
// app's pages beside it (2026-10-17). Its BuildConfig says what of the app's build it needs.
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

val stillfailBuild = providers.gradleProperty("stillfailBuild")
    .orElse(providers.gradleProperty("emberBuild"))
    .orElse(providers.exec { commandLine("git", "rev-list", "--count", "HEAD"); isIgnoreExitValue = true }.standardOutput.asText.map { it.trim() })
    .get().toIntOrNull() ?: 1
val beta = providers.gradleProperty("stillfailBeta").isPresent

android {
    namespace = "fail.still.android.shared"
    compileSdk = 36
    lint {
        ignoreTestSources = true
        lintConfig = rootProject.file("lint.xml")
    }
    defaultConfig {
        minSdk = 29
        buildConfigField("String", "VERSION_NAME", "\"0.1.$stillfailBuild\"")
        buildConfigField("boolean", "BETA", "$beta")
        // As the app's (app/build.gradle.kts): the name it goes by, where its core finds still.fail cloud.
        buildConfigField("String", "APP_NAME", "\"${if (beta) "youdid.wtf" else "still.fail"}\"")
        val cloud = providers.gradleProperty("stillfailCloud").orElse(providers.gradleProperty("emberCloud")).getOrElse("https://app.still.fail")
        buildConfigField("String", "CLOUD_ORIGIN", "\"$cloud\"")
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    testImplementation(libs.junit)
    implementation(project(":core"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.haze)
    // Signing in in a Custom Tab (screens/SettingParts.kt signIn).
    implementation(libs.androidx.browser)
    // What was played kept on the phone (data/DriveCache.kt): media3's cache and the index it keeps.
    implementation(libs.androidx.media3.datasource)
    implementation(libs.androidx.media3.database)
}
