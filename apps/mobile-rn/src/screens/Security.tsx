// The workspace's security mode (its lock, docs/workspace-lock.md), as the narrow web has it (web/src/mobile/Security.tsx):
// its page from the settings, turning it on, a device to confirm in a bottom sheet, and what a device waiting itself
// shows. All of it is the core's (`lock`, `lockDraft` topics, `lock.*` calls, client/core-ts/src/views/lock.ts).
import { useEffect, useState, type ReactNode } from "react";
import { Pressable, ScrollView, TextInput, View, type StyleProp, type ViewStyle } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import type { LockDevice, LockDraftView, LockRequest, LockView } from "../../../../web/src/core/shapes.ts";
import { app as theApp, SheetSpec, useApp, type AppState } from "../AppState";
import { ROLE_LABEL, type WorkspaceEntry } from "../data/Accounts";
import { rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { PickRow } from "../ui/Controls";
import { Icons } from "../ui/Icon";
import { IconIn, LargeTitle, ListCard, ListRow, ripple, SectionHeader } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { CODE_FONT, useC, withAlpha } from "../ui/Theme";
import { BusyIcon, Spinner, WaitLine, WaitShape, Waiting } from "../ui/Waiting";
import { PageNote } from "./SettingParts";
import { TopBack } from "./Stations";
import { vaultAct } from "./Vault";

const roleLabel = (role: string) => ROLE_LABEL[role] ?? role;

/** A device's name as people know it: its label, or what kind of client it is. */
function deviceName(kind: string, label: string, older = false): string {
  if (older) return label || t("web-pages.security.olderClient");
  if (label !== "") return label;
  if (kind === "web") return t("web-pages.security.webDevice");
  return t("web-pages.security.appDevice");
}

/** `lock.<name>` on this workspace, let go on by itself and said how it ended. */
function lockCall(app: AppState, workspace: string, name: string, what: string, done: string | null = null, params: Record<string, string> = {}) {
  app.act(what, () => app.core.call(`lock.${name}`, { workspace, ...params }), done);
}

export function Dot({ on, warn = false }: { on: boolean; warn?: boolean }) {
  const C = useC();
  return <View style={{ width: 7, height: 7, borderRadius: 3.5, backgroundColor: on ? C.green : warn ? C.warn : C.line }} />;
}

export function Body({ children }: { children?: ReactNode }) {
  return <View style={{ alignSelf: "stretch", paddingHorizontal: 16, paddingVertical: 14, gap: 12 }}>{children}</View>;
}

export function Para({ main, sub = null }: { main: string; sub?: string | null }) {
  const C = useC();
  return (
    <View>
      <T size={15} line={22} color={C.ink}>{main}</T>
      {sub != null && <T size={15} line={22} color={C.subtle}>{sub}</T>}
    </View>
  );
}

function Note({ text }: { text: string }) {
  const C = useC();
  return <T size={12} line={18} color={C.subtle}>{text}</T>;
}

/** A main action as wide as where it is (the screen's foot, a sheet's half). */
export function WideButton({ label, primary, modifier, busy = false, enabled = true, danger = false, onClick }: { label: string; primary: boolean; modifier?: StyleProp<ViewStyle>; busy?: boolean; enabled?: boolean; danger?: boolean; onClick: () => void }) {
  const C = useC();
  const on = enabled && !busy;
  // `danger`: red, and faded red (not grey) until it can be pressed, so it reads as the same button.
  // The secondary one a shade of ink, not the chip colour: on a sheet's frosted paper the chip all but disappears.
  const ground = !primary ? withAlpha(C.ink, 0.08) : danger ? (enabled ? C.red : withAlpha(C.red, 0.4)) : !enabled ? C.line : C.ink;
  const ink = primary && danger ? "#FFFFFF" : primary ? C.bg : C.ink;
  return (
    <Smooth radius={23} style={[{ height: 46, backgroundColor: ground }, modifier]}>
      <Pressable disabled={!on} onPress={onClick} android_ripple={ripple(primary ? C.bg : C.ink)} style={{ flex: 1, flexDirection: "row", alignItems: "center", justifyContent: "center" }}>
        {/* A solid one's spinner in its words' colour. */}
        <BusyIcon busy={busy} solid={primary ? ink : null} />
        {busy && <View style={{ width: 8 }} />}
        <T size={15} weight="600" color={ink}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

/** The page's main action along the bottom of the screen, as wide as it; the page scrolls above it. */
export function Foot({ note = null, children }: { note?: string | null; children?: ReactNode }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  return (
    <View style={{ alignSelf: "stretch", backgroundColor: C.bg, paddingBottom: insets.bottom }}>
      <View style={{ paddingHorizontal: 16, paddingVertical: 10, alignItems: "center", gap: 8 }}>
        {note != null && <Note text={note} />}
        {children}
      </View>
    </View>
  );
}

export function SecurityScreen({ current }: { current: WorkspaceEntry }) {
  const app = theApp;
  const topic = rememberTopic<LockView>(Topics.lock(current.workspace.id));
  const lock = topic.value;
  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }}>
        <TopBack label={t("android-settings.title")} onBack={() => app.pop()} />
        <LargeTitle small="" big={t("web-pages.security.title")} />
        {lock == null ? <Waiting shape={WaitShape.Cards} text={t("web-pages.settings.reading")} error={topic.error?.message} />
          : !lock.available ? <ListCard><Body><Note text={t("web-pages.security.unavailable")} /></Body></ListCard>
          : lock.locked ? <On current={current} lock={lock} />
          : <Off lock={lock} />}
        <View style={{ height: 30 }} />
      </ScrollView>
      {lock != null && lock.available && !lock.locked && lock.owner && lock.canSign && (
        <Foot>
          <WideButton label={t("web-pages.security.turnOn")} primary modifier={{ alignSelf: "stretch" }} onClick={() => app.push({ kind: "SecurityOpen" })} />
        </Foot>
      )}
    </View>
  );
}

