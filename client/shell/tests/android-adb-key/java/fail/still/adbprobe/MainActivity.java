package fail.still.adbprobe;

import android.app.Activity;
import android.os.Bundle;
import android.system.Os;
import android.system.ErrnoException;
import android.util.Log;
import java.io.File;
import java.nio.file.Files;
import java.util.concurrent.atomic.AtomicBoolean;

public final class MainActivity extends Activity {
    static { System.loadLibrary("adb_key_probe"); }
    private static final AtomicBoolean started = new AtomicBoolean();
    private native int probe();
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (!started.compareAndSet(false, true)) return;
        final String token = getIntent().getStringExtra("token");
        new Thread(() -> {
            try {
                File original = new File(getFilesDir(), "link-original");
                Files.write(original.toPath(), new byte[] {1});
                try {
                    Os.link(original.getAbsolutePath(), new File(getFilesDir(), "link-copy").getAbsolutePath());
                    Log.i("AdbKeyProbe", "hardlink=succeeded");
                } catch (ErrnoException e) {
                    Log.i("AdbKeyProbe", "hardlink errno=" + e.errno + " message=" + e.getMessage());
                }
                int result = probe();
                String detail = new String(Files.readAllBytes(new File(getFilesDir(), "result.txt").toPath()), java.nio.charset.StandardCharsets.UTF_8);
                Log.i("AdbKeyProbe", token + " RESULT " + result + " " + detail);
            } catch (Throwable e) {
                Log.e("AdbKeyProbe", token + " RESULT 2 " + e, e);
            }
            finish();
        }).start();
    }
}
