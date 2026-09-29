// The workspace's stations on a narrow screen, as the Android app has them (apps/android/…/screens/Stations.kt): each
// with the buddy's face for its state and its load as rings; one station's profiles (which models may be used) and
// connections.
import { useEffect, useMemo, useRef, useState } from "react";
import { useParams } from "react-router";
import { stationApi, useStationCall, useStations, type Profile, type StationView } from "../api.ts";
import { illustrationUrl } from "../brand.tsx";
import { Check, ChevronRight, More } from "../icons.tsx";
import { cloud, useWorkspace } from "../cloud/api.ts";
import { track } from "../telemetry.ts";
import { useDark } from "../theme.ts";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { ConnectRow, Presence, WaitingAppRow } from "./Connects.tsx";
import { accessLabel, MachineLoginOffers, quotaTrouble, toneDot } from "./Profiles.tsx";
import { ask, CommandBox, confirm } from "./sheets.tsx";
import { Button, Card, Field, Illustration, LargeTitle, ListCard, ListRow, Loading, Mark, NavBar, NavButton, PickRow, QuotaRings, Ring, SectionHeader, SlackMark, Spinner, TopBack } from "./parts.tsx";
import * as css from "./Stations.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as newChatCss from "./styles/new-chat.css.ts";

const BASE = import.meta.env.BASE_URL;

/** The buddy's face for a station: at work, idle, or asleep. */
export function Buddy({ s, size = 40 }: { s: StationView; size?: number }) {
  const dark = useDark();
  const face = !s.online ? "offline" : (s.overview?.counts.running ?? 0) > 0 ? "working" : "idle";
  return <img className={css.mBuddy} src={`${BASE}${face}${dark ? "-dark" : ""}.svg`} alt="" width={size} height={size} />;
}

export function StationsScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id);
  const list = stations.value;
  const manager = useManager();
  // No station yet: adding the first one is the page.
  if (list && list.length === 0) {
    return (
      <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
        <TopBack label="会话" onBack={app.pop} />
        <FirstStation />
      </div>
    );
  }
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label="会话" onBack={app.pop} />
      <LargeTitle small={list ? `${app.entry.name} · ${list.filter((s) => s.online).length}/${list.length} 在线` : app.entry.name} big="Station" />
      {!list ? <p className={`${partsCss.mMuted} ${css.mPad20}`}>{stations.error?.message ?? "正在读取 station…"}</p> : list.map((s) => (
        <Card key={s.station} onClick={() => app.push(app.at(`/s/${s.id}/overview`))}>
          <span className={css.mStationHead}>
            <Buddy s={s} />
            <span className={partsCss.mGrow}><b className={css.mStationName}>{s.name}</b><span className={css.mStationSummary}>{s.summary}</span></span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </span>
          {s.online && s.host ? (
            <span className={css.mStationRings}>{s.host.meters.map((m) => <Ring key={m.label} percent={m.percent} label={m.short} level={m.level} size={40} />)}</span>
          ) : !s.online ? (
            <span className={css.mStationOffline}><Illustration name="station-offline" width={220} /><span>这台机器很久没联系 ember 了</span></span>
          ) : null}
        </Card>
      ))}
      <ListCard>
        {manager && list && (
          <ListRow onClick={() => app.sheet({ height: 0.72, draggable: true, content: () => <AddStationSheet known={list.map((s) => s.id)} /> })}>
            <span className={`${partsCss.mAccent} ${listsCss.mRowTitle}`}>＋ 添加 station</span>
          </ListRow>
        )}
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}

/**
 * Adding a station: a name, then the command to run on that machine (which installs ember and joins it); the sheet
 * waits for it to join.
 */
