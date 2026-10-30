package dev.mbui;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * The phone started again, or the app updated: the process started for it, and so (StillfailApp, AdbShare.install)
 * 共享调试 held up again while its switch is on, lent for the chats' grants, Wireless debugging turned on where the app
 * may (AdbShareService), with no one opening the app. Nothing of its own to do.
 */
public final class AdbBoot extends BroadcastReceiver {
    @Override
    public void onReceive(Context c, Intent intent) {
        Host.log("adb share: process started for " + intent.getAction());
    }
}
