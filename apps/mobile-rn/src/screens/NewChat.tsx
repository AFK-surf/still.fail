// A new chat rises from the bottom: say what to do, having picked where it
// runs (station), on what (model) and how hard it thinks. The first message
// (or file) makes the session on that station; then the page becomes the chat.
import { useContext, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { BackHandler, Pressable, ScrollView, View, type StyleProp, type ViewStyle } from "react-native";
import Animated, { Easing, useAnimatedStyle } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { CoreError } from "../../../../web/src/core/client.ts";
import { core } from "../../../../web/src/core/react.ts";
import type { Attachment, NewChatView, PickView, StationView } from "../../../../web/src/core/shapes.ts";
import { LocalApp, SheetSpec, useApp, type AppState } from "../AppState";
import { APP_NAME } from "../build";
import type { WorkspaceEntry } from "../data/Accounts";
import { errorText, type MachineSaid, type MachineSession } from "../data/Calls";
import { rememberTopic, Topics } from "../data/Topics";
import { RUNTIME_LABEL } from "../data/Words";
import { t } from "../i18n";
import { Button, PickRow } from "../ui/Controls";
import { Illustration } from "../ui/Drawing";
import { Floating, FootGlass } from "../ui/Glass";
import { Icon, Icons } from "../ui/Icon";
import { Markdown } from "../ui/Markdown";
import { MakerIcon, NavBar, ProviderMark, StationMark } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { dp, lerpColor, useC, withAlpha } from "../ui/Theme";
import { BusyIcon, WaitLine, WaitShape, Waiting } from "../ui/Waiting";
import { AttachLaunchers, openAttach } from "./Attach";
import { SCENE_LEAVE_MS, type Host } from "./ChatHost";
import { rememberDraft, sendSharing, upload, type DraftQuote, type Pending, type Picked } from "./Composer";
import { MachineLoginOffers } from "./Profiles";
import { optionOf } from "./SettingParts";
import { FirstStation } from "./Settings";
import { openStationFiles } from "./StationFiles";

/** What a failure says (data/Calls.ts errorText), whatever was thrown. */
const why = (e: unknown) => (e instanceof CoreError ? errorText(e) : e instanceof Error ? e.message : String(e));

/** Ease.Arrive and Ease.LeaveFade as functions of progress (ui/Motion.ts has them as Reanimated's easing factories). */
const arrive = Easing.bezierFn(0.2, 0.8, 0.2, 1);
const leaveFade = Easing.bezierFn(0.3, 0, 0.5, 1);

/** Picks for a new chat in a scope (`station`: its id; the core keeps them, client/core-ts/src/choose.ts): each given changes only that. */
function pickNew(app: AppState, scope: string, fill: Record<string, unknown>) {
  core().call("newChat.pick", { scope, ...fill }).catch((e: unknown) => { app.toast = t("android-chat.pick.failed", { error: why(e) }); });
}

/**
 * The new chat, above its host's composer (ChatHost.tsx). `leaving`: it has become its chat, which is under it now; only
 * its scene is drawn, going (up out of view, its choices fading where they are).
 */
export function NewChatScreen({ current, host, leaving = false }: { current: WorkspaceEntry; host: Host; leaving?: boolean }) {
  const app = useContext(LocalApp);
  const C = useC();
  const scope = current.workspace.id;
  // The station last started on (or picked) in this workspace and what it runs there, as the core keeps them (web/src/pick.ts).
  const chat = rememberTopic<NewChatView>(Topics.newChat(scope));
  const choice = chat.value;
  const onStation = (id: string) => pickNew(app, scope, { station: id });
  const view = choice?.station;
  const online = choice?.stations;
  // No composer without a station to write to.
  useLayoutEffect(() => { if (view == null && !leaving) host.spec = null; });
  let body: ReactNode;
  // Its stations not read yet: under its bar, their first read (why they could not be, in red).
  if (choice == null || online == null) body = <Waiting shape={WaitShape.Rows} text={t("common.readingStations")} error={choice?.error ?? chat.error?.message ?? null} />;
  else if (!choice.any) body = <ScrollView style={{ flex: 1 }}><FirstStation current={current} /></ScrollView>;
  else if (view == null) {
    body = (
      <View style={{ flex: 1, padding: 30, alignItems: "center", justifyContent: "center", gap: 10 }}>
        <Illustration light="illus_station_offline" dark="illus_station_offline_dark" width={240} />
        <T size={17} weight="600">{t("android-chat.new.offline.title")}</T>
        <T size={14} color={C.muted} align="center">{t("android-chat.new.offline.text", { app: APP_NAME })}</T>
      </View>
    );
  } else body = <NewChatOn key={view.station} workspace={scope} choice={choice} view={view} stations={online} onStation={onStation} host={host} leaving={leaving} />;
  return (
    <View style={[{ flex: 1 }, !leaving && { backgroundColor: C.bg }]}>
      {/* Gone at once as it leaves (the chat has its own bar), its room kept so the scene leaves from where it was. */}
      <View style={{ opacity: leaving ? 0 : 1 }}><NavBar back={t("common.cancel")} onBack={() => app.pop()} title={t("android-chat.new.title")} /></View>
      {body}
    </View>
  );
}

function NewChatOn({ workspace, choice, view, stations, onStation, host, leaving }: { workspace: string; choice: NewChatView; view: StationView; stations: StationView[]; onStation: (id: string) => void; host: Host; leaving: boolean }) {
  const app = useContext(LocalApp);
  const C = useC();
  // Kept on the device like a chat's, by its station (web/src/NewChat.tsx: `new:<address>`).
  const draft = rememberDraft(`new:${view.station}`);
  // What it runs on, as the core resolved it against what the station has now (the same as the web's).
  const entry = choice.model;
  const model = entry?.model;
  const runtime = choice.runtime;
  const effort = choice.effort ?? "";
  const profile = choice.profile;
  // The chat, made once with the first message (web/src/NewChat.tsx → useEnsureChat), with what is picked here: the
  // core has it at once under the key it answers, its station makes it behind it; the next new chat starts here too.
  // (The page is keyed by its station: both start again with another.)
  const made = useRef<string | null>(null);
  // Whether a message went out to it: until then, another choice (model, runtime, depth, account) is made anew.
  const sent = useRef(false);
  useEffect(() => { if (!sent.current && !draft.starting) made.current = null; }, [runtime, model, effort, profile, choice.fast]);
  const ensure = async (): Promise<string> => {
    if (made.current != null) return made.current;
    const key = await app.api(view.station).createNewChat();
    made.current = key;
    return key;
  };
  const launchers = AttachLaunchers((picked: Picked) => upload(app, draft, view.station, picked));
  // Leaving: the scene up out of view as it fades (140 ms, Ease.Arrive), the choices fading where they are (80 ms).
  const lift = 32;
  // The host's shared value alone into the worklets (the host is a class the UI thread cannot take).
  const leave = host.leave;
  const scene = useAnimatedStyle(() => {
    const a = leaving ? arrive(Math.min(1, Math.max(0, leave.value / SCENE_LEAVE_MS))) : 0;
    const s = 1 - 0.04 * a;
    return { transform: [{ translateY: -lift * a }, { scaleX: s }, { scaleY: s }], opacity: 1 - a };
  });
  const footFade = useAnimatedStyle(() => ({ opacity: 1 - (leaving ? leaveFade(Math.min(1, Math.max(0, leave.value / 80))) : 0) }));
  // What stands at the foot (the choices, the composer's room) is over the scene, which runs on under them: they frost it.
  const [foot, setFoot] = useState(0);
  // The composer's room: as tall as it was when the page began to leave (it changes shape under what leaves).
  const room = useRef(0);
  if (!leaving) room.current = host.composerHeight;
  const overview = view.overview;
  const p = choice.pick;

  useLayoutEffect(() => {
    if (leaving) return;
    host.spec = {
      station: view.station, here: null, draft, placeholder: t("android-chat.new.placeholder"),
      onPlus: () => openAttach(app, launchers, () => openStationFiles(app, draft, view.station)),
      // Once what it refers to can be read in this workspace (sendSharing).
      onSend: () => sendSharing(app, draft, view.station, () => {
        // Its words stay where they were in the composer until the chat's page takes them (ChatHost.tsx).
        host.sending(draft.text.trim(), true, [...draft.files]);
        const taken = draft.take();
        draft.starting = true;
        void (async () => {
          try {
            const key = await ensure();
            // The message waits in the new chat (its outbox) until its station has made it; then it goes.
            await app.api(view.station).sendIn(key, taken.text, taken.files.map((f: Pending) => f.done).filter((d: Attachment | null | undefined): d is Attachment => d != null), taken.quotes.map((q: DraftQuote) => q.sent()));
            sent.current = true;
            // The new item's page, by the key the core gave it: this page becomes it, its composer kept.
            host.madeChat();
            app.made({ kind: "Chat", station: view.station, of: { session: key } });
          } catch (e) {
            // Nothing sent: the draft comes back.
            host.notSent();
            draft.restore(taken);
            draft.error = e instanceof Error ? e.message : String(e);
          } finally {
            draft.starting = false;
          }
        })();
      }),
    };
  });

  return (
    <View style={{ flex: 1, alignSelf: "stretch" }}>
      {/* What the composer and the choices frost: the scene (its own paper) until it leaves. */}
      <View style={[{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0 }, !leaving && { backgroundColor: C.bg }]}>
        <Animated.ScrollView style={[{ flex: 1 }, scene]}>
          <View style={{ alignSelf: "stretch", paddingLeft: 30, paddingRight: 30, paddingTop: 30, paddingBottom: 10, alignItems: "center", gap: 6 }}>
            <Illustration light="illus_new_chat" dark="illus_new_chat_dark" width={230} />
            <T size={22} weight="700" style={{ paddingTop: 6 }}>{t("android-chat.new.heading")}</T>
            <T size={14} color={C.muted} align="center">{t("android-chat.new.sub", { station: view.name })}</T>
            {choice.frequent != null && choice.frequent.length > 0 && (
              <View style={{ alignSelf: "stretch", paddingVertical: 12, alignItems: "center", gap: 8 }}>
                <T size={12} color={C.muted}>{t("android-chat.new.frequent")}</T>
                <View style={{ alignSelf: "stretch", flexDirection: "row", flexWrap: "wrap", justifyContent: "center", gap: 6 }}>
                  {choice.frequent.map((combo) => (
                    <Smooth key={`${combo.runtime}/${combo.model}/${combo.effort ?? ""}`} radius={18} style={{ backgroundColor: withAlpha(C.ink, combo.selected ? 0.1 : 0.04) }}>
                      <Pressable
                        disabled={leaving}
                        accessibilityState={{ selected: combo.selected }}
                        onPress={() => pickNew(app, workspace, { model: combo.model, runtime: combo.runtime, effort: combo.effort ?? null })}
                        android_ripple={{ color: withAlpha(C.ink, 0.1) }}
                        style={{ paddingHorizontal: 10, paddingVertical: 8 }}
                      >
                        <T size={13} line={18} color={combo.selected ? C.ink : C.muted}>{combo.label}</T>
                      </Pressable>
                    </Smooth>
                  ))}
                </View>
              </View>
            )}
            {choice.problem != null && <T size={13} color={choice.waiting ? C.muted : C.red} align="center" style={{ paddingTop: 6 }}>{choice.problem}</T>}
            {/* No profile yet: adding one is the first step, here (the machine's own logins, when there are any, offered too). */}
            {overview != null && choice.blocked === "profile" && (
              <>
                <T size={13} color={C.muted} align="center" style={{ paddingTop: 6 }}>{t("android-chat.new.profile.text", { station: view.name })}</T>
                <Button label={t("android-chat.new.profile.add")} primary onClick={() => app.push({ kind: "NewProfile", station: view.station })} />
                <View style={{ alignSelf: "stretch", paddingTop: 12 }}><MachineLoginOffers station={view.station} overview={overview} inset={0} /></View>
              </>
            )}
            {/* The machine's own Claude Code and Codex sessions, to go on with one (web/src/MachineSessions.tsx).
                Not on a station this workspace joined with no profile open to it (the machine's sessions are its home's). */}
            {overview != null && choice.blocked !== "profile" && choice.blocked !== "shared" && <MachineSessionsOffer view={view} />}
          </View>
          {/* Its end clear of what stands at the foot. */}
          <View style={{ height: foot }} />
        </Animated.ScrollView>
      </View>
      {/* A band of glass of its own, from the choices to the screen's end: what runs under it is frosted all over,
          not seen between the choices; it goes with them as the page leaves. */}
      <Animated.View style={[{ position: "absolute", left: 0, right: 0, bottom: 0 }, footFade]} onLayout={(e) => setFoot(e.nativeEvent.layout.height)}>
        <FootGlass>
          {/* Chosen anyway (it is the person's call), but said: what is sent waits for its quota. */}
          {!leaving && choice.spent != null && (
            <View style={{ paddingHorizontal: 12 }}>
              <Smooth radius={12} style={{ alignSelf: "stretch", backgroundColor: lerpColor(C.bg, C.warn, 0.12), paddingHorizontal: 12, paddingVertical: 8 }}>
                <T size={13}>{choice.spent}</T>
              </Smooth>
            </View>
          )}
          {/* The choices, over the composer (the host's, a floating capsule as in a chat), with room for it below. */}
          <View style={{ alignSelf: "stretch", paddingLeft: dp(10), paddingRight: dp(10), paddingTop: dp(8) }}>
            {/* One line that fits the width, no scrolling: where it runs, and what it runs on as one control (web/src/ModelTriple.tsx),
                cut short rather than pushed off the edge. Room above and below for the chips' shadows. */}
            <View style={{ alignSelf: "stretch", flexDirection: "row", paddingHorizontal: dp(2), paddingVertical: dp(6), gap: dp(6) }}>
              <Chooser leading={<StationMark emoji={view.emoji} icon={view.icon} size={14} tint={C.ink} none={Icons.Server} />} label={view.name} style={{ maxWidth: 128 }} onClick={() => pickStation(app, stations, view.station, onStation)} />
              {runtime == null || model == null || p == null || p.options.length === 0 ? (
                // Nothing to choose from: the chooser leads to where models are enabled.
                <Chooser leading={null} label={t("android-chat.new.noModels")} style={{ flexShrink: 1, minWidth: 0 }} onClick={() => app.push({ kind: "Profiles" })} />
              ) : (
                <Chooser leading={<MakerIcon maker={p.valueOption?.maker ?? entry!.maker} runtime={runtime} size={14} />} label={tripleLabel(p)} style={{ flexShrink: 1, minWidth: 0 }} chevron onClick={() => openRunPicker(app, view.station)} />
              )}
            </View>
          </View>
          <View style={{ height: room.current }} />
        </FootGlass>
      </Animated.View>
    </View>
  );
}

function Chooser({ leading, label, style, chevron = false, onClick }: { leading: ReactNode | null; label: string; style?: StyleProp<ViewStyle>; chevron?: boolean; onClick: () => void }) {
  const C = useC();
  // The same glass as the composer's capsule under it, over the scene running on under both.
  return (
    <Floating radius={15} style={[{ height: dp(30) }, style]}>
      <Pressable onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ flex: 1, flexDirection: "row", paddingHorizontal: dp(11), alignItems: "center", gap: dp(6) }}>
        {leading}
        <T size={13} numberOfLines={1} style={{ flexShrink: 1, minWidth: 0 }}>{label}</T>
        {chevron && <Icon icon={Icons.ChevronDown} size={12} color={C.muted} />}
      </Pressable>
    </Floating>
  );
}

