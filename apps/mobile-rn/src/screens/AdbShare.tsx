// A station's 共享调试 (docs/adb-share.md): this phone's adb lent to the station's agents, how it stands, what the phone
// needs for it (Developer options, Wi-Fi, Wireless debugging), pairing the first time, and the app turning Wireless
// debugging on itself from then on. The lending itself is the core's and modules/stillfail-adb's (the Android app's
// AdbShare.kt, in Kotlin); this page only shows and asks.
import { useEffect, useState, type Dispatch, type SetStateAction } from "react";
import { AppState as SystemAppState, PermissionsAndroid, Platform, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { CoreError } from "../../../../web/src/core/client.ts";
import type { AdbShareView, StationView } from "../../../../web/src/core/shapes.ts";
import { AdbShare, serve } from "../../modules/stillfail-adb";
import { app as theApp, useApp } from "../AppState";
import { errorText } from "../data/Calls";
import type { WorkspaceEntry } from "../data/Accounts";
import { rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { Notifier } from "../Notices";
import { stationName } from "../ui/ChatInk";
import { DoingMark } from "../ui/Controls";
import { ListCard, ListRow, NavBar, SectionHeader } from "../ui/Parts";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { Switch } from "./Connects";
import { ask } from "./Settings";

// The service's calls to the core (adb.share, adb.pair, adb.stop) and the topic it follows, made here for the app's life,
// from as the app starts (this page is imported then): the Android app's service calls its core itself.
serve(() => theApp.core, (e) => (e instanceof CoreError ? errorText(e) : e instanceof Error ? e.message : String(e)));

/** What the service's notifications say (AdbShare.kt's t), in the language now: given to it as it starts. */
const NATIVE_WORDS = [
  "android-misc.adb.title", "android-misc.adb.notify.title", "android-misc.adb.stop", "android-misc.adb.pair.channel",
  "android-misc.adb.code", "android-misc.adb.pair.ask", "android-misc.adb.pair.auto", "android-misc.adb.typeCode",
  "android-misc.adb.enterCode", "android-misc.adb.connecting", "android-misc.adb.connected.left", "android-misc.adb.connected",
  "android-misc.adb.notPaired", "android-misc.adb.pair.popped", "android-misc.adb.off", "android-misc.adb.attaching",
  "android-misc.adb.pairing", "android-misc.adb.paired", "android-misc.adb.pairFailed", "android-misc.adb.shareFailed",
  "android-misc.failed",
];

function nativeWords(): Record<string, string> {
  // Their places kept as they are (`{name}`), for the service to fill in.
  const words: Record<string, string> = Object.fromEntries(NATIVE_WORDS.map((key) => [key, t(key, { name: "{name}", n: "{n}", error: "{error}" })]));
  words["android-misc.adb.connected.left#one"] = t("android-misc.adb.connected.left", { n: 1 });
  return words;
}

/** What the phone has for Wireless debugging, read again as the page comes back and as the setting changes. */
interface Phone { developer: boolean; wireless: boolean; wifi: boolean; canSwitch: boolean }

function rememberPhone(): [Phone, Dispatch<SetStateAction<Phone>>] {
  const read = (): Phone => ({ developer: AdbShare.developerOptions(), wireless: AdbShare.wirelessOn(), wifi: AdbShare.onWifi(), canSwitch: AdbShare.canSwitch() });
  const [phone, setPhone] = useState(read);
  // Back from Settings.
  useEffect(() => {
    const sub = SystemAppState.addEventListener("change", (state) => { if (state === "active") setPhone(read()); });
    return () => sub.remove();
  }, []);
  // Wireless debugging switched (by the app, or by Android as the Wi-Fi goes).
  useEffect(() => AdbShare.watchWireless(() => setPhone(read())), []);
  return [phone, setPhone];
}

export function AdbShareScreen({ current, address }: { current: WorkspaceEntry; address: string }) {
  const app = theApp;
  const C = useC();
  const insets = useSafeAreaInsets();
  useApp((s) => s.doing);
  const stations = rememberTopic<StationView[]>(Topics.stations(current.workspace.id));
  const name = stations.value?.find((s) => s.station === address)?.name ?? stationName(address);
  const shared = rememberTopic<AdbShareView>(Topics.adbShare);
  const view = shared.value;
  const here = view?.sharing === true && view.station === address;
  const elsewhere = view?.sharing === true && view.station !== address;
  const [phone, setPhone] = rememberPhone();
  // 还剩 N 分钟 as the minutes go.
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!here) return;
    const timer = setInterval(() => setNow(Date.now()), 20_000);
    return () => clearInterval(timer);
  }, [here]);
  // The pairing code is typed into the notification: it is asked for once, as the lending starts.
  const start = () => {
    const go = () => AdbShare.start(address, name, nativeWords());
    if (!Notifier.allowed() && Platform.OS === "android" && Number(Platform.Version) >= 33) PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS).then(go, go);
    else go();
  };
  const supported = AdbShare.supported;
  // 以后's switch: the station's adb granting the app to turn Wireless debugging on itself.
  const busy = app.isDoing("adb.grant");
  return (
    <View style={{ flex: 1 }}>
      <NavBar back="Station" onBack={() => app.pop()} title={t("android-misc.adb.title")} sub={() => <T size={11} color={C.muted} numberOfLines={1}>{name}</T>} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom, paddingTop: 12 }}>
        <T size={13} color={C.muted} style={{ paddingLeft: 24, paddingRight: 24, paddingBottom: 10 }}>{t("android-misc.adb.about", { name })}</T>
        {/* iOS has no Wireless debugging (nor any way to lend its own debugging): there the page says what the Android
            app says on a phone without it (before Android 11), and offers nothing to tap. */}
        {!supported ? <ListCard><ListRow><T size={15} color={C.muted}>{t("android-misc.adb.unsupported")}</T></ListRow></ListCard> : (
          <>
            <ListCard>
              {/* Lent or not, as settings' switches are; what it is doing under the title. */}
              <ListRow onClick={() => { if (here) app.act(t("android-misc.adb.stopWhat"), () => app.core.call("adb.stop")); else start(); }}>
                <View style={{ flex: 1 }}>
                  <T size={15} color={C.ink}>{t("android-misc.adb.title")}</T>
                  <T size={13} color={here && (view!.adb === "missing" || view!.adb === "failed") ? C.red : C.muted}>{
                    here ? state(view!, now)
                      : elsewhere ? t("android-misc.adb.elsewhere")
                      // Why it stopped by itself (its hour up, the station too old).
                      : view?.sharing === false && view.message != null ? view.message
                      : t("android-misc.adb.hour")
                  }</T>
                </View>
                <Switch on={here} />
              </ListRow>
              {here && view!.serial != null && view!.adb === "connected" && (
                <ListRow>
                  <T size={15} color={C.ink} style={{ flex: 1 }}>{t("android-misc.adb.agentsUse")}</T>
                  <T size={13} mono color={C.muted} selectable>{`adb -s ${view!.serial}`}</T>
                </ListRow>
              )}
              {/* What the station said, when it says more than the line above. */}
              {here && view!.adb !== "connected" && view!.message != null && view!.message.trim() !== "" && view!.message !== state(view!, now) && !state(view!, now).endsWith(view!.message) && (
                <ListRow><T size={13} color={C.muted}>{view!.message}</T></ListRow>
              )}
            </ListCard>
            <SectionHeader title={t("android-misc.adb.phone")} start={24} />
            <ListCard>
              <Need title={t("android-misc.adb.developer")} ok={phone.developer} value={phone.developer ? t("android-misc.adb.on") : t("android-misc.adb.developer.how")} />
              <Need title={t("android-misc.adb.wifi")} ok={phone.wifi} value={phone.wifi ? t("android-misc.adb.wifi.on") : t("android-misc.adb.wifi.needed")} />
              <ListRow onClick={() => {
                if (!phone.wireless && AdbShare.switchOn()) setPhone({ ...phone, wireless: true }); else AdbShare.openWireless();
              }}>
                <T size={15} color={C.ink} style={{ flex: 1 }}>{t("android-misc.adb.wireless")}</T>
                <T size={14} color={phone.wireless ? C.muted : C.accent}>{phone.wireless ? t("android-misc.adb.on") : phone.canSwitch ? t("android-misc.adb.wireless.turnOn") : t("android-misc.adb.wireless.settings")}</T>
              </ListRow>
            </ListCard>
            {here && view!.adb === "unpaired" && <Pairing view={view!} />}
            {here && view!.adb === "connected" && !phone.canSwitch && (
              <>
                <SectionHeader title={t("android-misc.adb.later")} start={24} />
                <ListCard>
                  <ListRow onClick={busy ? null : () => {
                    app.act(t("android-misc.adb.grantWhat"), async () => {
                      await app.core.call("adb.grant");
                      setPhone((p) => ({ ...p, canSwitch: AdbShare.canSwitch() }));
                    }, t("android-misc.adb.granted"));
                  }}>
                    <View style={{ flex: 1 }}>
                      <T size={15} color={C.ink}>{t("android-misc.adb.grant.title")}</T>
                      <T size={13} color={C.muted}>{t("android-misc.adb.grant.note")}</T>
                    </View>
                    <DoingMark running={busy} failed={app.failedOf("adb.grant")} />
                    <Switch on={false} />
                  </ListRow>
                </ListCard>
              </>
            )}
            <T size={12} color={C.subtle} style={{ paddingLeft: 24, paddingRight: 24, paddingTop: 16 }}>{t("android-misc.adb.warning")}</T>
            <View style={{ height: 30 }} />
          </>
        )}
      </ScrollView>
    </View>
  );
}