function Off({ lock }: { lock: LockView }) {
  const C = useC();
  return (
    <>
      <ListCard>
        <Body>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}><Dot on={false} /><T size={15} weight="600" color={C.ink}>{t("web-pages.security.off")}</T></View>
          <Para main={t("web-pages.security.now")} sub={t("web-pages.security.nowRisk")} />
          <Para main={t("web-pages.security.then")} />
          <Para main={t("web-pages.security.newDevices")} sub={t("web-pages.security.newDevicesHow")} />
          {!lock.owner ? <Note text={t("web-pages.security.ownerOnly")} /> : !lock.canSign ? <Note text={t("web-pages.security.webCannotSign")} /> : null}
        </Body>
      </ListCard>
      <SectionHeader title={t("web-pages.security.signing")} start={24} />
      <ListCard><Body><Note text={t("web-pages.security.signingWho")} /></Body></ListCard>
    </>
  );
}

function On({ current, lock }: { current: WorkspaceEntry; lock: LockView }) {
  const app = theApp;
  const C = useC();
  useApp((s) => s.doing);
  const ws = current.workspace.id;
  const turningOff = app.isDoing("lock.disable", { workspace: ws });
  return (
    <>
      <ListCard>
        <Body>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}><Dot on /><T size={15} weight="600" color={C.ink}>{t("web-pages.security.on")}</T></View>
          <Note text={t("web-pages.security.onMeta", { signers: lock.signers, stations: lock.protected })} />
          {!lock.signs && <Note text={lock.canSign ? t("web-pages.security.notSignerApp") : t("web-pages.security.notSignerWeb")} />}
        </Body>
      </ListCard>
      {lock.requests.length > 0 && (
        <>
          <SectionHeader title={`${t("web-pages.security.waiting")} · ${lock.requests.length}`} start={24} />
          <ListCard>
            {lock.requests.map((r) => (
              <ListRow key={r.device} onClick={lock.signs ? () => confirmSheet(app, ws, r) : null}>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <T size={15} color={C.ink}>{t("web-pages.security.newDeviceOf", { name: r.name || r.email })}</T>
                  <T size={13} color={C.muted}>{`${deviceName(r.kind, r.label)} · ${r.time?.["created_at"]?.ago ?? ""}`}</T>
                </View>
                <T size={14} weight="600" color={C.ink} style={{ fontFamily: CODE_FONT }}>{r.code}</T>
              </ListRow>
            ))}
          </ListCard>
        </>
      )}
      <SectionHeader title={t("web-pages.security.people")} start={24} />
      <ListCard>
        {lock.members.map((m) => (
          <View key={m.sub}>
            <ListRow>
              <T size={15} color={C.ink} style={{ flex: 1, minWidth: 0 }}>{m.name || m.email}</T>
              <T size={14} color={C.subtle}>{roleLabel(m.role)}</T>
            </ListRow>
            {m.devices.map((d) => <DeviceRow key={d.id} ws={ws} d={d} canRenew={lock.signs} />)}
          </View>
        ))}
      </ListCard>
      <SectionHeader title="Station" start={24} />
      <ListCard>
        {lock.stations.length === 0 && <Body><Note text={t("web-pages.security.noStations")} /></Body>}
        {lock.stations.map((s) => {
          const join = !s.protected && lock.owner && lock.signs;
          const joining = app.isDoing("lock.joinStation", { workspace: ws, station: s.id });
          return (
            <ListRow key={s.id} onClick={join && !joining ? () => joinSheet(app, ws, s.id, s.name) : null}>
              <Dot on={s.protected} warn={!s.protected} />
              <View style={{ flex: 1, minWidth: 0 }}>
                <T size={15} color={C.ink}>{s.name}</T>
                {!s.protected && <T size={13} color={C.muted}>{t("web-pages.security.unprotectedWhy")}</T>}
              </View>
              {s.protected ? <T size={13} color={C.subtle}>{t("web-pages.security.protected")}</T>
                : joining ? <Spinner />
                : join ? <T size={14} color={C.accent}>{t("web-pages.security.join")}</T>
                : <T size={13} color={C.warn}>{t("web-pages.security.unprotected")}</T>}
            </ListRow>
          );
        })}
      </ListCard>
      <SectionHeader title={t("web-pages.security.webTitle")} start={24} />
      <ListCard><Body><Note text={t("web-pages.security.webRisk")} /></Body></ListCard>
      {lock.owner && lock.signs && (
        <>
          <View style={{ height: 18 }} />
          <ListCard>
            <ListRow onClick={turningOff ? null : () => turnOffSheet(app, ws, current.workspace.name)}>
              <T size={15} color={C.red} style={{ flex: 1, minWidth: 0 }}>{t("web-pages.security.turnOff")}</T>
              {turningOff && <Spinner inline />}
            </ListRow>
          </ListCard>
        </>
      )}
    </>
  );
}

