// An agent of the chat in brief, on the phone: a sheet over the chat, opened from its name beside its messages or its
// mark in the chat's bar (the wide screen's card over its avatar, ../AgentCard.tsx; the Android app's AgentSheet.kt).
// What it runs and where it stands (with a stop while it works), its latest lines, the figures that say most (the
// `agentCard` view, views/brief.ts), then where to go on: the station it runs on, its screens, its account (how it runs), its history,
// its jobs, and its context by hand (compacted, cleared). Only what
// is worth a look is coloured. The same parts head its history's details (History.tsx).
import { stationApi, useAgentCard, useChat, useStationCall, useStationLook, type ChatAgent } from "../api.ts";
import type { AgentCardView, ChatScreen } from "../core/shapes.ts";
import { Elapsed, Waited } from "../Chat.tsx";
import { ChevronRight, Monitor, Phone, Stop, Web } from "@stillfail/ui/icons.tsx";
import { stationBase } from "../station.tsx";
import { StationMark } from "../StationMark.tsx";
import { useDoing, useDoingFailed } from "../doing.ts";
import { confirm } from "./sheets.tsx";
import { t } from "../i18n.ts";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { FailedMark, InfoList, InfoRow, ModelMark, PickRow, QuotaRings, stateOf } from "./parts.tsx";
import { Spinner } from "@stillfail/ui/waiting.tsx";
import * as partsCss from "./styles/parts.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as css from "./AgentSheet.css.ts";

/** Whose card: the chat's page (its address) and the agent's session. */
export interface AgentAt { station: string; chat: string; key: string }
/** Where its rows lead from the page that opened it; `station`, the card of the station it runs on, in its place. */
export interface AgentGo { history(): void; jobs(): void; station?: () => void }

const working = (agent: ChatAgent) => agent.status === "running" || agent.status === "queued";

/** As tall as what it shows: its head, its lines, its figures and its rows (their room kept while they are read). */
function tall(agent: ChatAgent, go: AgentGo, screens: number): number {
  const rows = 2 + (go.station ? 1 : 0) + (screens > 0 ? 1 : 0) + (agent.jobs.length > 0 ? 1 : 0);
  // What is wrong, a line each but a quota's (its account's windows say that).
  const notes = agent.attention.filter((a) => a.kind !== "quota").length;
  const px = 25 + 44 + (agent.turns.length > 0 ? 75 + 76 : 0) + (notes > 0 ? 10 + notes * 20 : 0) + 12 + rows * 41 + 28;
  return Math.min(0.9, px / window.innerHeight);
}

/** Opens `at`'s card over its chat. */
export function openAgent(app: MobileApp, at: AgentAt, agent: ChatAgent, go: AgentGo, screens = 0) {
  app.sheet({ height: tall(agent, go, screens), content: () => <AgentSheet at={at} go={go} /> });
}

/** A screen's mark by its kind: a tab of the station's browser, a simulator, else its display. */
function ScreenIcon({ kind }: { kind: string }) {
  const Icon = kind === "browser" ? Web : kind === "simulator" ? Phone : Monitor;
  return <Icon size={18} />;
}

