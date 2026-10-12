// An agent of the chat in brief, on the phone: a sheet over the chat, opened from its name beside its messages or its
// mark in the chat's bar (the wide screen's card over its avatar, ../AgentCard.tsx; the Android app's AgentSheet.kt).
// What it runs and where it stands (with a stop while it works), its latest lines, the figures that say most (the
// `agentCard` view, views/brief.ts), then where to go on: its account (how it runs), its history, its jobs. Only what
// is worth a look is coloured. The same parts head its history's details (History.tsx).
import { stationApi, useAgentCard, useChat, useStationCall, type ChatAgent } from "../api.ts";
import type { AgentCardView } from "../core/shapes.ts";
import { Elapsed, Waited } from "../Chat.tsx";
import { ChevronRight, Stop } from "../icons.tsx";
import { stationBase } from "../station.tsx";
import { useDoing } from "../doing.ts";
import { t } from "../i18n.ts";
import { SheetGrab, useApp, type MobileApp } from "./app.tsx";
import { InfoList, InfoRow, ModelMark, QuotaRings, Spinner, stateOf } from "./parts.tsx";
import * as partsCss from "./styles/parts.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as css from "./AgentSheet.css.ts";

/** Whose card: the chat's page (its address) and the agent's session. */
export interface AgentAt { station: string; chat: string; key: string }
/** Where its rows lead from the page that opened it. */
export interface AgentGo { history(): void; jobs(): void }

const working = (agent: ChatAgent) => agent.status === "running" || agent.status === "queued";

/** As tall as what it shows: its head, its lines, its figures and its rows (their room kept while they are read). */
function tall(agent: ChatAgent): number {
  const rows = 2 + (agent.jobs.length > 0 ? 1 : 0);
  // What is wrong, a line each but a quota's (its account's windows say that).
  const notes = agent.attention.filter((a) => a.kind !== "quota").length;
  const px = 25 + 44 + (agent.turns.length > 0 ? 75 + 76 : 0) + (notes > 0 ? 10 + notes * 20 : 0) + 12 + rows * 41 + 28;
  return Math.min(0.9, px / window.innerHeight);
}

/** Opens `at`'s card over its chat. */
export function openAgent(app: MobileApp, at: AgentAt, agent: ChatAgent, go: AgentGo) {
  app.sheet({ height: tall(agent), content: () => <AgentSheet at={at} go={go} /> });
}

function AgentSheet({ at, go }: { at: AgentAt; go: AgentGo }) {
  const app = useApp();
  const agent = useChat(at.station, { session: at.chat }).value?.agents.find((a) => a.session.key === at.key);
  const card = useAgentCard(at.station, at.key).value;
  // A sheet lies over the page, outside its station's context: the API by the station's address.
  const call = useStationCall(at.station);
  const stopping = useDoing("session.stop", { station: at.station, key: at.key });
  if (!agent) return <SheetGrab />;
  const s = agent.session;
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
              {stopping ? <Spinner size={11} color="var(--m-red)" /> : <Stop size={11} fill="currentColor" />}{t("web-mobile.history.stop")}
            </button>
          )}
        </div>
        <AgentLines card={card} />
        <AgentTiles card={card} />
        <AgentNotes card={card} />
        <div className={css.mAgentRows}>
          <InfoList>
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
          </InfoList>
        </div>
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
export function AgentTiles({ card }: { card: AgentCardView | undefined }) {
  const context = card?.context;
  if (!card?.cost && !card?.cache && !context) return null;
  const tile = (figure: string, name: string, level?: string) => (
    <span className={css.mAgentTile} data-level={level} data-long={figure.length > LONG ? "" : undefined}><b>{figure}</b><small>{name}</small></span>
  );
  return (
    <div className={css.mAgentTiles}>
      {card.cost && tile(card.cost, t("web-main.chat.agentCard.cost"))}
      {card.cache && tile(card.cache.text, t("web-main.chat.agentCard.cache"))}
      {/* How full, of a window that is known; else how much it holds. */}
      {context && (context.unknown ? tile(context.text, t("web-main.chat.agentCard.context")) : tile(`${Math.round(context.percent)}%`, t("web-main.chat.agentCard.context"), context.level))}
    </div>
  );
}

/** What is wrong (an account that cannot run, the disk filling up), a line each. */
export function AgentNotes({ card }: { card: AgentCardView | undefined }) {
  if (!card?.attention.length) return null;
  return <div className={css.mAgentNotes}>{card.attention.map((a, i) => <span key={i} data-level={a.level}>{a.text}</span>)}</div>;
}