function pickStation(app: AppState, stations: StationView[], current: string, onPick: (id: string) => void) {
  app.sheet = new SheetSpec(0.5, false, null, null, false, () => <PickStationSheet app={app} stations={stations} current={current} onPick={onPick} />);
}

function PickStationSheet({ app, stations, current, onPick }: { app: AppState; stations: StationView[]; current: string; onPick: (id: string) => void }) {
  const C = useC();
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-chat.new.station.pick")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        {stations.map((s) => (
          <PickRow
            key={s.station}
            label={s.name}
            sub={s.summary}
            checked={s.station === current}
            leading={<StationMark emoji={s.emoji} icon={s.icon} size={22} tint={C.ink} none={Icons.Server} />}
            onClick={() => { onPick(s.id); app.sheet = null; }}
          />
        ))}
      </ScrollView>
    </>
  );
}

/** What the control says: the model, the runtime where there is a choice, how hard it thinks, and who runs it when that matters. */
function tripleLabel(p: PickView): string {
  const v = p.value;
  return [
    p.valueOption?.name ?? v.model ?? t("android-chat.pick.model"),
    !p.runtimeFixed && (p.valueOption?.runtimes?.length ?? 0) > 1 ? (RUNTIME_LABEL[v.runtime] ?? v.runtime) : null,
    v.effort ?? t("android-chat.pick.effort.default"),
    p.fastText,
    p.account?.text,
  ].filter((x) => x != null).join(" · ");
}

