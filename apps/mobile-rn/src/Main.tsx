// The app's root, what the Android app's MainActivity does that is not Android's own plumbing: the first frame drawn
// with the core's prefs (the theme among them), edge to edge with the system's bars in the theme's look, the links the
// app is opened with (still.fail cloud's sign-in coming back, an item's link), being on screen or not (the core woken
// after a while away), the network changing, and every touch for the bar's timing.
import * as Linking from "expo-linking";
import * as NavigationBar from "expo-navigation-bar";
import * as Network from "expo-network";
import { StatusBar } from "expo-status-bar";
import * as SystemUI from "expo-system-ui";
import { Component, useEffect, useRef, useState, type ErrorInfo, type ReactNode } from "react";
import { AppState as SystemAppState, Platform, Text, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { useTopic } from "../../../web/src/core/react.ts";
import { StillFailApp } from "./App";
import { LocalApp, app } from "./AppState";
import { BarTiming } from "./BarTiming";
import { client } from "./core";
import { Auth } from "./data/Calls";
import { Topics } from "./data/Topics";
import { t } from "./i18n";
import { Notifier, showNotices } from "./Notices";
import { Splash } from "./ui/Parts";
import { Dark, Light, useC } from "./ui/Theme";

/**
 * The sign-in callback's schemes: stillfail:// is what the Android app asks for; ember:// (the name before, and what
 * this app asks for: build.ts AUTH_REDIRECT) is still accepted; the beta app's is stillfail-beta://.
 */
const AUTH_SCHEMES = new Set(["stillfail", "ember", "stillfail-beta"]);

/**
 * Since when the app has been off screen (Date.now(): it counts deep sleep too); null while on it. The process's, not a
 * root's: one closed with back and made again later is the same app coming back to the same core.
 */
let hidden: number | null = null;

/** The links already handled (the first one is given again when the root is made anew). */
const handled = new Set<string>();

/**
 * Back on screen after a while in the background, as the web page does on visibilitychange (web/src/core/client.ts
 * connectCore): the core gives up requests that went out before and reconnects links gone quiet
 * (client/core-ts/src/wake.ts), so nothing hangs on a socket the system dropped while away.
 */
function wake() {
  const since = hidden;
  if (since == null) return;
  hidden = null;
  client.wake(Math.max(0, Date.now() - since));
}

/** What the system allows now, to the core: again each time the app comes back (from the system's settings, say). */
function tellPermission() {
  // An older core without it: nothing to tell.
  app.core.call("notify.permission", { state: Notifier.permission(app.notifyAsked) }).catch(() => undefined);
}

/**
 * still.fail cloud's sign-in comes back as ember://auth/callback?… (stillfail://, stillfail-beta:// too), which the core
 * finishes; an item's link (https://app.still.fail/o/<workspace>/<station>/<session>, or the old host ember.3720.org)
 * opens that item; a service's link (`?service=<job>`, from Slack) has the service over it; an invitation's link and a
 * chat's reference link go as links tapped in the app (AppState.openLink). What the link opens is the core's
 * (`link.parse`), including a dev cloud's http origin.
 */
function handle(url: string | null) {
  if (url == null || handled.has(url)) return;
  const parsed = Linking.parse(url);
  const scheme = parsed.scheme?.toLowerCase() ?? "";
  if (scheme === "https" || scheme === "http") {
    handled.add(url);
    app.openLink(url, true, null);
    return;
  }
  if (!AUTH_SCHEMES.has(scheme) || parsed.hostname !== "auth") return;
  handled.add(url);
  const q = url.indexOf("?");
  const query = q < 0 ? "" : url.slice(q + 1).replace(/#.*$/, "");
  Auth.complete(app.core, `?${query}`).then(
    () => app.home(),
    (e: unknown) => { app.toast = t("android-misc.signIn.unfinished", { error: e instanceof Error ? e.message : String(e) }); },
  );
}

/**
 * The default network, followed: told to the core when it becomes another one than before (Wi-Fi to mobile data, back
 * online after none). Every connection the core has was on the old one and is dead with nothing said; iroh cannot see
 * this on Android itself (client/core-ts/src/wake.ts, mesh.ts `watch`). The first network seen is the one the core
 * started on, so nothing is said of it.
 */
function watchNetwork(changed: () => void): () => void {
  // NATIVE: the default network itself (ConnectivityManager's Network, registerDefaultNetworkCallback): expo-network
  // says only its type and whether it is up, so another network is a new type, or one up again after none.
  let current: string | null = null;
  let seen = false;
  const heard = (s: Network.NetworkState) => {
    const now = s.isConnected === false ? null : String(s.type ?? "unknown");
    const before = current;
    const wasSeen = seen;
    if (now != null) { current = now; seen = true; }
    else current = null;
    if (now != null && wasSeen && before !== now) changed();
  };
  Network.getNetworkStateAsync().then(heard, () => undefined);
  const sub = Network.addNetworkStateListener(heard);
  return () => sub.remove();
}

export function Main() {
  // Started once: what the bar's switches are timed by, and the app following the core (its prefs, what is under way,
  // its notifications' settings).
  useState(() => {
    BarTiming.start();
    app.start();
    return true;
  });
  const C = useC();
  const dark = C.dark;
  // The prefs are the core's: the first frame is drawn with them (the theme among them), not with defaults first.
  const prefs = useTopic<unknown>(Topics.prefs);
  const ready = !prefs.loading;

  // Edge to edge from the first frame (app.json edgeToEdgeEnabled); the system's bars in the theme's look, and the
  // window's own ground following it (the system's theme changes without the app made again).
  useEffect(() => {
    if (Platform.OS === "android") NavigationBar.setStyle(dark ? "light" : "dark");
    SystemUI.setBackgroundColorAsync((dark ? Dark : Light).bg).catch(() => undefined);
  }, [dark]);

  // The core's `notices`, shown while the app is in front (Notices); the pushes are shown the rest of the time.
  const notices = useRef<(() => void) | null>(null);
  const listen = () => {
    if (notices.current == null && Notifier.inFront) notices.current = showNotices(app);
  };

  // On screen and off (onStart and onStop): the app in front; back after a while, the core woken.
  useEffect(() => {
    const started = () => {
      // NATIVE: Wi-Fi's multicast lock while on screen (WifiManager.MulticastLock "stillfail-mdns"): Android drops the
      // multicast that reaches the phone unless an app holds it, and the core's mDNS would never hear a station answer.
      Notifier.inFront = true;
      app.inFront = true;
      listen();
      void app.checkUpdates();
      tellPermission();
      wake();
    };
    const stopped = () => {
      Notifier.inFront = false;
      app.inFront = false;
      notices.current?.();
      notices.current = null;
      if (hidden == null) hidden = Date.now();
    };
    if (SystemAppState.currentState !== "background") started();
    const sub = SystemAppState.addEventListener("change", (state) => {
      if (state === "active") started();
      else if (state === "background") stopped();
    });
    // Back to a root made anew (the last one closed with back, the process kept): as back on screen.
    wake();
    // The links the app was opened with, and those that come while it runs.
    Linking.getInitialURL().then(handle, () => undefined);
    const links = Linking.addEventListener("url", (e) => handle(e.url));
    const network = watchNetwork(() => client.networkChanged());
    return () => { sub.remove(); links.remove(); network(); stopped(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: C.bg }}>
      <SafeAreaProvider>
        <StatusBar style={dark ? "light" : "dark"} translucent backgroundColor="transparent" />
        {/* Every touch of the app: the last finger lifted is where a switch from the bar begins (BarTiming). */}
        <View style={{ flex: 1 }} onTouchEndCapture={() => BarTiming.touched()}>
          {/* The app's state made in a moment: the same buddy as the app starting (App.tsx), so startup is one picture. */}
          {!ready ? <Splash /> : <Failing><LocalApp.Provider value={app}><StillFailApp app={app} /></LocalApp.Provider></Failing>}
        </View>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

/**
 * What a page throwing as it draws leaves: its error and where, to the log (its stack, which `npx metro-symbolicate`
 * reads against the bundle's map, and the components it was in) and on the screen, not a blank app. Not the Kotlin's:
 * a Compose app that throws ends.
 */
class Failing extends Component<{ children: ReactNode }, { error: Error | null; where: string }> {
  state = { error: null as Error | null, where: "" };
  static getDerivedStateFromError(error: Error) { return { error }; }
  componentDidCatch(error: Error, info: ErrorInfo) {
    const where = `${error?.stack ?? String(error)}\n${info.componentStack ?? ""}`;
    console.log(`stillfail: a page failed: ${where}`);
    this.setState({ where });
  }
  render() {
    const e = this.state.error;
    if (e == null) return this.props.children;
    return (
      <View style={{ flex: 1, padding: 24, paddingTop: 80 }}>
        <Text selectable style={{ fontSize: 13, color: "#A12F35" }}>{String(e?.message ?? e)}</Text>
        <Text selectable style={{ fontSize: 10, color: "#666", marginTop: 12 }}>{this.state.where}</Text>
      </View>
    );
  }
}
