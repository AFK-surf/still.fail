// An agent's execution history on a narrow screen, as the Android app has it (apps/android/…/screens/History.kt): a
// sheet that drags between half and full height. What it received and what it sent are drawn alike (a line, then the
// words beside a bar); what it did in between is grouped, each group opening to its commands and output; its details
// (how it runs, what it used, the station). Changing how it runs is a page of its own.
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useParams } from "react-router";
import { stationApi, useApi, useChat, useHistory, useHistoryOlder, useHost, useStationCall, useStations, type ChatAgent, type HistoryGroup, type HistoryItem, type HistoryPhase, type HistoryStep, type HistoryView, type ModelOption, type Place, type RunnableProfile } from "../api.ts";
import { ArrowRight, Check, ChevronDown, ChevronRight, Received, Send, Stop, Unplug } from "../icons.tsx";
import { modelName, optionOf } from "../ModelTriple.tsx";
import { Prose } from "../Prose.tsx";
import { useStickToBottom } from "../scroll.ts";
import { useOlderOnScroll } from "../Chat.tsx";
import { stationBase, useStation } from "../station.tsx";
import { SheetGrab, useApp, type MobileApp } from "./app.tsx";
import { GroupLabel, MakerIcon, Mark, ModelMark, NavBar, ProviderMark, QuotaRing, QuotaRings, Ring, Seg, SlackMark, Spinner, stateOf, type Icon } from "./parts.tsx";
import * as partsCss from "./styles/parts.css.ts";
import * as css from "./History.css.ts";
import { ToolCall, ToolResult } from "../ToolStep.tsx";
import * as toolCss from "../ToolStep.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as historyCss from "./styles/history.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as settingsCss from "./styles/settings.css.ts";

/** Opens an agent's execution history over the item's page it belongs to; `entry`: the transcript entry to open at. */
export function openHistory(app: MobileApp, station: string, chat: string, key: string, entry?: number) {
  app.sheet({ height: 0.55, draggable: true, content: () => <HistorySheet station={station} chat={chat} agentKey={key} entry={entry} /> });
}

function HistorySheet({ station, chat, agentKey, entry }: { station: string; chat: string; agentKey: string; entry: number | undefined }) {
  const view = useChat(station, { session: chat });
  const history = useHistory(station, agentKey).value;
  const [tab, setTab] = useState(0);
  const agent = view.value?.agents.find((a) => a.session.key === agentKey);
  if (!agent) return <><SheetGrab /><p className={`${partsCss.mMuted} ${partsCss.mPad18}`}>{view.error?.message ?? "正在读取…"}</p></>;
  const s = agent.session;
  return (
    <>
      <SheetGrab />
      <div className={css.mHHead}>
        <ModelMark maker={s.maker} runtime={s.runtime} size={20} state={stateOf(agent.badge)} />
        <b>{s.agentText}</b>
        <Actions station={station} agent={agent} />
        <Seg options={["步骤", "详情"]} selected={tab} onSelect={setTab} />
      </div>
      <Summary agent={agent} />
      <div className={css.mHBody}>
        {tab === 0 ? <Steps station={station} chat={chat} agent={agent} history={history} entry={entry} /> : <Details station={station} chat={chat} agent={agent} history={history} />}
      </div>
    </>
  );
}

/** What can be done to it right now: stop a turn, release an idle process. */
function Actions({ station, agent }: { station: string; agent: ChatAgent }) {
  const app = useApp();
  const api = useStationApi(station);
  const s = agent.session;
  return (
    <>
      {(agent.status === "running" || agent.status === "queued") && <Act icon={Stop} label="停止" run={() => api.stop(s.key).then(() => app.toast("已请求停止"))} />}
      {s.process === "warm" && <Act icon={Unplug} label="释放进程" run={() => api.evict(s.key).then(() => app.toast("已释放进程"))} />}
    </>
  );
}

