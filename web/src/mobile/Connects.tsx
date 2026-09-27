// Connects on a narrow screen (what the desktop's ../pages/Connects.tsx and Connect.tsx do, in the Android app's
// manner): the list, all or the viewer's; a connect's page (how it runs, how its conversations become sessions, its
// Slack link, what is done to it less often under "…"); how it runs, picked on a page of its own; a new one, in steps.
import { useMemo, useState } from "react";
import { useParams } from "react-router";
import { stationApi, useConnects, useOverview, useStationCall, useStations, type Connect, type ConnectItem, type ConnectMode, type MadeSlackApp, type ModelOption, type RunnableProfile, type RuntimeKind, type SlackIdentity } from "../api.ts";
import { useWorkspace } from "../cloud/api.ts";
import { MODE, RUNTIME_LABEL } from "../format.ts";
import { ChevronRight, More } from "../icons.tsx";
import { consequences } from "../pages/Connect.tsx";
import { NEW_APP } from "../pages/SlackApp.tsx";
import { stationBase, useOnlyMine, useStation } from "../station.tsx";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { AccountList, ModelList, SettingRow } from "./History.tsx";
import { Button, Field, GroupLabel, LargeTitle, ListCard, ListRow, Loading, MakerIcon, NavBar, NavButton, PickRow, SectionHeader, Seg, SlackMark, Spinner, TopBack } from "./parts.tsx";
import { ask, confirm } from "./sheets.tsx";

/** A connect's presence as a dot: online green, at work orange, failing red, offline hollow. */
function Presence({ state }: { state: string }) {
  return <span className="m-presence" data-state={state} />;
}

