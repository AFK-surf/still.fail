// The Android host of the MoonBit UI prototype: a GLSurfaceView driving
// libmbui.so (the MoonBit app as C, the runtime, and android_host.c),
// built by scripts/android.sh into src/main/jniLibs.
plugins {
    id("com.android.application")
}

android {
    namespace = "dev.mbui"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.mbui.demo"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        // the ABI scripts/android.sh built libmbui.so for (its ABI: arm64-v8a, or x86_64 for an x86 emulator)
        ndk { abiFilters += (System.getenv("MBUI_ABI") ?: "arm64-v8a") }
    }
    // What an app adds (scripts/android.sh's MBUI_ANDROID_HOOK: .so files and assets), which scripts/android.sh puts in
    // out/android/apk (empty for mbui's own apps).
    sourceSets.getByName("main") {
        jniLibs.srcDir("../../out/android/apk/jniLibs")
        assets.srcDir("../../out/android/apk/assets")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// Native views over the canvas (NativeViews.java): the video player is Media3's ExoPlayer, as still.fail's Android
// app's (its version there, apps/android/gradle/libs.versions.toml).
dependencies {
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-datasource:1.8.0")
}
