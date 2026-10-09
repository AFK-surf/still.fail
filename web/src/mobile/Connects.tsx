import { StatusText } from "../ui.tsx";
import { useConnectFlow } from "../connect-flow.ts";
// Connects on a narrow screen (what the desktop's ../pages/Connects.tsx and Connect.tsx do, in the Android app's
// manner): the list, all or the viewer's; a connect's page (how it runs, how its conversations become sessions, its
// Slack link, what is done to it less often under "…"); how it runs, picked on a page of its own; a new one, in steps.
import { useEffect, useMemo, useRef, useState } from "react";
import { useParams, useSearchParams } from "react-router";
import { stationApi, useConnects, useOverview, useStationCall, useStations, type Connect, type ConnectItem, type ConnectMode, type MadeSlackApp, type ModelOption, type RuntimeKind, type SlackAppSettings, type SlackIdentity } from "../api.ts";
import { useWorkspace } from "../cloud/api.ts";
import { MODE, RUNTIME_LABEL } from "../format.ts";
import { illustrationUrl } from "../brand.tsx";
import { ChevronRight, More, Plus } from "../icons.tsx";
import { usePick } from "../pick.ts";
import { consequences } from "../pages/Connect.tsx";
import { edgeColour, MAKERS, NEW_APP, renderAvatar, toIcon, useBuddies, type Avatar } from "../pages/SlackApp.tsx";
import { useSlackTokens, type TokenCheck } from "../slack.tsx";
import { StationContext, stationBase, useOnlyMine, useStation } from "../station.tsx";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { AccountList, ModelList, SettingRow } from "./History.tsx";
import { Button, Field, GroupLabel, LargeTitle, LinkButton, ListCard, ListRow, Loading, MakerIcon, NavBar, NavButton, PickRow, SectionHeader, Seg, SlackMark, Spinner, tNodes, TopBack } from "./parts.tsx";
import { ask, confirm } from "./sheets.tsx";
import { PickStation } from "./Profiles.tsx";
import * as settingsCss from "./styles/settings.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as historyCss from "./styles/history.css.ts";
import * as css from "./Connects.css.ts";
import * as newChatCss from "./styles/new-chat.css.ts";

import { NAME } from "../channel.ts";
import { useDoing, useDoingFailed } from "../doing.ts";
import { t } from "../i18n.ts";
/** A connect's presence as a dot: online green, at work orange, failing red, offline hollow. */
export function Presence({ state }: { state: string }) {
  return <span className={settingsCss.mPresence} data-state={state} />;
}

/** A connect as its people see it in Slack: its bot's picture; Slack's mark until Slack has said what that is. */
function ConnectAvatar({ connect, size }: { connect: Connect; size: number }) {
  return connect.botImage ? <img className={chatCss.botAvatar} src={connect.botImage} width={size} height={size} alt="" loading="lazy" referrerPolicy="no-referrer" /> : <SlackMark size={Math.round(size * 0.55)} />;
}

/** A connect in its station's list: its mark and name, how it runs, and its presence. */
export function ConnectRow({ connect: c, onClick }: { connect: Connect; onClick: () => void }) {
  return (
    <ListRow onClick={onClick}>
      <ConnectAvatar connect={c} size={30} />
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{c.name}{c.team && <span className={settingsCss.mRowAside}> · {c.team}</span>}</span>
        <span className={listsCss.mRowNote}>{c.modeText} · {c.runtimeText}{c.bind.model ? ` · ${c.modelName ?? c.bind.model}` : ""}</span>
      </span>
      <span className={settingsCss.mRowStatus}><Presence state={c.presence} />{c.statusText}</span>
    </ListRow>
  );
}

/** Where a Slack app made and not connected yet stands, in words. */
function waitingText(made: MadeSlackApp): string {
  return made.installed ? t("web-mobile.connects.waiting.installed", { team: made.installedTeam ?? made.team ?? t("web-mobile.connects.slackWorkspace") }) : made.install ? t("web-mobile.connects.waiting.install") : t("web-mobile.connects.waiting.token");
}

/**
 * A Slack app made and not connected yet, in its station's list (the station in context): where it stands; going on
 * from there (its station online), or dropping it (it stays in Slack), in a sheet.
 */
export function WaitingAppRow({ made, online }: { made: MadeSlackApp; online: boolean }) {
  const app = useApp();
  return (
    <ListRow onClick={() => app.sheet({ height: 0.4, content: () => <WaitingAppSheet made={made} online={online} /> })}>
      <SlackMark size={16} />
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{made.name}{made.team && <span className={settingsCss.mRowAside}> · {made.team}</span>}</span>
        <span className={listsCss.mRowNote}>{waitingText(made)}</span>
      </span>
      {online ? <span className={partsCss.mLink}>{t("web-mobile.connects.continue")}</span> : <span className={listsCss.mRowNote}>{t("web-mobile.connects.stationOffline")}</span>}
    </ListRow>
  );
}