export function ConnectsScreen() {
  const app = useApp();
  const [onlyMine, setOnlyMine] = useOnlyMine();
  const connects = useConnects(app.entry.id, onlyMine);
  const stations = (useStations(app.entry.id).value ?? []).filter((s) => s.online);
  const items = connects.value?.items ?? [];
  const many = (useStations(app.entry.id).value ?? []).length > 1;
  const add = () => {
    if (stations.length === 1) return app.push(app.at(`/s/${stations[0]!.id}/connects/new`));
    app.sheet({ height: 0.45, content: () => (
      <>
        <SheetGrab /><SheetHead title="加在哪台 station 上" />
        <div className="m-sheet-scroll">{stations.map((s) => <PickRow key={s.id} label={s.name} onClick={() => app.push(app.at(`/s/${s.id}/connects/new`))} />)}</div>
      </>
    ) });
  };
  return (
    <div className="m-screen m-scroll">
      <TopBack label="会话" onBack={app.pop} />
      <LargeTitle small="设置" big="连接" />
      <p className="m-page-note">连接是人找到 ember 的地方，比如一个 Slack app。每个连接在一台 station 上，绑定一个模型。</p>
      <div className="m-pad-x-12 m-seg-block">
        <Seg options={["全部", "我添加的"]} selected={onlyMine ? 1 : 0} onSelect={(i) => setOnlyMine(i === 1)} height={36} fill />
      </div>
      <ListCard>
        {items.length === 0 && (
          <ListRow><span className="m-muted m-row-title">{connects.error?.message ?? (!connects.value || connects.value.loading ? "正在读取…" : onlyMine ? "没有你添加的连接。" : "还没有连接。")}</span></ListRow>
        )}
        {items.map(({ connect: c, station, stationName }) => (
          <ListRow key={`${station}/${c.id}`} onClick={() => app.push(`${stationBase(station)}/connects/${encodeURIComponent(c.id)}`)}>
            <SlackMark size={16} />
            <span className="m-grow m-row-text">
              <span className="m-row-title">{c.name}{c.team && <span className="m-row-aside"> · {c.team}</span>}</span>
              <span className="m-row-note">{c.modeText} · {c.runtimeText}{c.bind.model ? ` · ${c.bind.model}` : ""}{many ? ` · ${stationName}` : ""}</span>
            </span>
            <span className="m-row-status"><Presence state={c.presence} />{c.statusText}</span>
          </ListRow>
        ))}
        {stations.length > 0 && <ListRow onClick={add}><span className="m-accent m-row-title">＋ 添加连接</span></ListRow>}
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
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

export function ConnectScreen() {
  const app = useApp();
  const { item, loading, error } = useItem();
  if (!item) {
    return <div className="m-screen"><NavBar back="连接" onBack={app.pop} title="连接" /><Loading text={error?.message ?? (loading ? "正在读取连接…" : "没有这个连接。")} /></div>;
  }
  return <ConnectPage item={item} />;
}

function ConnectPage({ item }: { item: ConnectItem }) {
  const app = useApp();
  const station = useStation();
  const { connect, bound, sessions } = item;
  const c = connect.connection;
  return (
    <div className="m-screen">
      <NavBar back="连接" onBack={app.pop} title={connect.name} sub={<span className="m-navbar-note"><Presence state={connect.presence} /> {connect.statusText}</span>}
        trailing={<NavButton icon={More} label="更多" onClick={() => app.sheet({ height: 0.6, content: () => <ConnectMenu connect={connect} /> })} />} />
      <div className="m-scroll m-station-page">
        {(c.state === "no_tokens" || c.state === "error" || (c.state === "reconnecting" && c.lastError)) && (
          <div className="m-callout">
            {c.state === "no_tokens" ? <>这个连接还没接上 Slack。<button type="button" className="m-link" onClick={() => openTokens(app, connect)}>填 token</button></>
              : c.state === "error" ? c.error : `正在重连：${c.lastError}`}
          </div>
        )}
        <SectionHeader title="怎么跑" start={24} />
        <ListCard>
          <ListRow onClick={() => app.push(`${stationBase(station.address)}/connects/${encodeURIComponent(connect.id)}/run`)}>
            <span className="m-run-label">模型</span>
            <span className="m-grow m-row-title">{connect.bind.model ?? "选模型"}<span className="m-muted"> · {connect.bind.effort || "默认深度"} · {connect.bind.profile ? "固定账号" : "自动分配"}</span></span>
            <ChevronRight size={14} className="m-subtle" />
          </ListRow>
          <ListRow onClick={() => app.sheet({ height: 0.8, draggable: true, content: () => <ModeSheet item={item} /> })}>
            <span className="m-run-label">会话</span>
            <span className="m-grow m-row-text">
              <span className="m-row-title">{MODE[connect.mode].label}</span>
              <span className="m-row-note m-wrap">{MODE[connect.mode].description}{connect.mode === "single-session" && (connect.requireMention ? "只在被 @ 时唤醒。" : "它能看到的每条消息都会送进会话。")}</span>
            </span>
            <ChevronRight size={14} className="m-subtle" />
          </ListRow>
          {connect.mode === "single-session" && (
            <ListRow onClick={() => app.sheet({ height: 0.7, draggable: true, content: () => <SessionSheet item={item} /> })}>
              <span className="m-run-label">当前</span>
              <span className="m-grow m-row-title">{bound ? bound.titleText : <span className="m-muted">还没有会话；下一条消息会开始一个新的。</span>}</span>
              <ChevronRight size={14} className="m-subtle" />
            </ListRow>
          )}
        </ListCard>
        <p className="m-page-note">跑在 {connect.runtimeText} 上，创建后不能换；要用另一种运行时，新建一个连接。进行中的会话继续用开始时的设置。</p>
        <SectionHeader title="最近的会话" start={24} />
        <ListCard>
          {sessions.length === 0 && <ListRow><span className="m-muted m-row-title">还没有会话。在 Slack 里 @{connect.name} 就会开始。</span></ListRow>}
          {sessions.map((s) => (
            <ListRow key={s.key} onClick={() => app.push(`${stationBase(station.address)}/chats/${encodeURIComponent(s.key)}`)}>
              <span className="m-grow m-row-title">{s.titleText}</span>
              <span className="m-row-note">{s.statusText}</span>
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
  const done = (text: string) => () => { app.toast(text); app.sheet(null); };
  const failed = (e: Error) => app.toast(e.message);
  return (
    <>
      <SheetGrab />
      <SheetHead title={connect.name} />
      <div className="m-sheet-scroll">
        <PickRow label="重新连接" onClick={() => void api.reconnect(connect.id).then(done("已重新连接"), failed)} />
        <PickRow label="更换 token" onClick={() => openTokens(app, connect)} />
        {workspace?.url && <PickRow label="打开 Slack" onClick={() => window.open(workspace.url, "_blank", "noopener")} />}
        {connect.enabled
          ? <PickRow label="停用" sub="Slack 连接会断开" onClick={() => void api.putConnect(connect.id, { enabled: false }).then(done("已停用，Slack 连接已断开"), failed)} />
          : <PickRow label="启用" onClick={() => void api.putConnect(connect.id, { enabled: true }).then(done("已启用"), failed)} />}
        <PickRow label="更改所属用户" sub={connect.createdBy?.shown?.display ?? connect.createdBy?.name} onClick={() => app.sheet({ height: 0.6, content: () => <OwnerSheet connect={connect} /> })} />
        <PickRow label="删除连接" accent onClick={() => confirm(app, {
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
  return (
    <>
      <SheetGrab />
      <SheetHead title="更改所属用户" />
      <div className="m-sheet-scroll">
        <p className="m-muted m-pad m-small">连接属于谁，决定它出现在谁的「我添加的」里。</p>
        {members.map((m) => (
          <PickRow key={m.sub} label={m.name || m.email} sub={m.email} checked={m.email.toLowerCase() === connect.createdBy?.id.toLowerCase()}
            onClick={() => void api.putConnect(connect.id, { owner: { id: m.email, name: m.name || m.email } }).then(() => { app.toast("已更改所属用户"); app.sheet(null); }, (e: Error) => app.toast(e.message))} />
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
  const [busy, setBusy] = useState(false);
  const changed = next.mode !== connect.mode || (next.mode === "single-session" && next.requireMention !== connect.requireMention);
  const effects = changed ? consequences(connect, next, item.running) : [];
  return (
    <>
      <SheetGrab />
      <SheetHead title="会话方式" />
      <div className="m-sheet-scroll m-form">
        <ModeChoices value={next} onChange={setNext} />
        {effects.length > 0 && <div className="m-callout"><b>更改之后</b><ul>{effects.map((e) => <li key={e}>{e}</li>)}</ul></div>}
        <div className="m-form-actions">
          <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
          <Button label={next.mode === connect.mode ? "确认更改" : `改为${next.mode === "single-session" ? "单会话" : "多会话"}`} primary busy={busy} enabled={changed}
            onClick={() => { setBusy(true); api.putConnect(connect.id, next).then(() => { app.toast("已更改会话方式"); app.sheet(null); }, (e: Error) => app.toast(e.message)).finally(() => setBusy(false)); }} />
        </div>
      </div>
    </>
  );
}

function ModeChoices({ value, onChange }: { value: { mode: ConnectMode; requireMention: boolean }; onChange: (v: { mode: ConnectMode; requireMention: boolean }) => void }) {
  return (
    <div className="m-choices">
      {(["multi-session", "single-session"] as const).map((m) => (
        <button key={m} type="button" className="m-choice" data-on={value.mode === m || undefined}
          onClick={() => onChange({ mode: m, requireMention: m === "multi-session" ? true : value.requireMention })}>
          <b>{MODE[m].label}</b><span>{MODE[m].description}</span>
        </button>
      ))}
      {value.mode === "single-session" && (
        <button type="button" className="m-switch-row" onClick={() => onChange({ ...value, requireMention: !value.requireMention })}>
          <span className="m-grow"><b>只在被 @ 时唤醒</b><span>{value.requireMention ? "被 @ 的 thread 之后的回复不用再 @。" : "频道里它能看到的每条消息都会送进会话。"}</span></span>
          <span className="m-switch" data-on={value.requireMention || undefined} />
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
  const [busy, setBusy] = useState(false);
  return (
    <>
      <SheetGrab />
      <SheetHead title="选择会话" />
      <div className="m-sheet-scroll m-form">
        <p className="m-muted m-small">之后「{connect.name}」收到的消息都进选中的会话。原来的会话保留，但不再收到这个连接的新消息。</p>
        <PickRow label="新建会话" sub="从空白上下文开始" checked={choice === "new"} onClick={() => setChoice("new")} />
        {choice === "new" && <Field value={title} onChange={setTitle} placeholder="给它起个名字（可选），例如：值班" />}
        {candidates.map((s) => <PickRow key={s.key} label={s.titleText} sub={s.description} checked={choice === s.key} onClick={() => setChoice(s.key)} />)}
        <div className="m-form-actions">
          <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
          <Button label={choice === "new" ? "新建并使用" : "使用这个会话"} primary busy={busy} enabled={choice !== connect.session}
            onClick={() => { setBusy(true); api.bindSession(connect.id, choice === "new" ? null : choice, title).then(() => { app.toast(choice === "new" ? "已新建会话" : "已换成这个会话"); app.sheet(null); }, (e: Error) => app.toast(e.message)).finally(() => setBusy(false)); }} />
        </div>
      </div>
    </>
  );
}

// ── tokens ─────────────────────────────────────────────────────────────

interface Tokens { appToken: string; botToken: string; verified: SlackIdentity | null }
const NO_TOKENS: Tokens = { appToken: "", botToken: "", verified: null };

/** Replaces a connect's Slack tokens (either one; the other kept), verified before they are saved. */
function openTokens(app: MobileApp, connect: Connect) {
  app.sheet({ height: 0.72, draggable: true, content: () => <TokensSheet connect={connect} /> });
}

function TokensSheet({ connect }: { connect: Connect }) {
  const app = useApp();
  const api = useApi();
  const [tokens, setTokens] = useState<Tokens>(NO_TOKENS);
  const [busy, setBusy] = useState(false);
  return (
    <>
      <SheetGrab />
      <SheetHead title="Slack token" />
      <div className="m-sheet-scroll m-form">
        <p className="m-muted m-small">只换其中一个也可以，另一个留空会沿用已保存的。保存前先验证。</p>
        <TokenFields value={tokens} onChange={setTokens} connect={connect.id} masked={connect.slack} />
        <div className="m-form-actions">
          <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
          <Button label="保存并连接" primary busy={busy} enabled={!!tokens.verified}
            onClick={() => { setBusy(true); api.putConnect(connect.id, { slack: { appToken: tokens.appToken, botToken: tokens.botToken } }).then(() => { app.toast("已保存 token，正在连接"); app.sheet(null); }, (e: Error) => app.toast(e.message)).finally(() => setBusy(false)); }} />
        </div>
      </div>
    </>
  );
}

/**
 * The two tokens with a verify step. For an existing connect a blank field keeps the stored token. An app installed
 * through Slack's OAuth (`install`) has its bot token on the station already: only the app-level token is asked for.
 */
function TokenFields({ value, onChange, connect, masked, install }: { value: Tokens; onChange: (t: Tokens) => void; connect?: string; masked?: { appToken: string; botToken: string }; install?: string | undefined }) {
  const api = useApi();
  const [errors, setErrors] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const edit = (patch: Partial<Tokens>) => { setErrors([]); onChange({ ...value, ...patch, verified: null }); };
  const verify = () => {
    setBusy(true);
    api.verifySlack({ ...(connect ? { connect } : {}), ...(install ? { install } : {}), appToken: value.appToken, botToken: value.botToken }).then((r) => {
      setErrors(r.errors);
      onChange({ ...value, verified: r.errors.length === 0 ? r.identity : null });
    }, (e: Error) => setErrors([e.message])).finally(() => setBusy(false));
  };
  return (
    <div className="m-form-group">
      <b className="m-form-label">App-Level Token</b>
      <input className="m-field" data-mono type="password" autoComplete="off" spellCheck={false} value={value.appToken} onChange={(e) => edit({ appToken: e.target.value.trim() })}
        placeholder={masked?.appToken ? `已保存 ${masked.appToken}，留空不变` : "xapp-…"} />
      {!install && (
        <>
          <b className="m-form-label">Bot Token</b>
          <input className="m-field" data-mono type="password" autoComplete="off" spellCheck={false} value={value.botToken} onChange={(e) => edit({ botToken: e.target.value.trim() })}
            placeholder={masked?.botToken ? `已保存 ${masked.botToken}，留空不变` : "xoxb-…"} />
        </>
      )}
      <div className="m-verify">
        <Button label="验证 token" primary={false} busy={busy} enabled={!!(value.appToken || value.botToken || connect)} onClick={verify} />
        {value.verified && <span className="m-green m-small">连接到「{value.verified.team}」，bot 是 @{value.verified.botName}</span>}
      </div>
      {errors.map((e) => <p key={e} className="m-error">{e}</p>)}
    </div>
  );
}

// ── how it runs ────────────────────────────────────────────────────────

/** The model a connect runs, how hard it thinks and who runs it: picked like an agent's (./History.tsx), saved for new sessions. */
export function ConnectRunScreen() {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const { item } = useItem();
  const view = useStations(station.address.split("/")[0]!).value?.find((s) => s.station === station.address);
  const [list, setList] = useState<"model" | "account" | null>(null);
  const [draft, setDraft] = useState<{ model: string | null; effort: string; profile: string | null } | null>(null);
  const [busy, setBusy] = useState(false);
  const title = list === "model" ? "选模型" : list === "account" ? "选账号" : "换模型";
  const bar = <NavBar back={list ? "换模型" : "返回"} onBack={() => (list ? setList(null) : app.pop())} title={title} />;
  if (!item) return <div className="m-screen">{bar}<Loading text="正在读取连接…" /></div>;
  const { connect } = item;
  const runtime = connect.bind.runtime;
  const models = (view?.models ?? []).filter((m) => m.runtimes.includes(runtime));
  const model = draft ? draft.model : connect.bind.model ?? null;
  const effort = draft ? draft.effort : connect.bind.effort ?? "";
  const profile = draft ? draft.profile : connect.bind.profile ?? null;
  const set = (next: Partial<{ model: string | null; effort: string; profile: string | null }>) => setDraft({ model, effort, profile, ...next });
  const choice = models.find((m) => m.model === model);
  const accounts: RunnableProfile[] = choice?.accounts[runtime] ?? [];
  const efforts = choice?.efforts[runtime] ?? [];
  const changed = model !== (connect.bind.model ?? null) || effort !== (connect.bind.effort ?? "") || profile !== (connect.bind.profile ?? null);
  if (list === "model") return <div className="m-screen">{bar}<ModelList models={models} runtime={runtime} picked={model} onPick={(m) => { set({ model: m, profile: null }); setList(null); }} /></div>;
  if (list === "account") return <div className="m-screen">{bar}<AccountList accounts={accounts} runtime={runtime} picked={profile} onPick={(p) => { set({ profile: p }); setList(null); }} /></div>;
  return (
    <div className="m-screen">
      {bar}
      <div className="m-scroll m-pad-x-18">
        {models.length === 0 && <p className="m-callout">{connect.runtimeText} 的 Profile 还没有启用模型，先在 Station 页的 Profile 里勾选。</p>}
        <GroupLabel>模型</GroupLabel>
        <SettingRow onClick={() => setList("model")} leading={<MakerIcon maker={choice?.maker} runtime={runtime} size={18} />}><span className="m-setting-main">{model ?? "选一个模型"}</span></SettingRow>
        <GroupLabel>思考深度</GroupLabel>
        <div className="m-chips">
          {["", ...efforts].map((e) => <button key={e || "-"} type="button" className="m-chip" data-on={e === effort || undefined} onClick={() => set({ effort: e })}>{e || "默认"}</button>)}
        </div>
        <GroupLabel>账号</GroupLabel>
        <SettingRow onClick={() => setList("account")}>
          <span className="m-setting-main">{profile ? accounts.find((a) => a.id === profile)?.name ?? profile : "自动分配"}</span>
          <small className="m-muted">{profile ? "固定用它" : "额度用完或登录失效时换一个"}</small>
        </SettingRow>
        <p className="m-small m-subtle m-effort-note">新开的会话会用新的设置；进行中的会话继续用开始时的。</p>
      </div>
      <button type="button" className="m-run-go" data-changed={changed || undefined} disabled={busy || (changed && !model)}
        onClick={() => {
          if (!changed) return app.pop();
          setBusy(true);
          api.putConnect(connect.id, { bind: { model: model ?? "", effort, profile } }).then(() => { app.toast("已保存，新会话会用新的设置"); app.pop(); }, (e: Error) => app.toast(e.message)).finally(() => setBusy(false));
        }}>
        {busy && <Spinner size={14} />}{changed ? `改成 ${model ?? "默认模型"} · ${effort || "默认深度"}` : "不变"}
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
  const [step, setStep] = useState<Step>("team");
  const [team, setTeam] = useState<string | null>(null);
  const [appSettings, setAppSettings] = useState(NEW_APP);
  const [made, setMade] = useState<MadeSlackApp | null>(null);
  const [tokens, setTokens] = useState<Tokens>(NO_TOKENS);
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
  const order: Step[] = step === "manual" || (step === "bind" && !made) ? ["manual", "bind"] : ["team", "app", "install", "bind"];
  const titles: Record<Step, string> = { team: "选 Slack 工作区", token: "加配置 token", app: "配置 app", install: "安装", manual: "连接 Slack", bind: "绑定模型" };
  const run = (work: () => Promise<unknown>) => { setBusy(true); setError(null); work().catch((e: Error) => setError(e.message)).finally(() => setBusy(false)); };
  const back = () => ({ team: app.pop, token: () => setStep("team"), app: () => setStep("team"), install: () => setStep("app"), manual: () => setStep("team"), bind: () => setStep(made ? "install" : "manual") }[step]());
  const installed = made && overview?.slackInstalls.find((i) => i.state === made.state);
  return (
    <div className="m-screen">
      <NavBar back={step === "team" ? "取消" : "上一步"} onBack={back} title="添加连接" sub={<span className="m-navbar-note">{titles[step]} · {Math.max(1, order.indexOf(step) + 1)} / {order.length}</span>} />
      <div className="m-scroll m-pad-x-18 m-steps">
        {step === "team" && (teams.length === 0 ? (
          <>
            <p className="m-muted">有了 Slack 的配置 token，ember 替你在 Slack 建好 app：名字、权限都在这里填，不用去 Slack 后台一项项配。它只归你用。</p>
            <Button label="添加配置 token" primary onClick={() => setStep("token")} />
            <button type="button" className="m-link m-step-alt" onClick={() => setStep("manual")}>不用配置 token，自己在 Slack 建 app</button>
          </>
        ) : (
          <>
            <p className="m-muted">用哪个 Slack 工作区的配置 token 建 app。</p>
            <ListCard>{teams.map((t) => <PickRow key={t.teamId} label={t.name} sub={t.owner ? `${t.owner.user}${t.owner.teamDomain ? ` · ${t.owner.teamDomain}.slack.com` : ""}` : undefined} checked={chosen?.teamId === t.teamId} onClick={() => setTeam(t.teamId)} />)}</ListCard>
            <button type="button" className="m-link m-step-alt" onClick={() => setStep("token")}>＋ 添加工作区的配置 token</button>
            <button type="button" className="m-link m-step-alt" onClick={() => setStep("manual")}>不用配置 token，自己建 app</button>
            <Button label="下一步" primary enabled={!!chosen} onClick={() => setStep("app")} />
          </>
        ))}
        {step === "token" && (
          <>
            <ol className="m-steps-list">
              <li>打开 <a href="https://api.slack.com/apps" target="_blank" rel="noopener">api.slack.com/apps</a>，用要放 bot 的那个 Slack 工作区的账号登录。</li>
              <li>拉到页面最下面的「Your App Configuration Tokens」，点 Generate Token，选这个工作区。</li>
              <li>把以 xoxe-1- 开头的 Refresh Token 粘贴到下面。ember 会自己续期，以后不用再管。</li>
            </ol>
            <input className="m-field" data-mono type="password" autoComplete="off" spellCheck={false} value={config} placeholder="xoxe-1-…" onChange={(e) => setConfig(e.target.value.trim())} />
            {config.startsWith("xoxe.xoxp-") && <p className="m-error">这是 Access Token。要的是它下面那个 Refresh Token，以 xoxe-1- 开头。</p>}
            <Button label="加上" primary busy={busy} enabled={config.startsWith("xoxe-1-") && config.length > 20}
              onClick={() => run(() => api.addConfigToken(config).then(({ teamId }) => { setConfig(""); setTeam(teamId); setStep("app"); }))} />
          </>
        )}
        {step === "app" && (
          <>
            <b className="m-form-label">名字</b>
            <Field value={appSettings.name} onChange={(v) => setAppSettings({ ...appSettings, name: v, displayName: v })} placeholder="ember" />
            <b className="m-form-label">描述</b>
            <Field value={appSettings.description} onChange={(v) => setAppSettings({ ...appSettings, description: v })} placeholder="Coding agent in your threads" />
            <p className="m-small m-muted">头像、颜色和权限用默认的；建好以后可以在电脑上改。</p>
            <Button label="创建 app" primary busy={busy} enabled={!!appSettings.name.trim() && !!chosen}
              onClick={() => run(() => api.makeSlackApp({ team: chosen!.teamId, settings: appSettings }).then((r) => { setMade(r); setStep("install"); }))} />
          </>
        )}
        {step === "install" && made && (
          <>
            <ol className="m-steps-list">
              {made.install ? (
                <li>{installed?.installed ? `已装进「${installed.team ?? "工作区"}」。` : <>app 已经建好。<a href={made.install} target="_blank" rel="noopener">安装到工作区</a>：在 Slack 里点「允许」，bot token 会自动交给 station。</>}</li>
              ) : (
                <li>app 已经建好。<a href={made.links.install} target="_blank" rel="noopener">安装到工作区</a>，然后在 <a href={made.links.oauth} target="_blank" rel="noopener">OAuth 页</a> 复制 Bot User OAuth Token（xoxb- 开头）。</li>
              )}
              <li>在 <a href={made.links.appToken} target="_blank" rel="noopener">Basic Information</a> 页生成 App-Level Token，勾选 connections:write，复制（xapp- 开头）。</li>
              <li>{made.install ? "把 App-Level Token 填在下面。" : "把两个 token 填在下面。"}</li>
            </ol>
            <TokenFields value={tokens} onChange={setTokens} install={made.state ?? undefined} />
            <Button label="下一步" primary enabled={!!tokens.verified} onClick={() => setStep("bind")} />
          </>
        )}
        {step === "manual" && (
          <>
            <ol className="m-steps-list">
              <li><button type="button" className="m-link" onClick={() => void api.createAppUrl("ember").then(({ url }) => window.open(url, "_blank", "noopener"))}>用 ember 的配置在 Slack 新建一个 app</button>。</li>
              <li>在 app 的 Basic Information 页生成 App-Level Token，勾选 connections:write。</li>
              <li>在 Install App 页安装到工作区，复制 Bot User OAuth Token。</li>
              <li>把两个 token 填在下面。</li>
            </ol>
            <TokenFields value={tokens} onChange={setTokens} />
            <Button label="下一步" primary enabled={!!tokens.verified} onClick={() => setStep("bind")} />
          </>
        )}
        {step === "bind" && (
          <>
            <GroupLabel>模型</GroupLabel>
            {models.length === 0 ? <p className="m-callout">这台 station 的 Profile 还没有启用模型，先在 Station 页的 Profile 里勾选。</p> : (
              <ListCard>{models.map((m) => <PickRow key={m.model} label={m.model} sub={m.runtimes.map((r) => RUNTIME_LABEL[r] ?? r).join(" · ")} checked={entry?.model === m.model}
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
        {error && <p className="m-error">{error}</p>}
        <div style={{ height: 30 }} />
      </div>
    </div>
  );
}

