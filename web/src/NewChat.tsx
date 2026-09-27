// A new chat, after Zork's: say what to do, having picked where it runs
// (station), on what (runtime and model) and how hard it thinks. The first
// message (or file) makes the chat and its agent's session on that station.
import { Server } from "./icons.tsx";
import { Link } from "react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import { useApi, useStations, type RuntimeKind, type StationView } from "./api.ts";
import { Composer, firstMessage } from "./Chat.tsx";
import { profilesPage, StationContext, stationBase, type Station } from "./station.tsx";
import { Chooser, ChooserItem as Item } from "./ui.tsx";
import { ModelTriple } from "./ModelTriple.tsx";
import { Illustration } from "./brand.tsx";
import { track } from "./telemetry.ts";

interface Choice { runtime: RuntimeKind | ""; model: string; effort: string; profile?: string }
const LAST = "ember.newChat";

function lastChoice(station: string): Partial<Choice> {
  try {
    return (JSON.parse(localStorage.getItem(LAST) ?? "{}") as Record<string, Partial<Choice>>)[station] ?? {};
  } catch {
    return {};
  }
}
function keepChoice(station: string, choice: Choice): void {
  try {
    const all = JSON.parse(localStorage.getItem(LAST) ?? "{}") as Record<string, Choice>;
    localStorage.setItem(LAST, JSON.stringify({ ...all, [station]: choice, last: station }));
  } catch {
    // storage full or blocked: choices are just not remembered
  }
}

/** A new chat in a scope (a workspace, or "local"); `onCreated` gets the station's address and the new item's session (its address). */
export function NewChat({ scope, onCreated }: { scope: string; onCreated(station: string, session: string): void }) {
  const stations = useStations(scope);
  const online = (stations.value ?? []).filter((s) => s.online);
  const [stationId, setStationId] = useState(() => {
    try {
      return (JSON.parse(localStorage.getItem(LAST) ?? "{}") as { last?: string }).last ?? "";
    } catch {
      return "";
    }
  });
  const view = online.find((s) => s.id === stationId) ?? online[0];
  if (!stations.value) {
    // Laid out as the page will be (the composer's place held, the words under it), so nothing moves when it comes.
    return (
      <div className="new-chat"><div className="new-chat-inner">
        <Illustration name="new-chat" /><h1 className="new-chat-title">新对话</h1><p className="new-chat-sub">说要做什么。它会在选好的 station 上用选好的模型开一个新会话。</p>
        <div className="composer-wrap"><div className="composer-box new-chat-held" /></div>
        <p className={`new-chat-status${stations.error ? " field-error" : ""}`}>{stations.error?.message ?? "正在读取 station…"}</p>
      </div></div>
    );
  }
  if (!view) {
    return <div className="new-chat"><div className="new-chat-inner"><Illustration name="station-offline" /><h1 className="new-chat-title">新对话</h1><p className="muted">没有在线的 station。到设置里添加一台，或者启动已添加的 station。</p></div></div>;
  }
  // The composer's files and links belong to the station the chat goes to.
  const station: Station = { id: view.id, name: scope === "local" ? "" : view.name, base: stationBase(view.station), address: view.station, online: true, settings: scope === "local" ? "/settings" : `/w/${scope}/settings` };
  return (
    <StationContext.Provider value={station}>
      <NewChatOn key={view.station} view={view} station={station} stations={online} onStation={setStationId} onCreated={onCreated} />
    </StationContext.Provider>
  );
}

