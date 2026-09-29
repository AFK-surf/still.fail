// A new chat on a narrow screen, as the Android app has it (apps/android/…/screens/NewChat.kt): it rises from the
// bottom; say what to do, having picked where it runs (station), on what (model) and how hard it thinks. The first
// message (or file) makes the session on that station; then the page becomes the chat.
import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { stationApi, useStationCall, useStations, type ModelOption, type RuntimeKind, type StationView } from "../api.ts";
import { RUNTIME_LABEL } from "../format.ts";
import { Server } from "../icons.tsx";
import { sendDraft, toMadeChat } from "../Chat.tsx";
import { keepChoice, keepStation, lastChoice, lastStation, useEnsureChat, type Choice } from "../NewChat.tsx";
import { optionOf } from "../ModelTriple.tsx";
import { StationContext, stationBase, type Station } from "../station.tsx";
import { useNavigate } from "react-router";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import type { Draft } from "./Chat.tsx";
import { useHost } from "./ChatHost.tsx";
import { Button, Illustration, Loading, MakerIcon, ModelMark, NavBar, PickRow } from "./parts.tsx";
import { MachineLoginOffers } from "./Profiles.tsx";
import { Buddy, FirstStation } from "./Stations.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./NewChat.css.ts";
import * as newChatCss from "./styles/new-chat.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as settingsCss from "./styles/settings.css.ts";

export function NewChatScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id);
  const all = stations.value;
  const online = (all ?? []).filter((s) => s.online);
  // The station last started on (or picked) in this workspace, on either screen (../NewChat.tsx keeps it).
  const [picked, setPicked] = useState(() => lastStation(app.entry.id));
  const onStation = (id: string) => { setPicked(id); keepStation(app.entry.id, id); };
  const view = online.find((s) => s.id === picked) ?? online[0];
  return (
    <div className={`${pagesCss.mScreen} ${css.mNewchatScreen}`}>
      <NavBar back="取消" onBack={app.pop} title="新对话" />
      {!all ? <Loading text={stations.error?.message ?? "正在读取 station…"} />
        : !view ? (
          all.length === 0 ? <FirstStation /> : (
            <div className={newChatCss.mNewNone}>
              <Illustration name="station-offline" width={240} />
              <b>没有在线的 station</b>
              <p>在一台机器上打开 ember，它就会连上这个 workspace。</p>
            </div>
          )
        )
        : <NewChatOn key={view.station} view={view} stations={online} onStation={onStation} />}
    </div>
  );
}