/** What the phone needs, and whether it has it. */
function Need({ title, ok, value }: { title: string; ok: boolean; value: string }) {
  const C = useC();
  return (
    <ListRow>
      <T size={15} color={C.ink} style={{ flex: 1 }}>{title}</T>
      <T size={14} color={ok ? C.muted : C.red}>{value}</T>
    </ListRow>
  );
}

/**
 * The first time with a station: its adb pairs with the phone through the pairing dialog's code, read off the dialog
 * where the person turned that on (AdbCodeReader, asked for here), else typed into the notification or, split, here.
 */
function Pairing({ view }: { view: AdbShareView }) {
  const app = theApp;
  const C = useC();
  useApp((s) => s.doing);
  const busy = app.isDoing("adb.pair");
  // Back from Accessibility's settings.
  const [reads, setReads] = useState(() => AdbShare.reads());
  useEffect(() => {
    setReads(AdbShare.reads());
    const sub = SystemAppState.addEventListener("change", (state) => { if (state === "active") setReads(AdbShare.reads()); });
    return () => sub.remove();
  }, []);
  return (
    <>
      <SectionHeader title={t("android-misc.adb.pair.title")} start={24} />
      <ListCard>
        <ListRow onClick={() => AdbShare.openReader()}>
          <View style={{ flex: 1 }}>
            <T size={15} color={C.ink}>{t("android-misc.adb.reader.title")}</T>
            <T size={13} color={C.muted}>{t("android-misc.adb.reader.note")}</T>
          </View>
          <T size={14} color={reads ? C.muted : C.accent}>{reads ? t("android-misc.adb.on") : t("android-misc.adb.reader.turnOn")}</T>
        </ListRow>
        <ListRow onClick={() => AdbShare.openWireless(true)}>
          <View style={{ flex: 1 }}>
            <T size={15} color={C.ink}>{t("android-misc.adb.pair.open")}</T>
            <T size={13} color={C.muted}>{reads ? t("android-misc.adb.pair.open.auto") : t("android-misc.adb.pair.open.note")}</T>
          </View>
          <T size={14} color={C.accent}>{t("android-misc.adb.pair.go")}</T>
        </ListRow>
        {/* Split screen: the code typed here instead (in full screen, coming back here closes the dialog). */}
        <ListRow onClick={view.pairPort == null || busy ? null : () => {
          ask(app, t("android-misc.adb.pair.ask"), "", t("android-misc.adb.code"), t("android-misc.adb.pair.action"), { hint: t("android-misc.adb.pair.hint") }, async (code) => {
            await app.core.call("adb.pair", { code: code.replace(/\D/g, "") });
            app.toast = t("android-misc.adb.paired");
          });
        }}>
          <View style={{ flex: 1 }}>
            <T size={15} color={view.pairPort == null ? C.subtle : C.ink}>{t("android-misc.adb.pair.here")}</T>
            <T size={13} color={C.muted}>{view.pairPort == null ? t("android-misc.adb.pair.here.wait") : t("android-misc.adb.pair.here.split")}</T>
          </View>
          <DoingMark running={busy} failed={app.failedOf("adb.pair")} />
        </ListRow>
      </ListCard>
    </>
  );
}

/** How the lending stands, in a line. */
function state(view: AdbShareView, now: number): string {
  if (view.phase !== "offered") return view.message != null ? t("android-misc.adb.connecting.why", { why: view.message }) : t("android-misc.adb.connecting");
  if (view.adb === "connected") return view.until != null ? t("android-misc.adb.connected.left", { n: Math.max(0, Math.trunc((view.until - now) / 60_000)) }) : t("android-misc.adb.connected");
  if (view.adb === "unpaired") return t("android-misc.adb.unpaired");
  if (view.adb === "unauthorized") return t("android-misc.adb.unauthorized");
  if (view.adb === "off") return t("android-misc.adb.off");
  if (view.adb === "missing") return t("android-misc.adb.missing");
  if (view.adb === "failed") return t("android-misc.adb.failed");
  return t("android-misc.adb.attaching");
}
