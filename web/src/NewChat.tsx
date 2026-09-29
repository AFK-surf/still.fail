// A new chat, after Zork's: say what to do, having picked where it runs
// (station), on what (runtime and model) and how hard it thinks. The first
// message (or file) makes the chat and its agent's session on that station.
import { Key, Plus, Server } from "./icons.tsx";
import { Link } from "react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import { useApi, useChatSend, useStations, type ModelOption, type RuntimeKind, type StationView } from "./api.ts";
import { ComposerSlot, useCarryDraft } from "./dock.tsx";
import { LOCAL_STATION, profilesPage, StationContext, stationBase, type Station } from "./station.tsx";
import { Button, Chooser, ChooserItem as Item, FirstOne, Tip } from "./ui.tsx";
import { AddAccountDialog, MachineLoginOffers, PROFILE_LEAD, type Choice as ProfileKind } from "./pages/Accounts.tsx";
import { ModelTriple, optionOf } from "./ModelTriple.tsx";
import { Illustration } from "./brand.tsx";
import { track } from "./telemetry.ts";
import { keepTabs } from "./chatTabs.ts";
import * as css from "./NewChat.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import { MachineSessions } from "./MachineSessions.tsx";
import { composerText } from "./Chat.css.ts";
import { notSent, sendingFirst } from "./madeChat.ts";
import { OVER_DOCK } from "./Chat.tsx";

/** What a new chat runs on, kept per station (its id) for next time, on either screen (the phone's, mobile/NewChat.tsx). */
export interface Choice { runtime: RuntimeKind | ""; model: string; effort: string; profile?: string }
const LAST = "stillfail.newChat";

export function lastChoice(station: string): Partial<Choice> {
  try {
    return (JSON.parse(localStorage.getItem(LAST) ?? "{}") as Record<string, Partial<Choice>>)[station] ?? {};
  } catch {
    return {};
  }
}
export function keepChoice(station: string, choice: Choice): void {
  try {
    const all = JSON.parse(localStorage.getItem(LAST) ?? "{}") as Record<string, Choice>;
    localStorage.setItem(LAST, JSON.stringify({ ...all, [station]: choice }));
  } catch {
    // storage full or blocked: choices are just not remembered
  }
}
/** The station a scope's last chat was started on (or last picked there); `last` is what older pages kept, for any scope. */
export function lastStation(scope: string): string {
  try {
    const all = JSON.parse(localStorage.getItem(LAST) ?? "{}") as { last?: string; lastIn?: Record<string, string> };
    return all.lastIn?.[scope] ?? all.last ?? "";
  } catch {
    return "";
  }
}
export function keepStation(scope: string, station: string): void {
  try {
    const all = JSON.parse(localStorage.getItem(LAST) ?? "{}") as { lastIn?: Record<string, string> };
    localStorage.setItem(LAST, JSON.stringify({ ...all, last: station, lastIn: { ...all.lastIn, [scope]: station } }));
  } catch {
    // storage full or blocked: the first online station is taken
  }
}

