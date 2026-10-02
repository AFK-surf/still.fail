import type { SlackAppSettings } from "../api.ts";
import { useConnectFlow } from "../connect-flow.ts";
// A connect: where people reach ember (a Slack app today), the model it is
// bound to, and how its conversations become sessions.
import { profilesPage, scopeOf, useStation, useLink } from "../station.tsx";
import { CheckCircle, External, Key, Plus, Power, Refresh, Trash, User } from "../icons.tsx";
import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { useAction, useApi, useConnects, useOverview, useStations, type ConnectInput, type ConnectItem, type ConnectMode, type Connect, type ModelOption, type Overview, type MadeSlackApp } from "../api.ts";
import { MODE } from "../format.ts";
import { AppFields, ConfigTokenForm, NEW_APP, SlackAppSection } from "./SlackApp.tsx";
import { ModelTriple } from "../ModelTriple.tsx";
import { usePick } from "../pick.ts";
import { OwnerLabel } from "../components.tsx";
import { PeopleContext } from "../station.tsx";
import { useContext } from "react";
import { CreateAppSteps, emptyTokens, TokenFields, useSlackTokens } from "../slack.tsx";
import { useAct, useToast } from "../toast.tsx";
import { DoingShown, useDoingState } from "../DoingMark.tsx";
import * as waitingCss from "../styles/waiting.css.ts";
import { Button, Choices, Confirm, ConnectAvatar, Dialog, Empty, Field, ICON, Loading, Menu, BackLink, Pill, StatusText, Section, Select, SlackLogo, StatusDot, SwitchRow, Time } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./Connect.css.ts";
import * as cloudCss from "../styles/cloud.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as additionsCss from "../styles/additions.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as shellCss from "../styles/shell.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
export function ConnectPage() {
  const { id } = useParams();
  const station = useStation();
  const overview = useOverview(station.address);
  const connects = useConnects(scopeOf(station.address));
  const item = connects.value?.items.find((i) => i.station === station.address && i.connect.id === id);
  if (!overview.value || !connects.value || (connects.value.loading && !item)) {
    const error = overview.error ?? connects.error;
    return error ? <Empty><p>{error.message}</p></Empty> : <Loading label={t("web-pages.connect.loading")} />;
  }
  if (!item) return <Empty><p>{t("web-pages.connect.notFound", { id: id ?? "" })}</p></Empty>;
  return <ConnectDetail key={item.connect.id} item={item} overview={overview.value} />;
}

/** Saving a connect's settings; `put(input, done)` runs `done` once saved. */
function useSaveConnect(id: string) {
  const api = useApi();
  const save = useAction((input: ConnectInput) => api.putConnect(id, input));
  return { ...save, put: (input: ConnectInput, done?: () => void) => void save.run(input).then((saved) => { if (saved) done?.(); }) };
}

function useStationView() {
  const station = useStation();
  return useStations(scopeOf(station.address)).value?.find((s) => s.station === station.address);
}

/** The models the station can run, each with the runtimes it runs on (the core's). */
function useStationModels(): ModelOption[] {
  return useStationView()?.models ?? [];
}