function DeviceRow({ ws, d, canRenew }: { ws: string; d: LockDevice; canRenew: boolean }) {
  const app = theApp;
  const C = useC();
  useApp((s) => s.doing);
  const renewing = app.isDoing("lock.renew", { workspace: ws, device: d.id });
  const meta = [
    d.kind === "web" ? t("web-pages.security.web") : t("web-pages.security.app"),
    d.signs ? t("web-pages.security.signs") : null,
    d.mine ? t("web-pages.security.thisDevice") : null,
    d.daysLeft != null ? t("web-pages.security.daysLeft", { n: d.daysLeft }) : null,
    d.recent ? t("web-pages.security.recent") : null,
  ].filter((x) => x != null).join(" · ");
  const renew = d.daysLeft != null && canRenew;
  return (
    <ListRow onClick={renew && !renewing ? () => lockCall(app, ws, "renew", t("web-pages.security.renew"), t("web-pages.security.renewed"), { device: d.id }) : null}>
      <View style={{ flex: 1, minWidth: 0, paddingLeft: 14 }}>
        <T size={15} color={C.ink}>{deviceName(d.kind, d.label, d.older)}</T>
        <T size={13} color={d.renewSoon ? C.warn : C.muted}>{meta}</T>
      </View>
      {renewing ? <Spinner /> : renew ? <T size={14} color={C.accent}>{t("web-pages.security.renew")}</T> : null}
    </ListRow>
  );
}