/** A new chat in a scope (a workspace, or "local"); `onCreated` gets the station's address and the new item's session (its address). */
export function NewChat({ scope, onCreated }: { scope: string; onCreated(station: string, session: string): void }) {
  const stations = useStations(scope);
  const online = (stations.value ?? []).filter((s) => s.online);
  const [stationId, setStationId] = useState(() => lastStation(scope));
  const onStation = (id: string) => {
    setStationId(id);
    keepStation(scope, id);
  };
  const view = online.find((s) => s.id === stationId) ?? online[0];
  if (!stations.value) {
    // The station it will most likely be, by the one last written to (its draft comes with it).
    const address = scope === "local" ? "local" : `${scope}/${stationId}`;
    const held: Station = scope === "local" ? LOCAL_STATION : { id: stationId, name: "", base: stationBase(address), address, online: true, settings: `/w/${scope}/settings` };
    // Laid out as the page will be (the composer's place held, the words under it), so nothing moves when it comes.
    return (
      <div className={css.newChat}><div className={css.newChatInner}>
        <Illustration name="new-chat" /><h1 className={css.newChatTitle}>新对话</h1><p className={css.newChatSub}>说要做什么。它会在选好的 station 上用选好的模型开一个新会话。</p>
        {/* The composer itself (dock.tsx), locked until there is a station to write to: it goes on from the page before
            without leaving the screen for as long as the stations take to come (the first time the page is opened). */}
        <ComposerSlot variant="new" station={held} draftKey={`new:${held.address}`} thread={null} sessionKey={null} placeholder="做任何事" locked roomy />
        <p className={`${css.newChatStatus}${stations.error ? ` ${controlsCss.fieldError}` : ""}`}>{stations.error?.message ?? "正在读取 station…"}</p>
      </div></div>
    );
  }
  if (!view) {
    return <div className={css.newChat}><div className={css.newChatInner}><Illustration name="station-offline" /><h1 className={css.newChatTitle}>新对话</h1><p className={shellCss.muted}>没有在线的 station。到设置里添加一台，或者启动已添加的 station。</p></div></div>;
  }
  // The composer's files and links belong to the station the chat goes to.
  const station: Station = { id: view.id, name: scope === "local" ? "" : view.name, base: stationBase(view.station), address: view.station, online: true, settings: scope === "local" ? "/settings" : `/w/${scope}/settings` };
  return (
    <StationContext.Provider value={station}>
      <NewChatOn key={view.station} view={view} station={station} stations={online} onStation={onStation} onCreated={onCreated} />
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
  const entry = optionOf(view.models, choice.model) ?? view.models[0];
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
  const [addingProfile, setAddingProfile] = useState(false);
  const [profileKind, setProfileKind] = useState<ProfileKind>("claude-sub");
  const pick = (next: Partial<Choice>) => {
    const c = { ...choice, ...next };
    setChoice(c);
    keepChoice(station.id, c);
  };
  // The chat is started here: the next new chat starts here too.
  const ensureChat = useEnsureChat(station.address, entry, runtime, choice, () => onStation(station.id));
  const toolbar = useMemo(() => (
    <>
      {station.name && (
        <Chooser side="top" label={<><Server size={14} />{station.name}</>} title="在哪台 station 上运行">
          {stations.map((s) => <Item key={s.station} checked={s.station === station.address} onSelect={() => onStation(s.id)}><Server size={14} />{s.name}</Item>)}
        </Chooser>
      )}
      {!runtime || !model ? (
        // Nothing to choose from: the chooser leads to where models are enabled.
        <Tip label="到 Profile 里勾选可以用的模型"><Link className={chatCss.chooser} to={profilesPage(station)}>没有可用模型 · 去勾选</Link></Tip>
      ) : (
        <ModelTriple side="top" quietAccount title="用哪个模型、运行时、思考深度和账号" options={view.models}
          value={{ model, runtime, effort: choice.effort || null, profile: choice.profile || null }}
          onPick={(p) => pick({ model: p.model, runtime: p.runtime, effort: p.effort ?? "", profile: p.profile ?? "" })} />
      )}
    </>
  ), [stations, station, view, runtime, choice, model]);

  const carry = useCarryDraft();
  // The chat pages' one composer (dock.tsx): here in the page, then, once the first message is sent, in the chat's page,
  // where that message already waits for the chat to be made.
  const composer = (
    <ComposerSlot variant="new" station={station} draftKey={`new:${station.address}`} thread={null} sessionKey={null} ensureChat={ensureChat}
      placeholder="做任何事" toolbar={toolbar} locked={!runtime || !model} roomy
      // Its words stay where they were until the chat's page takes them (../madeChat.ts), over the composer.
      onSending={(text) => {
        const field = document.querySelector<HTMLElement>(`[data-made-composer] .${composerText}`);
        const layer = field?.closest<HTMLElement>("[data-made-composer]")?.offsetParent;
        if (text === null) notSent();
        else if (field && layer instanceof HTMLElement) sendingFirst(field, text, layer, OVER_DOCK);
      }}
      onSent={(to) => {
        const key = String(to);
        // What is being typed goes on in the chat, in the same composer.
        carry(`${station.address}:${key}`);
        // Made here, the chat opens without its agent's history beside: it is opened from the agent when wanted.
        keepTabs(`${station.address}:${key}`, { tabs: [], active: null });
        onCreated(station.address, key);
      }} />
  );
  // Nothing to run a chat with yet: its first step is the page (the composer comes once it can send).
  const blocked = view.overview ? (profiles.length === 0 ? "profile" : view.models.length === 0 ? "models" : null) : null;
  if (blocked) {
    return (
      <div className={css.newChat}>
        <div className={css.newChatInner}>
          <FirstOne art={<Illustration name="no-profile" />} title={blocked === "profile" ? `给 ${station.name || "这台机器"} 添加一个 Profile` : "勾选要用的模型"}
            lead={blocked === "profile" ? PROFILE_LEAD : `${station.name || "这台机器"} 的 Profile 还没有启用模型，勾选之后就能开始对话。`}>
            {blocked === "profile"
              ? <Button variant="primary" icon={Plus} onClick={() => { setProfileKind("claude-sub"); setAddingProfile(true); }}>添加 Profile</Button>
              : <Link className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} to={profilesPage(station)}>去勾选模型</Link>}
            {stations.length > 1 && (
              <Chooser side="bottom" label={<><Server size={14} />{station.name}</>} title="换一台 station">
                {stations.map((s) => <Item key={s.station} checked={s.station === station.address} onSelect={() => onStation(s.id)}><Server size={14} />{s.name}</Item>)}
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
    <div className={css.newChat}>
      <div className={css.newChatInner}>
        {/* What leaves as the chat comes (../madeChat.ts): the scene above the composer out of view, what is by it where it is. */}
        <Illustration name="new-chat" data-made-leave="up" />
        <h1 className={css.newChatTitle} data-made-leave="up">新对话</h1>
        <p className={css.newChatSub} data-made-leave="up">说要做什么。它会在 {station.name || "这台机器"} 上用选好的模型开一个新会话。</p>
        {/* Chosen anyway (it is the person's call), but said: what is sent waits for its quota. */}
        {entry?.spent && (
          <p className={css.spentNotice} role="status" data-made-leave="up">
            {entry.name} 能用的账号额度都用完了{entry.spent.back ? `，${entry.spent.back}` : ""}。现在发的消息要等额度恢复才会有回复；也可以换一个模型。
          </p>
        )}
        {composer}
        {/* What it waits for, in a line of its own under the composer, kept whether or not there is anything to say. */}
        <p className={css.newChatStatus} data-made-leave="fade">{!view.overview ? `正在读取 ${station.name} 的 Profile…` : ""}</p>
        {/* Out of the page's flow: it comes once the station has said what there is, and would move the composer. */}
        <div className={css.newChatOffer} data-made-leave="fade">
          <MachineSessions models={view.models} onContinued={(key) => {
            keepTabs(`${station.address}:${key}`, { tabs: [], active: null });
            onCreated(station.address, key);
          }} />
        </div>
      </div>
    </div>
  );
}

/**
 * What makes a new chat with its first message, on either screen (the phone's, mobile/NewChat.tsx): on the station at
 * `address`, the model `entry` on `runtime`, with the effort chosen and the profile chosen while it still runs the model
 * there. The core has it at once (its page, its row, the message waiting in it); the station makes it behind it. Made
 * once: what is sent meanwhile goes to the same chat; if it could not be made, the next message tries again.
 */
export function useEnsureChat(address: string, entry: ModelOption | undefined, runtime: RuntimeKind | undefined, choice: Pick<Choice, "effort" | "profile">, onMade: () => void) {
  const chats = useChatSend(address);
  const made = useRef<Promise<{ key: string; thread: string }> | null>(null);
  return () => {
    const model = entry?.model;
    if (!runtime || !model) return Promise.reject(new Error("先在 Profile 里启用模型"));
    made.current ??= (async () => {
      const { key } = await chats.create({
        runtime, model,
        ...(choice.effort ? { effort: choice.effort } : {}),
        // Kept to a profile only while it still runs the model there.
        ...(choice.profile && entry.accounts[runtime]?.some((a) => a.id === choice.profile) ? { profile: choice.profile } : {}),
      });
      track("chat_created", { runtime, model, ...(choice.effort ? { effort: choice.effort } : {}) });
      onMade();
      return { key, thread: key };
    })().catch((error: unknown) => { made.current = null; throw error; });
    return made.current;
  };
}