function ConnectDetail({ item, overview }: { item: ConnectItem; overview: Overview }) {
  const connect = item.connect;
  const api = useApi();
  const station = useStation();
  const navigate = useNavigate();
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const [deleting, setDeleting] = useState(false);
  const [owning, setOwning] = useState(false);
  const [replacing, setReplacing] = useState(false);
  const remove = useAction(() => api.deleteConnect(connect.id), () => { toast(t("web-pages.connect.deleted")); navigate(`${station.settings}/connects`); });
  const reconnect = useAction(() => api.reconnect(connect.id), () => toast(t("web-pages.connect.reconnected")));
  // Reconnecting, or its settings on their way (from the menu or a section below): said in its status line meanwhile;
  // failed, a red mark and so for a few seconds, why on hover (the menu that asked has closed).
  const reconnectState = useDoingState("connect.reconnect", { station: station.address, id: connect.id });
  const saveState = useDoingState("connect.put", { station: station.address, id: connect.id });
  const reconnecting = reconnectState.running;
  const saving = saveState.running;
  const switching = save.busy && save.args?.[0].enabled !== undefined;
  const doing = reconnecting ? t("web-pages.connect.reconnecting") : switching ? (connect.enabled ? t("web-pages.connect.disabling") : t("web-pages.connect.enabling")) : saving ? t("web-pages.profiles.saving") : null;
  const failing = reconnectState.error !== undefined ? { error: reconnectState.error, text: t("web-pages.connect.reconnectFailedShort") }
    : saveState.error !== undefined ? { error: saveState.error, text: t("web-pages.connect.saveFailedShort") } : null;
  const c = connect.connection;
  const workspace = c.state === "connected" || c.state === "reconnecting" ? c.workspace : null;

  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <BackLink to={`${station.settings}/connects`} label={t("web-pages.settings.nav.connects")} />
      {/* Who it is and whether it is up; what is done to it less often is in the menu. */}
      <header className={pagesCss.identity}>
        <ConnectAvatar connect={connect} size={52} />
        <div className={pagesCss.identityText}>
          <h1 className={pagesCss.identityName}>{connect.name}</h1>
          <p className={pagesCss.identitySub}>
            <span className={css.connectStatus} role="status">
              {doing ? <><span className={`${waitingCss.spinner} ${controlsCss.iconSpinner}`} aria-hidden="true" />{doing}</>
                : failing ? <><DoingShown state={{ running: false, error: failing.error }} size={14} />{failing.text}</>
                : <><StatusDot state={connect.presence} />{connect.statusText}</>}
            </span>
            <span className={css.kindTag}><SlackLogo size={13} />{connect.team ?? "Slack"}</span>
            {station.name && <span className={cloudCss.stationTag}>{station.name}</span>}
            <span className={css.ownerLine}>{t("web-pages.connect.owner")} <OwnerLabel owner={connect.createdBy} /></span>
          </p>
        </div>
        <Menu items={[
          { label: t("web-pages.connect.reconnect"), icon: Refresh, disabled: reconnecting, onSelect: () => void reconnect.run() },
          { label: t("web-pages.connect.replaceToken"), icon: Key, onSelect: () => setReplacing(true) },
          ...(workspace?.url ? [{ label: t("web-pages.connect.openSlack"), icon: External, onSelect: () => window.open(workspace.url, "_blank", "noopener") }] : []),
          "separator",
          connect.enabled
            ? { label: t("web-pages.profiles.disable"), icon: Power, disabled: saving, onSelect: () => save.put({ enabled: false }, () => toast(t("web-pages.connect.disabled"))) }
            : { label: t("web-pages.connect.enable"), icon: Power, disabled: saving, onSelect: () => save.put({ enabled: true }, () => toast(t("web-pages.connect.enabled"))) },
          { label: t("web-pages.connect.changeOwner"), icon: User, onSelect: () => setOwning(true) },
          "separator",
          { label: t("web-pages.connect.delete"), icon: Trash, danger: true, onSelect: () => setDeleting(true) },
        ]} />
      </header>
      {save.error && <p className={`${controlsCss.fieldError} ${css.pageError}`} role="alert">{save.error.message}</p>}
      {reconnect.error && <p className={`${controlsCss.fieldError} ${css.pageError}`} role="alert">{t("web-pages.connect.reconnectFailed", { error: reconnect.error.message })}</p>}

      <SlackSection connect={connect} />
      <RunSection item={item} />
      <SlackAppSection connect={connect} />
      <ConnectSessions item={item} />

      {replacing && <TokenDialog connect={connect} onClose={() => setReplacing(false)} />}
      {owning && <OwnerDialog connect={connect} onClose={() => setOwning(false)} />}
      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.busy} onConfirm={() => void remove.run()}
        title={t("web-pages.archive.deleteConfirm", { title: connect.name })} action={t("web-pages.connect.delete")}
        description={connect.sessions ? t("web-pages.connect.deleteBodySessions", { n: connect.sessions }) : t("web-pages.connect.deleteBody")} error={remove.error?.message} />
    </div>
  );
}

/** The Slack link, when it needs something: tokens to connect with, or an error. Up and running, the header says so. */
function SlackSection({ connect }: { connect: Connect }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const [tokens, setTokens, check] = useSlackTokens();
  const c = connect.connection;
  if (c.state === "no_tokens") {
    return (
      <Section title={t("web-pages.connect.slack")} description={t("web-pages.connect.slackLead")}>
        <div className={pagesCss.card}>
          <CreateAppSteps name={connect.name} />
          <TokenFields value={tokens} onChange={setTokens} check={check} />
          <div className={pagesCss.cardActions}>
            <Button variant="primary" disabled={!check.ready} busy={check.busy || save.busy}
              onClick={() => check.then(() => save.put({ slack: { appToken: tokens.appToken, botToken: tokens.botToken } }, () => { setTokens(emptyTokens); toast(t("web-pages.connect.tokenSavedConnecting")); }))}>{t("web-pages.connect.saveConnect")}</Button>
          </div>
        </div>
      </Section>
    );
  }
  if (c.state === "error" || (c.state === "reconnecting" && c.lastError)) {
    return <div className={additionsCss.callout} data-tone="amber" role="status"><span>{c.state === "error" ? c.error : t("web-pages.connect.retrying", { error: c.lastError ?? "" })}</span></div>;
  }
  return null;
}

/** Replaces the connect's Slack tokens (either one; the other kept), verified before they are saved. */
function TokenDialog({ connect, onClose }: { connect: Connect; onClose(): void }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const [tokens, setTokens, check] = useSlackTokens({ connect: connect.id });
  return (
    <Dialog open onClose={onClose} title={t("web-pages.connect.replaceTitle")} description={t("web-pages.connect.replaceLead")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" disabled={!check.ready} busy={check.busy || save.busy}
          onClick={() => check.then(() => save.put({ slack: { appToken: tokens.appToken, botToken: tokens.botToken } }, () => { toast(t("web-pages.connect.tokenSavedReconnecting")); onClose(); }))}>{t("web-pages.connect.saveReconnect")}</Button>
      </>}>
      <TokenFields value={tokens} onChange={setTokens} masked={connect.slack} check={check} />
      {save.error && <p className={controlsCss.fieldError} role="alert">{save.error.message}</p>}
    </Dialog>
  );
}