function AgentSheet({ at, go }: { at: AgentAt; go: AgentGo }) {
  const app = useApp();
  const chat = useChat(at.station, { session: at.chat }).value;
  const agent = chat?.agents.find((a) => a.session.key === at.key);
  // The screens of the station it runs on (the chat view's `screens`): its own display first.
  const screens: ChatScreen[] = chat?.screens ?? [];
  const card = useAgentCard(at.station, at.key).value;
  // A sheet lies over the page, outside its station's context: the API by the station's address.
  const call = useStationCall(at.station);
  const stopping = useDoing("session.stop", { station: at.station, key: at.key });
  const handling = useDoing(CONTEXT_CALLS, { station: at.station, key: at.key });
  const handlingFailed = useDoingFailed(CONTEXT_CALLS, { station: at.station, key: at.key });
  const station = useStationLook(at.station);
  if (!agent) return <SheetGrab />;
  const s = agent.session;
  const entry: ContextEntry | undefined = s.canCompact || s.canClear ? { open: () => openContext(app, at), busy: handling, failed: handlingFailed, compacts: s.canCompact === true } : undefined;
  const account = agent.account ?? agent.profile;
  // Each row leaves the sheet for where it leads.
  const leave = (to: () => void) => () => { app.sheet(null); to(); };
  return (
    <>
      <SheetGrab />
      <div className={`${sheetsCss.mSheetScroll} ${css.mAgent}`}>
        <div className={css.mAgentHead}>
          <ModelMark maker={s.maker} runtime={s.runtime} size={40} state={stateOf(agent.badge)} around="var(--m-surface)" />
          <span className={css.mAgentNames}>
            <b className={css.mAgentName}>{s.agentText}</b>
            <AgentStatus agent={agent} />
          </span>
          {working(agent) && (
            <button type="button" className={css.mAgentStop} disabled={stopping}
              onClick={() => { stationApi(call).stop(s.key).then(() => app.toast(t("web-mobile.history.stopAsked")), (error) => app.toast(t("web-mobile.chat.stopFailed", { error: error instanceof Error ? error.message : String(error) }))); }}>
              {stopping ? <Spinner inline className={partsCss.mSpinOnColor} /> : <Stop size={11} fill="currentColor" />}{t("web-mobile.history.stop")}
            </button>
          )}
        </div>
        <AgentLines card={card} />
        <AgentTiles card={card} context={entry} />
        <AgentNotes card={card} />
        <div className={css.mAgentRows}>
          <InfoList>
            {go.station && station && (
              <InfoRow onClick={go.station}>
                <span className={css.mAgentRowLabel}>{t("web-mobile.agent.station")}</span>
                <span className={`${css.mAgentRowValue} ${css.mAgentStation}`}>
                  {(station.emoji || station.icon) && <StationMark emoji={station.emoji} icon={station.icon} size={14} />}<span>{station.name}</span>
                </span>
                <ChevronRight size={14} className={partsCss.mSubtle} />
              </InfoRow>
            )}
            {screens.length > 0 && (
              <InfoRow onClick={(e) => {
                // The one alone opened, more a menu of them where the row was.
                const open = (id: string) => app.push(`${stationBase(at.station)}/screen/${encodeURIComponent(id)}`);
                const anchor = e.currentTarget.getBoundingClientRect();
                app.sheet(null);
                if (screens.length === 1) open(screens[0]!.id);
                else app.menu({ anchor, items: screens.map((sc) => ({ label: sc.agent ? `${sc.title} · ${t("web-pages.chat.screenAgent")}` : sc.title, icon: <ScreenIcon kind={sc.kind} />, action: () => open(sc.id) })) });
              }}>
                <span className={css.mAgentRowLabel}>{t("android-chat.agent.screen")}</span>
                <span className={css.mAgentRowValue}>{screens.some((sc) => sc.agent) ? t("web-pages.chat.screenAgent") : screens[0]!.title}</span>
                <ChevronRight size={14} className={partsCss.mSubtle} />
              </InfoRow>
            )}
            <InfoRow onClick={leave(() => app.push(`${stationBase(at.station)}/chats/${encodeURIComponent(at.chat)}/run/${encodeURIComponent(s.key)}`))}>
              <span className={css.mAgentRowLabel}>{t("web-mobile.history.account")}</span>
              <span className={css.mAgentRowValue}>{account ? (s.profilePinned ? account.name : t("web-mobile.agent.accountAuto", { name: account.name })) : t("web-mobile.history.auto")}</span>
              <QuotaRings quota={account?.quota} />
              <ChevronRight size={14} className={partsCss.mSubtle} />
            </InfoRow>
            <InfoRow onClick={leave(go.history)}>
              <span className={css.mAgentRowLabel}>{t("web-mobile.agent.history")}</span>
              <span className={css.mAgentRowValue}>{card?.work ?? t("web-mobile.agent.noTurns")}</span>
              <ChevronRight size={14} className={partsCss.mSubtle} />
            </InfoRow>
            {agent.jobs.length > 0 && (
              <InfoRow onClick={leave(go.jobs)}>
                <span className={css.mAgentRowLabel}>{t("web-mobile.agent.jobs")}</span>
                <span className={css.mAgentRowValue}>{card?.jobs ?? t("web-mobile.agent.jobsIdle")}</span>
                <ChevronRight size={14} className={partsCss.mSubtle} />
              </InfoRow>
            )}
            {/* What can be done to its context, where no figure of it is known to be its tile (a station from before
                tells none of an agent at rest). */}
            {entry && !card?.context && (
              <InfoRow onClick={() => { if (!entry.busy) entry.open(); }}>
                <span className={css.mAgentRowLabel}>{t("web-main.chat.agentCard.context")}</span>
                <span className={css.mAgentRowValue} />
                {entry.busy ? <Spinner inline /> : entry.failed !== undefined ? <FailedMark error={entry.failed} size={11} /> : null}
                <ChevronRight size={14} className={partsCss.mSubtle} />
              </InfoRow>
            )}

          </InfoList>
        </div>
      </div>
    </>
  );
}

const CONTEXT_CALLS = ["session.compact", "session.clear"] as const;

/** What can be done to its context by hand, in a sheet of its own in the card's place: compacted, or cleared (asked first). */
function openContext(app: MobileApp, at: AgentAt) {
  app.sheet({ height: 0.34, content: () => <ContextSheet at={at} /> });
}

