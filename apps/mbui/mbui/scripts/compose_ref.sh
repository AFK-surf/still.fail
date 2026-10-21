#!/bin/sh
# Compose's own animation arithmetic, run on this machine's JVM from the
# animation-core the ember Android app builds with (gradle's cache): the
# reference values src/motion/motion_test.mbt checks mbui's springs and tweens
# against. Prints them; nothing is written outside out/compose-ref.
set -e
out=out/compose-ref
mkdir -p $out
aar=$(find ~/.gradle/caches/modules-2/files-2.1/androidx.compose.animation/animation-core-android -name 'animation-core.aar' | head -1)
(cd $out && unzip -o -q "$aar" classes.jar && mv -f classes.jar animation-core.jar)
gaar=$(find ~/.gradle/caches/modules-2/files-2.1/androidx.compose.ui/ui-graphics-android -name '*.aar' | sort | tail -1)
(cd $out && unzip -o -q "$gaar" classes.jar && mv -f classes.jar ui-graphics.jar)
uaar=$(find ~/.gradle/caches/modules-2/files-2.1/androidx.compose.ui/ui-util-android -name '*.aar' | sort | tail -1)
if [ -n "$uaar" ]; then (cd $out && unzip -o -q "$uaar" classes.jar && mv -f classes.jar ui-util.jar); else
  ujar=$(find ~/.gradle/caches/modules-2/files-2.1/androidx.compose.ui -name 'ui-util*.jar' | grep -v sources | sort | tail -1); cp "$ujar" $out/ui-util.jar; fi
std=$(find ~/.gradle/caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib -name 'kotlin-stdlib-2*.jar' | grep -v sources | sort | tail -1)
coll=$(find ~/.gradle/caches/modules-2/files-2.1/androidx.collection -name 'collection-jvm-*.jar' | grep -v sources | sort | tail -1)
annot=$(find ~/.gradle/caches/modules-2/files-2.1/androidx.annotation -name 'annotation-jvm-*.jar' | grep -v sources | sort | tail -1)
JAVA=${JAVA_HOME:+$JAVA_HOME/bin/}java
JAVAC=${JAVA_HOME:+$JAVA_HOME/bin/}javac
if ! command -v $JAVAC >/dev/null 2>&1; then
  for j in "/Applications/Android Studio.app/Contents/jbr/Contents/Home" $(/usr/libexec/java_home 2>/dev/null); do
    if [ -x "$j/bin/javac" ]; then JAVA="$j/bin/java"; JAVAC="$j/bin/javac"; break; fi
  done
fi
cp scripts/ComposeRef.java $out/
cp=$out/animation-core.jar:$out/ui-graphics.jar:$out/ui-util.jar:$std:$coll:$annot
"$JAVAC" -cp "$cp" -d $out $out/ComposeRef.java
"$JAVA" -cp "$out:$cp" ComposeRef
