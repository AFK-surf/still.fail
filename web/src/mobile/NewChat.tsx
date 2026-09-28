// A new chat on a narrow screen, as the Android app has it (apps/android/…/screens/NewChat.kt): it rises from the
// bottom; say what to do, having picked where it runs (station), on what (model) and how hard it thinks. The first
// message (or file) makes the session on that station; then the page becomes the chat.
import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { stationApi, useStationCall, useStations, type ModelOption, type RuntimeKind, type StationView } from "../api.ts";
import { useCall } from "../core/react.ts";
import { RUNTIME_LABEL } from "../format.ts";
import { Server } from "../icons.tsx";
import { toMadeChat } from "../Chat.tsx";
import { transitionTo } from "../ui.tsx";
import { optionOf } from "../ModelTriple.tsx";
import { StationContext, stationBase, type Station } from "../station.tsx";
import { useNavigate } from "react-router";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { BarFrame, type Draft } from "./Chat.tsx";
import { useHost } from "./ChatHost.tsx";
import { Button, Illustration, Loading, MakerIcon, ModelMark, NavBar, PickRow, Spinner } from "./parts.tsx";
import { MachineLoginOffers } from "./Profiles.tsx";
import { Buddy, FirstStation } from "./Stations.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./NewChat.css.ts";
import * as newChatCss from "./styles/new-chat.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as settingsCss from "./styles/settings.css.ts";

/** What the new chat runs on; kept per station for next time. */
interface Choice { runtime: string; model: string; effort: string }
const KEY = "ember.m.newChat";
function lastChoice(station: string): Choice | null {
  try { return (JSON.parse(localStorage.getItem(`${KEY}/${station}`) ?? "null") as Choice | null); } catch { return null; }
}
function keepChoice(station: string, c: Choice) {
  localStorage.setItem(`${KEY}/${station}`, JSON.stringify(c));
  localStorage.setItem(`${KEY}.last`, station);
}

export function NewChatScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id);
  const all = stations.value;
  const online = (all ?? []).filter((s) => s.online);
  const [picked, setPicked] = useState<string | null>(() => localStorage.getItem(`${KEY}.last`));
  const view = online.find((s) => s.station === picked) ?? online[0];
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
        : <NewChatOn key={view.station} view={view} stations={online} onStation={setPicked} />}
    </div>
  );
}

