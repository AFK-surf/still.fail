# The core's engine calls back into its listener by name from JNI (core/src/main/cpp/engine.cpp), and Hermes's
# fbjni finds its classes the same way.
-keep class fail.still.core.** { *; }
-keep class com.facebook.jni.** { *; }
-keep class com.facebook.hermes.** { *; }
-dontwarn com.facebook.**