function WaitingAppSheet({ made, online }: { made: MadeSlackApp; online: boolean }) {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  return (
    <>
      <SheetGrab />
      <SheetHead title={made.name} />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${partsCss.mPad} ${partsCss.mSmall}`}>{t("web-mobile.connects.sentence", { text: waitingText(made) })}</p>
        <PickRow label={made.installed ? t("web-mobile.connects.fillAppToken") : made.install ? t("web-mobile.connects.continueInstall") : t("web-mobile.connects.fillToken")} enabled={online} sub={online ? undefined : t("web-mobile.connects.offlineWait")}
          onClick={() => { app.sheet(null); app.push(`${stationBase(station.address)}/connects/new?resume=${encodeURIComponent(made.appId)}`); }} />
        <PickRow label={t("web-mobile.connects.drop")} accent onClick={() => confirm(app, {
          title: t("web-mobile.stations.removeAsk", { name: made.name }), action: t("web-mobile.workspace.remove"), danger: true,
          text: t("web-mobile.connects.dropText", { name: NAME }), atOnce: "web-mobile.workspace.removeFailed",
          run: () => api.dropSlackApp(made.appId).then(() => app.toast(t("web-mobile.workspace.removed"))),
        })} />
      </div>
    </>
  );
}

/** The station's API in context. */
function useApi() {
  const station = useStation();
  const call = useStationCall(station.address);
  return useMemo(() => stationApi(call), [call]);
}

function useItem(): { item: ConnectItem | undefined; loading: boolean; error: Error | null } {
  const station = useStation();
  const { id = "" } = useParams();
  const connects = useConnects(station.address.split("/")[0]!);
  const item = connects.value?.items.find((i) => i.station === station.address && i.connect.id === id);
  return { item, loading: !connects.value || connects.value.loading, error: connects.error };
}

/**
 * Every station's connects on one page, from settings (./Settings.tsx), as the desktop's settings have them: all or
 * those the viewer made, each station's under its name with the Slack apps made there and not connected yet; a
 * station offline says so. A new one is added on a station picked (the only one online, without asking).
 */
export function ConnectsScreen() {
  const app = useApp();
  const [mine, setMine] = useState(false);
  const connects = useConnects(app.entry.id, mine);
  // From a station's page (?station=<id>): that station's only, back to it.
  const [params] = useSearchParams();
  const only = params.get("station");
  const listed = useStations(app.entry.id).value;
  const stations = only ? listed?.filter((s) => s.id === only) : listed;
  const one = only ? stations?.[0] : undefined;
  const online = stations?.filter((s) => s.online) ?? [];
  const items = connects.value?.items ?? [];
  const add = () => online.length === 1
    ? app.push(app.at(`/s/${online[0]!.id}/connects/new`))
    : app.sheet({ height: 0.5, content: () => <PickStation title={t("web-mobile.connects.add")} stations={online} to={(s) => `/s/${s.id}/connects/new`} /> });
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={one?.name ?? t("web-mobile.settings.title")} onBack={app.pop} trailing={online.length > 0 ? <NavButton icon={Plus} iconSize={20} label={t("web-mobile.connects.add")} onClick={add} /> : undefined} />
      <LargeTitle small={one ? t("web-mobile.connects.on", { station: one.name }) : ""} big={t("web-mobile.settings.connects")} />
      <p className={settingsCss.mPageNote}>{t("web-mobile.connects.note", { name: NAME })}</p>
      <div className={css.mListSeg}><Seg options={[t("web-mobile.home.filterAll"), t("web-mobile.connects.mine")]} selected={mine ? 1 : 0} onSelect={(i) => setMine(i === 1)} height={34} fill /></div>
      {!stations || !connects.value ? <Loading text={connects.error?.message ?? t("web-mobile.connects.reading")} /> : stations.map((s) => {
        const here = items.filter((i) => i.station === s.station);
        const waiting = s.overview?.slackApps ?? [];
        if (s.online && here.length === 0 && waiting.length === 0 && mine && !one) return null;
        return (
          <StationContext.Provider key={s.id} value={{ id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${app.entry.id}/settings` }}>
            {!one && <SectionHeader title={s.online ? s.name : t("web-mobile.connects.stationOfflineTitle", { station: s.name })} start={24} />}
            <ListCard>
              {!s.online && here.length === 0 ? <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>{t("web-mobile.connects.offlineList")}</span></ListRow>
                : here.length === 0 && waiting.length === 0 ? <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>{s.overview ? t("web-mobile.connects.none") : t("web-mobile.reading")}</span></ListRow>
                : null}
              {here.map((i) => <ConnectRow key={i.connect.id} connect={i.connect} onClick={() => app.push(`${stationBase(i.station)}/connects/${encodeURIComponent(i.connect.id)}`)} />)}
              {/* The Slack apps made here that no connect has taken yet: to be finished any time. */}
              {waiting.map((a) => <WaitingAppRow key={a.appId} made={a} online={s.online} />)}
            </ListCard>
          </StationContext.Provider>
        );
      })}
      <div style={{ height: 30 }} />
    </div>
  );
}

export function ConnectScreen() {
  const app = useApp();
  const { item, loading, error } = useItem();
  if (!item) {
    return <div className={pagesCss.mScreen}><NavBar back={t("web-mobile.settings.connects")} onBack={app.pop} title={t("web-mobile.settings.connects")} /><Loading text={error?.message ?? (loading ? t("web-mobile.connects.reading") : t("web-mobile.connects.notFound"))} /></div>;
  }
  return <ConnectPage item={item} />;
}

