// A connect: where people reach ember (a Slack app today), the model it is
// bound to, and how its conversations become sessions.
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { MessageCircle, Pencil, Power, RefreshCw, Send, Slack, Trash2 } from "lucide-react";
import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { api, keys, useOverview, useSessions, type ConnectInput, type ConnectMode, type ConnectView, type Overview, type ProfileView, type RuntimeKind } from "../api.ts";
import { cleanText, connectionText, MODE, modeText, presence, relativeTime, RUNTIME_LABEL, sessionStatus, slug, STATUS_LABEL, statusTone } from "../format.ts";
import { CreateAppSteps, emptyTokens, TokenFields, type TokenState } from "../slack.tsx";
import { useToast } from "../toast.tsx";
import {
  Avatar, Button, Choices, Confirm, Dialog, Empty, Field, ICON, IconButton, Menu, MobileBack, Pill, Section, Segmented, Select, StatusDot, SwitchRow,
} from "../ui.tsx";

export function ConnectPage() {
  const { id } = useParams();
  const overview = useOverview();
  const connect = overview.data?.connects.find((c) => c.id === id);
  if (!overview.data) return null;
  if (!connect) return <Empty><p>没有 ID 为 {id} 的连接。</p></Empty>;
  return <ConnectDetail key={connect.id} connect={connect} overview={overview.data} />;
}

function useSaveConnect(id: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: ConnectInput) => api.putConnect(id, input),
    onSuccess: (data: Overview) => client.setQueryData(keys.overview, data),
  });
}

export function connectSubtitle(c: ConnectView, profiles: ProfileView[]): string {
  const account = profiles.find((p) => p.id === c.bind.profiles[0]);
  return [RUNTIME_LABEL[c.bind.runtime], c.bind.model ?? account?.model ?? "默认模型"].join(" · ");
}

function ConnectDetail({ connect, overview }: { connect: ConnectView; overview: Overview }) {
  const navigate = useNavigate();
  const toast = useToast();
  const client = useQueryClient();
  const save = useSaveConnect(connect.id);
  const [editingName, setEditingName] = useState(false);
  const [name, setName] = useState(connect.name);
  const [deleting, setDeleting] = useState(false);
  const remove = useMutation({
    mutationFn: () => api.deleteConnect(connect.id),
    onSuccess: (data) => { client.setQueryData(keys.overview, data); toast("已删除连接"); navigate("/sessions"); },
  });
  const rename = () => {
    setEditingName(false);
    if (name.trim() && name.trim() !== connect.name) save.mutate({ name: name.trim() }, { onSuccess: () => toast("已改名") });
  };

  return (
    <div className="page page-narrow">
      <MobileBack to="/sessions" label="返回" />
      <header className="identity">
        <Avatar id={connect.id} name={connect.name} size={52} />
        <div className="identity-text">
          {editingName ? (
            <input className="input identity-name-input" value={name} autoFocus aria-label="名称"
              onChange={(e) => setName(e.target.value)} onBlur={rename}
              onKeyDown={(e) => { if (e.key === "Enter") rename(); if (e.key === "Escape") { setName(connect.name); setEditingName(false); } }} />
          ) : (
            <h1 className="identity-name">{connect.name}<IconButton label="改名" icon={Pencil} onClick={() => setEditingName(true)} /></h1>
          )}
          <p className="identity-sub">
            <span className="kind-tag"><SlackGlyph />Slack</span>
            <span>{modeText(connect.mode, connect.requireMention)}</span>
            <span>{connectSubtitle(connect, overview.profiles)}</span>
          </p>
        </div>
        <Menu items={[
          connect.enabled
            ? { label: "停用", icon: Power, onSelect: () => save.mutate({ enabled: false }, { onSuccess: () => toast("已停用，Slack 连接已断开") }) }
            : { label: "启用", icon: Power, onSelect: () => save.mutate({ enabled: true }, { onSuccess: () => toast("已启用") }) },
          "separator",
          { label: "删除连接", icon: Trash2, danger: true, onSelect: () => setDeleting(true) },
        ]} />
      </header>
      {save.error && <p className="field-error page-error" role="alert">{save.error.message}</p>}

      <SlackSection connect={connect} />
      <ModeSection connect={connect} />
      <BindSection connect={connect} overview={overview} />
      <ConnectSessions connect={connect} />

      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.isPending} onConfirm={() => remove.mutate()}
        title={`删除「${connect.name}」？`} action="删除连接"
        description={`Slack 连接会断开${connect.sessions ? `；它的 ${connect.sessions} 个会话的记录会保留，但不再接收消息` : ""}。Slack 里的 app 需要你自己去删除。`} />
    </div>
  );
}