function NewChatOn({ view, stations, onStation }: { view: StationView; stations: StationView[]; onStation: (s: string) => void }) {
  const app = useApp();
  // The page's composer is its host's (ChatHost.tsx): kept as this new chat becomes its chat.
  const { draft, use } = useHost();
  const call = useCall();
  const stationCall = useStationCall(view.station);
  const api = useMemo(() => stationApi(stationCall), [stationCall]);
  const [choice, setChoice] = useState<Choice | null>(() => lastChoice(view.station));
  // The model first, from what the station's profiles have enabled; the runtime only when it runs on more than one. A
  // remembered model or runtime no longer there gives way to the first that is.
  const entry = optionOf(view.models, choice?.model) ?? view.models[0];
  const model = entry?.model;
  const runtime = entry?.runtimes.find((r) => r === choice?.runtime) ?? entry?.runtimes[0];
  const efforts = runtime ? entry?.efforts[runtime] ?? [] : [];
  const effort = choice?.effort && efforts.includes(choice.effort) ? choice.effort : "";
  const pick = (next: Choice) => { setChoice(next); keepChoice(view.station, next); };
  // The model list is what a profile's check found; profiles not checked since the station started are checked now, once.
  const profiles = view.overview?.profiles ?? [];
  const checked = useRef(new Set<string>());
  useEffect(() => {
    for (const p of profiles) if (!p.check && !checked.current.has(p.id)) { checked.current.add(p.id); api.checkProfile(p.id).catch(() => {}); }
  }, [profiles, api]);
  const [making, setMaking] = useState(false);
  /** What was sent from here, in order: once there is any, the page is the chat's (its messages on their way). */
  const [sent, setSent] = useState<string[]>([]);
  const made = useRef<Promise<{ key: string; thread: { id: number } }> | null>(null);
  const queue = useRef<Promise<unknown>>(Promise.resolve());
  const navigate = useNavigate();
  const problem = !view.overview ? `正在读取 ${view.name} 的 Profile…`
    : profiles.length === 0 ? null
    : view.models.length === 0 ? "这台 station 的 Profile 都还没有启用模型。点下面的「去勾选」，勾选可以用的模型。" : null;
  // The first message makes the page the chat's at once: the scene fades, the message is where the chat has it. More
  // can follow before the chat is made: they go in order once it is, and the page gives way to the chat.
  const sentCount = useRef(0);
  const send = (draft: Draft) => {
    const text = draft.text.trim();
    const files = draft.files;
    draft.setText(""); draft.setFiles(() => []); draft.setError(null);
    if (sentCount.current++ === 0) void transitionTo(() => setSent([text]));
    else setSent((all) => [...all, text]);
    if (!made.current) {
      const making = (async () => {
        if (!model || !runtime) throw new Error("先在 Profile 里启用模型");
        setMaking(true);
        try { return await api.newChat({ runtime: runtime as RuntimeKind, model, ...(effort ? { effort } : {}) }); } finally { setMaking(false); }
      })();
      made.current = making;
      making.then(
        // The new item's page, by its agent (its address from now on).
        (m) => toMadeChat(() => navigate(`${stationBase(view.station)}/chats/${encodeURIComponent(m.key)}`, { replace: true })),
        // No chat to send into: what was sent comes back to the composer.
        (error: unknown) => {
          made.current = null;
          sentCount.current = 0;
          setSent((all) => { draft.setText(all.join("\n\n")); return []; });
          draft.setError(error instanceof Error ? error.message : String(error));
        },
      );
    }
    const making = made.current;
    queue.current = queue.current.then(() => making).then((m) =>
      call("chat.send", { station: view.station, thread: m.thread.id, text, attachments: files.flatMap((f) => (f.done ? [f.done] : [])), quotes: [] })).catch(() => {});
  };
  useLayoutEffect(() => use({ station: view.station, placeholder: sent.length ? "发消息" : "做任何事", offline: false, send }));
  if (sent.length) {
    // Laid out as the chat's page (its list and bar; the composer is the host's), so it gives way to it without a move.
    return (
      <div className={`${chatCss.mChat} ${css.mNewAsChat}`}>
        <div className={chatCss.mMessages}>
          {sent.map((text, i) => (
            <div key={i} className={chatCss.mMine}>
              <div className={chatCss.mBubble}>{text}</div>
              <span className={`${chatCss.mMeta} ${chatCss.mWaiting}`}><Spinner size={10} />正在发送</span>
            </div>
          ))}
        </div>
        <BarFrame title={sent[0]!} more={false} />
      </div>
    );
  }
  return (
    <>
      <div className={css.mNewBody}>
        <Illustration name="new-chat" width={230} />
        <h2>想让 agent 做什么？</h2>
        <p className={partsCss.mMuted}>说要做什么。它会在 {view.name} 上用选好的模型开一个新会话。</p>
        {problem && <p className={css.mNewProblem} data-wait={!view.overview || undefined}>{problem}</p>}
        {/* No profile yet: adding one is the first step, here (the machine's own logins, when there are any, offered too). */}
        {view.overview && profiles.length === 0 && <NoProfile view={view} />}
        {making && <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>正在 {view.name} 上创建会话…</p>}
      </div>
      {/* Chosen anyway (it is the person's call), but said: what is sent waits for its quota. */}
      {entry?.spent && (
        <p className={css.mNewSpent}>{entry.name} 能用的账号额度都用完了{entry.spent.back ? `，${entry.spent.back}` : ""}。现在发的消息要等额度恢复才会有回复；也可以换一个模型。</p>
      )}
      {/* The choices, then the composer as a floating capsule, as in a chat. */}
      <div className={css.mNewBottom}>
        <div className={css.mChoosers}>
          <Chooser leading={<Server size={13} />} label={view.name} onClick={() => pickStation(app, stations, view.station, onStation)} />
          {!runtime || !model ? (
            // Nothing to choose from: the chooser leads to where models are enabled.
            <Chooser label="没有可用模型 · 去勾选" onClick={() => app.push(app.at(`/s/${view.id}/overview`))} />
          ) : (
            <>
              <Chooser leading={<MakerIcon maker={entry.maker} runtime={runtime} size={14} />} label={entry.name}
                onClick={() => pickModel(app, view, model, (m) => { const rt = m.runtimes.find((r) => r === runtime) ?? m.runtimes[0]!; pick({ runtime: rt, model: m.model, effort: rt !== runtime ? "" : effort }); })} />
              {/* The runtime only when the model runs on more than one. */}
              {entry.runtimes.length > 1 && <Chooser leading={<MakerIcon runtime={runtime} size={13} />} label={RUNTIME_LABEL[runtime as RuntimeKind] ?? runtime}
                onClick={() => pickRuntime(app, entry.runtimes, runtime, (rt) => pick({ runtime: rt, model, effort: "" }))} />}
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
      <div className={sheetsCss.mSheetScroll}>{stations.map((s) => <PickRow key={s.station} label={s.name} sub={s.summary} checked={s.station === current} leading={<Buddy s={s} size={36} />} onClick={() => { onPick(s.station); app.sheet(null); }} />)}</div>
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