function ConnectPage({ item }: { item: ConnectItem }) {
  const app = useApp();
  const station = useStation();
  const { connect, bound, sessions } = item;
  const c = connect.connection;
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={t("web-mobile.settings.connects")} onBack={app.pop} title={connect.name} sub={<span className={barsCss.mNavbarNote}><Presence state={connect.presence} /> {connect.statusText}</span>}
        trailing={<NavButton icon={More} label={t("common.more")} onClick={() => app.sheet({ height: 0.6, content: () => <ConnectMenu connect={connect} /> })} />} />
      <div className={`${pagesCss.mScroll} ${settingsCss.mStationPage}`}>
        {/* Who it is in Slack: its bot's picture, its Slack workspace, whose it is. */}
        <div className={`${listsCss.mCard} ${settingsCss.mProfileHead}`}>
          <ConnectAvatar connect={connect} size={44} />
          <span className={partsCss.mGrow}>
            <span className={listsCss.mRowTitle}>{connect.team ?? "Slack"}</span>
            <span className={listsCss.mRowNote}>{station.name}{connect.createdBy ? t("web-mobile.connects.owner", { owner: connect.createdBy.shown?.display ?? connect.createdBy.name }) : ""}</span>
          </span>
        </div>
        {(c.state === "no_tokens" || c.state === "error" || (c.state === "reconnecting" && c.lastError)) && (
          <div className={settingsCss.mCallout}>
            {c.state === "no_tokens" ? <>{t("web-mobile.connects.noTokens")}<button type="button" className={partsCss.mLink} onClick={() => openTokens(app, connect)}>{t("web-mobile.connects.fillToken")}</button></>
              : c.state === "error" ? c.error : t("web-mobile.connects.reconnecting", { error: c.lastError ?? "" })}
          </div>
        )}
        <SectionHeader title={t("web-mobile.connects.howRuns")} start={24} />
        <ListCard>
          <ListRow onClick={() => app.push(`${stationBase(station.address)}/connects/${encodeURIComponent(connect.id)}/run`)}>
            <span className={historyCss.mRunLabel}>{t("web-mobile.history.model")}</span>
            <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{connect.bind.model ? connect.modelName ?? connect.bind.model : t("web-mobile.history.pickModel")}<span className={partsCss.mMuted}> · {connect.bind.effort || t("web-mobile.newChat.effortDefault")} · {connect.bind.profile ? t("web-mobile.connects.pinnedAccount") : t("web-mobile.history.auto")}</span></span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
          <ListRow onClick={() => app.sheet({ height: 0.8, draggable: true, content: () => <ModeSheet item={item} /> })}>
            <span className={historyCss.mRunLabel}>{t("web-mobile.connects.session")}</span>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
              <span className={listsCss.mRowTitle}>{MODE[connect.mode].label}</span>
              <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{MODE[connect.mode].description}{connect.mode === "single-session" && (connect.requireMention ? t("web-mobile.connects.mentionOnly") : t("web-mobile.connects.everyMessage"))}</span>
            </span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
          {connect.mode === "single-session" && (
            <ListRow onClick={() => app.sheet({ height: 0.7, draggable: true, content: () => <SessionSheet item={item} /> })}>
              <span className={historyCss.mRunLabel}>{t("web-mobile.connects.current")}</span>
              <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{bound ? bound.titleText : <span className={partsCss.mMuted}>{t("web-mobile.connects.noSession")}</span>}</span>
              <ChevronRight size={14} className={partsCss.mSubtle} />
            </ListRow>
          )}
        </ListCard>
        <p className={settingsCss.mPageNote}>{t("web-mobile.connects.runtimeNote", { runtime: connect.runtimeText })}</p>
        <SectionHeader title={t("web-mobile.app.recent")} start={24} />
        <ListCard>
          {sessions.length === 0 && <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>{t("web-mobile.connects.noSessions", { name: connect.name })}</span></ListRow>}
          {sessions.map((s) => (
            <ListRow key={s.key} onClick={() => app.push(`${stationBase(station.address)}/chats/${encodeURIComponent(s.key)}`)}>
              <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{s.titleText}</span>
              <span className={listsCss.mRowNote}><StatusText text={s.statusText} /></span>
            </ListRow>
          ))}
        </ListCard>
        <div style={{ height: 30 }} />
      </div>
    </div>
  );
}

/** What is done to a connect less often: reconnecting, its tokens, Slack, turning it off or on, its owner, deleting it. */
function ConnectMenu({ connect }: { connect: Connect }) {
  const app = useApp();
  const api = useApi();
  const workspace = connect.connection.workspace;
  const station = useStation().address;
  // The sheet goes at once; what is under way shows on its row if it is opened again (one that failed with the failure
  // mark a few seconds), the toast says how it ended.
  const reconnecting = useDoing("connect.reconnect", { station, id: connect.id });
  const putting = useDoing("connect.put", { station, id: connect.id });
  const deleting = useDoing("connect.delete", { station, id: connect.id });
  const reconnectFailed = useDoingFailed("connect.reconnect", { station, id: connect.id });
  const putFailed = useDoingFailed("connect.put", { station, id: connect.id });
  const deleteFailed = useDoingFailed("connect.delete", { station, id: connect.id });
  const busy = reconnecting || putting || deleting;
  const go = (doing: Promise<unknown>, done: string, failed: string) => {
    app.sheet(null);
    doing.then(() => app.toast(done), (e: Error) => app.toast(t(failed, { error: e.message })));
  };
  return (
    <>
      <SheetGrab />
      <SheetHead title={connect.name} />
      <div className={sheetsCss.mSheetScroll}>
        <PickRow label={t("web-mobile.connects.reconnect")} busy={reconnecting} failed={reconnectFailed} enabled={!busy} onClick={() => go(api.reconnect(connect.id), t("web-mobile.connects.reconnected"), "web-mobile.connects.reconnectFailed")} />
        <PickRow label={t("web-mobile.connects.changeToken")} onClick={() => openTokens(app, connect)} />
        {workspace?.url && <PickRow label={t("web-mobile.connects.openSlack")} onClick={() => window.open(workspace.url, "_blank", "noopener")} />}
        {connect.enabled
          ? <PickRow label={t("web-mobile.connects.disable")} sub={t("web-mobile.connects.disableNote")} busy={putting} failed={putFailed} enabled={!busy} onClick={() => go(api.putConnect(connect.id, { enabled: false }), t("web-mobile.connects.disabled"), "web-mobile.connects.disableFailed")} />
          : <PickRow label={t("web-mobile.connects.enable")} busy={putting} failed={putFailed} enabled={!busy} onClick={() => go(api.putConnect(connect.id, { enabled: true }), t("web-mobile.connects.enabled"), "web-mobile.connects.enableFailed")} />}
        <PickRow label={t("web-mobile.connects.changeOwner")} sub={connect.createdBy?.shown?.display ?? connect.createdBy?.name} enabled={!busy} onClick={() => app.sheet({ height: 0.6, content: () => <OwnerSheet connect={connect} /> })} />
        <PickRow label={t("web-mobile.connects.delete")} accent busy={deleting} failed={deleteFailed} enabled={!busy} onClick={() => confirm(app, {
          title: t("web-mobile.archive.deleteAsk", { title: connect.name }), action: t("web-mobile.connects.delete"), danger: true,
          text: connect.sessions ? t("web-mobile.connects.deleteTextSessions", { n: connect.sessions }) : t("web-mobile.connects.deleteText"),
          atOnce: "web-main.chat.deleteFailed",
          run: () => { app.pop(); return api.deleteConnect(connect.id).then(() => app.toast(t("web-mobile.connects.deleted"))); },
        })} />
      </div>
    </>
  );
}