/** The mode picker, shared by the connect page and the new-connect dialog. */
export function ModeChoices({ mode, requireMention, onChange, disabled }:
  { mode: ConnectMode; requireMention: boolean; onChange(next: { mode: ConnectMode; requireMention: boolean }): void; disabled?: boolean | undefined }) {
  return (
    <Choices label={t("web-pages.connect.mode")} value={mode} onChange={(m) => onChange({ mode: m, requireMention: m === "multi-session" ? true : requireMention })}
      options={(["multi-session", "single-session"] as const).map((m) => ({
        value: m, title: MODE[m].label, description: MODE[m].description, disabled,
        extra: m === "single-session" ? (
          <SwitchRow title={t("web-pages.connect.mentionOnly")} checked={requireMention} disabled={disabled}
            description={requireMention ? t("web-pages.connect.mentionOn") : t("web-pages.connect.mentionOff")}
            onChange={(v) => onChange({ mode, requireMention: v })} />
        ) : undefined,
      }))} />
  );
}

/**
 * How it runs, in one card: the model it runs (and who runs it), how its conversations become sessions, and in
 * single-session mode the session they go into. The runtime is its own for good: a line under them.
 */
function RunSection({ item }: { item: ConnectItem }) {
  const { connect, bound } = item;
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const station = useStation();
  const link = useLink();
  const [changingMode, setChangingMode] = useState(false);
  const [choosing, setChoosing] = useState(false);
  const models = useStationModels().filter((m) => m.runtimes.includes(connect.bind.runtime));
  // What it runs on and what its control's panel picked, as the core has them (../pick.ts).
  const pick = usePick(station.address, `connect:${connect.id}`);
  const saveBind = useAction(() => pick.save(), ({ saved }) => { if (saved) toast(t("web-pages.connect.bindSaved")); });
  return (
    <Section title={t("web-pages.connect.run")}>
      <div className={`${pagesCss.card} ${css.runCard}`}>
        <div className={css.runCardRow}>
          <span className={css.runCardLabel}>{t("web-pages.profiles.models")}</span>
          {models.length === 0
            ? <Link className={chatCss.inlineLink} to={profilesPage(station)}>{t("web-pages.connect.noModelsFor", { runtime: connect.runtimeText })}</Link>
            : <ModelTriple pick={pick} onConfirm={() => void saveBind.run()} />}
        </div>
        <div className={css.runCardRow}>
          <span className={css.runCardLabel}>{t("web-pages.connect.session")}</span>
          <span className={css.runCardText}>
            <strong>{MODE[connect.mode].label}</strong>
            <span className={shellCss.muted}>{MODE[connect.mode].description}{connect.mode === "single-session" && (connect.requireMention ? t("web-pages.connect.mentionOnlySentence") : t("web-pages.connect.everyMessageSentence"))}</span>
          </span>
          <button type="button" className={chatCss.textButton} onClick={() => setChangingMode(true)}>{t("web-pages.connect.change")}</button>
        </div>
        {connect.mode === "single-session" && (
          <div className={css.runCardRow}>
            <span className={css.runCardLabel}>{t("web-pages.connect.current")}</span>
            <span className={css.runCardText}>
              {bound
                ? <Link className={chatCss.inlineLink} to={link(`/chats/${encodeURIComponent(bound.key)}`)}>{bound.titleText}</Link>
                : <span className={shellCss.muted}>{t("web-pages.connect.noSession")}</span>}
            </span>
            <button type="button" className={chatCss.textButton} onClick={() => setChoosing(true)}>{t("web-pages.connect.switch")}</button>
          </div>
        )}
        {(save.error ?? saveBind.error) && <p className={controlsCss.fieldError} role="alert">{(save.error ?? saveBind.error)!.message}</p>}
        <p className={`${controlsCss.cardFoot} ${shellCss.muted}`}>{t("web-pages.connect.runtimeNote", { runtime: connect.runtimeText })}</p>
      </div>
      {changingMode && <ModeDialog connect={connect} running={item.running} onClose={() => setChangingMode(false)} />}
      {choosing && <ChooseSessionDialog item={item} onClose={() => setChoosing(false)} />}
    </Section>
  );
}

/** What switching to `next` does to this connect's conversations, in plain words. */
export function consequences(connect: Connect, next: { mode: ConnectMode; requireMention: boolean }, running: number): string[] {
  const out: string[] = [];
  if (connect.mode === "multi-session" && next.mode === "single-session") {
    out.push(t("web-pages.connect.effects.toSingle"));
    out.push(connect.session ? t("web-pages.connect.effects.resumeSingle") : t("web-pages.connect.effects.newSingle"));
    if (!next.requireMention) out.push(t("web-pages.connect.effects.noMention"));
  } else if (connect.mode === "single-session" && next.mode === "multi-session") {
    out.push(t("web-pages.connect.effects.toMulti"));
    out.push(t("web-pages.connect.effects.threadsRestart"));
    out.push(t("web-pages.connect.effects.switchBack"));
  } else if (next.requireMention !== connect.requireMention) {
    out.push(next.requireMention
      ? t("web-pages.connect.effects.mentionOnly")
      : t("web-pages.connect.effects.noMention"));
  }
  if (running > 0) out.push(t("web-pages.connect.effects.running", { n: running }));
  return out;
}

