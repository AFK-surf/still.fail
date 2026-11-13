# JZlib 1.1.3

zlib's deflate and inflate in pure Java, by ymnk (JCraft), BSD-style licence (LICENSE, from the project's repository at
its tag 1.1.3: github.com/ymnk/jzlib).

- From: Maven Central, `com.jcraft:jzlib:1.1.3`, its sources jar
  (`https://repo1.maven.org/maven2/com/jcraft/jzlib/1.1.3/jzlib-1.1.3-sources.jar`,
  sha256 `35ebd67941ce7024e6e7d80b60a4252a9687fa0f909a7079ac904bef6c1658cf`, sha1 as Central says
  `3102d5e0e3e6cdb601b42f7bdcbff13167a2226d`).
- Taken: every `.java` file of `com/jcraft/jzlib`, unmodified, in `src/`. Left out: the jar's `META-INF/` (Maven's
  manifest). The inflate and gzip classes stay: ZStream, which the deflater extends, names them, so dropping them
  would mean changing upstream's code; R8 leaves out of the app what it does not reach.
- Why it is here: it is the deflater whose bytes an Android update's delta is checked against
  (`libs/mbui/android/app/src/main/java/dev/mbui/Delta.java`); the same code repacks the release's APK on the
  build machine (`libs/mbui/tools/apk`), so a phone deflating the entries it made comes to the released bytes.
  The system's `java.util.zip.Deflater` differs between Android versions and CPUs. Its version and the parameters
  Delta.java gives it are part of the delta format: a change to either makes every installed app fall back to a
  whole download once.
