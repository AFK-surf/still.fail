// A connect: where people reach ember (a Slack app today), the model it is
// bound to, and how its conversations become sessions.
import { profilesPage, scopeOf, useStation, useLink } from "../station.tsx";
import { CheckCircle, External, Key, Plus, Power, Refresh, Trash, User } from "../icons.tsx";
import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { useAction, useApi, useConnects, useOverview, useStations, type ConnectInput, type ConnectItem, type ConnectMode, type Connect, type ModelOption, type Overview, type RuntimeKind, type MadeSlackApp } from "../api.ts";
import { MODE } from "../format.ts";
import { AppFields, ConfigTokenForm, NEW_APP, SlackAppSection } from "./SlackApp.tsx";
import { ModelTriple } from "../ModelTriple.tsx";
import { OwnerLabel } from "../components.tsx";
import { PeopleContext } from "../station.tsx";
import { useContext } from "react";
import { CreateAppSteps, emptyTokens, TokenFields, useTokenCheck, type TokenState } from "../slack.tsx";
import { useToast } from "../toast.tsx";
import { Button, Choices, Confirm, ConnectAvatar, Dialog, Empty, Field, ICON, Loading, Menu, BackLink, Pill, Section, Select, SlackLogo, StatusDot, SwitchRow, Time } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./Connect.css.ts";
import * as cloudCss from "../styles/cloud.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as additionsCss from "../styles/additions.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as shellCss from "../styles/shell.css.ts";

export function ConnectPage() {
  const { id } = useParams();
  const station = useStation();
  const overview = useOverview(station.address);
  const connects = useConnects(scopeOf(station.address));
  const item = connects.value?.items.find((i) => i.station === station.address && i.connect.id === id);
  if (!overview.value || !connects.value || (connects.value.loading && !item)) {
    const error = overview.error ?? connects.error;
    return error ? <Empty><p>{error.message}</p></Empty> : <Loading label="正在读取连接…" />;
  }
  if (!item) return <Empty><p>没有 ID 为 {id} 的连接。</p></Empty>;
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
  const remove = useAction(() => api.deleteConnect(connect.id), () => { toast("已删除连接"); navigate(`${station.settings}/connects`); });
  const reconnect = useAction(() => api.reconnect(connect.id), () => toast("已重新连接"));
  const c = connect.connection;
  const workspace = c.state === "connected" || c.state === "reconnecting" ? c.workspace : null;

  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <BackLink to={`${station.settings}/connects`} label="连接" />
      {/* Who it is and whether it is up; what is done to it less often is in the menu. */}
      <header className={pagesCss.identity}>
        <ConnectAvatar connect={connect} size={52} />
        <div className={pagesCss.identityText}>
          <h1 className={pagesCss.identityName}>{connect.name}</h1>
          <p className={pagesCss.identitySub}>
            <span className={css.connectStatus}><StatusDot state={connect.presence} />{connect.statusText}</span>
            <span className={css.kindTag}><SlackLogo size={13} />{connect.team ?? "Slack"}</span>
            {station.name && <span className={cloudCss.stationTag}>{station.name}</span>}
            <span className={css.ownerLine}>所属 <OwnerLabel owner={connect.createdBy} /></span>
          </p>
        </div>
        <Menu items={[
          { label: "重新连接", icon: Refresh, onSelect: () => void reconnect.run() },
          { label: "更换 token", icon: Key, onSelect: () => setReplacing(true) },
          ...(workspace?.url ? [{ label: "打开 Slack", icon: External, onSelect: () => window.open(workspace.url, "_blank", "noopener") }] : []),
          "separator",
          connect.enabled
            ? { label: "停用", icon: Power, onSelect: () => save.put({ enabled: false }, () => toast("已停用，Slack 连接已断开")) }
            : { label: "启用", icon: Power, onSelect: () => save.put({ enabled: true }, () => toast("已启用")) },
          { label: "更改所属用户", icon: User, onSelect: () => setOwning(true) },
          "separator",
          { label: "删除连接", icon: Trash, danger: true, onSelect: () => setDeleting(true) },
        ]} />
      </header>
      {save.error && <p className={`${controlsCss.fieldError} ${css.pageError}`} role="alert">{save.error.message}</p>}

      <SlackSection connect={connect} />
      <RunSection item={item} />
      <ConnectSessions item={item} />
      <SlackAppSection connect={connect} />

      {replacing && <TokenDialog connect={connect} onClose={() => setReplacing(false)} />}
      {owning && <OwnerDialog connect={connect} onClose={() => setOwning(false)} />}
      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.busy} onConfirm={() => void remove.run()}
        title={`删除「${connect.name}」？`} action="删除连接"
        description={`Slack 连接会断开${connect.sessions ? `；它的 ${connect.sessions} 个会话的记录会保留，但不再接收消息` : ""}。Slack 里的 app 需要你自己去删除。`} error={remove.error?.message} />
    </div>
  );
}