function ModeDialog({ connect, running, onClose }: { connect: Connect; running: number; onClose(): void }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const [next, setNext] = useState({ mode: connect.mode, requireMention: connect.requireMention });
  const changed = next.mode !== connect.mode || (next.mode === "single-session" && next.requireMention !== connect.requireMention);
  const effects = changed ? consequences(connect, next, running) : [];
  return (
    <Dialog open onClose={onClose} wide title={t("web-pages.connect.modeTitle")}
      description={t("web-pages.connect.modeLead")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" disabled={!changed} busy={save.busy}
          onClick={() => save.put(next, () => { toast(t("web-pages.connect.modeChanged")); onClose(); })}>
          {next.mode === connect.mode ? t("web-pages.connect.confirmChange") : next.mode === "single-session" ? t("web-pages.connect.toSingle") : t("web-pages.connect.toMulti")}
        </Button>
      </>}>
      <ModeChoices mode={next.mode} requireMention={next.requireMention} onChange={setNext} />
      {effects.length > 0 && (
        <div className={additionsCss.callout} data-tone="amber" role="note">
          <strong>{t("web-pages.connect.afterChange")}</strong>
          <ul>{effects.map((e) => <li key={e}>{e}</li>)}</ul>
        </div>
      )}
      {save.error && <p className={controlsCss.fieldError} role="alert">{save.error.message}</p>}
    </Dialog>
  );
}

/** A single-session connect's session: the one its messages go into, which people can switch or start afresh. */
function ChooseSessionDialog({ item, onClose }: { item: ConnectItem; onClose(): void }) {
  const { connect, candidates } = item;
  const api = useApi();
  const toast = useToast();
  const [choice, setChoice] = useState<string>(connect.session ?? "new");
  const [title, setTitle] = useState("");
  const bind = useAction(() => api.bindSession(connect.id, choice === "new" ? null : choice, title), () => {
    toast(choice === "new" ? t("web-pages.connect.sessionCreated") : t("web-pages.connect.sessionSwitched"));
    onClose();
  });
  return (
    <Dialog open onClose={onClose} wide title={t("web-pages.connect.chooseTitle")}
      description={t("web-pages.connect.chooseLead", { name: connect.name })}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={bind.busy} disabled={choice === connect.session}
          onClick={() => void bind.run()}>{choice === "new" ? t("web-pages.connect.createUse") : t("web-pages.connect.useThis")}</Button>
      </>}>
      <div className={css.sessionChoices}>
        <Choices label={t("web-pages.connect.session")} value={choice} onChange={setChoice} options={[
          {
            value: "new", title: t("web-pages.connect.newSession"), description: t("web-pages.connect.newSessionLead"),
            extra: <input className={controlsCss.input} value={title} onChange={(e) => setTitle(e.target.value)} placeholder={t("web-pages.connect.newSessionPlaceholder")} aria-label={t("web-pages.connect.newSessionName")} />,
          },
          ...candidates.map((s) => ({
            value: s.key,
            title: <>{s.titleText}{s.current && <span className={additionsCss.choiceBadge}>{t("web-pages.connect.current")}</span>}</>,
            description: s.description,
          })),
        ]} />
      </div>
      {bind.error && <p className={controlsCss.fieldError} role="alert">{bind.error.message}</p>}
    </Dialog>
  );
}

/** How many of its latest sessions show before the rest are asked for. */
const SESSIONS_SHOWN = 5;

function ConnectSessions({ item }: { item: ConnectItem }) {
  const { connect, sessions } = item;
  const link = useLink();
  const [all, setAll] = useState(false);
  const shown = all ? sessions : sessions.slice(0, SESSIONS_SHOWN);
  return (
    <Section title={t("web-pages.connect.recent")}>
      {sessions.length === 0 ? <p className={shellCss.muted}>{t("web-pages.connect.recentNone", { name: connect.name })}</p> : (
        <ul className={pagesCss.list}>
          {shown.map((s) => {
            const row = (
              <>
                <span className={pagesCss.listRowTitle}>{s.titleText}</span>
                <Pill tone={s.tone}><StatusText text={s.statusText} /></Pill>
                <Time className={`${shellCss.muted} ${css.listRowTime}`} stamp={s.time?.lastActiveAt} />
              </>
            );
            return <li key={s.key}><Link className={pagesCss.listRow} to={link(`/chats/${encodeURIComponent(s.key)}`)}>{row}</Link></li>;
          })}
        </ul>
      )}
      {sessions.length > SESSIONS_SHOWN && (
        <button type="button" className={`${chatCss.textButton} ${css.moreSessions}`} onClick={() => setAll(!all)}>
          {all ? t("web-pages.profiles.collapse") : t("web-pages.connect.showAll", { n: sessions.length })}
        </button>
      )}
    </Section>
  );
}


/**
 * A new connect. Slack first: its app (made by ember with the workspace's configuration token, or by hand) and its
 * two tokens; the connect is named as its bot is in Slack, and its id comes from that. Then the model it runs.
 */
type NewStep = "team" | "app" | "install" | "manual" | "bind";

