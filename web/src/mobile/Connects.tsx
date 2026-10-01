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
import { Button, Field, GroupLabel, LargeTitle, LinkButton, ListCard, ListRow, Loading, MakerIcon, NavBar, NavButton, PickRow, SectionHeader, Seg, SlackMark, Spinner, TopBack } from "./parts.tsx";
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
  return made.installed ? `已装进「${made.installedTeam ?? made.team ?? "工作区"}」，还差 App-Level Token` : made.install ? "还没安装到工作区" : "还差 token";
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
      {online ? <span className={partsCss.mLink}>继续</span> : <span className={listsCss.mRowNote}>station 离线</span>}
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
        <p className={`${partsCss.mMuted} ${partsCss.mPad} ${partsCss.mSmall}`}>{waitingText(made)}。</p>
        <PickRow label={made.installed ? "填 App-Level Token" : made.install ? "继续安装" : "填 token"} enabled={online} sub={online ? undefined : "station 离线，等它上线再继续"}
          onClick={() => { app.sheet(null); app.push(`${stationBase(station.address)}/connects/new?resume=${encodeURIComponent(made.appId)}`); }} />
        <PickRow label="从这里移除" accent onClick={() => confirm(app, {
          title: `移除「${made.name}」？`, action: "移除", danger: true,
          text: `只从 ${NAME} 里移除；这个 app 还在 Slack 里，不用了可以去 Slack 的 app 设置页删除。`,
          run: () => api.dropSlackApp(made.appId).then(() => app.toast("已移除")),
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
    : app.sheet({ height: 0.5, content: () => <PickStation title="添加连接" stations={online} to={(s) => `/s/${s.id}/connects/new`} /> });
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={one?.name ?? "设置"} onBack={app.pop} trailing={online.length > 0 ? <NavButton icon={Plus} iconSize={20} label="添加连接" onClick={add} /> : undefined} />
      <LargeTitle small={one ? `${one.name} 上的` : ""} big="连接" />
      <p className={settingsCss.mPageNote}>连接是人找到 {NAME} 的地方，比如一个 Slack app。每个连接在一台 station 上，绑定一个模型。</p>
      <div className={css.mListSeg}><Seg options={["全部", "我建的"]} selected={mine ? 1 : 0} onSelect={(i) => setMine(i === 1)} height={34} fill /></div>
      {!stations || !connects.value ? <Loading text={connects.error?.message ?? "正在读取连接…"} /> : stations.map((s) => {
        const here = items.filter((i) => i.station === s.station);
        const waiting = s.overview?.slackApps ?? [];
        if (s.online && here.length === 0 && waiting.length === 0 && mine && !one) return null;
        return (
          <StationContext.Provider key={s.id} value={{ id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${app.entry.id}/settings` }}>
            {!one && <SectionHeader title={s.online ? s.name : `${s.name} · 离线`} start={24} />}
            <ListCard>
              {!s.online && here.length === 0 ? <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>station 离线，读不到它的连接</span></ListRow>
                : here.length === 0 && waiting.length === 0 ? <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>{s.overview ? "这台机器上还没有连接" : "正在读取…"}</span></ListRow>
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
    return <div className={pagesCss.mScreen}><NavBar back="连接" onBack={app.pop} title="连接" /><Loading text={error?.message ?? (loading ? "正在读取连接…" : "没有这个连接。")} /></div>;
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
      <NavBar back="连接" onBack={app.pop} title={connect.name} sub={<span className={barsCss.mNavbarNote}><Presence state={connect.presence} /> {connect.statusText}</span>}
        trailing={<NavButton icon={More} label="更多" onClick={() => app.sheet({ height: 0.6, content: () => <ConnectMenu connect={connect} /> })} />} />
      <div className={`${pagesCss.mScroll} ${settingsCss.mStationPage}`}>
        {/* Who it is in Slack: its bot's picture, its Slack workspace, whose it is. */}
        <div className={`${listsCss.mCard} ${settingsCss.mProfileHead}`}>
          <ConnectAvatar connect={connect} size={44} />
          <span className={partsCss.mGrow}>
            <span className={listsCss.mRowTitle}>{connect.team ?? "Slack"}</span>
            <span className={listsCss.mRowNote}>{station.name}{connect.createdBy ? ` · 所属 ${connect.createdBy.shown?.display ?? connect.createdBy.name}` : ""}</span>
          </span>
        </div>
        {(c.state === "no_tokens" || c.state === "error" || (c.state === "reconnecting" && c.lastError)) && (
          <div className={settingsCss.mCallout}>
            {c.state === "no_tokens" ? <>这个连接还没接上 Slack。<button type="button" className={partsCss.mLink} onClick={() => openTokens(app, connect)}>填 token</button></>
              : c.state === "error" ? c.error : `正在重连：${c.lastError}`}
          </div>
        )}
        <SectionHeader title="怎么跑" start={24} />
        <ListCard>
          <ListRow onClick={() => app.push(`${stationBase(station.address)}/connects/${encodeURIComponent(connect.id)}/run`)}>
            <span className={historyCss.mRunLabel}>模型</span>
            <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{connect.bind.model ? connect.modelName ?? connect.bind.model : "选模型"}<span className={partsCss.mMuted}> · {connect.bind.effort || "默认深度"} · {connect.bind.profile ? "固定账号" : "自动分配"}</span></span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
          <ListRow onClick={() => app.sheet({ height: 0.8, draggable: true, content: () => <ModeSheet item={item} /> })}>
            <span className={historyCss.mRunLabel}>会话</span>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
              <span className={listsCss.mRowTitle}>{MODE[connect.mode].label}</span>
              <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{MODE[connect.mode].description}{connect.mode === "single-session" && (connect.requireMention ? "只在被 @ 时唤醒。" : "它能看到的每条消息都会送进会话。")}</span>
            </span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
          {connect.mode === "single-session" && (
            <ListRow onClick={() => app.sheet({ height: 0.7, draggable: true, content: () => <SessionSheet item={item} /> })}>
              <span className={historyCss.mRunLabel}>当前</span>
              <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{bound ? bound.titleText : <span className={partsCss.mMuted}>还没有会话；下一条消息会开始一个新的。</span>}</span>
              <ChevronRight size={14} className={partsCss.mSubtle} />
            </ListRow>
          )}
        </ListCard>
        <p className={settingsCss.mPageNote}>跑在 {connect.runtimeText} 上，创建后不能换；要用另一种运行时，新建一个连接。进行中的会话继续用开始时的设置。</p>
        <SectionHeader title="最近的会话" start={24} />
        <ListCard>
          {sessions.length === 0 && <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>还没有会话。在 Slack 里 @{connect.name} 就会开始。</span></ListRow>}
          {sessions.map((s) => (
            <ListRow key={s.key} onClick={() => app.push(`${stationBase(station.address)}/chats/${encodeURIComponent(s.key)}`)}>
              <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{s.titleText}</span>
              <span className={listsCss.mRowNote}>{s.statusText}</span>
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
  // What is under way shows on its row; the sheet stays until it answers (a failure says so and leaves it open, its row
  // with the failure mark a few seconds).
  const reconnecting = useDoing("connect.reconnect", { station, id: connect.id });
  const putting = useDoing("connect.put", { station, id: connect.id });
  const deleting = useDoing("connect.delete", { station, id: connect.id });
  const reconnectFailed = useDoingFailed("connect.reconnect", { station, id: connect.id });
  const putFailed = useDoingFailed("connect.put", { station, id: connect.id });
  const deleteFailed = useDoingFailed("connect.delete", { station, id: connect.id });
  const busy = reconnecting || putting || deleting;
  const done = (text: string) => () => { app.toast(text); app.sheet(null); };
  const failed = (what: string) => (e: Error) => app.toast(`没能${what}：${e.message}`);
  return (
    <>
      <SheetGrab />
      <SheetHead title={connect.name} />
      <div className={sheetsCss.mSheetScroll}>
        <PickRow label="重新连接" busy={reconnecting} failed={reconnectFailed} enabled={!busy} onClick={() => { api.reconnect(connect.id).then(done("已重新连接"), failed("重新连接")); }} />
        <PickRow label="更换 token" onClick={() => openTokens(app, connect)} />
        {workspace?.url && <PickRow label="打开 Slack" onClick={() => window.open(workspace.url, "_blank", "noopener")} />}
        {connect.enabled
          ? <PickRow label="停用" sub="Slack 连接会断开" busy={putting} failed={putFailed} enabled={!busy} onClick={() => { api.putConnect(connect.id, { enabled: false }).then(done("已停用，Slack 连接已断开"), failed("停用")); }} />
          : <PickRow label="启用" busy={putting} failed={putFailed} enabled={!busy} onClick={() => { api.putConnect(connect.id, { enabled: true }).then(done("已启用"), failed("启用")); }} />}
        <PickRow label="更改所属用户" sub={connect.createdBy?.shown?.display ?? connect.createdBy?.name} enabled={!busy} onClick={() => app.sheet({ height: 0.6, content: () => <OwnerSheet connect={connect} /> })} />
        <PickRow label="删除连接" accent busy={deleting} failed={deleteFailed} enabled={!busy} onClick={() => confirm(app, {
          title: `删除「${connect.name}」？`, action: "删除连接", danger: true,
          text: `Slack 连接会断开${connect.sessions ? `；它的 ${connect.sessions} 个会话的记录会保留，但不再接收消息` : ""}。Slack 里的 app 需要你自己去删除。`,
          run: () => api.deleteConnect(connect.id).then(() => { app.toast("已删除连接"); app.pop(); }),
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
      <SheetHead title="更改所属用户" />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${partsCss.mPad} ${partsCss.mSmall}`}>连接属于谁，决定它出现在谁的「我添加的」里。</p>
        {members.map((m) => (
          <PickRow key={m.sub} label={m.name || m.email} sub={m.email} checked={m.email.toLowerCase() === connect.createdBy?.id.toLowerCase()}
            busy={asked === m.email} failed={picked === m.email ? putFailed : undefined} enabled={!putting}
            onClick={() => {
              setPicked(m.email);
              api.putConnect(connect.id, { owner: { id: m.email, name: m.name || m.email } })
                .then(() => { app.toast("已更改所属用户"); app.sheet(null); }, (e: Error) => app.toast(`没能更改所属用户：${e.message}`));
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
      <SheetHead title="会话方式" />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <ModeChoices value={next} onChange={setNext} />
        {effects.length > 0 && <div className={settingsCss.mCallout}><b>更改之后</b><ul>{effects.map((e) => <li key={e}>{e}</li>)}</ul></div>}
        <div className={sheetsCss.mFormActions}>
          <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
          <Button label={next.mode === connect.mode ? "确认更改" : `改为${next.mode === "single-session" ? "单会话" : "多会话"}`} primary busy={busy} enabled={changed}
            onClick={() => { api.putConnect(connect.id, next).then(() => { app.toast("已更改会话方式"); app.sheet(null); }, (e: Error) => app.toast(e.message)); }} />
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
          <span className={partsCss.mGrow}><b>只在被 @ 时唤醒</b><span>{value.requireMention ? "被 @ 的 thread 之后的回复不用再 @。" : "频道里它能看到的每条消息都会送进会话。"}</span></span>
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
      <SheetHead title="选择会话" />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>之后「{connect.name}」收到的消息都进选中的会话。原来的会话保留，但不再收到这个连接的新消息。</p>
        <PickRow label="新建会话" sub="从空白上下文开始" checked={choice === "new"} onClick={() => setChoice("new")} />
        {choice === "new" && <Field value={title} onChange={setTitle} placeholder="给它起个名字（可选），例如：值班" />}
        {candidates.map((s) => <PickRow key={s.key} label={s.titleText} sub={s.description} checked={choice === s.key} onClick={() => setChoice(s.key)} />)}
        <div className={sheetsCss.mFormActions}>
          <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
          <Button label={choice === "new" ? "新建并使用" : "使用这个会话"} primary busy={busy} enabled={choice !== connect.session}
            onClick={() => { api.bindSession(connect.id, choice === "new" ? null : choice, title).then(() => { app.toast(choice === "new" ? "已新建会话" : "已换成这个会话"); app.sheet(null); }, (e: Error) => app.toast(e.message)); }} />
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
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>只换其中一个也可以，另一个留空会沿用已保存的。</p>
        <TokenFields value={tokens} onChange={setTokens} masked={connect.slack} check={check} />
        <div className={sheetsCss.mFormActions}>
          <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
          <Button label="保存并连接" primary busy={busy || check.busy} enabled={check.ready}
            onClick={() => check.then(() => { api.putConnect(connect.id, { slack: { appToken: tokens.appToken, botToken: tokens.botToken } }).then(() => { app.toast("已保存 token，正在连接"); app.sheet(null); }, (e: Error) => app.toast(e.message)); })} />
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
        placeholder={masked?.appToken ? `已保存 ${masked.appToken}，留空不变` : "xapp-…"} />
      {!install && (
        <>
          <b className={sheetsCss.mFormLabel}>Bot Token</b>
          <input className={listsCss.mField} data-mono type="password" autoComplete="off" spellCheck={false} value={value.botToken} onChange={(e) => edit({ botToken: e.target.value.trim() })}
            placeholder={masked?.botToken ? `已保存 ${masked.botToken}，留空不变` : "xoxb-…"} />
        </>
      )}
      {value.verified && <span className={`${css.mGreen} ${partsCss.mSmall}`}>连接到「{value.verified.team}」，bot 是 @{value.verified.botName}</span>}
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
  const [busy, setBusy] = useState(false);
  const title = list === "model" ? "选模型" : list === "account" ? "选账号" : "换模型";
  const bar = <NavBar back={list ? "换模型" : "返回"} onBack={() => (list ? setList(null) : app.pop())} title={title} />;
  if (!item || !v) return <div className={pagesCss.mScreen}>{bar}<Loading text="正在读取连接…" /></div>;
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
        {models.length === 0 && <p className={settingsCss.mCallout}>{connect.runtimeText} 的 Profile 还没有启用模型，先在 Station 页的 Profile 里勾选。</p>}
        <GroupLabel>模型</GroupLabel>
        <SettingRow onClick={() => setList("model")} leading={<MakerIcon maker={v.maker} runtime={runtime} size={18} />}><span className={historyCss.mSettingMain}>{v.modelText}</span></SettingRow>
        <GroupLabel>思考深度</GroupLabel>
        <div className={historyCss.mChips}>
          {["", ...efforts].map((e) => <button key={e || "-"} type="button" className={historyCss.mChip} data-on={e === effort || undefined} onClick={() => set({ effort: e })}>{e || "默认"}</button>)}
        </div>
        <GroupLabel>账号</GroupLabel>
        <SettingRow onClick={() => setList("account")}>
          <span className={historyCss.mSettingMain}>{v.accountText}</span>
          <small className={partsCss.mMuted}>{v.accountNote}</small>
        </SettingRow>
        <p className={`${partsCss.mSmall} ${partsCss.mSubtle} ${historyCss.mEffortNote}`}>新开的会话会用新的设置；进行中的会话继续用开始时的。</p>
      </div>
      <button type="button" className={historyCss.mRunGo} data-changed={changed || undefined} disabled={busy || (changed && !model)}
        onClick={() => {
          if (!changed) return app.pop();
          setBusy(true);
          pick.save().then(() => { app.toast("已保存，新会话会用新的设置"); app.pop(); }, (e: Error) => app.toast(e.message)).finally(() => setBusy(false));
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
  const overview = useOverview(station.address).value;
  const view = useStations(station.address.split("/")[0]!).value?.find((s) => s.station === station.address);
  const teams = overview?.slackTeams ?? [];
  // `?resume=`: an app made before and still waiting on the station, picked up where it was left (installing it).
  const [params] = useSearchParams();
  const resume = params.get("resume");
  const [step, setStep] = useState<Step>(resume ? "install" : "team");
  const [team, setTeam] = useState<string | null>(null);
  const [appSettings, setAppSettings] = useState(NEW_APP);
  const [icon, setIcon] = useState<string | null>(null);
  const [iconError, setIconError] = useState<string | null>(null);
  // The app made, as the station keeps it (it outlives this screen until a connect takes it).
  const [madeId, setMadeId] = useState<string | null>(resume);
  const made: MadeSlackApp | undefined = madeId ? overview?.slackApps?.find((a) => a.appId === madeId) : undefined;
  const [tokens, setTokens, check] = useSlackTokens({ install: made?.state ?? undefined });
  const [config, setConfig] = useState("");
  const models = view?.models ?? [];
  const [model, setModel] = useState<ModelOption | null>(null);
  const entry = model ?? models[0] ?? null;
  const [runtime, setRuntime] = useState<RuntimeKind | null>(null);
  const rt: RuntimeKind = entry && runtime && entry.runtimes.includes(runtime) ? runtime : (entry?.runtimes[0] ?? "claude");
  const [mode, setMode] = useState<{ mode: ConnectMode; requireMention: boolean }>({ mode: "multi-session", requireMention: true });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const chosen = teams.find((t) => t.teamId === team) ?? (teams.length === 1 ? teams[0] : undefined);
  const order: Step[] = step === "manual" || (step === "bind" && !madeId) ? ["manual", "bind"] : ["team", "app", "install", "bind"];
  const titles: Record<Step, string> = { team: "选 Slack 工作区", token: "加配置 token", app: "配置 app", install: "安装", manual: "连接 Slack", bind: "绑定模型" };
  const run = (work: () => Promise<unknown>) => { setBusy(true); setError(null); work().catch((e: Error) => setError(e.message)).finally(() => setBusy(false)); };
  const back = () => ({ team: app.pop, token: () => setStep("team"), app: () => setStep("team"), install: resume ? app.pop : () => setStep("app"), manual: () => setStep("team"), bind: () => setStep(madeId ? "install" : "manual") }[step]());
  // A connect runs a profile's model: with none on the station, the first step is a profile.
  const noProfile = !resume && overview !== undefined && overview.profiles.length === 0;
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={step === "team" || (resume && step === "install") ? "取消" : "上一步"} onBack={back} title="添加连接" sub={<span className={barsCss.mNavbarNote}>{titles[step]} · {Math.max(1, order.indexOf(step) + 1)} / {order.length}</span>} />
      <div className={`${pagesCss.mScroll} ${partsCss.mPadX18} ${settingsCss.mSteps}`}>
        {step === "team" && noProfile ? (
          <div className={newChatCss.mNewNone}>
            <img className={partsCss.mIllus} src={illustrationUrl("no-profile")} alt="" width={240} />
            <b>先添加一个 Profile</b>
            <p>连接要用 Profile 来跑模型。先添加一个，再来加连接。</p>
            <Button label="去添加 Profile" primary onClick={() => app.replace(`${stationBase(station.address)}/profiles/new`)} />
          </div>
        ) : step === "team" && (teams.length === 0 ? (
          <>
            <p className={partsCss.mMuted}>有了 Slack 的配置 token，{NAME} 替你在 Slack 建好 app：名字、头像、权限都在这里填，不用去 Slack 后台一项项配。它只归你用。</p>
            <Button label="添加配置 token" primary onClick={() => setStep("token")} />
            <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} onClick={() => setStep("manual")}>不用配置 token，自己在 Slack 建 app</button>
          </>
        ) : (
          <>
            <p className={partsCss.mMuted}>用哪个 Slack 工作区的配置 token 建 app。</p>
            <ListCard>{teams.map((t) => <PickRow key={t.teamId} label={t.name} sub={t.owner ? `${t.owner.user}${t.owner.teamDomain ? ` · ${t.owner.teamDomain}.slack.com` : ""}` : undefined} checked={chosen?.teamId === t.teamId} onClick={() => setTeam(t.teamId)} />)}</ListCard>
            <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} onClick={() => setStep("token")}>＋ 添加工作区的配置 token</button>
            <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} onClick={() => setStep("manual")}>不用配置 token，自己建 app</button>
            <Button label="下一步" primary enabled={!!chosen} onClick={() => setStep("app")} />
          </>
        ))}
        {step === "token" && (
          <>
            <ol className={css.mStepsList}>
              <li>打开 <a href="https://api.slack.com/apps" target="_blank" rel="noopener">api.slack.com/apps</a>，用要放 bot 的那个 Slack 工作区的账号登录。</li>
              <li>拉到页面最下面的「Your App Configuration Tokens」，点 Generate Token，选这个工作区。</li>
              <li>把以 xoxe-1- 开头的 Refresh Token 粘贴到下面。{NAME} 会自己续期，以后不用再管。</li>
            </ol>
            <input className={listsCss.mField} data-mono type="password" autoComplete="off" spellCheck={false} value={config} placeholder="xoxe-1-…" onChange={(e) => setConfig(e.target.value.trim())} />
            {config.startsWith("xoxe.xoxp-") && <p className={partsCss.mError}>这是 Access Token。要的是它下面那个 Refresh Token，以 xoxe-1- 开头。</p>}
            <Button label="加上" primary busy={busy} enabled={config.startsWith("xoxe-1-") && config.length > 20}
              onClick={() => run(() => api.addConfigToken(config).then(({ teamId }) => { setConfig(""); setTeam(teamId); setStep("app"); }))} />
          </>
        )}
        {step === "app" && (
          <>
            <b className={sheetsCss.mFormLabel}>名字</b>
            <Field value={appSettings.name} onChange={(v) => setAppSettings({ ...appSettings, name: v, displayName: v })} placeholder={NAME} />
            <b className={sheetsCss.mFormLabel}>描述</b>
            <Field value={appSettings.description} onChange={(v) => setAppSettings({ ...appSettings, description: v })} placeholder="Coding agent in your threads" />
            <AppLook settings={appSettings} onChange={setAppSettings} icon={icon} onIcon={(i, e) => { setIcon(i); setIconError(e); }} />
            {iconError && <p className={partsCss.mError}>{iconError}</p>}
            <p className={`${partsCss.mSmall} ${partsCss.mMuted}`}>权限用默认的（全部打开）；建好以后可以在电脑上改。</p>
            <Button label="创建 app" primary busy={busy} enabled={!!appSettings.name.trim() && !!chosen}
              onClick={() => run(() => api.makeSlackApp({ team: chosen!.teamId, settings: appSettings, ...(icon ? { icon } : {}) }).then((r) => { setMadeId(r.appId); setIconError(r.iconError); setStep("install"); }))} />
          </>
        )}
        {step === "install" && !made && <p className={partsCss.mMuted}>{overview ? "这个 app 已经不在这台 station 上了：可能已经连上，或者被移除了。" : "正在读取…"}</p>}
        {step === "install" && made && (
          <>
            {iconError && <p className={partsCss.mError}>图标没传上：{iconError}</p>}
            <ol className={css.mStepsList}>
              {made.install ? (
                <li>{made.installed ? `已装进「${made.installedTeam ?? made.team ?? "工作区"}」。` : <>app 已经建好。<a href={made.install} target="_blank" rel="noopener">安装到工作区</a>：在 Slack 里点「允许」，bot token 会自动交给 station。</>}</li>
              ) : (
                <li>app 已经建好。<a href={made.links.install} target="_blank" rel="noopener">安装到工作区</a>，然后在 <a href={made.links.oauth} target="_blank" rel="noopener">OAuth 页</a> 复制 Bot User OAuth Token（xoxb- 开头）。</li>
              )}
              <li>在 <a href={made.links.appToken} target="_blank" rel="noopener">Socket Mode</a> 页生成 App-Level Token 并复制（xapp- 开头，权限已经选好）。</li>
              <li>{made.install ? "把 App-Level Token 填在下面。" : "把两个 token 填在下面。"}</li>
            </ol>
            <TokenFields value={tokens} onChange={setTokens} install={made.state ?? undefined} check={check} />
            <Button label="下一步" primary busy={check.busy} enabled={check.ready} onClick={() => check.then(() => setStep("bind"))} />
          </>
        )}
        {step === "manual" && (
          <>
            <ol className={css.mStepsList}>
              <li><LinkButton busy={busy} label={`用 ${NAME} 的配置在 Slack 新建一个 app`} onClick={() => {
                // The page opens now, while the tap still counts (one opened once the station answers is blocked), and goes
                // to Slack once its address is here; with no page to open, this one goes there.
                const page = window.open("", "_blank");
                if (page) page.opener = null;
                run(() => api.createAppUrl(NAME).then(({ url }) => { if (page) page.location.href = url; else window.location.assign(url); }, (e: unknown) => { page?.close(); throw e; }));
              }} />。</li>
              <li>在 app 的 Socket Mode 页生成 App-Level Token（权限已经选好）。</li>
              <li>在 Install App 页安装到工作区，复制 Bot User OAuth Token。</li>
              <li>把两个 token 填在下面。</li>
            </ol>
            <TokenFields value={tokens} onChange={setTokens} check={check} />
            <Button label="下一步" primary busy={check.busy} enabled={check.ready} onClick={() => check.then(() => setStep("bind"))} />
          </>
        )}
        {step === "bind" && (
          <>
            <GroupLabel>模型</GroupLabel>
            {models.length === 0 ? <p className={settingsCss.mCallout}>这台 station 的 Profile 还没有启用模型，先在 Station 页的 Profile 里勾选。</p> : (
              <ListCard>{models.map((m) => <PickRow key={m.model} label={m.name} sub={m.runtimes.map((r) => RUNTIME_LABEL[r] ?? r).join(" · ")} checked={entry?.model === m.model}
                leading={<MakerIcon maker={m.maker} runtime={m.runtimes[0]} size={18} />} onClick={() => setModel(m)} />)}</ListCard>
            )}
            {entry && entry.runtimes.length > 1 && (
              <>
                <GroupLabel>运行时（创建后不能换）</GroupLabel>
                <Seg options={entry.runtimes.map((r) => RUNTIME_LABEL[r] ?? r)} selected={Math.max(0, entry.runtimes.indexOf(rt))} onSelect={(i) => setRuntime(entry.runtimes[i]!)} height={36} fill />
              </>
            )}
            <GroupLabel>会话方式</GroupLabel>
            <ModeChoices value={mode} onChange={setMode} />
            <Button label="添加并连接" primary busy={busy} enabled={!!entry}
              onClick={() => run(() => api.createConnect({
                kind: "slack", ...mode, bind: { runtime: rt, model: entry?.model ?? "", effort: "", profile: null },
                slack: made?.state ? { appToken: tokens.appToken, install: made.state } : { appToken: tokens.appToken, botToken: tokens.botToken, ...(made ? { appId: made.appId } : {}) },
              }).then(({ id }) => { app.toast("已添加连接，正在连接 Slack"); app.replace(`${stationBase(station.address)}/connects/${encodeURIComponent(id)}`); }))} />
          </>
        )}
        {error && <p className={partsCss.mError}>{error}</p>}
        <div style={{ height: 30 }} />
      </div>
    </div>
  );
}

/**
 * A new app's look, as the desktop's AppFields (../pages/SlackApp.tsx) has it: an avatar picked from ember's buddies or
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
    if (p && !("upload" in p)) void renderAvatar(p.avatar, bg, p.maker).then((i) => onIcon(i, null), () => onIcon(null, "画不出这个头像"));
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
      <b className={sheetsCss.mFormLabel}>头像</b>
      <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
        <button type="button" aria-label="上传图片" onClick={() => file.current?.click()}
          style={{ flex: "none", width: 72, height: 72, padding: 0, border: 0, borderRadius: 18, overflow: "hidden", background: settings.backgroundColor || undefined, cursor: "pointer" }}>
          {icon ? <img src={icon} alt="头像" width={72} height={72} style={{ display: "block" }} /> : <span className={`${partsCss.mSmall} ${partsCss.mMuted}`}>上传</span>}
        </button>
        <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
          <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>在下面挑一个，或者上传一张图片。</span>
          <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} onClick={() => file.current?.click()}>上传图片</button>
        </span>
        <input ref={file} type="file" accept="image/png,image/jpeg,image/webp" hidden onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) void toIcon(f).then(async (i) => {
            const bg = await edgeColour(i);
            setPicked({ upload: true, bg });
            onIcon(i, null);
            if (!colourSet) onChange({ ...settings, backgroundColor: bg });
          }).catch(() => onIcon(null, "读不了这张图片"));
        }} />
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(48px, 1fr))", gap: 10 }} aria-label="头像">
        {(buddies ?? []).map((a) => tile(a, false))}
        {MAKERS.map((a) => tile(a, true))}
      </div>
      <b className={sheetsCss.mFormLabel}>底色</b>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <input type="color" aria-label="底色" value={hex} onChange={(e) => colour(e.target.value.toUpperCase(), true)}
          style={{ flex: "none", width: 44, height: 44, padding: 0, border: 0, borderRadius: 12, background: "none", cursor: "pointer" }} />
        <input className={listsCss.mField} data-mono aria-label="底色色值" spellCheck={false} value={settings.backgroundColor} onChange={(e) => colour(e.target.value, true)} />
        {recommended && colourSet && recommended.toLowerCase() !== settings.backgroundColor.toLowerCase() && (
          <button type="button" className={partsCss.mLink} style={{ flex: "none" }} onClick={() => colour(recommended, false)}>用推荐色</button>
        )}
      </div>
    </>
  );
}
