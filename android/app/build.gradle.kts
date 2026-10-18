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
        ndk { abiFilters += "arm64-v8a" }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
