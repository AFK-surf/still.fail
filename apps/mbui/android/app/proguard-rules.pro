# The release build's R8 (build.gradle.kts). The host's classes stay as they are, names, members and all: libmbui.so
# (src/host/android_host.c, android_core.c) finds them, their methods and their fields by name over JNI, and their
# native methods are bound by name (Java_dev_mbui_…).
-keep class dev.mbui.** { *; }
# Crash reports (Crashes.java) carry the stack as it is: names, files and lines kept, so PostHog can group and show
# them without a mapping file (as still.fail's Android app's proguard-rules.pro).
-dontobfuscate
-keepattributes SourceFile,LineNumberTable