/**
 * 关闭安全模式？, as the desktop asks it (web/src/cloud/Security.tsx TurnOff): what turning it off gives up, a line each,
 * and the workspace's name typed before it can go. The core then has the system ask the person (fingerprint, the
 * screen lock) before it signs; their no says nothing.
 */
function turnOffSheet(app: AppState, ws: string, name: string) {
  // As tall as what it shows (grab, head, the words, the field, the buttons); the sheet rises over the keyboard itself.
  app.sheet = new SheetSpec(0.7, false, 470, null, false, () => <TurnOffSheet app={app} ws={ws} name={name} />);
}

function TurnOffSheet({ app, ws, name }: { app: AppState; ws: string; name: string }) {
  const C = useC();
  const [typed, setTyped] = useState("");
  const named = typed.trim() === name.trim();
  const lines: [typeof Icons.Server, string][] = [
    [Icons.Server, t("web-pages.security.nowRisk")],
    [Icons.Devices, t("web-pages.security.turnOffApproval")],
    [Icons.Key, t("web-pages.security.turnOffVault")],
  ];
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.security.turnOffTitle")} />
      <ScrollView style={{ flexShrink: 1, flexGrow: 0 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 12 }} keyboardShouldPersistTaps="handled">
        <T size={14} color={C.muted}>{t("web-pages.security.turnOffBody")}</T>
        {lines.map(([icon, said], i) => (
          <View key={i} style={{ flexDirection: "row", gap: 10 }}>
            <IconIn icon={icon} size={18} tint={C.muted} modifier={{ marginTop: 2 }} />
            <T size={15} line={22} color={C.ink} style={{ flexShrink: 1 }}>{said}</T>
          </View>
        ))}
        <T size={13} color={C.muted} style={{ paddingTop: 6 }}>{t("web-pages.security.turnOffType", { name })}</T>
        <NameField value={typed} onChange={setTyped} />
      </ScrollView>
      <View style={{ flexDirection: "row", paddingLeft: 20, paddingRight: 20, paddingTop: 16, paddingBottom: 16, gap: 10 }}>
        <WideButton label={t("common.cancel")} primary={false} modifier={{ flex: 1 }} onClick={() => { app.sheet = null; }} />
        <WideButton label={t("web-pages.security.turnOff")} primary danger enabled={named} modifier={{ flex: 1 }} onClick={() => {
          app.sheet = null;
          vaultAct(app, t("web-pages.security.turnOff"), null, async () => { await app.core.call("lock.disable", { workspace: ws }); });
        }} />
      </View>
    </>
  );
}

/** A line to type in on a sheet (docs/ui-panels.md 浮起面板里的输入框): no ground of its own, a stronger line round it. */
function NameField({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const C = useC();
  const [focused, setFocused] = useState(false);
  return (
    <Smooth radius={12} stroke={{ width: 1, color: withAlpha(C.ink, focused ? 0.32 : 0.18) }} style={{ alignSelf: "stretch" }}>
      <TextInput
        value={value}
        onChangeText={onChange}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        autoCapitalize="none"
        autoCorrect={false}
        cursorColor={C.accent}
        selectionColor={withAlpha(C.accent, 0.4)}
        style={{ color: C.ink, fontSize: 15, lineHeight: 21, paddingHorizontal: 12, paddingVertical: 11, includeFontPadding: false }}
      />
    </Smooth>
  );
}

/** A station of the workspace not in the lock, taken in once its owner says it is theirs. */
function joinSheet(app: AppState, ws: string, station: string, name: string) {
  app.sheet = new SheetSpec(0.4, false, null, null, false, () => <JoinSheet app={app} ws={ws} station={station} name={name} />);
}

function JoinSheet({ app, ws, station, name }: { app: AppState; ws: string; station: string; name: string }) {
  const C = useC();
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.security.joinTitle", { name })} />
      <View style={{ paddingHorizontal: 20, gap: 12 }}>
        <T size={14} color={C.muted}>{t("web-pages.security.joinBody")}</T>
        <View style={{ flexDirection: "row", paddingTop: 4, gap: 10 }}>
          <WideButton label={t("common.cancel")} primary={false} modifier={{ flex: 1 }} onClick={() => { app.sheet = null; }} />
          <WideButton label={t("web-pages.security.join")} primary modifier={{ flex: 1 }} onClick={() => {
            app.sheet = null;
            lockCall(app, ws, "joinStation", t("web-pages.security.join"), t("web-pages.security.joined", { name }), { station });
          }} />
        </View>
      </View>
    </>
  );
}

