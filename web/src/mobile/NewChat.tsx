// A new chat on a narrow screen, as the Android app has it (apps/android/…/screens/NewChat.kt): it rises from the
// bottom; say what to do, having picked where it runs (station), on what (model) and how hard it thinks. The first
// message (or file) makes the session on that station; then the page becomes the chat.
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { stationApi, useStationCall, useStations, type ModelOption, type RuntimeKind, type StationView } from "../api.ts";
import { useCall } from "../core/react.ts";
import { RUNTIME_LABEL } from "../format.ts";
import { Server } from "../icons.tsx";
import { firstMessage, toFirstMessage } from "../Chat.tsx";
import { stationBase } from "../station.tsx";
import { useNavigate } from "react-router";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { ComposerBar, DraftExtras, openAttach, useDraft, useUpload } from "./Chat.tsx";
import { Illustration, Loading, MakerIcon, ModelMark, NavBar, PickRow } from "./parts.tsx";

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
    <div className="m-screen m-newchat-screen">
      <NavBar back="取消" onBack={app.pop} title="新对话" />
      {!all ? <Loading text={stations.error?.message ?? "正在读取 station…"} />
        : !view ? (
          <div className="m-new-none">
            <Illustration name="station-offline" width={240} />
            <b>没有在线的 station</b>
            <p>在一台机器上打开 ember，它就会连上这个 workspace。</p>
          </div>
        )
        : <NewChatOn key={view.station} view={view} stations={online} onStation={setPicked} />}
    </div>
  );
}

function NewChatOn({ view, stations, onStation }: { view: StationView; stations: StationView[]; onStation: (s: string) => void }) {
  const app = useApp();
  const draft = useDraft();
  const call = useCall();
  const stationCall = useStationCall(view.station);
  const api = useMemo(() => stationApi(stationCall), [stationCall]);
  const upload = useUpload(draft, view.station);
  const [choice, setChoice] = useState<Choice | null>(() => lastChoice(view.station));
  // The model first, from what the station's profiles have enabled; the runtime only when it runs on more than one. A
  // remembered model or runtime no longer there gives way to the first that is.
  const entry = view.models.find((m) => m.model === choice?.model) ?? view.models[0];
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
  const [sending, setSending] = useState<string | null>(null);
  const navigate = useNavigate();
  const problem = !view.overview ? `正在读取 ${view.name} 的 Profile…`
    : profiles.length === 0 ? "这台 station 还没有 Profile，先在电脑上到 设置 → Profile 里加一个。"
    : view.models.length === 0 ? "这台 station 的 Profile 都还没有启用模型。点下面的「去勾选」，勾选可以用的模型。" : null;
  const send = () => {
    const text = draft.text.trim();
    const files = draft.files;
    draft.setText(""); draft.setFiles(() => []); draft.setError(null);
    draft.setStarting(true);
    setSending(text); firstMessage.text = text;
    void (async () => {
      let made: { key: string; thread: { id: number } };
      try {
        if (!model || !runtime) throw new Error("先在 Profile 里启用模型");
        setMaking(true);
        made = await api.newChat({ runtime: runtime as RuntimeKind, model, ...(effort ? { effort } : {}) });
      } catch (error) {
        // No chat to send into: the draft comes back.
        draft.setText(text); draft.setFiles(() => files); draft.setError(error instanceof Error ? error.message : String(error));
        setSending(null); firstMessage.text = null;
        return;
      } finally {
        draft.setStarting(false);
        setMaking(false);
      }
      call("chat.send", { station: view.station, thread: made.thread.id, text, attachments: files.flatMap((f) => (f.done ? [f.done] : [])), quotes: [] }).catch(() => {});
      // The new item's page, by its agent (its address from now on).
      // Its first message the anchor: the bubble over the composer moves to its place in the chat.
      toFirstMessage(() => navigate(`${stationBase(view.station)}/chats/${encodeURIComponent(made.key)}`, { replace: true }));
    })();
  };
  return (
    <>
      <div className="m-new-body">
        <Illustration name="new-chat" width={230} />
        <h2>想让 agent 做什么？</h2>
        <p className="m-muted">说要做什么。它会在 {view.name} 上用选好的模型开一个新会话。</p>
        {problem && <p className="m-new-problem" data-wait={!view.overview || undefined}>{problem}</p>}
        {making && <p className="m-muted m-small">正在 {view.name} 上创建会话…</p>}
        {sending !== null && <div className="m-mine m-new-sent"><div className="m-bubble" style={{ viewTransitionName: "sent-message" }}>{sending}</div></div>}
      </div>
      {/* Chosen anyway (it is the person's call), but said: what is sent waits for its quota. */}
      {entry?.spent && (
        <p className="m-new-spent">{entry.model} 能用的账号额度都用完了{entry.spent.back ? `，${entry.spent.back}` : ""}。现在发的消息要等额度恢复才会有回复；也可以换一个模型。</p>
      )}
      {/* The choices, then the composer as a floating capsule, as in a chat. */}
      <div className="m-new-bottom">
        <div className="m-choosers">
          <Chooser leading={<Server size={13} />} label={view.name} onClick={() => pickStation(app, stations, view.station, onStation)} />
          {!runtime || !model ? (
            // Nothing to choose from: the chooser leads to where models are enabled.
            <Chooser label="没有可用模型 · 去勾选" onClick={() => app.push(app.at(`/s/${view.id}/overview`))} />
          ) : (
            <>
              <Chooser leading={<MakerIcon maker={entry.maker} runtime={runtime} size={14} />} label={model}
                onClick={() => pickModel(app, view, model, (m) => { const rt = m.runtimes.find((r) => r === runtime) ?? m.runtimes[0]!; pick({ runtime: rt, model: m.model, effort: rt !== runtime ? "" : effort }); })} />
              {/* The runtime only when the model runs on more than one. */}
              {entry.runtimes.length > 1 && <Chooser leading={<MakerIcon runtime={runtime} size={13} />} label={RUNTIME_LABEL[runtime as RuntimeKind] ?? runtime}
                onClick={() => pickRuntime(app, entry.runtimes, runtime, (rt) => pick({ runtime: rt, model, effort: "" }))} />}
              <Chooser label={effort || "默认深度"} onClick={() => pickEffort(app, efforts, effort, (e) => pick({ runtime, model, effort: e }))} />
            </>
          )}
        </div>
        <div className="m-floating m-composer-capsule" onClick={(e) => { if (e.target === e.currentTarget) draft.bumpFocus(); }}
          onPaste={(e) => { if (e.clipboardData.files.length) { e.preventDefault(); upload(e.clipboardData.files); } }}
          onDragOver={(e) => { if (e.dataTransfer.types.includes("Files")) e.preventDefault(); }}
          onDrop={(e) => { if (e.dataTransfer.files.length) { e.preventDefault(); upload(e.dataTransfer.files); } }}>
          <DraftExtras draft={draft} />
          <ComposerBar draft={draft} placeholder="做任何事" onPlus={() => openAttach(app, upload)} onType={() => {}} onSend={send} />
          {draft.error && <p className="m-error m-composer-error">{draft.error}</p>}
        </div>
      </div>
    </>
  );
}