/**
 * What a new chat runs on, as the PC's panel picks it (web/src/ModelTriple.tsx), in a sheet: the models in a column,
 * the runtime and how hard it thinks beside them, who runs it in the foot (a list of its own, and back). Picks are a
 * draft (`pick.set`) until 确定 (`pick.save`); closed otherwise, nothing changes.
 */
function openRunPicker(app: AppState, station: string) {
  app.sheet = new SheetSpec(0.66, false, null, null, false, () => <RunPicker app={app} station={station} />);
}

function RunPicker({ app, station }: { app: AppState; station: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const topic = rememberTopic<PickView>(Topics.pick(station, "new"));
  const set = (fill: Record<string, unknown>) => {
    app.api(station).pickSet("new", fill).catch((e: unknown) => { app.toast = t("android-chat.pick.failed", { error: why(e) }); });
  };
  // Picked from what it runs on now, each time it is opened.
  useEffect(() => { set({ open: true }); }, []);
  const [accounts, setAccounts] = useState(false);
  useEffect(() => {
    if (!accounts) return;
    const back = BackHandler.addEventListener("hardwareBackPress", () => { setAccounts(false); return true; });
    return () => back.remove();
  }, [accounts]);
  // Saving: a spinner in it, the sheet open until the core has it (closed then, unless another took its place).
  useApp((s) => s.doing);
  const saving = app.isDoing("pick.save", { station, of: "new" });
  const v = topic.value;
  const head = accounts ? (
    <View style={{ flexDirection: "row", paddingLeft: 8, paddingRight: 18, paddingTop: 4, paddingBottom: 10, alignItems: "center" }}>
      <Smooth radius={18} style={{ width: 36, height: 36 }}>
        <Pressable onPress={() => setAccounts(false)} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
          <Icon icon={Icons.ChevronLeft} size={20} color={C.ink} />
        </Pressable>
      </Smooth>
      <T size={17} weight="700">{t("android-chat.new.account")}</T>
    </View>
  ) : <SheetHead title={t("android-chat.new.model")} />;
  if (v == null) {
    return (
      <>
        <SheetGrab />
        {head}
        <Waiting shape={WaitShape.Rows} text={t("common.reading")} error={topic.error?.message ?? null} />
      </>
    );
  }
  const draft = v.draft;
  if (accounts) {
    return (
      <>
        <SheetGrab />
        {head}
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 12, paddingBottom: insets.bottom }}>
          {v.dropped != null && <T size={12} color={C.warn} style={{ paddingHorizontal: 12, paddingVertical: 4 }}>{v.dropped}</T>}
          <CascadeOption label={t("android-chat.new.auto")} sub={v.autoNote} checked={draft.profile == null} onClick={() => { set({ profile: null }); setAccounts(false); }} />
          {v.accounts.map((a) => (
            <CascadeOption
              key={a.id}
              label={a.name}
              sub={a.quotaLine?.text ?? null}
              checked={draft.profile === a.id}
              subColor={a.quotaLine?.level != null ? C.warn : C.muted}
              leading={<ProviderMark runtime={a.runtime ?? draft.runtime} kind={a.kind ?? null} size={16} mark={a.mark ?? null} />}
              onClick={() => { set({ profile: a.id }); setAccounts(false); }}
            />
          ))}
        </ScrollView>
      </>
    );
  }
  // Side by side, each scrolling on its own: the models (by series, in the core's order), and what goes with the one picked.
  const groups = new Map<string, typeof v.options>();
  for (const o of v.options) {
    const who = o.family ?? t("android-chat.pick.family.other");
    const list = groups.get(who);
    if (list) list.push(o); else groups.set(who, [o]);
  }
  return (
    <>
      <SheetGrab />
      {head}
      <View style={{ flex: 1, alignSelf: "stretch", flexDirection: "row", paddingHorizontal: 10, gap: 8 }}>
        <ScrollView style={{ flex: 1.35 }}>
          {[...groups].map(([who, list]) => (
            <View key={who}>
              {groups.size > 1 && <CascadeLabel text={who} />}
              {list.map((o) => (
                <CascadeOption key={o.model} label={o.name} sub={o.spent?.text ?? null} checked={v.option === o.model} leading={<MakerIcon maker={o.maker} runtime={o.runtimes[0] ?? draft.runtime} size={16} />} onClick={() => set({ model: o.model })} />
              ))}
            </View>
          ))}
          <View style={{ height: 12 }} />
        </ScrollView>
        <Smooth radius={14} style={{ flex: 1, backgroundColor: C.surface }}>
          <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 4 }}>
            {v.runtimes.length > 0 && (
              <>
                <CascadeLabel text={t("android-chat.new.runtime")} />
                {v.runtimes.map((r) => <CascadeOption key={r} label={RUNTIME_LABEL[r] ?? r} sub={null} checked={draft.runtime === r} leading={<MakerIcon maker={null} runtime={r} size={16} />} onClick={() => set({ runtime: r })} />)}
              </>
            )}
            <CascadeLabel text={t("android-chat.new.effort")} />
            {[null, ...v.efforts].map((e) => <CascadeOption key={e ?? ""} label={e ?? t("android-chat.pick.default")} sub={null} checked={(draft.effort ?? null) === e} onClick={() => set({ effort: e })} />)}
            {v.fastAvailable === true && (
              <>
                <CascadeLabel text={t("android-chat.new.speed")} />
                {([null, false, true] as const).map((fast) => (
                  <CascadeOption
                    key={String(fast)}
                    label={fast === true ? "Fast" : fast === false ? t("android-chat.pick.speed.standard") : t("android-chat.pick.speed.follow")}
                    sub={fast === true ? t("android-chat.new.fast.note") : null}
                    checked={(draft.fast ?? null) === fast}
                    onClick={() => set({ fast })}
                  />
                ))}
              </>
            )}
          </ScrollView>
        </Smooth>
      </View>
      {/* The foot: who runs it (the station's pick, most of the time), and 确定. */}
      <View style={{ alignSelf: "stretch", flexDirection: "row", marginBottom: insets.bottom, paddingLeft: 10, paddingRight: 14, paddingTop: 10, paddingBottom: 12, alignItems: "center", gap: 8 }}>
        <Smooth radius={12} style={{ flex: 1, minWidth: 0 }}>
          <Pressable onPress={() => setAccounts(true)} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ paddingHorizontal: 10, paddingVertical: 10, flexDirection: "row", alignItems: "center", gap: 4 }}>
            <T size={14} color={C.muted}>{t("android-chat.new.account")}</T>
            <T size={14} color={v.whoLevel != null ? C.warn : C.ink} numberOfLines={1} style={{ flexShrink: 1, minWidth: 0 }}>{v.who}</T>
            <Icon icon={Icons.ChevronRight} size={14} color={C.muted} />
          </Pressable>
        </Smooth>
        <Smooth radius={19} style={{ backgroundColor: v.changed ? C.ink : C.chip }}>
          <Pressable
            disabled={v.option == null || saving}
            onPress={() => {
              if (!v.changed) { app.sheet = null; return; }
              const sheet = app.sheet;
              app.api(station).pickSave("new").then(
                () => { if (app.sheet === sheet) app.sheet = null; },
                (err: unknown) => { app.toast = t("android-chat.save.failed", { error: why(err) }); },
              );
            }}
            android_ripple={{ color: withAlpha(v.changed ? C.bg : C.ink, 0.1) }}
            style={{ paddingHorizontal: 22, paddingVertical: 9, flexDirection: "row", alignItems: "center", gap: 6 }}
          >
            <BusyIcon busy={saving} solid={v.changed ? C.bg : null} />
            <T size={15} weight="600" color={v.changed ? C.bg : C.ink}>{v.changed ? t("android-chat.new.confirm") : t("android-chat.new.unchanged")}</T>
          </Pressable>
        </Smooth>
      </View>
    </>
  );
}