/** The Slack link, when it needs something: tokens to connect with, or an error. Up and running, the header says so. */
function SlackSection({ connect }: { connect: Connect }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const [tokens, setTokens] = useState<TokenState>(emptyTokens);
  const check = useTokenCheck(tokens, setTokens);
  const c = connect.connection;
  if (c.state === "no_tokens") {
    return (
      <Section title="接上 Slack" description="这个连接还没接上 Slack。">
        <div className={pagesCss.card}>
          <CreateAppSteps name={connect.name} />
          <TokenFields value={tokens} onChange={setTokens} check={check} />
          <div className={pagesCss.cardActions}>
            <Button variant="primary" disabled={!check.ready} busy={check.busy || save.busy}
              onClick={() => check.then(() => save.put({ slack: { appToken: tokens.appToken, botToken: tokens.botToken } }, () => { setTokens(emptyTokens); toast("已保存 token，正在连接"); }))}>保存并连接</Button>
          </div>
        </div>
      </Section>
    );
  }
  if (c.state === "error" || (c.state === "reconnecting" && c.lastError)) {
    return <div className={additionsCss.callout} data-tone="amber" role="status"><span>{c.state === "error" ? c.error : `正在重连：${c.lastError}`}</span></div>;
  }
  return null;
}

/** Replaces the connect's Slack tokens (either one; the other kept), verified before they are saved. */
function TokenDialog({ connect, onClose }: { connect: Connect; onClose(): void }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const [tokens, setTokens] = useState<TokenState>(emptyTokens);
  const check = useTokenCheck(tokens, setTokens, { connect: connect.id });
  return (
    <Dialog open onClose={onClose} title="更换 Slack token" description="只换其中一个也可以，另一个留空会沿用已保存的。"
      footer={<>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" disabled={!check.ready} busy={check.busy || save.busy}
          onClick={() => check.then(() => save.put({ slack: { appToken: tokens.appToken, botToken: tokens.botToken } }, () => { toast("已保存 token，正在重新连接"); onClose(); }))}>保存并重新连接</Button>
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
    <Choices label="会话方式" value={mode} onChange={(m) => onChange({ mode: m, requireMention: m === "multi-session" ? true : requireMention })}
      options={(["multi-session", "single-session"] as const).map((m) => ({
        value: m, title: MODE[m].label, description: MODE[m].description, disabled,
        extra: m === "single-session" ? (
          <SwitchRow title="只在被 @ 时唤醒" checked={requireMention} disabled={disabled}
            description={requireMention ? "被 @ 的 thread 之后的回复不用再 @。" : "频道里它能看到的每条消息都会送进会话。"}
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
  return (
    <Section title="怎么跑">
      <div className={`${pagesCss.card} ${css.runCard}`}>
        <div className={css.runCardRow}>
          <span className={css.runCardLabel}>模型</span>
          {models.length === 0
            ? <Link className={chatCss.inlineLink} to={profilesPage(station)}>{connect.runtimeText} 的 Profile 还没有启用模型 · 去勾选</Link>
            : <ModelTriple title="换模型、思考深度和账号" runtimeFixed options={models}
                value={{ model: connect.bind.model ?? "", runtime: connect.bind.runtime, effort: connect.bind.effort ?? null, profile: connect.bind.profile ?? null }}
                onPick={(p) => save.put({ bind: { model: p.model, effort: p.effort ?? "", profile: p.profile } }, () => toast("已保存，新会话会用新的设置"))} />}
        </div>
        <div className={css.runCardRow}>
          <span className={css.runCardLabel}>会话</span>
          <span className={css.runCardText}>
            <strong>{MODE[connect.mode].label}</strong>
            <span className={shellCss.muted}>{MODE[connect.mode].description}{connect.mode === "single-session" && (connect.requireMention ? "只在被 @ 时唤醒。" : "它能看到的每条消息都会送进会话。")}</span>
          </span>
          <button type="button" className={chatCss.textButton} onClick={() => setChangingMode(true)}>更改</button>
        </div>
        {connect.mode === "single-session" && (
          <div className={css.runCardRow}>
            <span className={css.runCardLabel}>当前</span>
            <span className={css.runCardText}>
              {bound
                ? <Link className={chatCss.inlineLink} to={link(`/chats/${encodeURIComponent(bound.key)}`)}>{bound.titleText}</Link>
                : <span className={shellCss.muted}>还没有会话；下一条消息会开始一个新的。</span>}
            </span>
            <button type="button" className={chatCss.textButton} onClick={() => setChoosing(true)}>换一个</button>
          </div>
        )}
        {save.error && <p className={controlsCss.fieldError} role="alert">{save.error.message}</p>}
        <p className={`${controlsCss.cardFoot} ${shellCss.muted}`}>跑在 {connect.runtimeText} 上，创建后不能换；要用另一种运行时，新建一个连接。进行中的会话继续用开始时的设置。</p>
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
    out.push("之后它收到的消息都进同一个会话；已有的每个 thread 的会话不再收到新消息，包括这些 thread 里的回复。记录会保留。");
    out.push(connect.session ? "会接着使用之前绑定的单会话。" : "下一条消息会开始一个新的单会话；也可以在切换后选一个已有会话。");
    if (!next.requireMention) out.push("不需要 @：它能看到的所有频道和私信里的每条消息都会送给 agent，消耗会明显增加。");
  } else if (connect.mode === "single-session" && next.mode === "multi-session") {
    out.push("当前绑定的会话不再收到新消息。之后每个 thread 被 @ 时各开一个新会话。");
    out.push("在单会话里进行过的 thread，要继续就需要重新 @，会开一个新会话，不带之前的上下文。");
    out.push("以后切回单会话，会接着用原来的那个会话。");
  } else if (next.requireMention !== connect.requireMention) {
    out.push(next.requireMention
      ? "之后只有被 @ 的 thread 会进会话；已经进来的 thread 里的回复仍然会送到。"
      : "不需要 @：它能看到的所有频道和私信里的每条消息都会送给 agent，消耗会明显增加。");
  }
  if (running > 0) out.push(`现在有 ${running} 个会话正在运行，它们会跑完当前这一轮。`);
  return out;
}

function ModeDialog({ connect, running, onClose }: { connect: Connect; running: number; onClose(): void }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const [next, setNext] = useState({ mode: connect.mode, requireMention: connect.requireMention });
  const changed = next.mode !== connect.mode || (next.mode === "single-session" && next.requireMention !== connect.requireMention);
  const effects = changed ? consequences(connect, next, running) : [];
  return (
    <Dialog open onClose={onClose} wide title="更改会话方式"
      description="这会改变之后每条消息进哪个会话。已经开始的对话可能因此断开，请看清下面的影响再确认。"
      footer={<>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" disabled={!changed} busy={save.busy}
          onClick={() => save.put(next, () => { toast("已更改会话方式"); onClose(); })}>
          {next.mode === connect.mode ? "确认更改" : `改为${next.mode === "single-session" ? "单会话" : "多会话"}`}
        </Button>
      </>}>
      <ModeChoices mode={next.mode} requireMention={next.requireMention} onChange={setNext} />
      {effects.length > 0 && (
        <div className={additionsCss.callout} data-tone="amber" role="note">
          <strong>更改之后</strong>
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
    toast(choice === "new" ? "已新建会话" : "已换成这个会话");
    onClose();
  });
  return (
    <Dialog open onClose={onClose} wide title="选择会话"
      description={`之后「${connect.name}」收到的消息都进选中的会话。原来的会话保留，但不再收到这个连接的新消息。`}
      footer={<>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" busy={bind.busy} disabled={choice === connect.session}
          onClick={() => void bind.run()}>{choice === "new" ? "新建并使用" : "使用这个会话"}</Button>
      </>}>
      <div className={css.sessionChoices}>
        <Choices label="会话" value={choice} onChange={setChoice} options={[
          {
            value: "new", title: "新建会话", description: "从空白上下文开始。",
            extra: <input className={controlsCss.input} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="给它起个名字（可选），例如：值班" aria-label="新会话的名字" />,
          },
          ...candidates.map((s) => ({
            value: s.key,
            title: <>{s.titleText}{s.current && <span className={additionsCss.choiceBadge}>当前</span>}</>,
            description: s.description,
          })),
        ]} />
      </div>
      {bind.error && <p className={controlsCss.fieldError} role="alert">{bind.error.message}</p>}
    </Dialog>
  );
}

function ConnectSessions({ item }: { item: ConnectItem }) {
  const { connect, sessions } = item;
  const link = useLink();
  return (
    <Section title="最近的会话">
      {sessions.length === 0 ? <p className={shellCss.muted}>还没有会话。在 Slack 里 @{connect.name} 就会开始。</p> : (
        <ul className={pagesCss.list}>
          {sessions.map((s) => {
            const row = (
              <>
                <span className={pagesCss.listRowTitle}>{s.titleText}</span>
                <Pill tone={s.tone}>{s.statusText}</Pill>
                <Time className={`${shellCss.muted} ${css.listRowTime}`} stamp={s.time?.lastActiveAt} />
              </>
            );
            return <li key={s.key}><Link className={pagesCss.listRow} to={link(`/chats/${encodeURIComponent(s.key)}`)}>{row}</Link></li>;
          })}
        </ul>
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
export function NewConnectDialog({ open, onClose, resume }: { open: boolean; onClose(): void; resume?: string | undefined }) {
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
  const [tokens, setTokens] = useState<TokenState>(emptyTokens);
  const check = useTokenCheck(tokens, setTokens, { install: made?.state ?? undefined });
  // The model first; the runtime only when the model runs on more than one.
  const models = useStationModels();
  const [model, setModel] = useState("");
  const [picked, setPicked] = useState<RuntimeKind | null>(null);
  const entry = models.find((m) => m.model === model) ?? models[0];
  const runtime: RuntimeKind = entry && picked && entry.runtimes.includes(picked) ? picked : entry?.runtimes[0] ?? "claude";
  const [effort, setEffort] = useState("");
  const [profile, setProfile] = useState<string | null>(null);
  const [mode, setMode] = useState<{ mode: ConnectMode; requireMention: boolean }>({ mode: "multi-session", requireMention: true });
  // The workspace chosen, else the only one there is.
  const chosen = teams.find((t) => t.teamId === team) ?? (teams.length === 1 ? teams[0] : undefined);

  const close = () => {
    setStep("team"); setTeam(null); setAdding(false); setApp(NEW_APP); setIcon(null); setIconError(null); setMadeId(null);
    setTokens(emptyTokens); setModel(""); setPicked(null); setEffort(""); setMode({ mode: "multi-session", requireMention: true });
    onClose();
  };
  const makeApp = useAction(() => api.makeSlackApp({ team: chosen!.teamId, settings: app, ...(icon ? { icon } : {}) }), (result) => {
    setMadeId(result.appId); setIconError(result.iconError); setStep("install");
  });
  const create = useAction(() => api.createConnect({
    kind: "slack", ...mode, bind: { runtime, model: entry?.model ?? "", effort, profile },
    slack: made?.state ? { appToken: tokens.appToken, install: made.state }
      : { appToken: tokens.appToken, botToken: tokens.botToken, ...(made ? { appId: made.appId } : {}) },
  }), ({ id }) => {
    toast("已添加连接，正在连接 Slack");
    close();
    navigate(link(`/connects/${id}`));
  });

  // Getting a token is a view of its own: when there is none yet, or another is being added.
  const gettingToken = step === "team" && (teams.length === 0 || adding);
  const TITLES: Record<NewStep, string> = { team: teams.length === 0 ? "先拿一个 Slack 配置 token" : adding ? "添加 Slack 配置 token" : "选 Slack 工作区", app: "配置 app", install: "安装", manual: "连接 Slack", bind: "绑定模型" };
  const order: NewStep[] = step === "manual" || (step === "bind" && !madeId) ? ["manual", "bind"] : ["team", "app", "install", "bind"];
  const footer = step === "team" ? (
    <>
      {adding && teams.length > 0
        ? <Button variant="ghost" onClick={() => setAdding(false)}>返回</Button>
        : <Button variant="ghost" onClick={close}>取消</Button>}
      {!gettingToken && <Button variant="primary" disabled={!chosen} onClick={() => setStep("app")}>下一步</Button>}
    </>
  ) : step === "app" ? (
    <>
      <Button variant="ghost" onClick={() => setStep("team")}>上一步</Button>
      <Button variant="primary" disabled={!app.name.trim()} busy={makeApp.busy} onClick={() => void makeApp.run()}>创建 app</Button>
    </>
  ) : step === "install" || step === "manual" ? (
    <>
      <Button variant="ghost" onClick={step === "manual" ? () => setStep("team") : close}>{step === "manual" ? "上一步" : "取消"}</Button>
      <Button variant="primary" disabled={!check.ready} busy={check.busy} onClick={() => check.then(() => setStep("bind"))}>下一步</Button>
    </>
  ) : (
    <>
      <Button variant="ghost" onClick={() => setStep(madeId ? "install" : "manual")}>上一步</Button>
      <Button variant="primary" disabled={models.length === 0} busy={create.busy} onClick={() => void create.run()}>添加并连接</Button>
    </>
  );

  return (
    <Dialog open={open} onClose={close} wide title={<>{TITLES[step]}<span className={css.dialogStep}>{order.indexOf(step) + 1} / {order.length}</span></>} footer={footer}
      description={step === "team" && !gettingToken ? "用哪个 Slack 工作区的配置 token 建 app。" : undefined}>
      {gettingToken && (
        <div className={css.tokenStart}>
          <p className={shellCss.muted}>有了它，still.fail 替你在 Slack 建好 app：名字、头像、权限都在这里填，不用去 Slack 后台一项项配。它只归你用，这台 station 上的其他人看不到。</p>
          <ConfigTokenForm onSaved={(id) => { setTeam(id); setAdding(false); setStep("app"); }} />
          {teams.length === 0 && <p className={`${shellCss.muted} ${css.tokenManual}`}>不想用配置 token？<button type="button" className={chatCss.textButton} onClick={() => setStep("manual")}>自己在 Slack 建 app，再粘贴 token</button></p>}
        </div>
      )}
      {step === "team" && !gettingToken && (
        <>
          <Choices label="Slack 工作区" value={chosen?.teamId ?? ""} onChange={setTeam}
            options={teams.map((t) => ({ value: t.teamId, title: t.name, icon: <SlackTeamIcon team={t} />, description: <TokenOwner team={t} /> }))} />
          <div className={css.teamMore}>
            <Button variant="ghost" onClick={() => setAdding(true)}><Plus {...ICON} />添加工作区的配置 token</Button>
            <button type="button" className={`${chatCss.textButton} ${css.tokenManual}`} onClick={() => setStep("manual")}>不用配置 token，自己建 app</button>
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
          {iconError && <p className={controlsCss.fieldError} role="alert">图标没传上：{iconError}</p>}
          <TokenFields value={tokens} onChange={setTokens} install={made.state ?? undefined} check={check} />
        </>
      )}
      {step === "manual" && (
        <>
          <CreateAppSteps name="ember" />
          <TokenFields value={tokens} onChange={setTokens} check={check} />
        </>
      )}
      {step === "bind" && (
        <>
          <Field label="模型" hint={entry && entry.runtimes.length > 1 ? "这个模型两个运行时都能跑；运行时创建后不能换。" : undefined}>
            {models.length === 0
              ? <Link className={`${controlsCss.input} ${css.inputLink}`} to={profilesPage(station)}>Profile 还没有启用模型 · 去勾选</Link>
              : <ModelTriple title="用哪个模型、运行时、思考深度和账号" options={models}
                  value={{ model: entry?.model ?? "", runtime, effort: effort || null, profile }}
                  onPick={(p) => { setModel(p.model); setPicked(p.runtime); setEffort(p.effort ?? ""); setProfile(p.profile); }} />}
          </Field>
          <Field label="会话方式">
            <ModeChoices mode={mode.mode} requireMention={mode.requireMention} onChange={setMode} />
          </Field>
          {create.error && <p className={controlsCss.fieldError} role="alert">{create.error.message}</p>}
        </>
      )}
    </Dialog>
  );
}

/**
 * What is left in Slack once ember made the app: installing it, and the app-level token. Installed through Slack's
 * OAuth (`made.install`), Slack sends the bot token back to the station itself; else it is copied from the OAuth page.
 */
function MadeAppSteps({ made }: { made: MadeSlackApp }) {
  const { links } = made;
  return (
    <ol className={controlsCss.steps}>
      {made.install ? (
        <li>
          {made.installed
            ? <span className={controlsCss.verifyOk}><CheckCircle {...ICON} />已装进「{made.installedTeam ?? made.team ?? "工作区"}」</span>
            : <span>app 已经建好。把它安装到工作区：在 Slack 里点「允许」，bot token 会自动交给 station。</span>}
          {!made.installed && <a className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} href={made.install} target="_blank" rel="noopener"><External {...ICON} />安装到工作区</a>}
        </li>
      ) : (
        <li>
          <span>app 已经建好。把它安装到工作区，然后在 OAuth 页复制 Bot User OAuth Token（xoxb- 开头）。</span>
          <span className={css.stepActions}>
            <a className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} href={links.install} target="_blank" rel="noopener"><External {...ICON} />安装到工作区</a>
            <a className={`${controlsCss.btn} btn-secondary`} href={links.oauth} target="_blank" rel="noopener">打开 OAuth 页</a>
          </span>
        </li>
      )}
      <li>
        <span>在 Socket Mode 页生成 App-Level Token 并复制（xapp- 开头，权限已经选好）。</span>
        <a className={`${controlsCss.btn} btn-secondary`} href={links.appToken} target="_blank" rel="noopener"><External {...ICON} />打开 Socket Mode</a>
      </li>
      <li>{made.install ? "把 App-Level Token 填在下面。" : "把两个 token 填在下面。"}</li>
    </ol>
  );
}

/** Hands a connect to another person: a workspace member in ember cloud, any email on the station's own page. */
function OwnerDialog({ connect, onClose }: { connect: Connect; onClose(): void }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const people = [...useContext(PeopleContext).values()];
  const [owner, setOwner] = useState(connect.createdBy?.id ?? people[0]?.email ?? "");
  const chosen = people.find((p) => p.email.toLowerCase() === owner.toLowerCase());
  return (
    <Dialog open onClose={onClose} title="更改所属用户" description="连接属于谁，决定它出现在谁的「我创建的」里。只有 owner、管理员和当前所属用户能改。"
      footer={<>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" disabled={!owner.trim() || owner === connect.createdBy?.id} busy={save.busy}
          onClick={() => save.put({ owner: { id: owner.trim(), name: chosen?.name ?? owner.trim() } }, () => { toast("已更改所属用户"); onClose(); })}>保存</Button>
      </>}>
      {people.length > 0 ? (
        <Field label="所属用户">
          <Select value={owner} onChange={setOwner} label="所属用户" options={people.map((p) => ({ value: p.email, label: p.name ? `${p.name}（${p.email}）` : p.email }))} />
        </Field>
      ) : (
        <Field label="所属用户的邮箱" htmlFor="owner-email">
          <input id="owner-email" className={controlsCss.input} type="email" value={owner} onChange={(e) => setOwner(e.target.value)} placeholder="name@example.com" />
        </Field>
      )}
      {save.error && <p className={controlsCss.fieldError} role="alert">{save.error.message}</p>}
    </Dialog>
  );
}