function Act({ icon: I, label, run }: { icon: Icon; label: string; run: () => Promise<unknown> }) {
  const app = useApp();
  const [busy, setBusy] = useState(false);
  return (
    <button type="button" className={css.mHAct} disabled={busy} aria-label={label}
      onClick={() => { setBusy(true); run().catch((e: unknown) => app.toast(e instanceof Error ? e.message : String(e))).finally(() => setBusy(false)); }}>
      <I size={14} />
    </button>
  );
}

/** A station's API by its address: a sheet lies over the page, outside its station's context. */
function useStationApi(station: string) {
  const call = useStationCall(station);
  return useMemo(() => stationApi(call), [call]);
}

/** The head's short line: only what is worth a look now (an account signed out, a quota running out, the disk filling up). */
function Summary({ agent }: { agent: ChatAgent }) {
  if (!agent.attention.length) return <div style={{ height: 8 }} />;
  return (
    <div className={css.mHSummary}>
      {agent.attention.map((a, i) => a.quota
        ? <span key={i} className={partsCss.mQuotaWindow}><QuotaRing left={a.quota.left} level={a.quota.level} /><i>{a.quota.mark}</i></span>
        : <span key={i} className={a.kind === "disk" ? css.mWarn : partsCss.mRed}>{a.text}</span>)}
    </div>
  );
}

function Steps({ station, chat, agent, history, entry }: { station: string; chat: string; agent: ChatAgent; history: HistoryView | undefined; entry: number | undefined }) {
  const list = useRef<HTMLDivElement>(null);
  // It opens at its newest, and follows new steps while the reader stays there.
  useStickToBottom(list, ".m-h-line");
  const [marked, setMarked] = useState<string | null>(null);
  const items = history?.items ?? [];
  // Only its latest entries come first: the pages before them load as the reader nears the top.
  const older = useHistoryOlder(station, agent.session.key);
  useOlderOnScroll(list, history?.more ?? false, items[0]?.key, older);
  // Opened at an entry (an activity row): that item, near the top, for a moment marked. One before what is loaded: the
  // pages before come first.
  const placed = useRef(false);
  useEffect(() => {
    if (placed.current || !history || entry === undefined) return;
    const at = items.findIndex((it) => it.entries.length === 2 && entry >= it.entries[0]! && entry <= it.entries[1]!);
    if (at < 0 && history.more && entry < (items[0]?.entries[0] ?? 0)) {
      void older().catch(() => { placed.current = true; });
      return;
    }
    placed.current = true;
    if (at < 0) return;
    const el = list.current?.querySelector<HTMLElement>(`[data-item="${at}"]`);
    const pane = list.current;
    if (!el || !pane) return;
    // Once the pages just loaded are laid out (the pane holds its bottom through them until then).
    requestAnimationFrame(() => requestAnimationFrame(() => {
      pane.dispatchEvent(new WheelEvent("wheel"));
      pane.scrollTop += el.getBoundingClientRect().top - pane.getBoundingClientRect().top - 24;
    }));
    setMarked(items[at]!.key);
    const timer = setTimeout(() => setMarked(null), 1600);
    return () => clearTimeout(timer);
  }, [history]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!history) return <Edge text="正在读取执行历史…" />;
  if (history.empty) return <Edge text={history.edge} />;
  return (
    <div className={css.mHSteps} ref={list}>
      <Edge text={history.edge} />
      {items.map((item, i) => (
        <div key={item.key} className={`m-h-line ${css.mHItem}`} data-item={i} data-marked={item.key === marked || undefined}>
          <Item item={item} station={station} chat={chat} agent={agent} />
        </div>
      ))}
      {history.live.map((step) => <div key={`live/${step.id}`} className={`m-h-line ${css.mHLive}`}>{step.text}</div>)}
      {history.phase && <div className="m-h-line"><PhaseLine phase={history.phase} /></div>}
    </div>
  );
}

function Edge({ text }: { text: string }) {
  return <p className={css.mHEdge}>{text}</p>;
}