export function SlackGlyph() {
  return <Slack {...ICON} size={13} />;
}

function SlackSection({ connect }: { connect: ConnectView }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const [replacing, setReplacing] = useState(false);
  const [tokens, setTokens] = useState<TokenState>(emptyTokens);
  const reconnect = useMutation({ mutationFn: () => api.reconnect(connect.id), onSuccess: () => toast("已重新连接") });
  const saveTokens = () => save.mutate({ slack: { appToken: tokens.appToken, botToken: tokens.botToken } }, {
    onSuccess: () => { setReplacing(false); setTokens(emptyTokens); toast("已保存 token，正在重新连接"); },
  });
  const c = connect.connection;
  const workspace = c.state === "connected" || c.state === "reconnecting" ? c.workspace : null;
  const close = () => { setReplacing(false); setTokens(emptyTokens); };

  if (c.state === "no_tokens") {
    return (
      <Section title="Slack" description="这个连接还没接上 Slack。">
        <div className="card">
          <CreateAppSteps name={connect.name} />
          <TokenFields value={tokens} onChange={setTokens} />
          <div className="card-actions">
            <Button variant="primary" disabled={!tokens.verified} busy={save.isPending} onClick={saveTokens}>保存并连接</Button>
          </div>
        </div>
      </Section>
    );
  }
  return (
    <Section title="Slack" actions={<>
      <Button icon={RefreshCw} onClick={() => reconnect.mutate()} busy={reconnect.isPending} disabled={!connect.enabled}>重新连接</Button>
      <Button onClick={() => setReplacing(true)}>更换 token</Button>
    </>}>
      <div className="card card-row">
        <StatusDot state={presence(c)} />
        <div className="card-row-text">
          <strong>{connectionText(c)}{workspace ? ` · ${workspace.team}` : ""}</strong>
          <span className="muted">
            {workspace ? `在 Slack 里是 @${workspace.botName}` : c.state === "error" ? c.error : c.state === "disabled" ? "停用后不接收新消息，已有会话保留。" : ""}
            {c.state === "reconnecting" && c.lastError ? `（${c.lastError}）` : ""}
          </span>
        </div>
        {workspace?.url && <a className="btn btn-ghost" href={workspace.url} target="_blank" rel="noopener">打开 Slack</a>}
      </div>
      <Dialog open={replacing} onClose={close} title="更换 Slack token" description="只换其中一个也可以，另一个留空会沿用已保存的。保存前先验证。"
        footer={<>
          <Button variant="ghost" onClick={close}>取消</Button>
          <Button variant="primary" disabled={!tokens.verified} busy={save.isPending} onClick={saveTokens}>保存并重新连接</Button>
        </>}>
        <TokenFields value={tokens} onChange={setTokens} connect={connect.id} masked={connect.slack} />
        {save.error && <p className="field-error" role="alert">{save.error.message}</p>}
      </Dialog>
    </Section>
  );
}

