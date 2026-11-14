# The release build's R8 (apk.json). The host's classes stay as they are, names, members and all: libmbui.so
# (src/host/android_host.c) finds them, their methods and their fields by name over JNI, and their native methods are
# bound by name (Java_dev_mbui_…).
-keep class dev.mbui.** { *; }
-dontobfuscate
-keepattributes SourceFile,LineNumberTable
