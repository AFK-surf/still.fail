package dev.mbui;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.net.Socket;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.LinkedHashMap;
import java.util.List;

/**
 * Wireless debugging's ports on this phone, as it announces them (DNS-SD; still.fail's AdbPorts, AdbShare.kt): adb's
 * (`_adb-tls-connect._tcp`) while it is on and, while the pairing dialog is open, the pairing one
 * (`_adb-tls-pairing._tcp`). Only this phone's own: others' on the same Wi-Fi are announced too. `changed` is told on
 * the main thread each time they change.
 */
final class AdbPorts {
    private final NsdManager nsd;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable changed;
    private final List<NsdManager.DiscoveryListener> listeners = new ArrayList<>();
    /** adb's ports announced, by their service's name (the latest last). An OPPO goes on announcing the one before
     * Wireless debugging was turned off and on again, under its old name, beside the new one under "<name> (2)"
     * (2026-10-18: the latest found was the old one, refused, and the station's adb never reached the phone). */
    private final LinkedHashMap<String, Integer> connect = new LinkedHashMap<>();
    private final LinkedHashMap<String, Integer> pairing = new LinkedHashMap<>();
    /** The older resolver takes one at a time. */
    private boolean resolving;
    private final ArrayDeque<Object[]> queue = new ArrayDeque<>();

    AdbPorts(Context c, Runnable changed) {
        this.nsd = c.getSystemService(NsdManager.class);
        this.changed = changed;
    }

    void start() {
        discover("_adb-tls-connect._tcp", connect);
        discover("_adb-tls-pairing._tcp", pairing);
    }

    void stop() {
        for (NsdManager.DiscoveryListener l : listeners) {
            try {
                nsd.stopServiceDiscovery(l);
            } catch (Exception ignored) {
            }
        }
        listeners.clear();
    }

    /** adb's ports announced, the latest first (main thread). */
    List<Integer> connects() {
        List<Integer> out = new ArrayList<>(connect.values());
        Collections.reverse(out);
        return out;
    }

    /** The pairing port announced (the latest), null while the dialog is closed (main thread). */
    Integer pair() {
        Integer p = null;
        for (Integer v : pairing.values()) p = v;
        return p;
    }

    private void discover(String type, LinkedHashMap<String, Integer> found) {
        // by the service's name: one goes as Wireless debugging (or the dialog) closes, another comes as it opens again
        NsdManager.DiscoveryListener listener = new NsdManager.DiscoveryListener() {
            @Override
            public void onServiceFound(NsdServiceInfo info) {
                resolve(info, port -> main.post(() -> {
                    found.remove(info.getServiceName());
                    found.put(info.getServiceName(), port);
                    changed.run();
                }));
            }

            @Override
            public void onServiceLost(NsdServiceInfo info) {
                main.post(() -> {
                    if (found.remove(info.getServiceName()) != null) changed.run();
                });
            }

            @Override
            public void onDiscoveryStarted(String t) {}

            @Override
            public void onDiscoveryStopped(String t) {}

            @Override
            public void onStartDiscoveryFailed(String t, int code) {}

            @Override
            public void onStopDiscoveryFailed(String t, int code) {}
        };
        listeners.add(listener);
        try {
            nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener);
        } catch (Exception e) {
            Host.log("adb ports: " + e);
        }
    }

    private interface Port {
        void found(int port);
    }

    private void resolve(NsdServiceInfo info, Port done) {
        if (Build.VERSION.SDK_INT >= 34) {
            NsdManager.ServiceInfoCallback callback = new NsdManager.ServiceInfoCallback() {
                @Override
                public void onServiceUpdated(NsdServiceInfo resolved) {
                    if (mine(resolved.getHostAddresses())) done.found(resolved.getPort());
                    try {
                        nsd.unregisterServiceInfoCallback(this);
                    } catch (Exception ignored) {
                    }
                }

                @Override
                public void onServiceInfoCallbackRegistrationFailed(int code) {}

                @Override
                public void onServiceLost() {}

                @Override
                public void onServiceInfoCallbackUnregistered() {}
            };
            try {
                nsd.registerServiceInfoCallback(info, main::post, callback);
            } catch (Exception e) {
                Host.log("adb ports: " + e);
            }
            return;
        }
        main.post(() -> {
            queue.addLast(new Object[] {info, done});
            next();
        });
    }

    @SuppressWarnings("deprecation")
    private void next() {
        if (resolving) return;
        Object[] q = queue.pollFirst();
        if (q == null) return;
        resolving = true;
        Port done = (Port) q[1];
        nsd.resolveService((NsdServiceInfo) q[0], new NsdManager.ResolveListener() {
            @Override
            public void onServiceResolved(NsdServiceInfo resolved) {
                List<InetAddress> hosts = new ArrayList<>();
                if (resolved.getHost() != null) hosts.add(resolved.getHost());
                if (mine(hosts)) done.found(resolved.getPort());
                main.post(() -> {
                    resolving = false;
                    next();
                });
            }

            @Override
            public void onResolveFailed(NsdServiceInfo failed, int code) {
                main.post(() -> {
                    resolving = false;
                    next();
                });
            }
        });
    }

    /** Of adb's ports announced (the latest first), the one adbd listens on: the first that takes a connection here,
     * else the latest (adbd still starting). Off the main thread. */
    static Integer live(List<Integer> connects) {
        for (Integer port : connects) {
            try (Socket s = new Socket()) {
                s.connect(new InetSocketAddress(InetAddress.getLoopbackAddress(), port), 500);
                return port;
            } catch (Exception ignored) {
            }
        }
        return connects.isEmpty() ? null : connects.get(0);
    }

    /** Whether an announced host is this phone. */
    private static boolean mine(List<InetAddress> hosts) {
        List<InetAddress> own = new ArrayList<>();
        try {
            for (Enumeration<NetworkInterface> e = NetworkInterface.getNetworkInterfaces(); e.hasMoreElements(); ) {
                own.addAll(Collections.list(e.nextElement().getInetAddresses()));
            }
        } catch (Exception ignored) {
        }
        for (InetAddress h : hosts) if (own.contains(h)) return true;
        return false;
    }
}