function AddStationSheet({ known }: { known: string[] }) {
  const app = useApp();
  const me = app.entry.account;
  const stations = useStations(app.entry.id).value ?? [];
  const [name, setName] = useState("");
  const [made, setMade] = useState<{ install: string; command: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const joined = made && stations.find((s) => !known.includes(s.id));
  return (
    <>
      <SheetGrab />
      <SheetHead title="添加 station" />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        {!made ? (
          <>
            <p className={partsCss.mMuted}>station 是一台运行 ember 的机器。给它起个名字，然后在那台机器的终端里执行生成的一行命令，它会装好 ember 并加入。</p>
            <b className={sheetsCss.mFormLabel}>名字</b>
            <Field value={name} onChange={setName} placeholder="比如机器名：studio、mac-mini" />
            {error && <p className={partsCss.mError}>{error}</p>}
            <div className={sheetsCss.mFormActions}>
              <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
              <Button label="生成命令" primary busy={busy} enabled={!!name.trim()} onClick={() => {
                setBusy(true); setError(null);
                cloud.enroll(me.sub, app.entry.id, name.trim()).then(setMade, (e: Error) => setError(e.message)).finally(() => setBusy(false));
              }} />
            </div>
          </>
        ) : joined ? (
          <>
            <p>「{joined.name}」已加入，现在可以打开它了。</p>
            <div className={sheetsCss.mFormActions}><Button label="完成" primary onClick={() => app.sheet(null)} /></div>
          </>
        ) : <EnrollSteps install={made.install} />}
      </div>
    </>
  );
}

export function StationScreen() {
  const app = useApp();
  const { station: id = "" } = useParams();
  const stations = useStations(app.entry.id);
  const s = stations.value?.find((x) => x.id === id);
  const manager = useManager();
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back="Station" onBack={app.pop} title={s?.name ?? id} sub={s ? <span className={barsCss.mNavbarNote}>{s.host?.cpuModel || (s.online ? "在线" : "离线")}</span> : undefined}
        trailing={s && manager ? <NavButton icon={More} label="更多" onClick={() => app.sheet({ height: 0.34, content: () => <StationMenu s={s} /> })} /> : undefined} />
      {!s ? <Loading text={stations.error?.message ?? "正在读取…"} /> : (
        <div className={`${pagesCss.mScroll} ${settingsCss.mStationPage}`}>
          {s.online && s.host ? (
            <Card>
              <span className={`${css.mStationRings} ${css.mRings18}`}>{s.host.meters.map((m) => <Ring key={m.label} percent={m.percent} label={m.short} level={m.level} />)}</span>
              <span className={css.mStationLine}>{s.host.line}</span>
              {s.overview?.processesText && <span className={css.mStationLine}>{s.overview.processesText}</span>}
            </Card>
          ) : !s.online ? (
            <Card><span className={css.mStationOffline}><Illustration name="station-offline" width={220} /><span>离线：在这台机器上打开 ember 就会重新连上</span></span></Card>
          ) : null}
          {s.overview && (
            <>
              <SectionHeader title="Profile" start={24} />
              <ListCard>
                {s.overview.profiles.length === 0 && <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>这台机器还没有 Profile。</span></ListRow>}
                {s.overview.profiles.map((p) => <ProfileRow key={p.id} station={s} p={p} />)}
                {s.online && <ListRow onClick={() => app.push(app.at(`/s/${s.id}/profiles/new`))}><span className={`${partsCss.mAccent} ${listsCss.mRowTitle}`}>＋ 添加 Profile</span></ListRow>}
              </ListCard>
              {/* The machine's own logins not used yet, each offered as a profile. */}
              {s.online && <MachineLoginOffers logins={s.overview.machineLogins} profiles={s.overview.profiles}
                onSignIn={(kind) => app.push(app.at(`/s/${s.id}/profiles/new?kind=${kind}`))} />}
              <SectionHeader title="连接" start={24} />
              <ListCard>
                {s.overview.connects.map((c) => <ConnectRow key={c.id} connect={c} onClick={() => app.push(app.at(`/s/${s.id}/connects/${encodeURIComponent(c.id)}`))} />)}
                <ListRow><Mark size={14} /><span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>ember 对话</span><span className={listsCss.mRowNote}>内置</span></ListRow>
                {s.online && (
                  <ListRow onClick={() => app.push(app.at(`/s/${s.id}/connects/new`))}>
                    <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                      <span className={`${partsCss.mAccent} ${listsCss.mRowTitle}`}>＋ 添加连接</span>
                      {s.overview.profiles.length === 0 && <span className={listsCss.mRowNote}>连接要用 Profile 来跑模型，先添加一个 Profile</span>}
                    </span>
                  </ListRow>
                )}
              </ListCard>
              {/* The Slack apps made here that no connect has taken yet: to be finished any time. */}
              {(s.overview.slackApps?.length ?? 0) > 0 && (
                <>
                  <SectionHeader title="还没连上的 Slack app" start={24} />
                  <ListCard>{s.overview.slackApps!.map((a) => <WaitingAppRow key={a.appId} made={a} online={s.online} />)}</ListCard>
                </>
              )}
            </>
          )}
          <div style={{ height: 30 }} />
        </div>
      )}
    </div>
  );
}

/** The command that adds a station, to copy and run on that machine, and the wait for it to join. */
function EnrollSteps({ install }: { install: string }) {
  return (
    <>
      <p>在那台机器的终端里执行：</p>
      <CommandBox text={install} />
      <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>macOS（Apple 芯片）和 Linux 都行；装过 ember 的机器也用这条命令。它会装好 ember、加入这个 workspace，并在后台一直运行。加入以后，在它的 Station 页添加 Profile。</p>
      <p className={`${partsCss.mMuted} ${partsCss.mSmall} ${chatCss.mWaiting}`}><Spinner size={10} />等待这台机器加入… 执行命令后会自动继续 · 命令 1 小时内有效</p>
    </>
  );
}

