import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Pencil, RefreshCw } from "lucide-react";
import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { api, keys, useOverview, useSessions, type BotView, type Overview } from "../api.ts";
import { cleanText, connectionText, presence, relativeTime, RUNTIME_LABEL, sessionStatus, STATUS_LABEL } from "../format.ts";
import { CreateAppSteps, emptyTokens, TokenFields, type TokenState } from "../slack.tsx";
import { useToast } from "../toast.tsx";
import { Avatar, Button, Dialog, Empty, Field, IconButton, Menu, Pill, StatusDot } from "../ui.tsx";

export function BotPage() {
  const { id } = useParams();
  const overview = useOverview();
  const bot = overview.data?.bots.find((b) => b.id === id);
  if (!overview.data) return null;
  if (!bot) return <Empty><p>没有 ID 为 {id} 的 bot。</p></Empty>;
  return <BotView key={bot.id} bot={bot} overview={overview.data} />;
}

function useSave() {
  const client = useQueryClient();
  return (data: Overview) => client.setQueryData(keys.overview, data);
}

function BotView({ bot, overview }: { bot: BotView; overview: Overview }) {
  const navigate = useNavigate();
  const toast = useToast();
  const apply = useSave();
  const account = overview.profiles.find((p) => p.id === bot.profiles[0]);
  const [editingName, setEditingName] = useState(false);
  const [name, setName] = useState(bot.name);

  const save = useMutation({
    mutationFn: (input: Parameters<typeof api.putBot>[1]) => api.putBot(bot.id, input),
    onSuccess: (data) => apply(data),
  });
  const remove = useMutation({
    mutationFn: () => api.deleteBot(bot.id),
    onSuccess: (data) => { apply(data); toast("已删除 bot"); navigate("/sessions"); },
  });
  const rename = () => {
    setEditingName(false);
    if (name.trim() && name.trim() !== bot.name) save.mutate({ name: name.trim() }, { onSuccess: () => toast("已改名") });
  };

  return (
    <div className="page page-narrow">
      <header className="identity">
        <Avatar id={bot.id} name={bot.name} size={48} />
        <div className="identity-text">
          {editingName ? (
            <input className="input identity-name-input" value={name} autoFocus aria-label="名称"
              onChange={(e) => setName(e.target.value)} onBlur={rename}
              onKeyDown={(e) => { if (e.key === "Enter") rename(); if (e.key === "Escape") { setName(bot.name); setEditingName(false); } }} />
          ) : (
            <h1 className="identity-name">{bot.name}<IconButton label="改名" icon={Pencil} onClick={() => setEditingName(true)} /></h1>
          )}
          <p className="identity-sub">
            {RUNTIME_LABEL[bot.runtime]}{bot.model ? ` · ${bot.model}` : ""}{account ? ` · ${account.name}` : ""} · <span className="mono">{bot.id}</span>
          </p>
        </div>
        <Menu items={[
          bot.enabled
            ? { label: "停用", onSelect: () => save.mutate({ enabled: false }, { onSuccess: () => toast("已停用，Slack 连接已断开") }) }
            : { label: "启用", onSelect: () => save.mutate({ enabled: true }, { onSuccess: () => toast("已启用") }) },
          { label: "删除 bot", danger: true, onSelect: () => {
            const kept = bot.sessions ? `它的 ${bot.sessions} 个会话会保留，但不再有人接管。` : "";
            if (window.confirm(`删除「${bot.name}」？${kept}`)) remove.mutate();
          } },
        ]} />
      </header>
      {save.error && <p className="field-error" role="alert">{save.error.message}</p>}

      <SlackSection bot={bot} />
      <RunSection bot={bot} overview={overview} />
      <BotSessions bot={bot} />
    </div>
  );
}