/** The mode picker, shared by the connect page and the new-connect dialog. */
export function ModeChoices({ mode, requireMention, onChange, disabled }:
  { mode: ConnectMode; requireMention: boolean; onChange(next: { mode: ConnectMode; requireMention: boolean }): void; disabled?: boolean }) {
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

function ModeSection({ connect }: { connect: ConnectView }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  return (
    <Section title="会话方式" description="改动只影响之后的新消息；已有的会话保留原样。无论哪种方式，agent 都能看到每条消息来自哪个 thread，并回到那个 thread。">
      <ModeChoices mode={connect.mode} requireMention={connect.requireMention} disabled={save.isPending}
        onChange={(next) => save.mutate(next, { onSuccess: () => toast("已保存会话方式") })} />
    </Section>
  );
}

/** Model choice: the account's model list when it has been checked, free text otherwise. */
export function ModelPicker({ id, account, value, onChange }: { id: string; account: ProfileView | undefined; value: string; onChange(value: string): void }) {
  const models = account?.check?.models ?? [];
  const fallback = account?.model ? `账号默认（${account.model}）` : "运行时默认";
  if (models.length === 0) {
    return <input id={id} className="input mono" spellCheck={false} value={value} onChange={(e) => onChange(e.target.value)} placeholder={fallback} />;
  }
  const options = [{ value: "", label: fallback }, ...[...new Set([...(value ? [value] : []), ...models])].map((m) => ({ value: m, label: m }))];
  return <Select id={id} value={value} onChange={onChange} options={options} label="模型" />;
}

function BindSection({ connect, overview }: { connect: ConnectView; overview: Overview }) {
  const toast = useToast();
  const save = useSaveConnect(connect.id);
  const accounts = overview.profiles.filter((p) => p.runtime === connect.bind.runtime);
  const [account, setAccount] = useState(connect.bind.profiles[0] ?? "");
  const [model, setModel] = useState(connect.bind.model ?? "");
  const chosen = accounts.find((p) => p.id === account);
  const dirty = account !== (connect.bind.profiles[0] ?? "") || model.trim() !== (connect.bind.model ?? "");
  const reset = () => { setAccount(connect.bind.profiles[0] ?? ""); setModel(connect.bind.model ?? ""); };
  return (
    <Section title="模型" description="新会话用这里的设置；进行中的会话继续用开始时的账号和模型。">
      <div className="card">
        <div className="field-grid">
          <Field label="运行时">
            <p className="static-value">{RUNTIME_LABEL[connect.bind.runtime]}</p>
          </Field>
          <Field label="运行时账号" htmlFor="bind-account">
            <Select id="bind-account" value={account} onChange={(v) => { setAccount(v); setModel(""); }}
              options={accounts.map((p) => ({ value: p.id, label: p.name }))} />
          </Field>
        </div>
        <Field label="模型" htmlFor="bind-model" hint={chosen?.check?.models?.length ? `这个账号有 ${chosen.check.models.length} 个可用模型。` : "账号检查过后这里会列出可用模型。"}>
          <ModelPicker id="bind-model" account={chosen} value={model} onChange={setModel} />
        </Field>
        {dirty && (
          <div className="card-actions">
            <Button variant="ghost" onClick={reset}>还原</Button>
            <Button variant="primary" busy={save.isPending} onClick={() => save.mutate(
              { bind: { profiles: [account, ...connect.bind.profiles.filter((p) => p !== account)], model: model.trim() } },
              { onSuccess: () => toast("已保存，新会话会用新的模型") },
            )}>保存</Button>
          </div>
        )}
        <p className="card-foot muted">运行时在创建后不能换；要用另一种运行时，新建一个连接。</p>
      </div>
    </Section>
  );
}

function ConnectSessions({ connect }: { connect: ConnectView }) {
  const sessions = (useSessions().data ?? []).filter((s) => s.connect === connect.id).sort((a, b) => b.lastActiveAt - a.lastActiveAt).slice(0, 12);
  return (
    <Section title="最近的会话">
      {sessions.length === 0 ? <p className="muted">还没有会话。在 Slack 里 @{connect.name} 就会开始。</p> : (
        <ul className="list">
          {sessions.map((s) => {
            const status = sessionStatus(s);
            return (
              <li key={s.key}>
                <Link className="list-row" to={`/sessions/${encodeURIComponent(s.key)}`}>
                  <span className="list-row-title">{s.scope === "all" ? `${connect.name} 的会话` : cleanText(s.firstText) || "（没有消息）"}</span>
                  <Pill tone={statusTone(status)}>{STATUS_LABEL[status]}</Pill>
                  <span className="muted list-row-time">{relativeTime(s.lastActiveAt)}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </Section>
  );
}

const KINDS = [
  { value: "slack", title: "Slack", description: "一个 Slack app，用 Socket Mode 连接，不需要公网地址。", icon: <span className="mark"><Slack {...ICON} size={16} /></span> },
  { value: "wechat", title: "微信", description: "即将支持。", disabled: true, icon: <span className="mark"><MessageCircle {...ICON} size={16} /></span> },
  { value: "telegram", title: "Telegram", description: "即将支持。", disabled: true, icon: <span className="mark"><Send {...ICON} size={16} /></span> },
];

export function NewConnectDialog({ open, onClose }: { open: boolean; onClose(): void }) {
  const overview = useOverview();
  const client = useQueryClient();
  const navigate = useNavigate();
  const toast = useToast();
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [name, setName] = useState("");
  const [id, setId] = useState("");
  const [idTouched, setIdTouched] = useState(false);
  const [runtime, setRuntime] = useState<RuntimeKind>("claude");
  const [account, setAccount] = useState("");
  const [model, setModel] = useState("");
  const [mode, setMode] = useState<{ mode: ConnectMode; requireMention: boolean }>({ mode: "multi-session", requireMention: true });
  const [tokens, setTokens] = useState<TokenState>(emptyTokens);

  const accounts = (overview.data?.profiles ?? []).filter((p) => p.runtime === runtime);
  const chosen = accounts.find((p) => p.id === account) ?? accounts[0];
  const connectId = idTouched ? id : slug(name);
  const taken = overview.data?.connects.some((c) => c.id === connectId) ?? false;
  const idValid = /^[a-z0-9][a-z0-9-]*$/.test(connectId) && !taken;

  const close = () => {
    setStep(1); setName(""); setId(""); setIdTouched(false); setAccount(""); setModel(""); setTokens(emptyTokens);
    setMode({ mode: "multi-session", requireMention: true });
    onClose();
  };
  const create = useMutation({
    mutationFn: (withTokens: boolean) => api.putConnect(connectId, {
      name: name.trim(), kind: "slack", ...mode,
      bind: { runtime, profiles: chosen ? [chosen.id] : [], model: model.trim() },
      ...(withTokens ? { slack: { appToken: tokens.appToken, botToken: tokens.botToken } } : {}),
    }),
    onSuccess: (data, withTokens) => {
      client.setQueryData(keys.overview, data);
      toast(withTokens ? "已添加连接，正在连接 Slack" : "已添加连接");
      close();
      navigate(`/connects/${connectId}`);
    },
  });

  const titles = { 1: "添加连接", 2: "绑定模型", 3: "连接 Slack" } as const;
  const footer = step === 1 ? (
    <>
      <Button variant="ghost" onClick={close}>取消</Button>
      <Button variant="primary" disabled={!name.trim() || !idValid} onClick={() => setStep(2)}>下一步</Button>
    </>
  ) : step === 2 ? (
    <>
      <Button variant="ghost" onClick={() => setStep(1)}>上一步</Button>
      <Button variant="primary" disabled={!chosen} onClick={() => setStep(3)}>下一步</Button>
    </>
  ) : (
    <>
      <Button variant="ghost" onClick={() => setStep(2)}>上一步</Button>
      <Button onClick={() => create.mutate(false)} busy={create.isPending && create.variables === false}>稍后连接</Button>
      <Button variant="primary" disabled={!tokens.verified} busy={create.isPending && create.variables === true} onClick={() => create.mutate(true)}>添加并连接</Button>
    </>
  );

  return (
    <Dialog open={open} onClose={close} wide title={<>{titles[step]}<span className="dialog-step">{step} / 3</span></>} footer={footer}
      description={step === 1 ? "连接是人找到 ember 的地方。每个连接绑定一个模型，在哪个连接说话就由哪个模型来做。" : undefined}>
      {step === 1 && (
        <>
          <Field label="连接到">
            <Choices label="连接到" value="slack" onChange={() => {}} options={KINDS} />
          </Field>
          <div className="field-grid">
            <Field label="名称" htmlFor="new-connect-name" hint="Slack 里显示的名字，也是 agent 对自己的称呼。">
              <input id="new-connect-name" className="input" value={name} autoFocus onChange={(e) => setName(e.target.value)} placeholder="例如 ember-claude" />
            </Field>
            <Field label="ID" htmlFor="new-connect-id" error={taken ? "这个 ID 已经被别的连接用了" : undefined} hint="会话记录用它区分连接，创建后不能改。">
              <input id="new-connect-id" className="input mono" spellCheck={false} value={connectId} onChange={(e) => { setIdTouched(true); setId(e.target.value); }} />
            </Field>
          </div>
        </>
      )}
      {step === 2 && (
        <>
          <Field label="运行时">
            <Segmented label="运行时" value={runtime} onChange={(r) => { setRuntime(r); setAccount(""); setModel(""); }}
              options={[{ value: "claude", label: "Claude Code" }, { value: "codex", label: "Codex" }]} />
          </Field>
          <div className="field-grid">
            <Field label="运行时账号" htmlFor="new-connect-account"
              error={accounts.length === 0 ? `还没有 ${RUNTIME_LABEL[runtime]} 账号，先到「设置 → 运行时账号」添加。` : undefined}>
              <Select id="new-connect-account" value={chosen?.id ?? ""} onChange={(v) => { setAccount(v); setModel(""); }} disabled={accounts.length === 0}
                options={accounts.map((p) => ({ value: p.id, label: p.name }))} placeholder="没有可用账号" />
            </Field>
            <Field label="模型" htmlFor="new-connect-model">
              <ModelPicker id="new-connect-model" account={chosen} value={model} onChange={setModel} />
            </Field>
          </div>
          <Field label="会话方式">
            <ModeChoices mode={mode.mode} requireMention={mode.requireMention} onChange={setMode} />
          </Field>
        </>
      )}
      {step === 3 && (
        <>
          <CreateAppSteps name={name} />
          <TokenFields value={tokens} onChange={setTokens} />
          {create.error && <p className="field-error" role="alert">{create.error.message}</p>}
        </>
      )}
    </Dialog>
  );
}