/**
 * A workspace's first station, added in the page (as the desktop's Onboarding, ../cloud/workspace.tsx): what a station
 * is, its name, then the command to copy and the wait. The workspace's pages take over once it has joined. Only its
 * owner and admins add one; anyone else is told to wait for them.
 */
export function FirstStation() {
  const app = useApp();
  const view = useWorkspace(app.entry.id).value;
  const manager = view?.role === "owner" || view?.role === "admin";
  const [name, setName] = useState("");
  const [made, setMade] = useState<{ install: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const shown = useRef(0);
  useEffect(() => { if (made) shown.current = performance.now(); }, [made]);
  // Joined: the page is gone (the workspace has a station), so this is said as it goes.
  useEffect(() => () => { if (shown.current) track("station_added", { ms: Math.round(performance.now() - shown.current), first: true }); }, []);
  return (
    <div className={newChatCss.mNewNone}>
      <img className={partsCss.mIllus} src={illustrationUrl("no-station")} alt="" width={240} />
      <b>添加第一台 station</b>
      <p>agent 在你的机器上干活。先把一台 Mac 或 Linux 机器加进来。</p>
      <div className={`${sheetsCss.mForm} ${settingsCss.mSteps}`} style={{ alignSelf: "stretch", padding: 0, textAlign: "left" }}>
        {!view ? <p className={`${partsCss.mMuted} ${chatCss.mWaiting}`}><Spinner size={13} />正在读取 workspace…</p>
          : !manager ? <p className={settingsCss.mCallout}>这个 workspace 还没有 station，等管理员添加。</p>
          : made ? <EnrollSteps install={made.install} />
          : (
            <>
              <b className={sheetsCss.mFormLabel}>给这台机器起个名字</b>
              <Field value={name} onChange={setName} placeholder="比如 studio、mac-mini" />
              {error && <p className={partsCss.mError}>{error}</p>}
              <Button label="生成命令" primary busy={busy} enabled={!!name.trim()} onClick={() => {
                setBusy(true); setError(null);
                cloud.enroll(app.entry.account.sub, app.entry.id, name.trim()).then(setMade, (e: Error) => setError(e.message)).finally(() => setBusy(false));
              }} />
            </>
          )}
      </div>
    </div>
  );
}

/** Whether the viewer may add, rename and remove stations: the workspace's owner and admins. */
function useManager(): boolean {
  const app = useApp();
  const role = useWorkspace(app.entry.id).value?.role;
  return role === "owner" || role === "admin";
}

function StationMenu({ s }: { s: StationView }) {
  const app = useApp();
  const me = app.entry.account;
  return (
    <>
      <SheetGrab />
      <SheetHead title={s.name} />
      <div className={sheetsCss.mSheetScroll}>
        <PickRow label="改名" onClick={() => ask(app, { title: "station 的名字", value: s.name, placeholder: "比如机器名：studio", action: "保存",
          run: (name) => cloud.renameStation(me.sub, app.entry.id, s.id, name).then(() => app.toast("已改名")) })} />
        <PickRow label="从 workspace 移除" accent onClick={() => confirm(app, {
          title: `移除「${s.name}」？`, action: "移除 station", danger: true,
          text: "它会断开与 ember cloud 的连接，成员不能再从这里访问它。那台机器上的 ember 和数据不受影响，之后可以重新添加。",
          run: () => cloud.removeStation(me.sub, app.entry.id, s.id).then(() => { app.toast("已移除 station"); app.pop(); }),
        })} />
      </div>
    </>
  );
}

/**
 * A profile on its station's page: whether it works (a dot before its name, its state in words, why when its provider
 * refuses it), what it is, how many of its models are enabled, and its allowance; its page picks them.
 */
function ProfileRow({ station, p }: { station: StationView; p: Profile }) {
  const app = useApp();
  const trouble = quotaTrouble(p.quota);
  return (
    <ListRow onClick={() => app.push(app.at(`/s/${station.id}/settings/accounts/${encodeURIComponent(p.id)}`))}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}><Presence state={toneDot(p.checkTone)} /> {p.name}</span>
        <span className={listsCss.mRowNote}>{p.checkText} · {accessLabel(p)} · {p.modelsText}</span>
        {trouble && <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{trouble}</span>}
      </span>
      <QuotaRings quota={p.quota} />
      <ChevronRight size={14} className={partsCss.mSubtle} />
    </ListRow>
  );
}