type SlackTeam = Overview["slackTeams"][number];

/** A Slack workspace's icon, or Slack's mark before it is known. */
function SlackTeamIcon({ team }: { team: SlackTeam }) {
  return team.owner?.teamIcon
    ? <img className={css.slackTeamIcon} src={team.owner.teamIcon} alt="" width={28} height={28} referrerPolicy="no-referrer" />
    : <span className={css.slackTeamIcon}><SlackLogo size={18} /></span>;
}

/** Whose configuration token it is there: the person (picture, name, email) and the workspace's address. */
function TokenOwner({ team }: { team: SlackTeam }) {
  const o = team.owner;
  if (!o) return null;
  return (
    <span className={css.tokenOwner}>
      {o.image && <img src={o.image} alt="" width={16} height={16} referrerPolicy="no-referrer" />}
      <span>{o.user}{o.email ? `（${o.email}）` : ""}</span>
      {o.teamDomain && <span className={shellCss.muted}>{o.teamDomain}.slack.com</span>}
    </span>
  );
}

/**
 * A new Slack connect, in steps: the Slack workspace to make its app in (a configuration token each, or a new one);
 * the app's look and permissions; making it and installing it (Slack's OAuth gives the station the bot token), then
 * the app-level token; last, the model it runs. Without a configuration token the app is made in Slack by hand and
 * both tokens are pasted.
 */
export function NewConnectDialog(props: { open: boolean; onClose(): void; resume?: string | undefined }) {
  return props.open ? <CoreNewConnectDialog {...props} /> : null;
}

function CoreNewConnectDialog({ open, onClose, resume }: { open: boolean; onClose(): void; resume?: string | undefined }) {
  const station = useStation();
  const link = useLink();
  const navigate = useNavigate();
  const toast = useToast();
  const flow = useConnectFlow(station.address, false, resume);
  const [tokens, setTokens, tokenCheck] = useSlackTokens({ install: flow.view?.made?.state ?? undefined, form: flow.form });
  // Only the input's immediate echo belongs to React; all decisions use the core's view.
  const [echo, setEcho] = useState<SlackAppSettings | null>(null);
  if (flow.unsupported) return <LegacyNewConnectDialog open={open} onClose={onClose} resume={resume} />;
  const view = flow.view;
  if (!view) return <Dialog open={open} onClose={onClose} title={t("web-pages.connects.add")}>{t("web-pages.settings.reading")}</Dialog>;
  const { step, teams, chosen, made, madeId, adding, gettingToken } = view;
  const app = echo ?? view.settings as SlackAppSettings;
  const icon = view.icon ?? null;
  const iconError = view.iconError ?? null;
  const pick = flow.pick;
  const models = pick.view?.options ?? [];
  const mode = { mode: view.mode, requireMention: view.requireMention };
  const setMode = (mode: { mode: ConnectMode; requireMention: boolean }) => flow.edit(mode);
  const setApp = (settings: SlackAppSettings) => { setEcho(settings); flow.edit({ settings }); };
  const setTeam = (team: string | null) => flow.edit({ team });
  const setAdding = (adding: boolean) => flow.edit({ adding });
  const setIcon = (icon: string | null) => flow.edit({ icon });
  const setIconError = (iconError: string | null) => flow.edit({ iconError });
  const setStep = (step: string) => flow.go(step);
  const close = onClose;
  const act = (_: Promise<unknown>, __: string) => { void _.catch((e: Error) => toast(e.message)); };
  const check = { ...tokenCheck, busy: flow.busy, then: (_go: () => void) => flow.act("verify") };
  const makeApp = { busy: flow.busy, error: flow.error ? new Error(flow.error) : null, run: () => flow.act("make") };
  const create = { busy: flow.busy, error: flow.error ? new Error(flow.error) : null, run: () => flow.act("create", ({ id }) => {
    toast(t("web-pages.connect.added")); close(); navigate(link(`/connects/${id}`));
  }) };
  const footer = step === "team" ? (
    <>
      {adding && teams.length > 0
        ? <Button variant="ghost" onClick={() => setAdding(false)}>{t("common.back")}</Button>
        : <Button variant="ghost" onClick={close}>{t("common.cancel")}</Button>}
      {!gettingToken && <Button variant="primary" disabled={!chosen} onClick={() => setStep("app")}>{t("web-pages.connect.next")}</Button>}
    </>
  ) : step === "app" ? (
    <>
      <Button variant="ghost" onClick={() => setStep("team")}>{t("web-pages.connect.previous")}</Button>
      <Button variant="primary" disabled={!view.canMake} busy={makeApp.busy} onClick={() => void makeApp.run()}>{t("web-pages.connect.createApp")}</Button>
    </>
  ) : step === "install" || step === "manual" ? (
    <>
      <Button variant="ghost" onClick={step === "manual" ? () => setStep("team") : close}>{step === "manual" ? t("web-pages.connect.previous") : t("common.cancel")}</Button>
      <Button variant="primary" disabled={!check.ready} busy={check.busy} onClick={() => check.then(() => setStep("bind"))}>{t("web-pages.connect.next")}</Button>
    </>
  ) : (
    <>
      <Button variant="ghost" onClick={() => setStep(madeId ? "install" : "manual")}>{t("web-pages.connect.previous")}</Button>
      <Button variant="primary" disabled={models.length === 0} busy={create.busy} onClick={() => void create.run()}>{t("web-pages.connect.addConnect")}</Button>
    </>
  );

  return (
    <Dialog open={open} onClose={close} wide title={<>{view.title}<span className={css.dialogStep}>{view.number} / {view.total}</span></>} footer={footer}
      description={step === "team" && !gettingToken ? t("web-pages.connect.teamLead") : undefined}>
      {gettingToken && (
        <div className={css.tokenStart}>
          <p className={shellCss.muted}>{t("web-pages.connect.tokenWhy", { name: NAME })}</p>
          <ConfigTokenForm flow={flow} onSaved={() => {}} />
          {teams.length === 0 && <p className={`${shellCss.muted} ${css.tokenManual}`}>{t("web-pages.connect.noToken")}<button type="button" className={chatCss.textButton} onClick={() => setStep("manual")}>{t("web-pages.connect.manualApp")}</button></p>}
        </div>
      )}
      {step === "team" && !gettingToken && (
        <>
          <Choices label={t("web-pages.connect.slackWorkspace")} value={chosen?.teamId ?? ""} onChange={setTeam}
            options={teams.map((t) => ({ value: t.teamId, title: t.name, icon: <SlackTeamIcon team={t} />, description: <TokenOwner team={t} /> }))} />
          <div className={css.teamMore}>
            <Button variant="ghost" onClick={() => setAdding(true)}><Plus {...ICON} />{t("web-pages.connect.addTeamToken")}</Button>
            <button type="button" className={`${chatCss.textButton} ${css.tokenManual}`} onClick={() => setStep("manual")}>{t("web-pages.connect.manualShort")}</button>
          </div>
        </>
      )}
      {step === "app" && (
        <div className="slack-app">
          <AppFields fresh settings={app} onChange={setApp} icon={icon} onIcon={(i, e) => { setIcon(i); setIconError(e); }} />
          {iconError && <p className={controlsCss.fieldError} role="alert">{iconError}</p>}
          {makeApp.error && <p className={controlsCss.fieldError} role="alert">{makeApp.error.message}</p>}
        </div>
      )}
      {step === "install" && made && (
        <>
          <MadeAppSteps made={made} />
          {iconError && <p className={controlsCss.fieldError} role="alert">{t("web-pages.connect.iconFailed", { error: iconError })}</p>}
          <TokenFields value={tokens} onChange={setTokens} install={made.state ?? undefined} check={check} />
        </>
      )}
      {step === "manual" && (
        <>
          <CreateAppSteps name={NAME} />
          <TokenFields value={tokens} onChange={setTokens} check={check} />
        </>
      )}
      {step === "bind" && (
        <>
          <Field label={t("web-pages.profiles.models")} hint={(pick.view?.valueOption?.runtimes.length ?? 0) > 1 ? t("web-pages.connect.bothRuntimes") : undefined}>
            {models.length === 0
              ? <Link className={`${controlsCss.input} ${css.inputLink}`} to={profilesPage(station)}>{t("web-pages.connect.noModels")}</Link>
              : <ModelTriple pick={pick} onConfirm={() => act(pick.save(), t("web-pages.connect.changeModel"))} />}
          </Field>
          <Field label={t("web-pages.connect.mode")}>
            <ModeChoices mode={mode.mode} requireMention={mode.requireMention} onChange={setMode} />
          </Field>
          {create.error && <p className={controlsCss.fieldError} role="alert">{create.error.message}</p>}
        </>
      )}
    </Dialog>
  );
}