function CascadeLabel({ text }: { text: string }) {
  const C = useC();
  return <T size={12} color={C.muted} style={{ paddingLeft: 10, paddingTop: 10, paddingBottom: 2 }}>{text}</T>;
}

/** A choice in a column of the picker: the chosen one on the accent's pale ground, its words in the accent and bold. */
function CascadeOption({ label, sub, checked, subColor, leading = null, onClick }: { label: string; sub: string | null; checked: boolean; subColor?: string; leading?: ReactNode | null; onClick: () => void }) {
  const C = useC();
  return (
    <Smooth radius={10} style={{ alignSelf: "stretch", backgroundColor: checked ? C.accentBg : "transparent" }}>
      <Pressable onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ paddingHorizontal: 10, paddingVertical: 10, flexDirection: "row", alignItems: "center", gap: 10 }}>
        {leading}
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={15} color={checked ? C.accentInk : C.ink} weight={checked ? "600" : "400"} numberOfLines={1}>{label}</T>
          {sub != null && <T size={12} color={subColor ?? C.muted} numberOfLines={2}>{sub}</T>}
        </View>
        {checked && <Icon icon={Icons.Check} size={14} color={C.accent} />}
      </Pressable>
    </Smooth>
  );
}

// ── going on with a session the machine kept (web/src/MachineSessions.tsx) ──