/** A waiting device: confirmed once its code is the one on its screen. */
function confirmSheet(app: AppState, ws: string, r: LockRequest, onClose: (() => void) | null = null) {
  app.sheet = new SheetSpec(0.55, false, null, onClose, false, () => <ConfirmDeviceSheet app={app} ws={ws} r={r} />);
}

function ConfirmDeviceSheet({ app, ws, r }: { app: AppState; ws: string; r: LockRequest }) {
  const C = useC();
  const who = r.name || r.email;
  // Answered on another device: gone here too.
  const lock = rememberTopic<LockView>(Topics.lock(ws));
  const gone = lock.value != null && !lock.value.requests.some((it) => it.device === r.device);
  useEffect(() => { if (gone) app.sheet = null; }, [gone, app]);
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.security.confirmTitle", { name: who })} />
      <View style={{ paddingHorizontal: 20, gap: 12 }}>
        <T size={14} color={C.muted}>{t("web-pages.security.confirmBody", { device: deviceName(r.kind, r.label), name: who })}</T>
        <T size={34} weight="600" color={C.ink} align="center" style={{ fontFamily: CODE_FONT, letterSpacing: 5, alignSelf: "stretch" }}>{r.code}</T>
        <Note text={r.kind === "web" ? t("web-pages.security.confirmWeb") : t("web-pages.security.confirmApp")} />
        <View style={{ flexDirection: "row", paddingTop: 4, gap: 10 }}>
          <WideButton label={t("web-pages.security.deny")} primary={false} modifier={{ flex: 1 }} onClick={() => {
            app.sheet = null; lockCall(app, ws, "deny", t("web-pages.security.deny"), null, { device: r.device });
          }} />
          <WideButton label={t("web-pages.security.confirm")} primary modifier={{ flex: 1 }} onClick={() => {
            app.sheet = null; lockCall(app, ws, "confirm", t("web-pages.security.confirm"), t("web-pages.security.confirmed"), { device: r.device, code: r.code });
          }} />
        </View>
      </View>
    </>
  );
}

/** 开启安全模式. */
export function SecurityOpenScreen({ current }: { current: WorkspaceEntry }) {
  const app = theApp;
  const C = useC();
  useApp((s) => s.doing);
  const ws = current.workspace.id;
  const topic = rememberTopic<LockDraftView>(Topics.lockDraft(ws));
  const draft = topic.value;
  const opening = app.isDoing("lock.open", { workspace: ws });
  const toggle = (id: string) => app.act(t("web-pages.security.turnOn"), () => app.core.call("lock.toggle", { workspace: ws, id }));
  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }}>
        <TopBack label={t("web-pages.security.title")} onBack={() => app.pop()} />
        <LargeTitle small="" big={t("web-pages.security.openTitle")} />
        {draft == null || draft.loading ? <Waiting shape={WaitShape.Cards} text={t("web-pages.settings.reading")} error={topic.error?.message} /> : (
          <>
            <PageNote text={t("web-pages.security.openLead")} />
            <SectionHeader title={t("web-pages.security.members")} start={24} />
            <ListCard>
              {draft.members.map((m) => (
                <ListRow key={m.sub}>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <T size={15} color={C.ink}>{m.name || m.email}</T>
                    <T size={13} color={C.muted}>{m.email}</T>
                  </View>
                  <T size={14} color={C.subtle}>{roleLabel(m.role)}</T>
                </ListRow>
              ))}
            </ListCard>
            <SectionHeader title={t("web-pages.security.devices")} start={24} />
            <ListCard>
              {draft.devices.map((d) => (
                <PickRow
                  key={d.id}
                  label={`${d.person} · ${d.current ? t("web-pages.security.thisDevice") : deviceName(d.kind, d.label, d.older)}`}
                  sub={d.older ? t("web-pages.security.olderHow") : d.kind === "web" ? t("web-pages.security.web") : t("web-pages.security.app")}
                  checked={d.on}
                  enabled={!d.fixed}
                  onClick={() => toggle(d.id)}
                />
              ))}
            </ListCard>
            <SectionHeader title="Station" start={24} />
            <ListCard>
              {draft.stations.map((s) => (
                <PickRow
                  key={s.id}
                  label={s.name}
                  sub={s.state === "ok" ? s.version : s.state === "asking" ? t("web-pages.security.asking") : s.state === "old" ? t("web-pages.security.tooOld") : t("web-pages.security.offline")}
                  checked={s.on}
                  enabled={!s.fixed}
                  onClick={() => toggle(s.id)}
                />
              ))}
            </ListCard>
            <PageNote text={t("web-pages.security.unprotectedNote")} />
            <View style={{ height: 24 }} />
          </>
        )}
      </ScrollView>
      {draft != null && !draft.loading && (
        <Foot note={draft.canSign ? t("web-pages.security.webExpiry") : t("web-pages.security.webCannotSign")}>
          <WideButton label={t("web-pages.security.signAndTurnOn")} primary modifier={{ alignSelf: "stretch" }} busy={opening} enabled={draft.ready && draft.owner && draft.canSign} onClick={() => {
            app.act(t("web-pages.security.turnOn"), async () => {
              await app.core.call("lock.open", { workspace: ws });
              app.pop();
            }, t("web-pages.security.turnedOn"));
          }} />
        </Foot>
      )}
    </View>
  );
}