function ContextSheet({ at }: { at: AgentAt }) {
  const app = useApp();
  const call = useStationCall(at.station);
  const s = useChat(at.station, { session: at.chat }).value?.agents.find((a) => a.session.key === at.key)?.session;
  const said = (error: unknown) => (error instanceof Error ? error.message : String(error));
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.chat.context")} />
      <div className={sheetsCss.mSheetScroll}>
        {s?.canCompact && (
          <PickRow label={t("web-pages.chat.compact")} sub={t("web-mobile.agent.compactSub")} onClick={() => {
            app.sheet(null);
            stationApi(call).compact(at.key).then(() => app.toast(t("web-mobile.agent.compacting")), (error) => app.toast(t("web-mobile.agent.compactFailed", { error: said(error) })));
          }} />
        )}
        {s?.canClear && (
          <PickRow label={t("web-pages.chat.clear")} sub={t("web-mobile.agent.clearSub")} accent onClick={() => confirm(app, {
            title: t("web-pages.chat.clearConfirm"), text: t("web-pages.chat.clearBody"), action: t("web-pages.chat.clear"), danger: true,
            atOnce: "web-mobile.agent.clearFailed", run: () => stationApi(call).clear(at.key),
          })} />
        )}
      </div>
    </>
  );
}

/** Where it stands, in words after a dot in its tone, and for how long. */
export function AgentStatus({ agent }: { agent: ChatAgent }) {
  return <p className={css.mAgentStatus} data-tone={agent.session.tone}>{agent.session.statusText}<AgentSince agent={agent} /></p>;
}

/** For how long it has stood where it does: at work since its turn began, waiting as long as it has (of at most), else
 * when it was last at it. */
export function AgentSince({ agent }: { agent: ChatAgent }) {
  const ago = agent.session.time?.lastActiveAt?.ago;
  if (agent.wait) return <span className={css.mAgentElapsed}> · <Waited since={agent.wait.since} seconds={agent.wait.seconds} /></span>;
  if (agent.since) return <span className={css.mAgentElapsed}> · <Elapsed since={agent.since} /></span>;
  return ago ? <span className={css.mAgentElapsed}> · {ago}</span> : null;
}

/** Its latest lines (the core's): the things it did, then what it does now. */
function AgentLines({ card }: { card: AgentCardView | undefined }) {
  const latest = card?.latest ?? [];
  if (latest.length === 0) return null;
  return <ol className={css.mAgentLines}>{latest.map((l) => <li key={l.key} data-now={l.now ? "" : undefined}>{l.text}</li>)}</ol>;
}

/** A figure of more letters than this is drawn a size down (three tiles share a phone's width). */
const LONG = 6;

/** The figures that say most: what it cost, the cache's hit rate, how full its context is. */
/**
 * What can be done to its context from its tile (the card's): opens it; under way or failed, said where the tile's ›
 * is; `compacts`: it can be compacted, which the tile says once the context is filling up (amber or red), not before.
 */
export interface ContextEntry { open(): void; busy: boolean; failed: string | undefined; compacts: boolean }

export function AgentTiles({ card, context: entry }: { card: AgentCardView | undefined; context?: ContextEntry | undefined }) {
  const context = card?.context;
  // None known (a station from before tells none of an agent at rest): no figures, its context's entry a row instead.
  if (!card?.cost && !card?.cache && !context) return null;
  const tile = (figure: string, name: string, level?: string) => (
    <span className={css.mAgentTile} data-level={level} data-long={figure.length > LONG ? "" : undefined}><b>{figure}</b><small>{name}</small></span>
  );
  /** Its context's tile: one to press when something can be done to it, its name then ending in ›. */
  const contextTile = (figure: string, level?: string) => {
    if (!entry) return tile(figure, t("web-main.chat.agentCard.context"), level);
    const filling = entry.compacts && (level === "amber" || level === "red");
    return (
      <button type="button" className={`${css.mAgentTile} ${css.mAgentTileButton}`} data-level={level} data-long={figure.length > LONG ? "" : undefined} disabled={entry.busy} onClick={entry.open}>
        <b>{figure}</b>
        <small className={css.mAgentTileName}>
          <span>{filling ? t("web-mobile.agent.contextCompactable") : t("web-main.chat.agentCard.context")}</span>
          {entry.busy ? <Spinner inline /> : entry.failed !== undefined ? <FailedMark error={entry.failed} size={11} /> : <ChevronRight size={11} />}
        </small>
      </button>
    );
  };
  return (
    <div className={css.mAgentTiles}>
      {card?.cost && tile(card.cost, t("web-main.chat.agentCard.cost"))}
      {card?.cache && tile(card.cache.text, t("web-main.chat.agentCard.cache"))}
      {/* How full, of a window that is known; else how much it holds. */}
      {context && (context.unknown ? contextTile(context.text) : contextTile(`${Math.round(context.percent)}%`, context.level))}
    </div>
  );
}

/** What is wrong (an account that cannot run, the disk filling up), a line each. */
export function AgentNotes({ card }: { card: AgentCardView | undefined }) {
  if (!card?.attention.length) return null;
  return <div className={css.mAgentNotes}>{card.attention.map((a, i) => <span key={i} data-level={a.level}>{a.text}</span>)}</div>;
}