/**
 * The offer, when the station's machine kept any sessions of its own Claude Code or Codex (a station from before them
 * offers none): a quiet line under the page's words; its list and a look at one before going on with it are sheets.
 */
function MachineSessionsOffer({ view }: { view: StationView }) {
  const app = useContext(LocalApp);
  const C = useC();
  const [sessions, setSessions] = useState<MachineSession[]>([]);
  useEffect(() => {
    let live = true;
    setSessions([]);
    app.api(view.station).machineSessions().then(
      (list) => { if (live) setSessions(list); },
      () => { if (live) setSessions([]); },
    );
    return () => { live = false; };
  }, [view.station]);
  if (sessions.length === 0) return null;
  return (
    <View style={{ paddingTop: 8 }}>
      <Smooth radius={10}>
        <Pressable onPress={() => openMachineSessions(app, view, sessions)} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ paddingHorizontal: 10, paddingVertical: 6, flexDirection: "row", alignItems: "center", gap: 6 }}>
          <Icon icon={Icons.Monitor} size={14} color={C.muted} />
          <T size={14} color={C.muted}>{t("android-chat.new.machine.offer", { station: view.name || t("android-chat.new.machine.here") })}</T>
        </Pressable>
      </Smooth>
    </View>
  );
}

function openMachineSessions(app: AppState, view: StationView, sessions: MachineSession[]) {
  app.sheet = new SheetSpec(0.7, false, null, null, false, () => <MachineSessionsSheet app={app} view={view} sessions={sessions} />);
}

