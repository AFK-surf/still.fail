import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// The build's number: -PstillfailBuild=<n> (-PemberBuild, the name before the rename, still read), or the commits in
// the history (scripts/release.sh publishes by it). Each release is higher than the one before it, so the app sees it
// as newer (Updates.kt) and Android installs it over.
val stillfailBuild = providers.gradleProperty("stillfailBuild")
    .orElse(providers.gradleProperty("emberBuild"))
    .orElse(providers.exec { commandLine("git", "rev-list", "--count", "HEAD"); isIgnoreExitValue = true }.standardOutput.asText.map { it.trim() })
    .get().toIntOrNull() ?: 1

// Firebase Cloud Messaging (Push.kt), without google-services.json: -PfcmProjectId=… -PfcmAppId=… -PfcmApiKey=…
// -PfcmSenderId=…, or the same keys in apps/android/firebase.properties (not secrets: they are in every APK). Any one
// missing leaves FCM off; notices are still shown while the app is in front.
val firebase = Properties().apply { rootProject.file("firebase.properties").takeIf { it.exists() }?.reader()?.use { load(it) } }
fun fcm(key: String): String = providers.gradleProperty(key).orNull ?: firebase.getProperty(key) ?: ""

android {
    namespace = "fail.still.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "fail.still.android"
        minSdk = 29
        targetSdk = 36
        versionCode = stillfailBuild
        versionName = "0.1.$stillfailBuild"
        ndk { abiFilters += "arm64-v8a" }
        // Where the core finds still.fail cloud: -PstillfailCloud=http://127.0.0.1:8787 for a dev cloud (adb reverse its
        // ports); -PemberCloud (the name before the rename) is still read.
        val cloud = providers.gradleProperty("stillfailCloud").orElse(providers.gradleProperty("emberCloud")).getOrElse("https://app.still.fail")
        buildConfigField("String", "CLOUD_ORIGIN", "\"$cloud\"")
        buildConfigField("String", "FCM_PROJECT_ID", "\"${fcm("fcmProjectId")}\"")
        buildConfigField("String", "FCM_APP_ID", "\"${fcm("fcmAppId")}\"")
        buildConfigField("String", "FCM_API_KEY", "\"${fcm("fcmApiKey")}\"")
        buildConfigField("String", "FCM_SENDER_ID", "\"${fcm("fcmSenderId")}\"")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    // The motion tests (src/androidTest, run by src/androidTest/motion.sh): -PmotionTest builds the app as an app of its
    // own (fail.still.android.motion), so the tests install, run and uninstall it beside the signed-in one, untouched.
    if (providers.gradleProperty("motionTest").isPresent) buildTypes.getByName("debug") { applicationIdSuffix = ".motion" }
    buildTypes {
        // What goes on a phone: optimized (R8), signed with the debug key for now so it installs over a debug build.
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    // An inline visualization's page is the web's: its stylesheet and bridge, from web/src/viz (ui/Viz.kt).
    sourceSets["main"].assets.srcDir(rootProject.file("../../web/src/viz"))
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
    // Pushes while the app is not in front (Push.kt); set up by hand, without the google-services plugin.
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
    // The motion tests: frame by frame on the test clock (src/androidTest).
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.runner)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
