# The core is reached through JNA (uniffi): its classes and the generated bindings are found by reflection.
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-keep class fail.still.core.** { *; }
-dontwarn java.awt.**
-dontwarn com.sun.jna.**