function MachineSessionsSheet({ app, view, sessions }: { app: AppState; view: StationView; sessions: MachineSession[] }) {
  const C = useC();
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-chat.new.machine.title", { station: view.name || t("android-chat.new.machine.here") })} />
      <T size={13} color={C.muted} style={{ paddingLeft: 20, paddingRight: 20, paddingBottom: 8 }}>{t("android-chat.new.machine.text")}</T>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        {sessions.map((s) => (
          <Pressable key={`${s.runtime}/${s.id}`} onPress={() => lookAtMachineSession(app, view, sessions, s)} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ paddingHorizontal: 20, paddingVertical: 10, flexDirection: "row", alignItems: "center", gap: 12 }}>
            <MakerIcon maker={null} runtime={s.runtime} size={18} />
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} numberOfLines={1}>{s.title ?? s.first ?? ""}</T>
              <T size={12} color={C.muted} numberOfLines={1}>{s.meta ?? ""}</T>
            </View>
            {s.session != null && <T size={12} color={C.muted} numberOfLines={1}>{t("android-chat.new.machine.inApp", { app: APP_NAME })}</T>}
          </Pressable>
        ))}
      </ScrollView>
    </>
  );
}

/** One of them looked at before going on with it: what was said in it, the latest at the bottom. */
function lookAtMachineSession(app: AppState, view: StationView, sessions: MachineSession[], s: MachineSession) {
  app.sheet = new SheetSpec(0.85, false, null, null, false, () => <MachineSessionSheet app={app} view={view} sessions={sessions} s={s} />);
}