function Item({ item, station, chat, agent }: { item: HistoryItem; station: string; chat: string; agent: ChatAgent }) {
  const app = useApp();
  const body = item.body;
  switch (body.kind) {
    case "received":
      return (
        <div className={css.mHReceived}>
          {body.content.note && <Message icon={Received} label={<>收到来自 <b>ember</b> 的提醒</>} text={body.content.note} full={<p className={chatCss.mPlain}>{body.content.note}</p>} />}
          {body.content.messages.map((m) => (
            <Message key={m.key} icon={Received}
              label={<>收到来自 <b>{m.from.name}</b> 的消息{m.place && <> · <PlaceMark station={station} chat={chat} place={m.place} /></>}</>}
              text={m.text} full={<p className={chatCss.mPlain}>{m.text}</p>} />
          ))}
        </div>
      );
    case "post":
      return (
        <Message icon={Send}
          label={<>发送到 {body.content.place ? <PlaceMark station={station} chat={chat} place={body.content.place} /> : <span className={css.mHPlace}><SlackMark size={12} /><b> Slack</b></span>}
            {body.content.block && <Pill text="Block" tone="blue" />}{body.content.failed && <Pill text="发送失败" tone="red" />}</>}
          text={body.content.text} full={<div className={chatCss.mMarkdown}><Prose>{body.content.text}</Prose></div>} />
      );
    case "mark":
      return <p className={css.mHMark}>{body.content.text}</p>;
    case "text":
      return (
        <div className={body.content.subagent ? css.mHSub : undefined}>
          <Brief text={body.content.text} open={() => app.reader({ label: <span className={partsCss.mMuted}>{agent.session.agentText} 写道</span>, content: <div className={chatCss.mMarkdown}><Prose>{body.content.text}</Prose></div> })} />
        </div>
      );
    case "group":
      return <Group g={body.content} />;
  }
}

/** Markdown as one run of plain words, for a brief: no fences, headings, emphasis or line breaks. */
function plain(text: string): string {
  return text.replace(/```[^\n]*/g, " ").replace(/^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+/gm, "").replace(/\*\*|__|`/g, "").replace(/\s+/g, " ").trim();
}

/** What an entry says, in brief: its words as plain text, two lines at most. A tap opens it in full. */
function Brief({ text, open }: { text: string; open: () => void }) {
  return <button type="button" className={css.mHBrief} onClick={open}>{plain(text)}</button>;
}

/**
 * A message in or out, drawn alike: a line saying what and where, then its words in brief beside a bar (they answer
 * each other). A tap on the words opens the whole of it on its own page, under the same line.
 */
function Message({ icon: I, label, text, full }: { icon: Icon; label: ReactNode; text: string; full: ReactNode }) {
  const app = useApp();
  const line = <span className={css.mHLabel}><I size={14} />{label}</span>;
  return (
    <div className={css.mHMessage}>
      {line}
      <div className={css.mHQuote}><Brief text={text} open={() => app.reader({ label: line, content: full })} /></div>
    </div>
  );
}

function Pill({ text, tone }: { text: string; tone: "blue" | "red" | "accent" }) {
  return <span className={historyCss.mPill} data-tone={tone}>{text}</span>;
}

/** A place, as the core names it: its platform's mark and its name; a chat on ember's page leads to it. */
function PlaceMark({ station, chat, place }: { station: string; chat: string; place: Place }) {
  const app = useApp();
  // An ember chat is its agent's item: opened by the session it is bound to.
  // A Slack thread opens in Slack.
  const open = place.url ? () => { window.open(place.url!, "_blank", "noopener"); }
    : place.session ? () => { if (place.session !== chat) app.push(`${stationBase(station)}/chats/${encodeURIComponent(place.session!)}`); else app.sheet(null); } : undefined;
  return (
    <button type="button" className={css.mHPlace} data-link={open ? true : undefined} disabled={!open} onClick={open}>
      {place.surface === "ember" ? <Mark size={12} /> : <SlackMark size={12} />}<b>{place.name}</b>
    </button>
  );
}