/** Hands a connect to another person of the workspace. */
function OwnerSheet({ connect }: { connect: Connect }) {
  const app = useApp();
  const api = useApi();
  const members = useWorkspace(app.entry.id).value?.members ?? [];
  // The one picked, its row busy while the station changes it (connect.put says not which field: this sheet knows).
  const [picked, setPicked] = useState<string | null>(null);
  const station = useStation().address;
  const putting = useDoing("connect.put", { station, id: connect.id });
  const putFailed = useDoingFailed("connect.put", { station, id: connect.id });
  const asked = putting ? picked : null;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.connects.changeOwner")} />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${partsCss.mPad} ${partsCss.mSmall}`}>{t("web-mobile.connects.ownerNote")}</p>
        {members.map((m) => (
          <PickRow key={m.sub} label={m.name || m.email} sub={m.email} checked={m.email.toLowerCase() === connect.createdBy?.id.toLowerCase()}
            busy={asked === m.email} failed={picked === m.email ? putFailed : undefined} enabled={!putting}
            onClick={() => {
              setPicked(m.email);
              app.sheet(null);
              api.putConnect(connect.id, { owner: { id: m.email, name: m.name || m.email } })
                .then(() => app.toast(t("web-mobile.connects.ownerChanged")), (e: Error) => app.toast(t("web-mobile.connects.ownerFailed", { error: e.message })));
            }} />
        ))}
      </div>
    </>
  );
}

/** How its conversations become sessions: picked, with what changing it does said before it is done. */
function ModeSheet({ item }: { item: ConnectItem }) {
  const app = useApp();
  const api = useApi();
  const { connect } = item;
  const [next, setNext] = useState({ mode: connect.mode, requireMention: connect.requireMention });
  const busy = useDoing("connect.put", { station: useStation().address, id: connect.id });
  const changed = next.mode !== connect.mode || (next.mode === "single-session" && next.requireMention !== connect.requireMention);
  const effects = changed ? consequences(connect, next, item.running) : [];
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.connects.mode")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <ModeChoices value={next} onChange={setNext} />
        {effects.length > 0 && <div className={settingsCss.mCallout}><b>{t("web-mobile.connects.afterChange")}</b><ul>{effects.map((e) => <li key={e}>{e}</li>)}</ul></div>}
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={next.mode === connect.mode ? t("web-mobile.connects.confirmChange") : next.mode === "single-session" ? t("web-mobile.connects.toSingle") : t("web-mobile.connects.toMulti")} primary busy={busy} enabled={changed}
            onClick={() => { app.sheet(null); api.putConnect(connect.id, next).then(() => app.toast(t("web-mobile.connects.modeChanged")), (e: Error) => app.toast(t("web-mobile.connects.modeFailed", { error: e.message }))); }} />
        </div>
      </div>
    </>
  );
}

function ModeChoices({ value, onChange }: { value: { mode: ConnectMode; requireMention: boolean }; onChange: (v: { mode: ConnectMode; requireMention: boolean }) => void }) {
  return (
    <div className={css.mChoices}>
      {(["multi-session", "single-session"] as const).map((m) => (
        <button key={m} type="button" className={css.mChoice} data-on={value.mode === m || undefined}
          onClick={() => onChange({ mode: m, requireMention: m === "multi-session" ? true : value.requireMention })}>
          <b>{MODE[m].label}</b><span>{MODE[m].description}</span>
        </button>
      ))}
      {value.mode === "single-session" && (
        <button type="button" className={css.mSwitchRow} onClick={() => onChange({ ...value, requireMention: !value.requireMention })}>
          <span className={partsCss.mGrow}><b>{t("web-mobile.connects.mentionTitle")}</b><span>{value.requireMention ? t("web-mobile.connects.mentionOn") : t("web-mobile.connects.mentionOff")}</span></span>
          <span className={css.mSwitch} data-on={value.requireMention || undefined} />
        </button>
      )}
    </div>
  );
}

/** A single-session connect's session: the one its messages go into, switched, or a new one. */
function SessionSheet({ item }: { item: ConnectItem }) {
  const app = useApp();
  const api = useApi();
  const { connect, candidates } = item;
  const [choice, setChoice] = useState<string>(connect.session ?? "new");
  const [title, setTitle] = useState("");
  const busy = useDoing("connect.bindSession", { station: useStation().address, connect: connect.id });
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.connects.pickSession")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.connects.pickSessionNote", { name: connect.name })}</p>
        <PickRow label={t("web-mobile.connects.newSession")} sub={t("web-mobile.connects.newSessionNote")} checked={choice === "new"} onClick={() => setChoice("new")} />
        {choice === "new" && <Field value={title} onChange={setTitle} placeholder={t("web-mobile.connects.sessionPlaceholder")} />}
        {candidates.map((s) => <PickRow key={s.key} label={s.titleText} sub={s.description} checked={choice === s.key} onClick={() => setChoice(s.key)} />)}
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={choice === "new" ? t("web-mobile.connects.createUse") : t("web-mobile.connects.useThis")} primary busy={busy} enabled={choice !== connect.session}
            onClick={() => { app.sheet(null); api.bindSession(connect.id, choice === "new" ? null : choice, title).then(() => app.toast(choice === "new" ? t("web-mobile.connects.sessionCreated") : t("web-mobile.connects.sessionSwitched")), (e: Error) => app.toast(t("web-main.history.bindFailed", { error: e.message }))); }} />
        </div>
      </div>
    </>
  );
}

