// A new chat, after Zork's: say what to do, having picked where it runs
// (station), on what (runtime and model) and how hard it thinks. The first
// message (or file) makes the chat and its agent's session on that station.
import { Key, Plus, Server } from "./icons.tsx";
import { Link } from "react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import { useApi, useStations, type RuntimeKind, type StationView } from "./api.ts";
import { useTopic } from "./core/react.ts";
import type { ChatView } from "./core/shapes.ts";
import { ComposerSlot, useCarryDraft } from "./dock.tsx";
import { profilesPage, StationContext, stationBase, type Station } from "./station.tsx";
import { Button, Chooser, ChooserItem as Item, FirstOne, transitionTo } from "./ui.tsx";
import { AddAccountDialog, MachineLoginOffers, PROFILE_LEAD, type Choice as ProfileKind } from "./pages/Accounts.tsx";
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
  /** What was sent from here, in order: once there is any, the page is the chat's (its messages on their way). */
  const [sent, setSent] = useState<string[]>([]);
  const left = useRef(false);
  // The chat made, read from here before going to it: its page then has its messages at once (from the core, which
  // keeps the topic) instead of showing an empty list until they come — over the relay that can take a second or more.
  const [madeKey, setMadeKey] = useState<string | null>(null);
  const madeChat = useTopic<ChatView>(madeKey ? { topic: "chat", station: station.address, session: madeKey } : null).value;
  const [leaving, setLeaving] = useState(false);
  const [addingProfile, setAddingProfile] = useState(false);
  const [profileKind, setProfileKind] = useState<ProfileKind>("claude-sub");
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
      setMadeKey(key);
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

  const carry = useCarryDraft();
  // The chat pages' one composer (dock.tsx): here in the page, then, once something is sent, at the foot as the chat's.
  const composer = (
    <ComposerSlot variant={sent.length ? "chat" : "new"} station={station} draftKey={`new:${station.address}`} thread={null} sessionKey={null} ensureChat={ensureChat}
      placeholder={sent.length ? "发消息" : "做任何事"} {...(sent.length ? {} : { toolbar })} locked={!runtime || !model} roomy={!sent.length}
      // The first message makes the page the chat's at once: the scene fades, the message is where the chat has it,
      // the composer goes down to where the chat's is. More can follow before the chat is made; they go in order.
      onSending={(text) => {
        if (text === null) return void setSent((all) => all.slice(0, -1));
        if (sent.length === 0) void transitionTo(() => setSent([text]));
        else setSent((all) => [...all, text]);
      }}
      onSent={() => setLeaving(true)} />
  );
  // Once the first message is sent, on to the chat as soon as it has what was sent from here (or, whatever it has, after
  // a while: its page then says it is loading).
  useEffect(() => {
    if (!leaving || !madeKey || left.current) return;
    const go = () => {
      if (left.current) return;
      left.current = true;
      // What is being typed goes on in the chat, in the same composer.
      carry(`${station.address}:${madeKey}`);
      onCreated(station.address, madeKey);
    };
    const shown = madeChat ? madeChat.messages.filter((m) => m.mine).length + madeChat.outbox.length : 0;
    if (shown >= sent.length) return go();
    const late = setTimeout(go, 8000);
    return () => clearTimeout(late);
  }, [leaving, madeKey, madeChat, sent.length]);
  if (sent.length) {
    // Laid out as the chat's page (its bar, its list, its composer, its agent's history beside), so it gives way to it
    // without a move.
    return (
      <div className="session-page" data-panel>
        <div className="session-main">
          <header className="page-bar"><div className="page-bar-title"><h1>{sent[0]}</h1></div></header>
          <section className="chat" aria-label="对话">
            <div className="chat-pane">
              <div className="chat-list">
                {sent.map((text, i) => (
                  <div key={i} className="msg msg-mine" data-author="你" data-role="person">
                    <div className="msg-bubble"><div className="msg-plain">{text}</div></div>
                    <span className="msg-time msg-waiting msg-sending"><span className="spinner" aria-hidden="true" />正在发送</span>
                  </div>
                ))}
              </div>
            </div>
            {composer}
          </section>
        </div>
        <div className="side-panel" aria-hidden="true" />
      </div>
    );
  }
  // Nothing to run a chat with yet: its first step is the page (the composer comes once it can send).
  const blocked = view.overview && sent.length === 0 ? (profiles.length === 0 ? "profile" : view.models.length === 0 ? "models" : null) : null;
  if (blocked) {
    return (
      <div className="new-chat">
        <div className="new-chat-inner">
          <FirstOne art={<Illustration name="no-profile" />} title={blocked === "profile" ? `给 ${station.name || "这台机器"} 添加一个 Profile` : "勾选要用的模型"}
            lead={blocked === "profile" ? PROFILE_LEAD : `${station.name || "这台机器"} 的 Profile 还没有启用模型，勾选之后就能开始对话。`}>
            {blocked === "profile"
              ? <Button variant="primary" icon={Plus} onClick={() => { setProfileKind("claude-sub"); setAddingProfile(true); }}>添加 Profile</Button>
              : <Link className="btn btn-primary" to={profilesPage(station)}>去勾选模型</Link>}
            {stations.length > 1 && (
              <Chooser side="bottom" label={<><Server size={13} />{station.name}</>} title="换一台 station">
                {stations.map((s) => <Item key={s.station} checked={s.station === station.address} onSelect={() => onStation(s.id)}><Server size={13} />{s.name}</Item>)}
              </Chooser>
            )}
            {blocked === "profile" && <MachineLoginOffers logins={view.overview?.machineLogins} onAdd={(c) => { setProfileKind(c); setAddingProfile(true); }} />}
          </FirstOne>
          <AddAccountDialog key={profileKind} initial={profileKind} open={addingProfile} onClose={() => setAddingProfile(false)} />
        </div>
      </div>
    );
  }
  return (
    <div className="new-chat">
      <div className="new-chat-inner">
        <Illustration name="new-chat" />
        <h1 className="new-chat-title">新对话</h1>
        <p className="new-chat-sub">说要做什么。它会在 {station.name || "这台机器"} 上用选好的模型开一个新会话。</p>
        {/* Chosen anyway (it is the person's call), but said: what is sent waits for its quota. */}
        {entry?.spent && (
          <p className="spent-notice" role="status">
            {entry.model} 能用的账号额度都用完了{entry.spent.back ? `，${entry.spent.back}` : ""}。现在发的消息要等额度恢复才会有回复；也可以换一个模型。
          </p>
        )}
        {composer}
        {/* What it waits for, in a line of its own under the composer, kept whether or not there is anything to say. */}
        <p className="new-chat-status">{making ? `正在 ${station.name} 上创建会话…` : !view.overview ? `正在读取 ${station.name} 的 Profile…` : ""}</p>
      </div>
    </div>
  );
}