function Group({ g }: { g: HistoryGroup }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="m-h-group">
      <button type="button" className={css.mHGroupHead} onClick={() => setOpen(!open)}>
        {open ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
        <span data-failed={g.failures > 0 || undefined} data-open={open || undefined}>{g.summary}</span>
        {g.failures > 0 && <Pill text={`${g.failures} 项失败`} tone="red" />}
        {g.pending > 0 && <Pill text={`${g.pending} 项进行中`} tone="accent" />}
      </button>
      {open && (
        <div className={css.mHGroupBody}>
          {g.thinking.map((t, i) => g.steps.length === 0
            ? <p key={i} className={css.mHThought}>{t.text}</p>
            : <Folding key={i} name="思考" hint={t.first} meta={null} failed={false}><p className={css.mHThought}>{t.text}</p></Folding>)}
          {g.steps.map((step, i) => <StepRow key={i} step={step} />)}
        </div>
      )}
    </div>
  );
}

function StepRow({ step }: { step: HistoryStep }) {
  return (
    <Folding name={step.said ?? step.name} hint={step.said === undefined ? step.hint : null} meta={step.meta} failed={step.failed}>
      <div className={toolCss.body}>
        <div className={toolCss.section}><ToolCall name={step.name} call={step.call} said={step.said !== undefined} /></div>
        {step.result !== undefined && <ToolResult name={step.name} call={step.call} result={step.result} failed={step.failed} />}
      </div>
    </Folding>
  );
}

/** A line that opens to what is behind it. */
function Folding({ name, hint, meta, failed, children }: { name: string; hint: string | null; meta: string | null; failed: boolean; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <div className={css.mHFold}>
      <button type="button" className={css.mHFoldHead} onClick={() => setOpen(!open)} data-failed={failed || undefined}>
        <span className={css.mHFoldName} data-hint={hint !== null || undefined}>{name}</span>
        {hint !== null && <span className={css.mHFoldHint}>{hint}</span>}
        {meta && <span className={css.mHFoldMeta}>{meta}</span>}
      </button>
      {open && children}
    </div>
  );
}

/** The turn's state with the model (the core's words), with a running clock. */
function PhaseLine({ phase }: { phase: HistoryPhase }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  return <span className={css.mHPhase}><i />{phase.text}<small>{Math.max(0, Math.floor((now - phase.since) / 1000))}s</small></span>;
}

/** How it runs (which can be changed here), what it has used, the station. */
function Details({ station, chat, agent, history }: { station: string; chat: string; agent: ChatAgent; history: HistoryView | undefined }) {
  const app = useApp();
  const host = useHost(station).value;
  const name = useStationName(station);
  const s = agent.session;
  return (
    <div className={css.mHDetails}>
      {/* Changing how it runs is a screen of its own. */}
      <RunRow agent={agent} onOpen={() => app.push(`${stationBase(station)}/chats/${encodeURIComponent(chat)}/run/${encodeURIComponent(s.key)}`)} />
      <div className={css.mHFacts}>
        <Detail label="运行时" value={s.runtimeText} />
        {s.processText && <Detail label="进程" value={s.processText} />}
        {history?.usage?.map((u) => <Detail key={u.label} label={u.label} value={u.value} />)}
      </div>
      <GroupLabel>Station</GroupLabel>
      <div className={css.mHFacts}>
        <Detail label="名字" value={name} />
        {host && <Detail label="机器" value={`${host.hostname} · ${host.summary}`} />}
      </div>
      {host && <div className={css.mHRings}>{host.meters.map((m) => <Ring key={m.label} percent={m.percent} label={m.short} level={m.level} />)}</div>}
    </div>
  );
}

/** A station's name in its workspace. */
function useStationName(station: string): string {
  const [workspace, id] = station.split("/");
  const list = useStations(workspace ?? "").value;
  return list?.find((s) => s.id === id)?.name ?? id ?? station;
}