// ── tokens ─────────────────────────────────────────────────────────────

interface Tokens { appToken: string; botToken: string; verified: SlackIdentity | null }

/** Replaces a connect's Slack tokens (either one; the other kept), verified before they are saved. */
function openTokens(app: MobileApp, connect: Connect) {
  app.sheet({ height: 0.72, draggable: true, content: () => <TokensSheet connect={connect} /> });
}

function TokensSheet({ connect }: { connect: Connect }) {
  const app = useApp();
  const api = useApi();
  const [tokens, setTokens, check] = useSlackTokens({ connect: connect.id });
  const busy = useDoing("connect.put", { station: useStation().address, id: connect.id });
  return (
    <>
      <SheetGrab />
      <SheetHead title="Slack token" />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.connects.tokensNote")}</p>
        <TokenFields value={tokens} onChange={setTokens} masked={connect.slack} check={check} />
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={t("web-mobile.connects.saveConnect")} primary busy={busy || check.busy} enabled={check.ready}
            onClick={() => check.then(() => { api.putConnect(connect.id, { slack: { appToken: tokens.appToken, botToken: tokens.botToken } }).then(() => { app.toast(t("web-mobile.connects.tokensSaved")); app.sheet(null); }, (e: Error) => app.toast(e.message)); })} />
        </div>
      </div>
    </>
  );
}

/**
 * The two tokens with a verify step. For an existing connect a blank field keeps the stored token. An app installed
 * through Slack's OAuth (`install`) has its bot token on the station already: only the app-level token is asked for.
 */
function TokenFields({ value, onChange, masked, install, check }: { value: Tokens; onChange: (t: Partial<Tokens>) => void; masked?: { appToken: string; botToken: string }; install?: string | undefined; check: TokenCheck }) {
  const edit = (patch: Partial<Tokens>) => onChange(patch);
  return (
    <div className={settingsCss.mFormGroup}>
      <b className={sheetsCss.mFormLabel}>App-Level Token</b>
      <input className={listsCss.mField} data-mono type="password" autoComplete="off" spellCheck={false} value={value.appToken} onChange={(e) => edit({ appToken: e.target.value.trim() })}
        placeholder={masked?.appToken ? t("web-mobile.connects.savedToken", { token: masked.appToken }) : "xapp-…"} />
      {!install && (
        <>
          <b className={sheetsCss.mFormLabel}>Bot Token</b>
          <input className={listsCss.mField} data-mono type="password" autoComplete="off" spellCheck={false} value={value.botToken} onChange={(e) => edit({ botToken: e.target.value.trim() })}
            placeholder={masked?.botToken ? t("web-mobile.connects.savedToken", { token: masked.botToken }) : "xoxb-…"} />
        </>
      )}
      {value.verified && <span className={`${css.mGreen} ${partsCss.mSmall}`}>{t("web-mobile.connects.verified", { team: value.verified.team, bot: value.verified.botName })}</span>}
      {[...check.errors, ...(check.error ? [check.error] : [])].map((e) => <p key={e} className={partsCss.mError}>{e}</p>)}
    </div>
  );
}

// ── how it runs ────────────────────────────────────────────────────────

/** The model a connect runs, how hard it thinks and who runs it: picked like an agent's (./History.tsx), saved for new sessions. */
export function ConnectRunScreen() {
  const app = useApp();
  const station = useStation();
  const { item } = useItem();
  const pick = usePick(station.address, `connect:${item?.connect.id ?? ""}`);
  const v = pick.view;
  const { set: pickSet } = pick;
  useEffect(() => { if (item) pickSet({ open: true }); }, [item?.connect.id, pickSet]);
  const [list, setList] = useState<"model" | "account" | null>(null);
  const busy = pick.saving;
  const title = list === "model" ? t("web-mobile.history.pickModel") : list === "account" ? t("web-mobile.history.pickAccount") : t("web-mobile.history.changeModel");
  const bar = <NavBar back={list ? t("web-mobile.history.changeModel") : t("common.back")} onBack={() => (list ? setList(null) : app.pop())} title={title} />;
  if (!item || !v) return <div className={pagesCss.mScreen}>{bar}<Loading text={t("web-mobile.connects.reading")} /></div>;
  const { connect } = item;
  const runtime = connect.bind.runtime;
  const models = v.options;
  const model = v.draft.model ?? null;
  const effort = v.draft.effort ?? "";
  const profile = v.draft.profile ?? null;
  const accounts = v.accounts;
  const efforts = v.efforts;
  const changed = v.changed;
  const set = pick.set;
  if (list === "model") return <div className={pagesCss.mScreen}>{bar}<ModelList models={models} runtime={runtime} picked={model} onPick={(m) => { set({ model: m }); setList(null); }} /></div>;
  if (list === "account") return <div className={pagesCss.mScreen}>{bar}<AccountList accounts={accounts} runtime={runtime} picked={profile} onPick={(p) => { set({ profile: p }); setList(null); }} /></div>;
  return (
    <div className={pagesCss.mScreen}>
      {bar}
      <div className={`${pagesCss.mScroll} ${partsCss.mPadX18}`}>
        {models.length === 0 && <p className={settingsCss.mCallout}>{t("web-mobile.connects.noModels", { runtime: connect.runtimeText })}</p>}
        <GroupLabel>{t("web-mobile.history.model")}</GroupLabel>
        <SettingRow onClick={() => setList("model")} leading={<MakerIcon maker={v.maker} runtime={runtime} size={18} />}><span className={historyCss.mSettingMain}>{v.modelText}</span></SettingRow>
        <GroupLabel>{t("web-mobile.newChat.pickEffort")}</GroupLabel>
        <div className={historyCss.mChips}>
          {["", ...efforts].map((e) => <button key={e || "-"} type="button" className={historyCss.mChip} data-on={e === effort || undefined} onClick={() => set({ effort: e })}>{e || t("web-mobile.newChat.default")}</button>)}
        </div>
        <GroupLabel>{t("web-mobile.history.account")}</GroupLabel>
        <SettingRow onClick={() => setList("account")}>
          <span className={historyCss.mSettingMain}>{v.accountText}</span>
          <small className={partsCss.mMuted}>{v.accountNote}</small>
        </SettingRow>
        <p className={`${partsCss.mSmall} ${partsCss.mSubtle} ${historyCss.mEffortNote}`}>{t("web-mobile.connects.runNote")}</p>
      </div>
      <button type="button" className={historyCss.mRunGo} data-changed={changed || undefined} disabled={busy || (changed && !model)}
        onClick={() => {
          // Back at once, not waiting on the station; failed, a toast says why.
          app.pop();
          if (!changed) return;
          pick.save().then(() => app.toast(t("web-mobile.connects.runSaved")), (e: Error) => app.toast(e.message));
        }}>
        {busy && <Spinner size={14} />}{v.saveText}
      </button>
    </div>
  );
}

