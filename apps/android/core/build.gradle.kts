// The core and its Kotlin API: the core in TypeScript (client/core-ts) run by Hermes (cpp/engine.cpp), its IO in the
// Rust shell (client/shell). build.py puts the shell's .so and the core's bytecode under build/generated; neither is
// committed. The engine is prebuilt too (scripts/native.ts, part engine): build.py puts its .so files beside the shell's
// and says so with -PstillfailPrebuiltEngine; without it, CMake builds it here (how the prebuilt one is made).
plugins {
    alias(libs.plugins.android.library)
}

val prebuiltEngine = providers.gradleProperty("stillfailPrebuiltEngine").isPresent

android {
    namespace = "fail.still.core"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    defaultConfig {
        minSdk = 29
        ndk { abiFilters += "arm64-v8a" }
        if (!prebuiltEngine) externalNativeBuild { cmake { arguments += listOf("-DANDROID_STL=c++_shared") } }
    }
    buildFeatures { prefab = !prebuiltEngine }
    if (!prebuiltEngine) externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt") } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    // StillFailCore logs through android.util.Log, which the JVM tests do not have.
    testOptions { unitTests.isReturnDefaultValues = true }
    sourceSets.getByName("main") {
        jniLibs.srcDir("build/generated/jniLibs")
        assets.srcDir("build/generated/assets")
    }
    // fbjni (Hermes's) brings its own copy of the C++ runtime the NDK puts in too.
    packaging { jniLibs { pickFirsts += listOf("**/libc++_shared.so", "**/libhermes.so") } }
}

dependencies {
    api(libs.kotlinx.coroutines.android)
    api(libs.kotlinx.serialization.json)
    implementation(libs.hermes.android)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