function Detail({ label, value }: { label: string; value: string }) {
  return <div className={css.mHDetail}><span>{label}</span><span>{value}</span></div>;
}

/** How it runs, in one line: the model (never cut short), how hard it thinks, the account (cut short first). */
function RunRow({ agent, onOpen }: { agent: ChatAgent; onOpen: () => void }) {
  const s = agent.session;
  const name = agent.account?.name ?? "";
  return (
    <button type="button" className={css.mRunRow} onClick={onOpen}>
      <MakerIcon maker={s.maker} runtime={s.runtime} size={15} />
      <b>{s.model ? s.modelName ?? s.model : "选模型"}</b>
      <span>{` · ${s.effort ?? "默认深度"} · ${s.profilePinned ? name : `自动 · ${name}`}`}</span>
      <ChevronDown size={14} />
    </button>
  );
}

// ── changing how it runs ───────────────────────────────────────────────

/**
 * Changing how an agent runs, full screen: what it is now, then the model, how hard it thinks and who runs it (the
 * station's pick, or one profile kept to), each said in plain words. Picks are a draft; the button at the bottom says
 * what it becomes (不变 when nothing changed); back leaves it as it was. A profile kept to that does not run the model
 * picked gives way to the station's pick, said so.
 */
export function RunSettingsScreen() {
  const app = useApp();
  const station = useStation();
  const api = useApi();
  const { chat = "", agent: key = "" } = useParams();
  const view = useChat(station.address, { session: chat });
  const agent = view.value?.agents.find((a) => a.session.key === key);
  // A long list (the models, the accounts) is a list of its own, picked from and back.
  const [list, setList] = useState<"model" | "account" | null>(null);
  const [draft, setDraft] = useState<{ model: string | null; effort: string | null; profile: string | null } | null>(null);
  const [busy, setBusy] = useState(false);
  const title = list === "model" ? "选模型" : list === "account" ? "选账号" : "换模型";
  const bar = <NavBar back={list ? "换模型" : "返回"} onBack={() => (list ? setList(null) : app.pop())} title={title} />;
  if (!agent) return <div className={pagesCss.mScreen}>{bar}<p className={`${partsCss.mMuted} ${partsCss.mPad18}`}>{view.error?.message ?? "正在读取…"}</p></div>;
  const s = agent.session;
  const current = agent.account;
  const currentName = current?.name ?? "";
  const kept = s.profilePinned ? s.profile ?? null : null;
  const model = draft ? draft.model : s.model ?? null;
  const effort = draft ? draft.effort : s.effort ?? null;
  const profile = draft ? draft.profile : kept;
  const set = (next: Partial<{ model: string | null; effort: string | null; profile: string | null }>) => setDraft({ model, effort, profile, ...next });
  const choice = optionOf(agent.choices, model);
  const named = (m: string | null) => (m === null ? null : m === s.model ? s.modelName ?? m : modelName(agent.choices, m));
  const accounts: RunnableProfile[] = choice?.accounts[s.runtime] ?? [];
  const chosen = profile && accounts.some((a) => a.id === profile) ? profile : null;
  const dropped = profile !== null && chosen === null;
  const efforts: (string | null)[] = [null, ...s.efforts];
  const changed = (model !== (s.model ?? null) && (!choice || choice !== optionOf(agent.choices, s.model))) || effort !== (s.effort ?? null) || chosen !== kept;
  const accountText = (id: string | null) => (id === null ? "自动分配" : accounts.find((a) => a.id === id)?.name ?? id);
  if (list === "model") return <div className={pagesCss.mScreen}>{bar}<ModelList models={agent.choices} runtime={s.runtime} picked={model} onPick={(m) => { set({ model: m }); setList(null); }} /></div>;
  if (list === "account") return <div className={pagesCss.mScreen}>{bar}<AccountList accounts={accounts} runtime={s.runtime} picked={chosen} onPick={(p) => { set({ profile: p }); setList(null); }} /></div>;
  const was = [named(s.model ?? null) ?? "默认模型", s.effort ?? "默认深度", kept !== null ? currentName : `自动 · ${currentName}`];
  // The station's pick moves off an account without the model (the one it is on now, when it has it).
  const movesOff = chosen === null && kept === null && model !== null && !!current && !accounts.some((a) => a.id === current.id);
  const becomes = [named(model) ?? "默认模型", effort ?? "默认深度",
    chosen !== null ? accountText(chosen) : movesOff ? "自动（换账号）" : current && accounts.some((a) => a.id === current.id) ? `自动 · ${currentName}` : "自动分配"];
  const force = dropped ? `指定的账号「${accountText(profile)}」没有启用 ${named(model)}，改成了自动分配`
    : movesOff ? `现在的账号「${currentName}」没有启用 ${named(model)}，会自动换一个启用了的` : null;
  const save = () => {
    if (!changed || !choice) return app.pop();
    setBusy(true);
    api.sessionSettings(s.key, { model: choice === optionOf(agent.choices, s.model) ? s.model ?? choice.model : choice.model, effort, profile: chosen })
      .then(() => { app.toast("已改，下一轮起生效"); app.pop(); }, (e: unknown) => app.toast(e instanceof Error ? e.message : String(e)))
      .finally(() => setBusy(false));
  };
  return (
    <div className={pagesCss.mScreen}>
      {bar}
      <div className={`${pagesCss.mScroll} ${partsCss.mPadX18}`}>
        {/* Always on top: what it was, and what it becomes, the changes marked; and when the account must change, why. */}
        <div className={css.mRunSummary}>
          {["模型", "深度", "账号"].map((label, i) => {
            const moved = becomes[i] !== was[i];
            return (
              <div key={label} className={css.mRunLine}>
                <span className={historyCss.mRunLabel}>{label}</span>
                <span className={css.mRunWas} data-moved={moved || undefined}>{was[i]}</span>
                {moved && <><ArrowRight size={14} className={partsCss.mAccent} /><b className={css.mRunBecomes}>{becomes[i]}</b></>}
              </div>
            );
          })}
          {force && <p className={`${css.mWarn} ${partsCss.mSmall}`}>{force}</p>}
          <p className={`${partsCss.mSubtle} ${partsCss.mSmall}`}>改了以后从下一轮开始生效。</p>
        </div>
        <GroupLabel>模型</GroupLabel>
        <SettingRow onClick={() => setList("model")} leading={<MakerIcon maker={choice?.maker} runtime={s.runtime} size={18} />}>
          <span className={historyCss.mSettingMain}>{named(model) ?? "选一个模型"}</span>
        </SettingRow>
        <GroupLabel>思考深度</GroupLabel>
        <p className={`${partsCss.mSmall} ${partsCss.mMuted} ${historyCss.mEffortNote}`}>想得越深越慢，也越费额度。</p>
        <div className={historyCss.mChips}>
          {efforts.map((e) => <button key={e ?? "-"} type="button" className={historyCss.mChip} data-on={e === effort || undefined} onClick={() => set({ effort: e })}>{e ?? "默认"}</button>)}
        </div>
        <GroupLabel>账号</GroupLabel>
        <SettingRow onClick={() => setList("account")} leading={(() => { const p = accounts.find((a) => a.id === chosen); return p ? <ProviderMark runtime={p.runtime ?? s.runtime} kind={p.kind} size={18} /> : null; })()}>
          <span className={historyCss.mSettingMain}>{accountText(chosen)}</span>
          <small className={partsCss.mMuted}>{chosen === null ? "额度用完或登录失效时换一个" : "固定用它"}</small>
          {(dropped || movesOff) && <small className={css.mWarn}>这个模型要换账号</small>}
        </SettingRow>
        <div style={{ height: 16 }} />
      </div>
      <button type="button" className={historyCss.mRunGo} data-changed={changed || undefined} disabled={busy} onClick={save}>
        {busy && <Spinner size={14} />}
        {changed ? `改成 ${named(model) ?? "默认模型"} · ${effort ?? "默认深度"} · ${accountText(chosen)}` : "不变"}
      </button>
    </div>
  );
}