function NewChatOn({ view, stations, onStation }: { view: StationView; stations: StationView[]; onStation: (s: string) => void }) {
  const app = useApp();
  // The page's composer is its host's (ChatHost.tsx): kept as this new chat becomes its chat.
  const { draft, use } = useHost();
  const stationCall = useStationCall(view.station);
  const api = useMemo(() => stationApi(stationCall), [stationCall]);
  // What it runs on, as the wide screen keeps it (../NewChat.tsx: per station, the same on both).
  const [choice, setChoice] = useState<Choice>(() => ({ runtime: "", model: "", effort: "", ...lastChoice(view.id) }));
  // The model first, from what the station's profiles have enabled; the runtime only when it runs on more than one. A
  // remembered model or runtime no longer there gives way to the first that is.
  const entry = optionOf(view.models, choice.model) ?? view.models[0];
  const model = entry?.model;
  const runtime = entry?.runtimes.find((r) => r === choice.runtime) ?? entry?.runtimes[0];
  const efforts = runtime ? entry?.efforts[runtime] ?? [] : [];
  const effort = choice.effort && efforts.includes(choice.effort) ? choice.effort : "";
  const pick = (next: Partial<Choice>) => { const c = { ...choice, ...next }; setChoice(c); keepChoice(view.id, c); };
  // The model list is what a profile's check found; profiles not checked since the station started are checked now, once.
  const profiles = view.overview?.profiles ?? [];
  const checked = useRef(new Set<string>());
  useEffect(() => {
    for (const p of profiles) if (!p.check && !checked.current.has(p.id)) { checked.current.add(p.id); api.checkProfile(p.id).catch(() => {}); }
  }, [profiles, api]);
  const navigate = useNavigate();
  const problem = !view.overview ? `正在读取 ${view.name} 的 Profile…`
    : profiles.length === 0 ? null
    : view.models.length === 0 ? "这台 station 的 Profile 都还没有启用模型。点下面的「去勾选」，勾选可以用的模型。" : null;
  // The first message makes the chat as the wide screen's does (../NewChat.tsx's useEnsureChat, then ../Chat.tsx's
  // sendDraft: the message waits in its outbox, its quotes and files with it), and the page becomes it; what follows
  // goes in after it. The chat is started on this station: the next new chat starts here too.
  const ensureChat = useEnsureChat(view.station, entry, runtime, { effort, ...(choice.profile ? { profile: choice.profile } : {}) }, () => onStation(view.id));
  const opened = useRef(false);
  const send = (draft: Draft) => {
    if (!model || !runtime) return draft.setError("先在 Profile 里启用模型");
    void sendDraft(draft, null, ensureChat).then((to) => {
      if (to === null || opened.current) return;
      opened.current = true;
      // The new item's page (its address from now on, until its station's key takes over: ChatScreen), crossfading in
      // above the composer, which stays.
      toMadeChat(() => navigate(`${stationBase(view.station)}/chats/${encodeURIComponent(String(to))}`, { replace: true }), false);
    });
  };
  useLayoutEffect(() => use({ station: view.station, placeholder: "做任何事", offline: false, send }));
  return (
    <>
      <div className={css.mNewBody}>
        <Illustration name="new-chat" width={230} />
        <h2>想让 agent 做什么？</h2>
        <p className={partsCss.mMuted}>说要做什么。它会在 {view.name} 上用选好的模型开一个新会话。</p>
        {problem && <p className={css.mNewProblem} data-wait={!view.overview || undefined}>{problem}</p>}
        {/* No profile yet: adding one is the first step, here (the machine's own logins, when there are any, offered too). */}
        {view.overview && profiles.length === 0 && <NoProfile view={view} />}
      </div>
      {/* Chosen anyway (it is the person's call), but said: what is sent waits for its quota. */}
      {entry?.spent && (
        <p className={css.mNewSpent}>{entry.name} 能用的账号额度都用完了{entry.spent.back ? `，${entry.spent.back}` : ""}。现在发的消息要等额度恢复才会有回复；也可以换一个模型。</p>
      )}
      {/* The choices, then the composer as a floating capsule, as in a chat. */}
      <div className={css.mNewBottom}>
        <div className={css.mChoosers}>
          <Chooser leading={<Server size={14} />} label={view.name} onClick={() => pickStation(app, stations, view.station, onStation)} />
          {!runtime || !model ? (
            // Nothing to choose from: the chooser leads to where models are enabled.
            <Chooser label="没有可用模型 · 去勾选" onClick={() => app.push(app.at(`/s/${view.id}/overview`))} />
          ) : (
            <>
              <Chooser leading={<MakerIcon maker={entry.maker} runtime={runtime} size={14} />} label={entry.name}
                onClick={() => pickModel(app, view, model, (m) => { const rt = m.runtimes.find((r) => r === runtime) ?? m.runtimes[0]!; pick({ runtime: rt as RuntimeKind, model: m.model, effort: rt !== runtime ? "" : effort }); })} />
              {/* The runtime only when the model runs on more than one. */}
              {entry.runtimes.length > 1 && <Chooser leading={<MakerIcon runtime={runtime} size={14} />} label={RUNTIME_LABEL[runtime as RuntimeKind] ?? runtime}
                onClick={() => pickRuntime(app, entry.runtimes, runtime, (rt) => pick({ runtime: rt as RuntimeKind, model, effort: "" }))} />}
              <Chooser label={effort || "默认深度"} onClick={() => pickEffort(app, efforts, effort, (e) => pick({ runtime, model, effort: e }))} />
            </>
          )}
        </div>
      </div>
    </>
  );
}

