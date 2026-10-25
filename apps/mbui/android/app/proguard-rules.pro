# The release build's R8 (build.gradle.kts). The host's classes stay as they are, names, members and all: libmbui.so
# (src/host/android_host.c, android_core.c) finds them, their methods and their fields by name over JNI, and their
# native methods are bound by name (Java_dev_mbui_…).
-keep class dev.mbui.** { *; }
# Hermes answers String's normalize, localeCompare, toLocale…Case and Intl in Java (AndroidUnicodeUtils, its Intl
# classes), found by name over JNI, as fbjni's own classes are.
-keep class com.facebook.hermes.unicode.** { *; }
-keep class com.facebook.hermes.intl.** { *; }
-keep class com.facebook.jni.** { *; }
-keep class com.facebook.soloader.nativeloader.** { *; }
# Crash reports (Crashes.java) carry the stack as it is: names, files and lines kept, so PostHog can group and show
# them without a mapping file (as still.fail's Android app's proguard-rules.pro).
-dontobfuscate
-keepattributes SourceFile,LineNumberTable