/** A line that leads to a list: what is chosen, and an arrow. */
export function SettingRow({ onClick, leading, children }: { onClick: () => void; leading?: ReactNode; children: ReactNode }) {
  return (
    <button type="button" className={css.mSettingRow} onClick={onClick}>
      {leading}
      <span className={`${partsCss.mGrow} ${css.mSettingText}`}>{children}</span>
      <ChevronRight size={16} />
    </button>
  );
}

/** Every model it can move to, by series (the core says); a filter once there are many. */
export function ModelList({ models, runtime, picked, onPick }: { models: ModelOption[]; runtime: string; picked: string | null; onPick: (m: string) => void }) {
  const [filter, setFilter] = useState("");
  const words = filter.trim().toLowerCase();
  const shown = models.filter((m) => [m.name, m.model, ...m.ids].some((s) => s.toLowerCase().includes(words)));
  const on = optionOf(models, picked);
  // By series, in the core's order.
  const groups = new Map<string, ModelOption[]>();
  for (const m of shown) groups.set(m.family ?? "其他", [...(groups.get(m.family ?? "其他") ?? []), m]);
  const names = [...groups.keys()];
  return (
    <div className={`${pagesCss.mScroll} ${partsCss.mPadX18}`}>
      {models.length > 8 && <input className={`${listsCss.mField} ${css.mFilter}`} value={filter} placeholder="搜索模型" onChange={(e) => setFilter(e.target.value)} />}
      {names.map((who) => (
        <div key={who}>
          {names.length > 1 && <GroupLabel>{who}</GroupLabel>}
          {groups.get(who)!.map((m) => <PickLine key={m.model} label={m.name} checked={m === on} onClick={() => onPick(m.model)} leading={<MakerIcon maker={m.maker} runtime={runtime} size={18} />} />)}
        </div>
      ))}
      {shown.length === 0 && <p className={partsCss.mMuted}>没有叫这个的模型</p>}
    </div>
  );
}