function Chooser({ leading, label, onClick }: { leading?: ReactNode; label: string; onClick: () => void }) {
  // The same glass as the composer's capsule under it.
  return <button type="button" className={`${css.mChooser} ${pagesCss.mFloating}`} onClick={onClick}>{leading}<span>{label}</span></button>;
}

function pickStation(app: MobileApp, stations: StationView[], current: string, onPick: (s: string) => void) {
  app.sheet({ height: 0.5, content: () => (
    <>
      <SheetGrab /><SheetHead title="在哪台 station 上跑" />
      <div className={sheetsCss.mSheetScroll}>{stations.map((s) => <PickRow key={s.station} label={s.name} sub={s.summary} checked={s.station === current} leading={<Buddy s={s} size={36} />} onClick={() => { onPick(s.id); app.sheet(null); }} />)}</div>
    </>
  ) });
}

function pickModel(app: MobileApp, view: StationView, current: string, onPick: (m: ModelOption) => void) {
  app.sheet({ height: 0.5, content: () => (
    <>
      <SheetGrab /><SheetHead title="用哪个模型" />
      <div className={sheetsCss.mSheetScroll}>
        {view.models.map((m) => (
          <PickRow key={m.model} label={m.name} sub={[m.runtimes.map((r) => RUNTIME_LABEL[r] ?? r).join(" · "), m.spent?.text].filter(Boolean).join(" · ")}
            checked={m.model === current} leading={<ModelMark maker={m.maker} runtime={m.runtimes[0]!} size={36} />} onClick={() => { onPick(m); app.sheet(null); }} />
        ))}
      </div>
    </>
  ) });
}

function pickRuntime(app: MobileApp, runtimes: string[], current: string, onPick: (r: string) => void) {
  app.sheet({ height: 0.36, content: () => (
    <>
      <SheetGrab /><SheetHead title="用哪个运行时" />
      <div className={sheetsCss.mSheetScroll}>{runtimes.map((rt) => <PickRow key={rt} label={RUNTIME_LABEL[rt as RuntimeKind] ?? rt} checked={rt === current} leading={<ModelMark runtime={rt as RuntimeKind} size={36} />} onClick={() => { onPick(rt); app.sheet(null); }} />)}</div>
    </>
  ) });
}

function pickEffort(app: MobileApp, efforts: string[], current: string, onPick: (e: string) => void) {
  app.sheet({ height: 0.48, content: () => (
    <>
      <SheetGrab /><SheetHead title="思考深度" />
      <div className={sheetsCss.mSheetScroll}>
        <PickRow label="默认" checked={current === ""} onClick={() => { onPick(""); app.sheet(null); }} />
        {efforts.map((e) => <PickRow key={e} label={e} checked={current === e} onClick={() => { onPick(e); app.sheet(null); }} />)}
      </div>
    </>
  ) });
}

/** A station with no profile: what one is, adding one, and the machine's own logins as ones to use right away. */
function NoProfile({ view }: { view: StationView }) {
  const app = useApp();
  const station: Station = { id: view.id, name: view.name, online: view.online, address: view.station, base: stationBase(view.station), settings: `/w/${app.entry.id}/settings` };
  return (
    <StationContext.Provider value={station}>
      <p className={css.mNewProblem} data-wait>给 {view.name} 添加一个 Profile。agent 用它来跑模型：一份订阅（Claude、ChatGPT），或者一个模型服务的 key。</p>
      <Button label="添加 Profile" primary onClick={() => app.push(app.at(`/s/${view.id}/profiles/new`))} />
      <div className={`${sheetsCss.mForm} ${settingsCss.mSteps}`} style={{ alignSelf: "stretch", marginTop: 12, padding: 0, textAlign: "left" }}>
        <MachineLoginOffers inForm logins={view.overview?.machineLogins} profiles={view.overview?.profiles ?? []}
          onSignIn={(kind) => app.push(app.at(`/s/${view.id}/profiles/new?kind=${kind}`))} />
      </div>
    </StationContext.Provider>
  );
}
