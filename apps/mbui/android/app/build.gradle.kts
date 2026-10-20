// still.fail mbui: still.fail's Android app written in mbui (apps/mbui), an app of its own beside still.fail's
// (fail.still.android, fail.still.android.beta): fail.still.mbui, its debug build fail.still.mbui.debug. Its host is
// mbui's (the Java of the pinned mbui checkout, apps/mbui/mbui: a GLSurfaceView driving libmbui.so) with the still.fail
// core's (CoreHost.java here); libmbui.so (the MoonBit app as C, the runtime, the hosts' C, the core's engine) is built
// by apps/mbui/scripts/android.sh into src/main/jniLibs.
//
// The release build is the beta (apps/mbui/scripts/beta.sh, the pipeline's mbui job): minified, signed as every
// still.fail Android release is, with the debug keystore $ANDROID_USER_HOME holds (CI: ANDROID_DEBUG_KEYSTORE_B64),
// its versionCode the build (ORG_GRADLE_PROJECT_stillfailBuild: git rev-list --count HEAD), versionName 0.1.<build>.
plugins {
    id("com.android.application")
}

val build = providers.gradleProperty("stillfailBuild").orNull?.toInt() ?: 1

android {
    namespace = "dev.mbui"
    compileSdk = 36

    defaultConfig {
        applicationId = "fail.still.mbui"
        minSdk = 29
        targetSdk = 36
        versionCode = build
        versionName = "0.1.$build"
        ndk { abiFilters += "arm64-v8a" }
        manifestPlaceholders["appLabel"] = "still.fail mbui"
        manifestPlaceholders["mbuiEnv"] = ""
        // PostHog's project (docs/telemetry.md → 安卓), where the app's crashes and bar timings go (Crashes.java,
        // BarTiming.java): the file $STILLFAIL_POSTHOG names ({host, key}; CI writes it from POSTHOG_JSON: beta.sh
        // build), as still.fail's Android app reads it. Without one, none are sent.
        val posthog = providers.environmentVariable("STILLFAIL_POSTHOG").orNull?.let { file(it) }?.takeIf { it.exists() }
            ?.let { groovy.json.JsonSlurper().parse(it) as? Map<*, *> }
        buildConfigField("String", "POSTHOG_HOST", "\"${posthog?.get("host") as? String ?: ""}\"")
        buildConfigField("String", "POSTHOG_KEY", "\"${posthog?.get("key") as? String ?: ""}\"")
    }
    buildFeatures { buildConfig = true }
    // mbui's host (its Java and the resources it uses), and the core's parts scripts/android.sh puts in
    // out/android/apk (the engine's and the shell's .so files, the core's bytecode).
    sourceSets.getByName("main") {
        java.srcDir("../../mbui/android/app/src/main/java")
        res.srcDir("../../mbui/android/app/src/main/res")
        jniLibs.srcDir("../../out/android/apk/jniLibs")
        assets.srcDir("../../out/android/apk/assets")
    }
    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "still.fail mbui dev"
        }
        getByName("release") {
            // R8 over the Java (Media3's most of it) and unused resources; the host's classes are kept whole
            // (proguard-rules.pro: the C calls into them by name).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug")
            // its updates: android/mbui/latest.json through still.fail cloud (the core's app.update; src/sfapp/updates.mbt)
            manifestPlaceholders["mbuiEnv"] = "MBUI_UPDATE_FEED=android/mbui"
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// The release's native libraries compressed in the APK (stored, as minSdk 29 has them by default, it was 27 MB; 12.5 MB):
// a download, every build, for phones; installed, they are unpacked once.
androidComponents {
    onVariants(selector().withBuildType("release")) { it.packaging.jniLibs.useLegacyPackaging.set(true) }
}

// Native views over the canvas (mbui's NativeViews.java): the video player is Media3's ExoPlayer, as still.fail's
// Android app's (apps/android/gradle/libs.versions.toml).
dependencies {
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-datasource:1.8.0")
}