// ── a new connect ──────────────────────────────────────────────────────

type Step = "team" | "token" | "app" | "install" | "manual" | "bind";

/**
 * A new Slack connect, a step a screen: the Slack workspace to make its app in (a configuration token each, or a new
 * one); the app's name and description; making and installing it, then the app-level token; last, the model it runs
 * and how its conversations become sessions. Without a configuration token the app is made in Slack by hand and both
 * tokens are pasted.
 */
export function NewConnectScreen() {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const [params] = useSearchParams();
  const flow = useConnectFlow(station.address, true, params.get("resume"));
  const [tokens, setTokens, tokenCheck] = useSlackTokens({ install: flow.view?.made?.state ?? undefined, form: flow.form });
  const [settingsEcho, setSettingsEcho] = useState<SlackAppSettings | null>(null);
  const [configEcho, setConfigEcho] = useState("");
  const view = flow.view;
  if (!view) return <div className={pagesCss.mScreen}><NavBar back={t("common.cancel")} onBack={app.pop} title={t("web-mobile.connects.add")} />{t("web-mobile.reading")}</div>;
  const { step, teams, chosen, made, noProfile } = view;
  const models = view.pick?.options ?? [];
  const entry = view.pick?.valueOption;
  const rt = view.pick?.value.runtime ?? "claude";
  const appSettings = settingsEcho ?? view.settings as SlackAppSettings;
  const icon = view.icon ?? null;
  const iconError = view.iconError ?? null;
  const config = configEcho;
  const mode = { mode: view.mode, requireMention: view.requireMention };
  const setMode = (mode: { mode: ConnectMode; requireMention: boolean }) => flow.edit(mode);
  const setStep = (step: string) => flow.go(step);
  const setTeam = (team: string) => flow.edit({ team });
  const setAppSettings = (settings: SlackAppSettings) => { setSettingsEcho(settings); flow.edit({ settings }); };
  const setIcon = (icon: string | null) => flow.edit({ icon });
  const setIconError = (iconError: string | null) => flow.edit({ iconError });
  const setConfig = (config: string) => { setConfigEcho(config); flow.edit({ config }); };
  const setModel = (model: ModelOption) => flow.choose({ model: model.model });
  const setRuntime = (runtime: RuntimeKind) => flow.choose({ runtime });
  const busy = flow.busy;
  const error = flow.error;
  const back = () => flow.go("back", app.pop);
  const check = { ...tokenCheck, busy, then: (_go: () => void) => flow.act("verify") };
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={view.back === "close" ? t("common.cancel") : t("web-mobile.connects.previous")} onBack={back} title={t("web-mobile.connects.add")} sub={<span className={barsCss.mNavbarNote}>{view.title} · {view.number} / {view.total}</span>} />
      <div className={`${pagesCss.mScroll} ${partsCss.mPadX18} ${settingsCss.mSteps}`}>
        {step === "team" && noProfile ? (
          <div className={newChatCss.mNewNone}>
            <img className={partsCss.mIllus} src={illustrationUrl("no-profile")} alt="" width={240} />
            <b>{t("web-mobile.connects.profileFirst")}</b>
            <p>{t("web-mobile.connects.profileFirstNote")}</p>
            <Button label={t("web-mobile.connects.goAddProfile")} primary onClick={() => app.replace(`${stationBase(station.address)}/profiles/new`)} />
          </div>
        ) : step === "team" && (teams.length === 0 ? (
          <>
            <p className={partsCss.mMuted}>{t("web-mobile.connects.configNote", { name: NAME })}</p>
            <Button label={t("web-mobile.connects.addConfig")} primary onClick={() => setStep("token")} />
            <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} onClick={() => setStep("manual")}>{t("web-mobile.connects.manualLong")}</button>
          </>
        ) : (
          <>
            <p className={partsCss.mMuted}>{t("web-mobile.connects.pickTeam")}</p>
            <ListCard>{teams.map((t) => <PickRow key={t.teamId} label={t.name} sub={t.owner ? `${t.owner.user}${t.owner.teamDomain ? ` · ${t.owner.teamDomain}.slack.com` : ""}` : undefined} checked={chosen?.teamId === t.teamId} onClick={() => setTeam(t.teamId)} />)}</ListCard>
            <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} onClick={() => setStep("token")}>{t("web-mobile.connects.addTeamConfig")}</button>
            <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} onClick={() => setStep("manual")}>{t("web-mobile.connects.manualShort")}</button>
            <Button label={t("web-mobile.connects.next")} primary enabled={!!chosen} onClick={() => setStep("app")} />
          </>
        ))}
        {step === "token" && (
          <>
            <ol className={css.mStepsList}>
              <li>{tNodes("web-mobile.connects.config.step1", { link: <a href="https://api.slack.com/apps" target="_blank" rel="noopener">api.slack.com/apps</a> })}</li>
              <li>{t("web-mobile.connects.config.step2")}</li>
              <li>{t("web-mobile.connects.config.step3", { name: NAME })}</li>
            </ol>
            <input className={listsCss.mField} data-mono type="password" autoComplete="off" spellCheck={false} value={config} placeholder="xoxe-1-…" onChange={(e) => setConfig(e.target.value.trim())} />
            {view.configError && <p className={partsCss.mError}>{view.configError}</p>}
            <Button label={t("web-mobile.connects.addIt")} primary busy={busy} enabled={view.configReady}
              onClick={() => flow.act("config", () => setConfigEcho(""))} />
          </>
        )}
        {step === "app" && (
          <>
            <b className={sheetsCss.mFormLabel}>{t("web-mobile.workspaces.name")}</b>
            <Field value={appSettings.name} onChange={(v) => setAppSettings({ ...appSettings, name: v, displayName: v })} placeholder={NAME} />
            <b className={sheetsCss.mFormLabel}>{t("web-mobile.connects.description")}</b>
            <Field value={appSettings.description} onChange={(v) => setAppSettings({ ...appSettings, description: v })} placeholder={t("web-pages.slackApp.descriptionPlaceholder")} />
            <AppLook settings={appSettings} onChange={setAppSettings} icon={icon} onIcon={(i, e) => { setIcon(i); setIconError(e); }} />
            {iconError && <p className={partsCss.mError}>{iconError}</p>}
            <p className={`${partsCss.mSmall} ${partsCss.mMuted}`}>{t("web-mobile.connects.scopesNote")}</p>
            <Button label={t("web-mobile.connects.createApp")} primary busy={busy} enabled={view.canMake}
              onClick={() => flow.act("make")} />
          </>
        )}
        {step === "install" && !made && <p className={partsCss.mMuted}>{view ? t("web-mobile.connects.appGone") : t("web-mobile.reading")}</p>}
        {step === "install" && made && (
          <>
            {iconError && <p className={partsCss.mError}>{t("web-mobile.connects.iconFailed", { error: iconError })}</p>}
            <ol className={css.mStepsList}>
              {made.install ? (
                <li>{made.installed ? t("web-mobile.connects.installedIn", { team: made.installedTeam ?? made.team ?? t("web-mobile.connects.slackWorkspace") }) : tNodes("web-mobile.connects.install.oauth", { link: <a href={made.install} target="_blank" rel="noopener">{t("web-mobile.connects.installLink")}</a> })}</li>
              ) : (
                <li>{tNodes("web-mobile.connects.install.manual", { link: <a href={made.links.install} target="_blank" rel="noopener">{t("web-mobile.connects.installLink")}</a>, oauth: <a href={made.links.oauth} target="_blank" rel="noopener">{t("web-mobile.connects.oauthLink")}</a> })}</li>
              )}
              <li>{tNodes("web-mobile.connects.install.socket", { link: <a href={made.links.appToken} target="_blank" rel="noopener">Socket Mode</a> })}</li>
              <li>{made.install ? t("web-mobile.connects.install.fillApp") : t("web-mobile.connects.install.fillBoth")}</li>
            </ol>
            <TokenFields value={tokens} onChange={setTokens} install={made.state ?? undefined} check={check} />
            <Button label={t("web-mobile.connects.next")} primary busy={check.busy} enabled={check.ready} onClick={() => check.then(() => setStep("bind"))} />
          </>
        )}
        {step === "manual" && (
          <>
            <ol className={css.mStepsList}>
              <li><LinkButton busy={busy} label={t("web-mobile.connects.manual.create", { name: NAME })} onClick={() => {
                // The page opens now, while the tap still counts (one opened once the station answers is blocked), and goes
                // to Slack once its address is here; with no page to open, this one goes there.
                const page = window.open("", "_blank");
                if (page) page.opener = null;
                void api.createAppUrl(NAME).then(({ url }) => { if (page) page.location.href = url; else window.location.assign(url); }, (e: unknown) => { page?.close(); app.toast(e instanceof Error ? e.message : String(e)); });
              }} />{t("web-mobile.connects.manual.end")}</li>
              <li>{t("web-mobile.connects.manual.socket")}</li>
              <li>{t("web-mobile.connects.manual.install")}</li>
              <li>{t("web-mobile.connects.install.fillBoth")}</li>
            </ol>
            <TokenFields value={tokens} onChange={setTokens} check={check} />
            <Button label={t("web-mobile.connects.next")} primary busy={check.busy} enabled={check.ready} onClick={() => check.then(() => setStep("bind"))} />
          </>
        )}
        {step === "bind" && (
          <>
            <GroupLabel>{t("web-mobile.history.model")}</GroupLabel>
            {models.length === 0 ? <p className={settingsCss.mCallout}>{t("web-mobile.connects.noModelsHere")}</p> : (
              <ListCard>{models.map((m) => <PickRow key={m.model} label={m.name} sub={m.runtimes.map((r) => RUNTIME_LABEL[r] ?? r).join(" · ")} checked={entry?.model === m.model}
                leading={<MakerIcon maker={m.maker} runtime={m.runtimes[0]} size={18} />} onClick={() => setModel(m)} />)}</ListCard>
            )}
            {entry && entry.runtimes.length > 1 && (
              <>
                <GroupLabel>{t("web-mobile.connects.runtimeFixed")}</GroupLabel>
                <Seg options={entry.runtimes.map((r) => RUNTIME_LABEL[r] ?? r)} selected={Math.max(0, entry.runtimes.indexOf(rt))} onSelect={(i) => setRuntime(entry.runtimes[i]!)} height={36} fill />
              </>
            )}
            <GroupLabel>{t("web-mobile.connects.mode")}</GroupLabel>
            <ModeChoices value={mode} onChange={setMode} />
            <Button label={t("web-mobile.connects.addConnect")} primary busy={busy} enabled={!!entry}
              onClick={() => flow.act("create", ({ id }) => { app.toast(t("web-mobile.connects.added")); app.replace(`${stationBase(station.address)}/connects/${encodeURIComponent(String(id))}`); })} />
          </>
        )}
        {error && <p className={partsCss.mError}>{error}</p>}
        <div style={{ height: 30 }} />
      </div>
    </div>
  );
}