function Chooser({ leading, label, onClick }: { leading?: ReactNode; label: string; onClick: () => void }) {
  // The same glass as the composer's capsule under it.
  return <button type="button" className="m-chooser m-floating" onClick={onClick}>{leading}<span>{label}</span></button>;
}

function pickStation(app: MobileApp, stations: StationView[], current: string, onPick: (s: string) => void) {
  app.sheet({ height: 0.5, content: () => (
    <>
      <SheetGrab /><SheetHead title="在哪台 station 上跑" />
      <div className="m-sheet-scroll">{stations.map((s) => <PickRow key={s.station} label={s.name} checked={s.station === current} onClick={() => { onPick(s.station); app.sheet(null); }} />)}</div>
    </>
  ) });
}

function pickModel(app: MobileApp, view: StationView, current: string, onPick: (m: ModelOption) => void) {
  app.sheet({ height: 0.5, content: () => (
    <>
      <SheetGrab /><SheetHead title="用哪个模型" />
      <div className="m-sheet-scroll">
        {view.models.map((m) => (
          <PickRow key={m.model} label={m.model} sub={[m.runtimes.map((r) => RUNTIME_LABEL[r] ?? r).join(" · "), m.spent?.text].filter(Boolean).join(" · ")}
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
      <div className="m-sheet-scroll">{runtimes.map((rt) => <PickRow key={rt} label={RUNTIME_LABEL[rt as RuntimeKind] ?? rt} checked={rt === current} onClick={() => { onPick(rt); app.sheet(null); }} />)}</div>
    </>
  ) });
}

function pickEffort(app: MobileApp, efforts: string[], current: string, onPick: (e: string) => void) {
  app.sheet({ height: 0.48, content: () => (
    <>
      <SheetGrab /><SheetHead title="思考深度" />
      <div className="m-sheet-scroll">
        <PickRow label="默认" checked={current === ""} onClick={() => { onPick(""); app.sheet(null); }} />
        {efforts.map((e) => <PickRow key={e} label={e} checked={current === e} onClick={() => { onPick(e); app.sheet(null); }} />)}
      </div>
    </>
  ) });
}