// Compatibility for desktop releases whose bundled core predates connect.flow.
function LegacyNewConnectDialog({ open, onClose, resume }: { open: boolean; onClose(): void; resume?: string | undefined }) {
  const api = useApi();
  const station = useStation();
  const link = useLink();
  const overview = useOverview(station.address);
  const navigate = useNavigate();
  const toast = useToast();
  const teams = overview.value?.slackTeams ?? [];
  // `resume`: an app made before and still waiting on the station, picked up where it was left (installing it).
  const [step, setStep] = useState<NewStep>(resume ? "install" : "team");
  const [team, setTeam] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  const [app, setApp] = useState(NEW_APP);
  const [icon, setIcon] = useState<string | null>(null);
  const [iconError, setIconError] = useState<string | null>(null);
  // The app made, as the station keeps it (it outlives this dialog: the connects page lists it until it is connected).
  const [madeId, setMadeId] = useState<string | null>(resume ?? null);
  const made: MadeSlackApp | undefined = madeId ? overview.value?.slackApps?.find((a) => a.appId === madeId) : undefined;
  const [tokens, setTokens, check] = useSlackTokens({ install: made?.state ?? undefined });
  // The model first; the runtime only when the model runs on more than one (the core's pick of a connect being added).
  const models = useStationModels();
  const pick = usePick(station.address, "connect-new");
  const act = useAct();
  const bound = pick.view?.value;
  const [mode, setMode] = useState<{ mode: ConnectMode; requireMention: boolean }>({ mode: "multi-session", requireMention: true });
  // The workspace chosen, else the only one there is.
  const chosen = teams.find((t) => t.teamId === team) ?? (teams.length === 1 ? teams[0] : undefined);

  const close = () => {
    setStep("team"); setTeam(null); setAdding(false); setApp(NEW_APP); setIcon(null); setIconError(null); setMadeId(null);
    setTokens(emptyTokens); pick.set({ clear: true }); setMode({ mode: "multi-session", requireMention: true });
    onClose();
  };
  const makeApp = useAction(() => api.makeSlackApp({ team: chosen!.teamId, settings: app, ...(icon ? { icon } : {}) }), (result) => {
    setMadeId(result.appId); setIconError(result.iconError); setStep("install");
  });
  const create = useAction(() => api.createConnect({
    kind: "slack", ...mode, bind: { runtime: bound?.runtime ?? "claude", model: bound?.model ?? "", effort: bound?.effort ?? "", profile: bound?.profile ?? null },
    slack: made?.state ? { appToken: tokens.appToken, install: made.state }
      : { appToken: tokens.appToken, botToken: tokens.botToken, ...(made ? { appId: made.appId } : {}) },
  }), ({ id }) => {
    toast(t("web-pages.connect.added"));
    close();
    navigate(link(`/connects/${id}`));
  });

  // Getting a token is a view of its own: when there is none yet, or another is being added.
  const gettingToken = step === "team" && (teams.length === 0 || adding);
  const TITLES: Record<NewStep, string> = { team: teams.length === 0 ? t("web-pages.connect.step.firstToken") : adding ? t("web-pages.slackApp.addTokenTitle") : t("web-pages.connect.step.team"), app: t("web-pages.connect.step.app"), install: t("web-pages.connect.step.install"), manual: t("web-pages.connect.step.manual"), bind: t("web-pages.connect.step.bind") };
  const order: NewStep[] = step === "manual" || (step === "bind" && !madeId) ? ["manual", "bind"] : ["team", "app", "install", "bind"];
  const footer = step === "team" ? (
    <>
      {adding && teams.length > 0
        ? <Button variant="ghost" onClick={() => setAdding(false)}>{t("common.back")}</Button>
        : <Button variant="ghost" onClick={close}>{t("common.cancel")}</Button>}
      {!gettingToken && <Button variant="primary" disabled={!chosen} onClick={() => setStep("app")}>{t("web-pages.connect.next")}</Button>}
    </>
  ) : step === "app" ? (
    <>
      <Button variant="ghost" onClick={() => setStep("team")}>{t("web-pages.connect.previous")}</Button>
      <Button variant="primary" disabled={!app.name.trim()} busy={makeApp.busy} onClick={() => void makeApp.run()}>{t("web-pages.connect.createApp")}</Button>
    </>
  ) : step === "install" || step === "manual" ? (
    <>
      <Button variant="ghost" onClick={step === "manual" ? () => setStep("team") : close}>{step === "manual" ? t("web-pages.connect.previous") : t("common.cancel")}</Button>
      <Button variant="primary" disabled={!check.ready} busy={check.busy} onClick={() => check.then(() => setStep("bind"))}>{t("web-pages.connect.next")}</Button>
    </>
  ) : (
    <>
      <Button variant="ghost" onClick={() => setStep(madeId ? "install" : "manual")}>{t("web-pages.connect.previous")}</Button>
      <Button variant="primary" disabled={models.length === 0} busy={create.busy} onClick={() => void create.run()}>{t("web-pages.connect.addConnect")}</Button>
    </>
  );

  return (
    <Dialog open={open} onClose={close} wide title={<>{TITLES[step]}<span className={css.dialogStep}>{order.indexOf(step) + 1} / {order.length}</span></>} footer={footer}
      description={step === "team" && !gettingToken ? t("web-pages.connect.teamLead") : undefined}>
      {gettingToken && (
        <div className={css.tokenStart}>
          <p className={shellCss.muted}>{t("web-pages.connect.tokenWhy", { name: NAME })}</p>
          <ConfigTokenForm onSaved={(id) => { setTeam(id); setAdding(false); setStep("app"); }} />
          {teams.length === 0 && <p className={`${shellCss.muted} ${css.tokenManual}`}>{t("web-pages.connect.noToken")}<button type="button" className={chatCss.textButton} onClick={() => setStep("manual")}>{t("web-pages.connect.manualApp")}</button></p>}
        </div>
      )}
      {step === "team" && !gettingToken && (
        <>
          <Choices label={t("web-pages.connect.slackWorkspace")} value={chosen?.teamId ?? ""} onChange={setTeam}
            options={teams.map((t) => ({ value: t.teamId, title: t.name, icon: <SlackTeamIcon team={t} />, description: <TokenOwner team={t} /> }))} />
          <div className={css.teamMore}>
            <Button variant="ghost" onClick={() => setAdding(true)}><Plus {...ICON} />{t("web-pages.connect.addTeamToken")}</Button>
            <button type="button" className={`${chatCss.textButton} ${css.tokenManual}`} onClick={() => setStep("manual")}>{t("web-pages.connect.manualShort")}</button>
          </div>
        </>
      )}
      {step === "app" && (
        <div className="slack-app">
          <AppFields fresh settings={app} onChange={setApp} icon={icon} onIcon={(i, e) => { setIcon(i); setIconError(e); }} />
          {iconError && <p className={controlsCss.fieldError} role="alert">{iconError}</p>}
          {makeApp.error && <p className={controlsCss.fieldError} role="alert">{makeApp.error.message}</p>}
        </div>
      )}
      {step === "install" && made && (
        <>
          <MadeAppSteps made={made} />
          {iconError && <p className={controlsCss.fieldError} role="alert">{t("web-pages.connect.iconFailed", { error: iconError })}</p>}
          <TokenFields value={tokens} onChange={setTokens} install={made.state ?? undefined} check={check} />
        </>
      )}
      {step === "manual" && (
        <>
          <CreateAppSteps name={NAME} />
          <TokenFields value={tokens} onChange={setTokens} check={check} />
        </>
      )}
      {step === "bind" && (
        <>
          <Field label={t("web-pages.profiles.models")} hint={(pick.view?.valueOption?.runtimes.length ?? 0) > 1 ? t("web-pages.connect.bothRuntimes") : undefined}>
            {models.length === 0
              ? <Link className={`${controlsCss.input} ${css.inputLink}`} to={profilesPage(station)}>{t("web-pages.connect.noModels")}</Link>
              : <ModelTriple pick={pick} onConfirm={() => act(pick.save(), t("web-pages.connect.changeModel"))} />}
          </Field>
          <Field label={t("web-pages.connect.mode")}>
            <ModeChoices mode={mode.mode} requireMention={mode.requireMention} onChange={setMode} />
          </Field>
          {create.error && <p className={controlsCss.fieldError} role="alert">{create.error.message}</p>}
        </>
      )}
    </Dialog>
  );
}