function SlackSection({ bot }: { bot: BotView }) {
  const toast = useToast();
  const client = useQueryClient();
  const [replacing, setReplacing] = useState(false);
  const [tokens, setTokens] = useState<TokenState>(emptyTokens);
  const reconnect = useMutation({ mutationFn: () => api.reconnect(bot.id), onSuccess: () => toast("已重新连接") });
  const save = useMutation({
    mutationFn: () => api.putBot(bot.id, { slack: { appToken: tokens.appToken, botToken: tokens.botToken } }),
    onSuccess: (data) => {
      client.setQueryData(keys.overview, data);
      setReplacing(false);
      setTokens(emptyTokens);
      toast("已保存 token，正在重新连接");
    },
  });
  const c = bot.connection;
  const workspace = c.state === "connected" || c.state === "reconnecting" ? c.workspace : null;
  const needsSetup = c.state === "no_tokens";

  return (
    <section className="section" aria-labelledby="slack-heading">
      <div className="section-head">
        <h2 id="slack-heading">Slack</h2>
        {!needsSetup && (
          <div className="section-actions">
            <Button icon={RefreshCw} onClick={() => reconnect.mutate()} busy={reconnect.isPending} disabled={!bot.enabled}>重新连接</Button>
            <Button onClick={() => setReplacing(true)}>更换 token</Button>
          </div>
        )}
      </div>
      {needsSetup ? (
        <div className="card">
          <p className="card-lead">这个 bot 还没连上 Slack。</p>
          <CreateAppSteps name={bot.name} />
          <TokenFields value={tokens} onChange={setTokens} />
          <div className="card-actions">
            <Button variant="primary" disabled={!tokens.verified} busy={save.isPending} onClick={() => save.mutate()}>保存并连接</Button>
          </div>
        </div>
      ) : (
        <div className="card card-row">
          <StatusDot state={presence(c)} />
          <div className="card-row-text">
            <strong>{connectionText(c)}</strong>
            <span className="muted">
              {workspace ? `${workspace.team} 工作区 · @${workspace.botName}` : c.state === "error" ? c.error : c.state === "disabled" ? "停用后不接收新消息，已有会话保留。" : ""}
              {c.state === "reconnecting" && c.lastError ? `（${c.lastError}）` : ""}
            </span>
          </div>
          {workspace?.url && <a className="btn btn-ghost" href={workspace.url} target="_blank" rel="noopener">打开 Slack</a>}
        </div>
      )}
      <Dialog open={replacing} onClose={() => { setReplacing(false); setTokens(emptyTokens); }} title="更换 Slack token"
        footer={<>
          <Button variant="ghost" onClick={() => { setReplacing(false); setTokens(emptyTokens); }}>取消</Button>
          <Button variant="primary" disabled={!tokens.verified} busy={save.isPending} onClick={() => save.mutate()}>保存并重新连接</Button>
        </>}>
        <p className="dialog-lead">只换其中一个也可以，另一个留空会沿用已保存的。保存前先验证。</p>
        <TokenFields value={tokens} onChange={setTokens} bot={bot.id} masked={bot.slack} />
        {save.error && <p className="field-error" role="alert">{save.error.message}</p>}
      </Dialog>
    </section>
  );
}

function RunSection({ bot, overview }: { bot: BotView; overview: Overview }) {
  const toast = useToast();
  const client = useQueryClient();
  const accounts = overview.profiles.filter((p) => p.runtime === bot.runtime);
  const [account, setAccount] = useState(bot.profiles[0] ?? "");
  const [model, setModel] = useState(bot.model ?? "");
  const chosen = accounts.find((p) => p.id === account);
  const models = chosen?.check?.models ?? [];
  const dirty = account !== (bot.profiles[0] ?? "") || model.trim() !== (bot.model ?? "");
  const save = useMutation({
    mutationFn: () => api.putBot(bot.id, { profiles: [account, ...bot.profiles.filter((p) => p !== account)], model: model.trim() }),
    onSuccess: (data) => { client.setQueryData(keys.overview, data); toast("已保存，新会话会用新的设置"); },
  });
  return (
    <section className="section" aria-labelledby="run-heading">
      <div className="section-head"><h2 id="run-heading">运行</h2></div>
      <div className="card">
        <Field label="运行时">
          <p className="static-value">{RUNTIME_LABEL[bot.runtime]}<span className="muted">　运行时在创建后不能换；需要另一种就新建一个 bot。</span></p>
        </Field>
        <Field label="运行时账号" htmlFor="bot-account">
          <select id="bot-account" className="select" value={account} onChange={(e) => setAccount(e.target.value)}>
            {accounts.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </Field>
        <Field label="模型" htmlFor="bot-model" hint={models.length ? `这个账号有 ${models.length} 个可用模型。` : "留空用账号的默认模型。"}>
          <input id="bot-model" className="input mono" list="bot-models" value={model} onChange={(e) => setModel(e.target.value)} placeholder={chosen?.model ?? "默认"} />
          <datalist id="bot-models">{models.map((m) => <option key={m} value={m} />)}</datalist>
        </Field>
        {dirty && (
          <div className="card-actions">
            <Button variant="ghost" onClick={() => { setAccount(bot.profiles[0] ?? ""); setModel(bot.model ?? ""); }}>还原</Button>
            <Button variant="primary" busy={save.isPending} onClick={() => save.mutate()}>保存</Button>
          </div>
        )}
        {save.error && <p className="field-error" role="alert">{save.error.message}</p>}
      </div>
    </section>
  );
}

function BotSessions({ bot }: { bot: BotView }) {
  const sessions = (useSessions().data ?? []).filter((s) => s.bot === bot.id).sort((a, b) => b.lastActiveAt - a.lastActiveAt).slice(0, 12);
  return (
    <section className="section" aria-labelledby="sessions-heading">
      <div className="section-head"><h2 id="sessions-heading">最近的会话</h2></div>
      {sessions.length === 0 ? <p className="muted">还没有会话。在 Slack 里 @{bot.name} 就会开始一个。</p> : (
        <ul className="list">
          {sessions.map((s) => {
            const status = sessionStatus(s);
            return (
              <li key={s.key}>
                <Link className="list-row" to={`/sessions/${encodeURIComponent(s.key)}`}>
                  <span className="list-row-title">{cleanText(s.firstText) || "（没有消息）"}</span>
                  <Pill tone={status === "running" || status === "queued" ? "accent" : status === "final" ? "green" : status === "block" ? "blue" : status === "failed" || status === "unexpected" ? "red" : "neutral"}>{STATUS_LABEL[status]}</Pill>
                  <span className="muted">{relativeTime(s.lastActiveAt)}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
