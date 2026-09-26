// A placeholder that runs the core end to end (DebugActivity); the real app replaces it.
plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "dev.ember.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "dev.ember.android"
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

dependencies {
    implementation(project(":core"))
}