/**
 * What is left in Slack once still.fail made the app: installing it, and the app-level token. Installed through Slack's
 * OAuth (`made.install`), Slack sends the bot token back to the station itself; else it is copied from the OAuth page.
 */
function MadeAppSteps({ made }: { made: MadeSlackApp }) {
  const { links } = made;
  return (
    <ol className={controlsCss.steps}>
      {made.install ? (
        <li>
          {made.installed
            ? <span className={controlsCss.verifyOk}><CheckCircle {...ICON} />{t("web-pages.cloud.slackInstalled.done", { team: made.installedTeam ?? made.team ?? t("web-pages.cloud.slackInstalled.workspace") })}</span>
            : <span>{t("web-pages.connect.made.oauth")}</span>}
          {!made.installed && <a className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} href={made.install} target="_blank" rel="noopener"><External {...ICON} />{t("web-pages.connect.made.install")}</a>}
        </li>
      ) : (
        <li>
          <span>{t("web-pages.connect.made.manual")}</span>
          <span className={css.stepActions}>
            <a className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} href={links.install} target="_blank" rel="noopener"><External {...ICON} />{t("web-pages.connect.made.install")}</a>
            <a className={`${controlsCss.btn} btn-secondary`} href={links.oauth} target="_blank" rel="noopener">{t("web-pages.connect.made.openOauth")}</a>
          </span>
        </li>
      )}
      <li>
        <span>{t("web-pages.connect.made.appToken")}</span>
        <a className={`${controlsCss.btn} btn-secondary`} href={links.appToken} target="_blank" rel="noopener"><External {...ICON} />{t("web-pages.connect.made.openSocket")}</a>
      </li>
      <li>{made.install ? t("web-pages.connect.made.fillOne") : t("web-pages.connect.made.fillBoth")}</li>
    </ol>
  );
}

