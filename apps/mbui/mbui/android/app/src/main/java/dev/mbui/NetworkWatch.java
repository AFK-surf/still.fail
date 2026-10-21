package dev.mbui;

import android.content.Context;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.Network;

/**
 * The default network, followed (as still.fail's MainActivity.kt NetworkWatch): said to the app when it becomes
 * another one than before (Wi-Fi to mobile data, back online after none: src/host/system.mbt `network`). Every
 * connection the app had was on the old one and is dead with nothing said. The first network seen is the one the app
 * started on, so nothing is said of it. Only with ACCESS_NETWORK_STATE in the app's manifest. One for the process, however
 * many activities are alive (MainActivity and OverActivity both, a share sheet over another app while the app is in
 * the background): the first one made starts it, the last one gone stops it, so a change is said once.
 */
final class NetworkWatch extends ConnectivityManager.NetworkCallback {
    private final ConnectivityManager connectivity;
    private Network current;
    private boolean seen;

    private NetworkWatch(ConnectivityManager connectivity) {
        this.connectivity = connectivity;
    }

    /** The process's watch, and how many activities hold it (the main thread's). */
    private static NetworkWatch shared;
    private static int holders;

    /** Held by an activity as it is made: started by the first. */
    static void hold(Context context) {
        if (holders++ == 0) shared = start(context.getApplicationContext());
    }

    /** Let go as an activity is destroyed: stopped with the last. */
    static void release() {
        if (holders == 0 || --holders > 0) return;
        if (shared != null) shared.stop();
        shared = null;
    }

    /** Followed from now on; null when the app may not (no permission) or the system will not (too many callbacks). */
    private static NetworkWatch start(Context context) {
        if (context.checkSelfPermission(android.Manifest.permission.ACCESS_NETWORK_STATE) != PackageManager.PERMISSION_GRANTED) return null;
        ConnectivityManager c = context.getSystemService(ConnectivityManager.class);
        if (c == null) return null;
        NetworkWatch w = new NetworkWatch(c);
        try {
            c.registerDefaultNetworkCallback(w);
        } catch (RuntimeException e) {
            return null;
        }
        return w;
    }

    private void stop() {
        try {
            connectivity.unregisterNetworkCallback(this);
        } catch (RuntimeException e) {
            // never registered, or gone already
        }
    }

    @Override
    public void onAvailable(Network network) {
        boolean changed;
        synchronized (this) {
            changed = seen && !network.equals(current);
            current = network;
            seen = true;
        }
        if (changed) {
            Native.post("system", "{\"network\":true}");
        }
    }

    @Override
    public void onLost(Network network) {
        synchronized (this) {
            if (network.equals(current)) current = null;
        }
    }
}