/**
 * A new app's look, as the desktop's AppFields (../pages/SlackApp.tsx) has it: an avatar picked from still.fail's buddies or
 * the model makers, or uploaded, on its colour; the colour follows the avatar until it is set by hand (and can go back).
 * It starts as the general helper.
 */
function AppLook({ settings, onChange, icon, onIcon }: {
  settings: SlackAppSettings; onChange: (s: SlackAppSettings) => void; icon: string | null; onIcon: (icon: string | null, error: string | null) => void;
}) {
  const file = useRef<HTMLInputElement>(null);
  const buddies = useBuddies();
  const [picked, setPicked] = useState<{ avatar: Avatar; maker: boolean } | { upload: true; bg: string } | null>(null);
  const [colourSet, setColourSet] = useState(false);
  const recommended = picked ? ("upload" in picked ? picked.bg : picked.avatar.bg) : null;
  const draw = (p: typeof picked, bg: string) => {
    if (p && !("upload" in p)) void renderAvatar(p.avatar, bg, p.maker).then((i) => onIcon(i, null), () => onIcon(null, t("web-mobile.connects.avatarFailed")));
  };
  const pick = (avatar: Avatar, maker: boolean) => {
    const p = { avatar, maker };
    setPicked(p);
    const bg = colourSet ? settings.backgroundColor : avatar.bg;
    if (bg !== settings.backgroundColor) onChange({ ...settings, backgroundColor: bg });
    draw(p, bg);
  };
  const colour = (bg: string, byHand: boolean) => {
    setColourSet(byHand);
    onChange({ ...settings, backgroundColor: bg });
    if (/^#[0-9a-fA-F]{6}$/.test(bg)) draw(picked, bg);
  };
  const started = useRef(false);
  useEffect(() => {
    if (started.current || icon || !buddies?.length) return;
    started.current = true;
    pick(buddies.find((a) => a.id === "general-helper") ?? buddies[0]!, false);
  });
  const isPicked = (a: Avatar) => picked !== null && !("upload" in picked) && picked.avatar.id === a.id;
  const tile = (a: Avatar, maker: boolean) => (
    <button key={a.id} type="button" aria-label={a.label} onClick={() => pick(a, maker)}
      style={{ display: "grid", placeItems: "center", aspectRatio: "1", padding: 0, border: 0, borderRadius: 12, overflow: "hidden", background: a.bg, cursor: "pointer",
        boxShadow: isPicked(a) ? "0 0 0 2px var(--m-bg), 0 0 0 4px var(--m-accent)" : undefined }}>
      <img src={a.thumb ?? a.src} alt="" loading="lazy"
        style={maker ? { width: "55%", height: "55%", filter: a.mono ? "brightness(0) invert(1)" : undefined } : { width: "100%", height: "100%", transform: "scale(1.18)" }} />
    </button>
  );
  const hex = /^#[0-9a-fA-F]{6}$/.test(settings.backgroundColor) ? settings.backgroundColor : "#7a2e0e";
  return (
    <>
      <b className={sheetsCss.mFormLabel}>{t("web-mobile.connects.avatar")}</b>
      <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
        <button type="button" aria-label={t("web-mobile.connects.upload")} onClick={() => file.current?.click()}
          style={{ flex: "none", width: 72, height: 72, padding: 0, border: 0, borderRadius: 18, overflow: "hidden", background: settings.backgroundColor || undefined, cursor: "pointer" }}>
          {icon ? <img src={icon} alt={t("web-mobile.connects.avatar")} width={72} height={72} style={{ display: "block" }} /> : <span className={`${partsCss.mSmall} ${partsCss.mMuted}`}>{t("web-mobile.connects.uploadShort")}</span>}
        </button>
        <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
          <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{t("web-mobile.connects.avatarNote")}</span>
          <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} onClick={() => file.current?.click()}>{t("web-mobile.connects.upload")}</button>
        </span>
        <input ref={file} type="file" accept="image/png,image/jpeg,image/webp" hidden onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) void toIcon(f).then(async (i) => {
            const bg = await edgeColour(i);
            setPicked({ upload: true, bg });
            onIcon(i, null);
            if (!colourSet) onChange({ ...settings, backgroundColor: bg });
          }).catch(() => onIcon(null, t("web-mobile.connects.imageFailed")));
        }} />
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(48px, 1fr))", gap: 10 }} aria-label={t("web-mobile.connects.avatar")}>
        {(buddies ?? []).map((a) => tile(a, false))}
        {MAKERS.map((a) => tile(a, true))}
      </div>
      <b className={sheetsCss.mFormLabel}>{t("web-mobile.connects.background")}</b>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <input type="color" aria-label={t("web-mobile.connects.background")} value={hex} onChange={(e) => colour(e.target.value.toUpperCase(), true)}
          style={{ flex: "none", width: 44, height: 44, padding: 0, border: 0, borderRadius: 12, background: "none", cursor: "pointer" }} />
        <input className={listsCss.mField} data-mono aria-label={t("web-mobile.connects.backgroundValue")} spellCheck={false} value={settings.backgroundColor} onChange={(e) => colour(e.target.value, true)} />
        {recommended && colourSet && recommended.toLowerCase() !== settings.backgroundColor.toLowerCase() && (
          <button type="button" className={partsCss.mLink} style={{ flex: "none" }} onClick={() => colour(recommended, false)}>{t("web-mobile.connects.recommended")}</button>
        )}
      </div>
    </>
  );
}