function NewChatOn({ view, station, stations, onStation, onCreated }: { view: StationView; station: Station; stations: StationView[]; onStation(id: string): void; onCreated(station: string, session: string): void }) {
  const api = useApi();
  const profiles = view.overview?.profiles ?? [];
  const [choice, setChoice] = useState<Choice>(() => ({ runtime: "", model: "", effort: "", ...lastChoice(station.id) }));
  // The model first, from what the station's profiles have enabled; then, only when it runs on more than one, the
  // runtime. Which profile runs the chat is the station's account pool's choice. A remembered model or runtime that is
  // no longer there gives way to the first that is.
  const entry = view.models.find((m) => m.model === choice.model) ?? view.models[0];
  const model = entry?.model ?? "";
  const runtimes = entry?.runtimes ?? [];
  const runtime: RuntimeKind | undefined = runtimes.includes(choice.runtime as RuntimeKind) ? (choice.runtime as RuntimeKind) : runtimes[0];
  useEffect(() => {
    if (runtime && runtime !== choice.runtime) setChoice((c) => ({ ...c, runtime, effort: "" }));
  }, [runtime]);
  // The model menu lists what a profile's check found; profiles not checked since the station started are checked now, once.
  const checked = useRef(new Set<string>());
  useEffect(() => {
    for (const p of profiles) {
      if (p.check || checked.current.has(p.id)) continue;
      checked.current.add(p.id);
      void api.checkProfile(p.id).catch(() => {});
    }
  }, [profiles, api]);
  const made = useRef<Promise<{ key: string; thread: number }> | null>(null);
  const [making, setMaking] = useState(false);
  const [sending, setSending] = useState<string | null>(null);
  const pick = (next: Partial<Choice>) => {
    const c = { ...choice, ...next };
    setChoice(c);
    keepChoice(station.id, c);
  };
  const ensureChat = () => {
    if (!runtime || !model) return Promise.reject(new Error("先在 Profile 里启用模型"));
    made.current ??= (async () => {
      setMaking(true);
      const at = performance.now();
      const { key, thread } = await api.newChat({
        runtime, model,
        ...(choice.effort ? { effort: choice.effort } : {}),
        // Kept to a profile only while it still runs the model there.
        ...(choice.profile && entry?.accounts[runtime]?.some((a) => a.id === choice.profile) ? { profile: choice.profile } : {}),
      });
      track("chat_created", { runtime, model, ...(choice.effort ? { effort: choice.effort } : {}), ms: Math.round(performance.now() - at) });
      return { key, thread: thread.id };
    })().catch((error: unknown) => { made.current = null; setMaking(false); throw error; });
    return made.current;
  };
  const toolbar = useMemo(() => (
    <>
      {station.name && (
        <Chooser side="top" label={<><Server size={13} />{station.name}</>} title="在哪台 station 上运行">
          {stations.map((s) => <Item key={s.station} checked={s.station === station.address} onSelect={() => onStation(s.id)}><Server size={13} />{s.name}</Item>)}
        </Chooser>
      )}
      {!runtime || !model ? (
        // Nothing to choose from: the chooser leads to where models are enabled.
        <Link className="chooser" to={profilesPage(station)} title="到 Profile 里勾选可以用的模型">没有可用模型 · 去勾选</Link>
      ) : (
        <ModelTriple side="top" title="用哪个模型、运行时、思考深度和账号" options={view.models}
          value={{ model, runtime, effort: choice.effort || null, profile: choice.profile || null }}
          onPick={(p) => pick({ model: p.model, runtime: p.runtime, effort: p.effort ?? "", profile: p.profile ?? "" })} />
      )}
    </>
  ), [stations, station, view, runtime, choice, model]);

  return (
    <div className="new-chat">
      <div className="new-chat-inner">
        <Illustration name="new-chat" />
        <h1 className="new-chat-title">新对话</h1>
        <p className="new-chat-sub">说要做什么。它会在 {station.name || "这台机器"} 上用选好的模型开一个新会话。</p>
        {!view.overview ? null
          : profiles.length === 0 ? <p className="field-error">这台 station 还没有 Profile，先到 <Link className="inline-link" to={profilesPage(station)}>设置 → Profile</Link> 里加一个。</p>
          : !runtimes.length && <p className="field-error">这台 station 的 Profile 都还没有启用模型。到 <Link className="inline-link" to={profilesPage(station)}>设置 → Profile</Link> 里勾选可以用的模型。</p>}
        {/* Chosen anyway (it is the person's call), but said: what is sent waits for its quota. */}
        {entry?.spent && (
          <p className="spent-notice" role="status">
            {entry.model} 能用的账号额度都用完了{entry.spent.back ? `，${entry.spent.back}` : ""}。现在发的消息要等额度恢复才会有回复；也可以换一个模型。
          </p>
        )}
        {/* The first message, sent: a bubble over the composer until the chat it made takes it (Chat.tsx firstMessage). */}
        {sending !== null && <div className="msg msg-mine new-chat-sent"><div className="msg-bubble" style={{ viewTransitionName: "sent-message" }}><div className="msg-plain">{sending}</div></div></div>}
        <Composer thread={null} sessionKey={null} ensureChat={ensureChat} placeholder="做任何事" toolbar={toolbar} locked={!runtime || !model} roomy
          onSending={(text) => { setSending(text); firstMessage.text = text; }}
          onSent={() => { void made.current?.then(({ key }) => onCreated(station.address, key)); }} />
        {/* What it waits for, in a line of its own under the composer, kept whether or not there is anything to say. */}
        <p className="new-chat-status">{making ? `正在 ${station.name} 上创建会话…` : !view.overview ? `正在读取 ${station.name} 的 Profile…` : ""}</p>
      </div>
    </div>
  );
}