function MachineSessionSheet({ app, view, sessions, s }: { app: AppState; view: StationView; sessions: MachineSession[]; s: MachineSession }) {
  const C = useC();
  const [shown, setShown] = useState<{ said: MachineSaid[]; total: number } | null>(null);
  const [error, setError] = useState<string | null>(null);
  useApp((st) => st.doing);
  const busy = app.isDoing("machineSessions.continue", { station: view.station, id: s.id });
  useEffect(() => {
    let live = true;
    app.api(view.station).machineSession(s.runtime, s.id).then(
      ([said, total]) => { if (live) setShown({ said, total }); },
      (e: unknown) => { if (live) setError(e instanceof Error ? e.message : String(e)); },
    );
    return () => { live = false; };
  }, [s.id]);
  const scroll = useRef<ScrollView>(null);
  // Once what was said is in, at its end (once: a later change of size does not move it).
  const toEnd = useRef(false);
  useEffect(() => { if (shown != null) toEnd.current = true; }, [shown]);
  const option = optionOf(view.models, s.model);
  const name = option?.name ?? s.model ?? (RUNTIME_LABEL[s.runtime] ?? s.runtime);
  const left = shown != null ? shown.total - shown.said.length : 0;
  return (
    <>
      <SheetGrab />
      <SheetHead title={s.title ?? s.first ?? ""} />
      <T size={12} color={C.muted} numberOfLines={1} style={{ paddingLeft: 18, paddingRight: 18, paddingBottom: 8 }}>{s.meta ?? ""}</T>
      <ScrollView
        ref={scroll}
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: 16, gap: 18 }}
        onContentSizeChange={() => { if (toEnd.current) { toEnd.current = false; scroll.current?.scrollToEnd({ animated: false }); } }}
      >
        {shown == null && error == null && (
          <View style={{ alignSelf: "stretch", paddingTop: 40, alignItems: "center" }}><WaitLine text={t("common.reading")} /></View>
        )}
        {shown != null && (
          <>
            {left > 0 && <T size={12} color={C.muted} align="center" style={{ alignSelf: "stretch" }}>{t("android-chat.new.machine.more", { n: left })}</T>}
            {shown.said.map((m, i) => m.person ? (
              <View key={i} style={{ alignSelf: "stretch", flexDirection: "row", justifyContent: "flex-end" }}>
                <Smooth radius={18} style={{ maxWidth: 300, backgroundColor: C.bubble, paddingHorizontal: 14, paddingVertical: 9 }}>
                  <T size={15}>{m.text}</T>
                </Smooth>
              </View>
            ) : (
              <View key={i} style={{ gap: 4 }}>
                <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
                  <MakerIcon maker={option?.maker ?? null} runtime={s.runtime} size={16} />
                  <T size={13} weight="600">{name}</T>
                </View>
                <Markdown text={m.text} />
              </View>
            ))}
          </>
        )}
      </ScrollView>
      {error != null && <T size={13} color={C.red} style={{ paddingHorizontal: 20, paddingVertical: 6 }}>{error}</T>}
      <View style={{ alignSelf: "stretch", flexDirection: "row", paddingLeft: 20, paddingRight: 20, paddingTop: 10, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
        <Button label={t("common.back")} primary={false} onClick={() => openMachineSessions(app, view, sessions)} />
        <Button
          label={s.session != null ? t("android-chat.new.machine.open") : t("android-chat.new.machine.continue")}
          primary
          busy={busy}
          onClick={() => {
            setError(null);
            app.api(view.station).continueMachineSession(s.runtime, s.id).then(
              (key) => { app.replace({ kind: "Chat", station: view.station, of: { session: key } }); },
              (e: unknown) => setError(e instanceof Error ? e.message : String(e)),
            );
          }}
        />
      </View>
    </>
  );
}
