// The Rust core (client/ffi) and its Kotlin API. build.py puts the .so and the
// uniffi bindings under build/generated; neither is committed.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "fail.still.core"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    defaultConfig {
        minSdk = 29
        ndk { abiFilters += "arm64-v8a" }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    // StillFailCore logs through android.util.Log, which the JVM tests do not have.
    testOptions { unitTests.isReturnDefaultValues = true }
    sourceSets.getByName("main") {
        kotlin.srcDir("build/generated/uniffi")
        jniLibs.srcDir("build/generated/jniLibs")
    }
}

dependencies {
    api(libs.kotlinx.coroutines.android)
    api(libs.kotlinx.serialization.json)
    implementation("${libs.jna.get()}@aar")
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