/** What a device waiting to be confirmed shows instead of the workspace's pages. */
export function SecurityWaitingScreen({ current, lock }: { current: WorkspaceEntry; lock: LockView }) {
  const app = theApp;
  const C = useC();
  const insets = useSafeAreaInsets();
  useApp((s) => s.doing);
  const ws = current.workspace.id;
  const asking = app.isDoing("lock.request", { workspace: ws });
  return (
    <View style={{ flex: 1, paddingHorizontal: 28, paddingBottom: insets.bottom, justifyContent: "center", alignItems: "center", gap: 14 }}>
      <IconIn icon={Icons.ShieldCheck} size={44} tint={C.ink} />
      <T size={22} weight="700" color={C.ink} align="center">{t("web-pages.security.waitingTitle")}</T>
      <T size={15} line={22} color={C.subtle} align="center">{t("web-pages.security.waitingLead", { name: current.workspace.name })}</T>
      <T size={36} weight="600" color={C.ink} style={{ fontFamily: CODE_FONT, letterSpacing: 5 }}>{lock.me?.code ?? ""}</T>
      {lock.me?.asked === false && !asking ? (
        <>
          <Note text={t("web-pages.security.notAsked")} />
          <WideButton label={t("web-pages.security.request")} primary onClick={() => lockCall(app, ws, "request", t("web-pages.security.request"))} />
        </>
      ) : (
        <WaitLine text={t("web-pages.security.waitingNote")} />
      )}
    </View>
  );
}

/** A device waiting to be confirmed into the workspace's lock sees that instead of the workspace (its settings stay). */
export function LockGate({ current, children }: { current: WorkspaceEntry; children?: ReactNode }) {
  const app = theApp;
  const topic = rememberTopic<LockView>(Topics.lock(current.workspace.id));
  const lock = topic.value;
  // A device waiting on this one, put up wherever in the workspace this device is (the core's `prompt`), and again
  // after a page change took the sheet away, until it is answered or closed by hand (`lock.shown`).
  const prompt = lock?.prompt;
  const free = useApp((s) => s.sheet == null);
  useEffect(() => {
    if (prompt == null || !free) return;
    confirmSheet(app, current.workspace.id, prompt, () => {
      app.core.call("lock.shown", { workspace: current.workspace.id, device: prompt.device }).catch(() => undefined);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [prompt?.device, free]);
  if (lock?.me?.waiting === true) return <SecurityWaitingScreen current={current} lock={lock} />;
  return <>{children}</>;
}
