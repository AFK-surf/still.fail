import { useAction } from "../action.ts";
// An agent's execution history on a narrow screen, as the Android app has it (apps/android/…/screens/History.kt): a
// full-screen page. What it received and what it sent are drawn alike (a line, then the
// words beside a bar); what it did in between is grouped, each group opening to its commands and output; its details
// (how it runs, what it used, the station). Changing how it runs is a page of its own.
import { useReady } from "../core/react.ts";
import { LOCAL_MS } from "../motion.ts";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useParams, useSearchParams } from "react-router";
import { stationApi, useChat, useHistory, useHistoryOlder, useHost, useStationCall, useStations, type ChatAgent, type HistoryGroup, type HistoryItem, type HistoryPhase, type HistoryStep, type HistoryView, type ModelOption, type Place, type RunnableProfile } from "../api.ts";
import { ArrowRight, Check, ChevronDown, Copy, ChevronRight, Wait, Received, Send, Stop, Unplug } from "../icons.tsx";
import { optionOf } from "../ModelTriple.tsx";
import { usePick } from "../pick.ts";
import { Prose } from "../Prose.tsx";
import { useStickToBottom } from "../scroll.ts";
import { useOlderOnScroll, Waited } from "../Chat.tsx";
import { stationBase, useStation } from "../station.tsx";
import { useApp, type MobileApp } from "./app.tsx";
import { GroupLabel, MakerIcon, Mark, ModelMark, NavBar, NavButton, ProviderMark, QuotaRings, Seg, SlackMark, Spinner, stateOf, tNodes, type Icon } from "./parts.tsx";
import * as partsCss from "./styles/parts.css.ts";
import * as css from "./History.css.ts";
import { ToolCall, ToolResult } from "../ToolStep.tsx";
import * as toolCss from "../ToolStep.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as rootCss from "./styles/root.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import * as historyCss from "./styles/history.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import { Tip } from "../ui.tsx";
import { useCopyChatLink } from "../ChatRef.tsx";
import { MeterChips, QuotaRing } from "../components.tsx";
import * as chatPageCss from "../pages/ChatPage.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
/** Opens an agent's execution history over the item's page it belongs to; `entry`: the transcript entry to open at. */
export function openHistory(app: MobileApp, station: string, chat: string, key: string, entry?: number) {
  app.sheet(null);
  app.push(`${stationBase(station)}/chats/${encodeURIComponent(chat)}/history/${encodeURIComponent(key)}${entry === undefined ? "" : `?entry=${entry}`}`);
}

export function HistoryScreen() {
  const app = useApp();
  const station = useStation().address;
  const { chat = "", agent: agentKey = "" } = useParams();
  const [search] = useSearchParams();
  const raw = search.get("entry");
  const entry = raw !== null && /^\d+$/.test(raw) && Number.isSafeInteger(Number(raw)) ? Number(raw) : undefined;
  // Slides in once what it shows is read from the device (LOCAL_MS at most, as Chat.tsx): not its loading look first.
  useReady({ topic: "history", station, key: agentKey }, LOCAL_MS);
  const view = useChat(station, { session: chat });
  // Its link, to paste into another chat for its agent to read (or a person to open here).
  const copyLink = useCopyChatLink(app.toast);
  const title = view.value?.title;
  const bar = <NavBar back={t("common.back")} onBack={app.pop} title={t("web-mobile.app.runHistory")}
    trailing={title !== undefined ? <NavButton icon={Copy} label={t("web-mobile.history.copyLink")} onClick={() => copyLink({ station, session: agentKey, id: agentKey, title }, { key: agentKey })} /> : undefined} />;
  const history = useHistory(station, agentKey).value;
  const [tab, setTab] = useState(0);
  const agent = view.value?.agents.find((a) => a.session.key === agentKey);
  if (!agent) return <div className={pagesCss.mScreen}>{bar}<p className={`${partsCss.mMuted} ${partsCss.mPad18}`}>{view.error?.message ?? t("web-mobile.reading")}</p></div>;
  const s = agent.session;
  return (
    <div className={pagesCss.mScreen}>
      {bar}
      <div className={css.mHHead}>
        <ModelMark maker={s.maker} runtime={s.runtime} size={20} state={stateOf(agent.badge)} />
        <b>{s.agentText}</b>
        <Actions station={station} agent={agent} />
        <Seg options={[t("web-mobile.history.steps"), t("web-mobile.history.details")]} selected={tab} onSelect={setTab} />
      </div>
      <Summary agent={agent} />
      <div className={css.mHBody}>
        {tab === 0 ? <Steps station={station} chat={chat} agent={agent} history={history} entry={entry} /> : <Details station={station} chat={chat} agent={agent} history={history} />}
      </div>
    </div>
  );
}