/** Hands a connect to another person: a workspace member (any email, while the members are not read yet). */
function OwnerDialog({ connect, onClose }: { connect: Connect; onClose(): void }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const people = [...useContext(PeopleContext).values()];
  const [owner, setOwner] = useState(connect.createdBy?.id ?? people[0]?.email ?? "");
  const chosen = people.find((p) => p.email.toLowerCase() === owner.toLowerCase());
  return (
    <Dialog open onClose={onClose} title={t("web-pages.connect.changeOwner")} description={t("web-pages.connect.ownerLead")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" disabled={!owner.trim() || owner === connect.createdBy?.id} busy={save.busy}
          onClick={() => save.put({ owner: { id: owner.trim(), name: chosen?.name ?? owner.trim() } }, () => { toast(t("web-pages.connect.ownerChanged")); onClose(); })}>{t("common.save")}</Button>
      </>}>
      {people.length > 0 ? (
        <Field label={t("web-pages.connect.ownerLabel")}>
          <Select value={owner} onChange={setOwner} label={t("web-pages.connect.ownerLabel")} options={people.map((p) => ({ value: p.email, label: p.name ? t("web-pages.connect.person", { name: p.name, email: p.email }) : p.email }))} />
        </Field>
      ) : (
        <Field label={t("web-pages.connect.ownerEmail")} htmlFor="owner-email">
          <input id="owner-email" className={controlsCss.input} type="email" value={owner} onChange={(e) => setOwner(e.target.value)} placeholder="name@example.com" />
        </Field>
      )}
      {save.error && <p className={controlsCss.fieldError} role="alert">{save.error.message}</p>}
    </Dialog>
  );
}
