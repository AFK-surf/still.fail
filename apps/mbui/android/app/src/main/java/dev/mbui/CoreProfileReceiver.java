package dev.mbui;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import java.io.File;

/**
 * What the core spends its time on, asked from adb (still.fail's CoreProfileReceiver.kt): only the shell (DUMP) may send it.
 *   adb shell am broadcast -n <app id>/dev.mbui.CoreProfileReceiver --ei seconds 60
 * writes Android/data/<app id>/files/core-<time>.cpuprofile once the time is up (logcat StillFailCore says so).
 */
public final class CoreProfileReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        int seconds = Math.max(1, Math.min(600, intent.getIntExtra("seconds", 60)));
        File dir = context.getExternalFilesDir(null);
        if (dir == null) return;
        try {
            CoreProfile.sample(seconds, new File(dir, "core-" + System.currentTimeMillis() + ".cpuprofile").getPath());
        } catch (Throwable e) {
            // (the core not started yet in this process: its natives not bound)
            Host.log("core profile: " + e);
        }
    }
}