/** What can be done to it right now: stop a turn, release an idle process. */
function Actions({ station, agent }: { station: string; agent: ChatAgent }) {
  const app = useApp();
  const api = useStationApi(station);
  const s = agent.session;
  return (
    <>
      {(agent.status === "running" || agent.status === "queued") && <Act icon={Stop} label={t("web-mobile.history.stop")} run={() => api.stop(s.key).then(() => app.toast(t("web-mobile.history.stopAsked")))} />}
      {s.process === "warm" && <Act icon={Unplug} label={t("web-mobile.history.evict")} run={() => api.evict(s.key).then(() => app.toast(t("web-mobile.history.evicted")))} />}
    </>
  );
}

function Act({ icon: I, label, run }: { icon: Icon; label: string; run: () => Promise<unknown> }) {
  const action = useAction(run);
  return <button type="button" className={css.mHAct} disabled={action.busy} aria-label={label} onClick={() => void action.run()}>
    {action.busy ? <Spinner size={14} /> : <I size={14} />}
  </button>;
}

/** A station's API by its explicit address. */
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
        ? <span key={i} className={`${chatPageCss.attention} ${chatPageCss.attentionQuota}`}><QuotaRing left={a.quota.left} level={a.quota.level} size={20} /><span>{a.quota.mark}</span></span>
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
  if (!history) return <Edge text={t("web-mobile.history.reading")} />;
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
          {body.content.note && <Message icon={Received} label={tNodes("web-mobile.history.reminder", { name: <b>{NAME}</b> })} text={body.content.note} full={<p className={chatCss.mPlain}>{body.content.note}</p>} />}
          {body.content.messages.map((m) => (
            <Message key={m.key} icon={Received}
              label={<>{tNodes("web-mobile.history.message", { name: <b>{m.from.name}</b> })}{m.place && <> · <PlaceMark station={station} chat={chat} place={m.place} /></>}</>}
              text={m.text} full={<p className={chatCss.mPlain}>{m.text}</p>} />
          ))}
        </div>
      );
    case "post":
      return (
        <Message icon={Send}
          label={<>{tNodes("web-mobile.history.sentTo", { place: body.content.place ? <PlaceMark station={station} chat={chat} place={body.content.place} /> : <span className={css.mHPlace}><SlackMark size={12} /><b> Slack</b></span> })}
            {body.content.block && <Pill text="Block" tone="blue" />}{body.content.failed && <Pill text={t("web-mobile.history.sendFailed")} tone="red" />}</>}
          text={body.content.text} full={<div className={`${rootCss.wide} ${conversationCss.markdown}`}><Prose>{body.content.text}</Prose></div>} />
      );
    case "mark":
      return (
        <p className={css.mHMark}>
          {body.content.wait && <Wait size={14} />}
          {body.content.wait && body.content.wait.until == null ? <span>{body.content.wait.what != null && <>{body.content.wait.what} · </>}{t("web-mobile.history.waiting")} <Waited since={body.content.wait.since} seconds={body.content.wait.seconds} /></span> : body.content.text}
        </p>
      );
    case "text":
      return (
        <div className={body.content.subagent ? css.mHSub : undefined}>
          <Brief text={body.content.text} open={() => app.reader({ label: <span className={partsCss.mMuted}>{t("web-mobile.history.wrote", { agent: agent.session.agentText })}</span>, content: <div className={`${rootCss.wide} ${conversationCss.markdown}`}><Prose>{body.content.text}</Prose></div> })} />
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

/** A place, as the core names it: its platform's mark and its name; a chat on still.fail's page leads to it. */
function PlaceMark({ station, chat, place }: { station: string; chat: string; place: Place }) {
  const app = useApp();
  // A still.fail chat is its agent's item: opened by the session it is bound to.
  // A Slack thread opens in Slack.
  const open = place.url ? () => { window.open(place.url!, "_blank", "noopener"); }
    : place.session ? () => { if (place.session !== chat) app.push(`${stationBase(station)}/chats/${encodeURIComponent(place.session!)}`); else app.pop(); } : undefined;
  return (
    <button type="button" className={css.mHPlace} data-link={open ? true : undefined} disabled={!open} onClick={open}>
      {(place.surface === "ember" || place.surface === "stillfail") ? <Mark size={12} /> : <SlackMark size={12} />}<b>{place.name}</b>
    </button>
  );
}

function Group({ g }: { g: HistoryGroup }) {
  const [open, setOpen] = useState(false);
  const calls = g.rows.some((row) => row.kind === "step");
  return (
    <div className="m-h-group">
      <button type="button" className={css.mHGroupHead} onClick={() => setOpen(!open)}>
        {open ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
        <span data-failed={g.failures > 0 || undefined} data-open={open || undefined}>{g.summary}</span>
        {g.failures > 0 && <Pill text={t("web-mobile.history.failures", { n: g.failures })} tone="red" />}
        {g.pending > 0 && <Pill text={t("web-mobile.history.pending", { n: g.pending })} tone="accent" />}
      </button>
      {open && (
        <div className={css.mHGroupBody}>
          {g.rows.map((row, i) => row.kind === "step"
            ? <StepRow key={i} step={row.content} />
            : calls
              ? <Folding key={i} name={t("web-mobile.history.thinking")} hint={row.content.first} meta={null} failed={false}><p className={css.mHThought}>{row.content.text}</p></Folding>
              : <p key={i} className={css.mHThought}>{row.content.text}</p>)}
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
        <Detail label={t("web-mobile.history.runtime")} value={s.runtimeText} />
        {s.processText && <Detail label={t("web-mobile.history.process")} value={s.processText} />}
        {history?.usage?.map((u) => <Detail key={u.label} label={u.label} value={u.value} />)}
      </div>
      <GroupLabel>Station</GroupLabel>
      <div className={css.mHFacts}>
        <Detail label={t("web-mobile.workspaces.name")} value={name} />
        {host && <Detail label={t("web-mobile.history.machine")} value={`${host.hostname} · ${host.summary}`} />}
      </div>
      {host && <div className={css.mHRings}><MeterChips meters={host.meters} /></div>}
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
      <b>{s.model ? s.modelName ?? s.model : t("web-mobile.history.pickModel")}</b>
      <span>{` · ${s.effort ?? t("web-mobile.newChat.effortDefault")} · ${s.profilePinned ? name : t("web-mobile.history.autoAccount", { name })}`}</span>
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
  const { chat = "", agent: key = "" } = useParams();
  const view = useChat(station.address, { session: chat });
  const agent = view.value?.agents.find((a) => a.session.key === key);
  // What it runs on, what is picked here and what that means, as the core has them (../pick.ts).
  const pick = usePick(station.address, `session:${key}`);
  const v = pick.view;
  // Picked from what it runs on now, each time it is opened.
  const { set: pickSet } = pick;
  useEffect(() => pickSet({ open: true }), [pickSet]);
  // A long list (the models, the accounts) is a list of its own, picked from and back.
  const [list, setList] = useState<"model" | "account" | null>(null);
  const busy = pick.saving;
  const title = list === "model" ? t("web-mobile.history.pickModel") : list === "account" ? t("web-mobile.history.pickAccount") : t("web-mobile.history.changeModel");
  const bar = <NavBar back={list ? t("web-mobile.history.changeModel") : t("common.back")} onBack={() => (list ? setList(null) : app.pop())} title={title} />;
  if (!agent || !v) return <div className={pagesCss.mScreen}>{bar}<p className={`${partsCss.mMuted} ${partsCss.mPad18}`}>{view.error?.message ?? t("web-mobile.reading")}</p></div>;
  const s = agent.session;
  const chosen = v.draft.profile ?? null;
  if (list === "model") return <div className={pagesCss.mScreen}>{bar}<ModelList models={v.options} runtime={s.runtime} picked={v.option ?? null} onPick={(m) => { pick.set({ model: m }); setList(null); }} /></div>;
  if (list === "account") return <div className={pagesCss.mScreen}>{bar}<AccountList accounts={v.accounts} runtime={s.runtime} picked={chosen} onPick={(p) => { pick.set({ profile: p }); setList(null); }} /></div>;
  // Back at once, not waiting on the station (its button under way where it shows, doing); failed, a toast says why.
  const save = () => {
    app.pop();
    if (!v.changed || !v.option) return;
    pick.save().then(() => app.toast(t("web-mobile.history.changed")), (e: unknown) => app.toast(e instanceof Error ? e.message : String(e)));
  };
  const effort = v.draft.effort ?? null;
  return (
    <div className={pagesCss.mScreen}>
      {bar}
      <div className={`${pagesCss.mScroll} ${partsCss.mPadX18}`}>
        {/* Always on top: what it was, and what it becomes, the changes marked; and when the account must change, why. */}
        <div className={css.mRunSummary}>
          {[t("web-mobile.history.model"), t("web-mobile.history.effort"), t("web-mobile.history.account"), ...(v.fastAvailable ? [t("web-mobile.newChat.speed")] : [])].map((label, i) => {
            const moved = v.becomes[i] !== v.was[i];
            return (
              <div key={label} className={css.mRunLine}>
                <span className={historyCss.mRunLabel}>{label}</span>
                <span className={css.mRunWas} data-moved={moved || undefined}>{v.was[i]}</span>
                {moved && <><ArrowRight size={14} className={partsCss.mAccent} /><b className={css.mRunBecomes}>{v.becomes[i]}</b></>}
              </div>
            );
          })}
          {v.force && <p className={`${css.mWarn} ${partsCss.mSmall}`}>{v.force}</p>}
          <p className={`${partsCss.mSubtle} ${partsCss.mSmall}`}>{t("web-mobile.history.changeNote")}</p>
        </div>
        <GroupLabel>{t("web-mobile.history.model")}</GroupLabel>
        <SettingRow onClick={() => setList("model")} leading={<MakerIcon maker={v.maker} runtime={s.runtime} size={18} />}>
          <span className={historyCss.mSettingMain}>{v.modelText}</span>
        </SettingRow>
        <GroupLabel>{t("web-mobile.newChat.pickEffort")}</GroupLabel>
        <p className={`${partsCss.mSmall} ${partsCss.mMuted} ${historyCss.mEffortNote}`}>{t("web-mobile.history.effortNote")}</p>
        <div className={historyCss.mChips}>
          {[null, ...v.efforts].map((e) => <button key={e ?? "-"} type="button" className={historyCss.mChip} data-on={e === effort || undefined} onClick={() => pick.set({ effort: e })}>{e ?? t("web-mobile.newChat.default")}</button>)}
        </div>
        {v.fastAvailable && <>
          <GroupLabel>{t("web-mobile.newChat.speed")}</GroupLabel>
          <p className={`${partsCss.mSmall} ${partsCss.mMuted} ${historyCss.mEffortNote}`}>{t("web-mobile.history.fastNote")}</p>
          <div className={historyCss.mChips}>
            {([null, false, true] as const).map((fast) => <button key={String(fast)} type="button" className={historyCss.mChip} data-on={(v.draft.fast ?? null) === fast || undefined} onClick={() => pick.set({ fast })}>{fast === null ? t("web-mobile.newChat.fastPlan") : fast ? "Fast" : t("web-mobile.newChat.fastStandard")}</button>)}
          </div>
        </>}
        <GroupLabel>{t("web-mobile.history.account")}</GroupLabel>
        <SettingRow onClick={() => setList("account")} leading={(() => { const p = v.accounts.find((a) => a.id === chosen); return p ? <ProviderMark runtime={p.runtime ?? s.runtime} kind={p.kind} mark={p.mark} size={18} /> : null; })()}>
          <span className={historyCss.mSettingMain}>{v.accountText}</span>
          <small className={partsCss.mMuted}>{v.accountNote}</small>
          {v.accountWarn && <small className={css.mWarn}>{t("web-mobile.history.accountWarn")}</small>}
        </SettingRow>
        <div style={{ height: 16 }} />
      </div>
      <button type="button" className={historyCss.mRunGo} data-changed={v.changed || undefined} disabled={busy} onClick={save}>
        {busy && <Spinner size={14} />}
        {v.saveText}
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
  const other = t("web-mobile.history.otherModels");
  for (const m of shown) groups.set(m.family ?? other, [...(groups.get(m.family ?? other) ?? []), m]);
  const names = [...groups.keys()];
  return (
    <div className={`${pagesCss.mScroll} ${partsCss.mPadX18}`}>
      {models.length > 8 && <input className={`${listsCss.mField} ${css.mFilter}`} value={filter} placeholder={t("web-mobile.history.search")} onChange={(e) => setFilter(e.target.value)} />}
      {names.map((who) => (
        <div key={who}>
          {names.length > 1 && <GroupLabel>{who}</GroupLabel>}
          {groups.get(who)!.map((m) => <PickLine key={m.model} label={m.name} checked={m === on} onClick={() => onPick(m.model)} leading={<MakerIcon maker={m.maker} runtime={runtime} size={18} />} />)}
        </div>
      ))}
      {shown.length === 0 && <p className={partsCss.mMuted}>{t("web-mobile.history.noMatch")}</p>}
    </div>
  );
}

/** Who can run the model picked: the station's pick, or one kept to, with its quota. */
export function AccountList({ accounts, runtime, picked, onPick }: { accounts: RunnableProfile[]; runtime: string; picked: string | null; onPick: (p: string | null) => void }) {
  return (
    <div className={`${pagesCss.mScroll} ${partsCss.mPadX18}`}>
      <p className={`${partsCss.mSmall} ${partsCss.mMuted} ${css.mAccountNote}`}>{t("web-mobile.history.accountNote")}</p>
      <PickLine label={t("web-mobile.history.auto")} checked={picked === null} onClick={() => onPick(null)} />
      {/* An account its provider refuses says so (a red dot, 被停用) where its allowance would be. */}
      {accounts.map((p) => (
        <PickLine key={p.id} label={p.name} checked={picked === p.id} onClick={() => onPick(p.id)}
          leading={<ProviderMark runtime={p.runtime ?? runtime} kind={p.kind} mark={p.mark} size={18} />}
          trailing={p.quota?.state === "blocked" ? <Tip label={p.quota.detail}><span className={settingsCss.mRowStatus}><span className={settingsCss.mPresence} data-state="error" />{t("web-mobile.history.blocked")}</span></Tip> : <QuotaRings quota={p.quota} />} />
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