/** Who can run the model picked: the station's pick, or one kept to, with its quota. */
export function AccountList({ accounts, runtime, picked, onPick }: { accounts: RunnableProfile[]; runtime: string; picked: string | null; onPick: (p: string | null) => void }) {
  return (
    <div className={`${pagesCss.mScroll} ${partsCss.mPadX18}`}>
      <p className={`${partsCss.mSmall} ${partsCss.mMuted} ${css.mAccountNote}`}>自动分配时，额度用完或登录失效会换一个；指定了就一直用它。</p>
      <PickLine label="自动分配" checked={picked === null} onClick={() => onPick(null)} />
      {/* An account its provider refuses says so (a red dot, 被停用) where its allowance would be. */}
      {accounts.map((p) => (
        <PickLine key={p.id} label={p.name} checked={picked === p.id} onClick={() => onPick(p.id)}
          leading={<ProviderMark runtime={p.runtime ?? runtime} kind={p.kind} size={18} />}
          trailing={p.quota?.state === "blocked" ? <span className={settingsCss.mRowStatus} title={p.quota.detail}><span className={settingsCss.mPresence} data-state="error" />被停用</span> : <QuotaRings quota={p.quota} />} />
      ))}
    </div>
  );
}

/** A choice in a list: what it is, a note under it, and a check when it is the one chosen. */
function PickLine({ label, checked, onClick, leading, trailing }: { label: string; checked: boolean; onClick: () => void; leading?: ReactNode; trailing?: ReactNode }) {
  return (
    <button type="button" className={css.mPickLine} onClick={onClick}>
      {leading}
      <span className={partsCss.mGrow}>{label}</span>
      {trailing}
      <span className={css.mPickCheck}>{checked && <Check size={16} />}</span>
    </button>
  );
}

