import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { api, keys, useOverview, type BotView, type Overview, type RuntimeKind } from "../api.ts";
import { connectionText, RUNTIME_LABEL } from "../format.ts";
import { useToast } from "../toast.tsx";

export function BotsPage() {
  const { id } = useParams();
  const overview = useOverview();
  const bots = overview.data?.bots ?? [];
  const editing = id === "new" ? null : bots.find((b) => b.id === id);
  return (
    <div className="settings" data-detail={Boolean(id)}>
      <section className="list-pane" aria-label="Bot 列表">
        <div className="page-head">
          <h1>Bot</h1>
          <Link className="button button-primary" to="/bots/new">新建 Bot</Link>
        </div>
        {bots.length === 0 && <div className="empty"><p>还没有 bot。新建一个，把它连到一个 Slack app 上。</p></div>}
        {bots.map((b) => (
          <Link key={b.id} className="row" to={`/bots/${b.id}`} aria-current={b.id === id}>
            <div className="row-title"><span className="dot" data-state={b.connection.state} />{b.name}</div>
            <div className="row-sub">{RUNTIME_LABEL[b.runtime]}{b.model ? `，${b.model}` : ""}；{connectionText(b.connection)}；{b.sessions} 个会话</div>
          </Link>
        ))}
      </section>
      <section className="detail-pane" aria-label="编辑 Bot">
        {id === "new" && <BotForm key="new" bot={null} overview={overview.data} />}
        {editing && <BotForm key={editing.id} bot={editing} overview={overview.data} />}
        {id && id !== "new" && !editing && overview.isSuccess && <div className="empty"><p>没有 id 为 {id} 的 bot。</p></div>}
        {!id && <div className="empty"><p>选一个 bot 编辑，或者新建一个。</p></div>}
      </section>
    </div>
  );
}

function BotForm({ bot, overview }: { bot: BotView | null; overview: Overview | undefined }) {
  const navigate = useNavigate();
  const client = useQueryClient();
  const toast = useToast();
  const [id, setId] = useState(bot?.id ?? "");
  const [name, setName] = useState(bot?.name ?? "");
  const [runtime, setRuntime] = useState<RuntimeKind>(bot?.runtime ?? "claude");
  const [profiles, setProfiles] = useState<string[]>(bot?.profiles ?? []);
  const [model, setModel] = useState(bot?.model ?? "");
  const [enabled, setEnabled] = useState(bot?.enabled ?? true);
  const [appToken, setAppToken] = useState("");
  const [botToken, setBotToken] = useState("");
  const candidates = (overview?.profiles ?? []).filter((p) => p.runtime === runtime);

  const save = useMutation({
    mutationFn: () => api.putBot(id.trim(), {
      name: name.trim(), runtime, profiles, model: model.trim(), enabled, slack: { appToken, botToken },
    }),
    onSuccess: (data) => {
      client.setQueryData(keys.overview, data);
      setAppToken("");
      setBotToken("");
      toast(bot ? "已保存" : "已创建 bot");
      if (!bot) navigate(`/bots/${id.trim()}`);
    },
  });
  const remove = useMutation({
    mutationFn: () => api.deleteBot(bot!.id),
    onSuccess: (data) => {
      client.setQueryData(keys.overview, data);
      toast("已删除 bot");
      navigate("/bots");
    },
  });
  const reconnect = useMutation({ mutationFn: () => api.reconnect(bot!.id), onSuccess: () => toast("已重新连接") });
  const openSlack = useMutation({
    mutationFn: () => api.createAppUrl(name.trim() || id.trim() || "ember"),
    onSuccess: ({ url }) => window.open(url, "_blank", "noopener"),
  });

  const submit = (event: FormEvent) => {
    event.preventDefault();
    save.mutate();
  };
  const confirmDelete = () => {
    const warning = bot!.sessions > 0 ? `它的 ${bot!.sessions} 个会话会保留，但不再有人接管。` : "";
    if (window.confirm(`删除 bot「${bot!.name}」？${warning}`)) remove.mutate();
  };
  const idValid = /^[a-z0-9][a-z0-9-]*$/.test(id.trim());

  return (
    <form className="form" onSubmit={submit}>
      <Link className="back" to="/bots">返回 Bot 列表</Link>
      <h2>{bot ? bot.name : "新建 Bot"}</h2>
      <p className="lead">
        {bot ? connectionText(bot.connection) : "一个 bot 对应一个 Slack app，绑定一种运行时和模型。在 Slack 里 @ 哪个 bot，就用哪个模型。"}
      </p>

      {!bot && (
        <div className="callout">
          先在 Slack 里建好 app：
          <ol>
            <li>填好下面的名称，点「在 Slack 创建 app」，确认预填的配置后创建。</li>
            <li>在 app 的 Basic Information 页生成一个带 connections:write 的 App-Level Token。</li>
            <li>安装到工作区，复制 Bot User OAuth Token。</li>
            <li>把两个 token 填到下面，保存。</li>
          </ol>
        </div>
      )}

      <div className="field">
        <label htmlFor="bot-id">ID</label>
        <input id="bot-id" className="input" value={id} onChange={(e) => setId(e.target.value)} disabled={Boolean(bot)} required
          pattern="[a-z0-9][a-z0-9\-]*" placeholder="例如 claude、gpt、ds" />
        <span className="hint">{bot ? "ID 创建后不能修改，会话记录用它来区分 bot。" : "小写字母、数字和短横线。创建后不能修改。"}</span>
      </div>
      <div className="field">
        <label htmlFor="bot-name">名称</label>
        <input id="bot-name" className="input" value={name} onChange={(e) => setName(e.target.value)} placeholder="Slack 里显示的名字，也是 agent 对自己的称呼" />
      </div>
      <div className="field">
        <label htmlFor="bot-runtime">运行时</label>
        <select id="bot-runtime" className="select" value={runtime} onChange={(e) => { setRuntime(e.target.value as RuntimeKind); setProfiles([]); }}>
          <option value="claude">Claude Code</option>
          <option value="codex">Codex</option>
        </select>
      </div>
      <div className="field">
        <span className="label">账号</span>
        {candidates.length === 0 ? (
          <span className="hint">还没有 {RUNTIME_LABEL[runtime]} 账号。先到「账号」页添加一个。</span>
        ) : (
          <div className="checks">
            {candidates.map((p) => (
              <label key={p.id} className="check">
                <input type="checkbox" checked={profiles.includes(p.id)}
                  onChange={(e) => setProfiles(e.target.checked ? [...profiles, p.id] : profiles.filter((x) => x !== p.id))} />
                {p.id}
              </label>
            ))}
          </div>
        )}
        <span className="hint">新会话用勾选的第一个账号。</span>
      </div>
      <div className="field">
        <label htmlFor="bot-model">模型</label>
        <input id="bot-model" className="input" value={model} onChange={(e) => setModel(e.target.value)} placeholder="留空用账号的默认模型" />
      </div>
      <div className="field">
        <label className="check"><input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />启用</label>
        <span className="hint">停用后断开 Slack 连接，配置和会话都保留。</span>
      </div>
      <div className="field">
        <label htmlFor="bot-app-token">App-Level Token</label>
        <input id="bot-app-token" className="input" type="password" autoComplete="off" value={appToken} onChange={(e) => setAppToken(e.target.value)}
          placeholder={bot?.slack.appToken ? `已设置（${bot.slack.appToken}），留空保持不变` : "xapp-…"} />
      </div>
      <div className="field">
        <label htmlFor="bot-bot-token">Bot Token</label>
        <input id="bot-bot-token" className="input" type="password" autoComplete="off" value={botToken} onChange={(e) => setBotToken(e.target.value)}
          placeholder={bot?.slack.botToken ? `已设置（${bot.slack.botToken}），留空保持不变` : "xoxb-…"} />
      </div>

      <div className="form-actions">
        <button type="submit" className="button button-primary" disabled={save.isPending || !idValid || profiles.length === 0}>{bot ? "保存" : "创建 bot"}</button>
        <button type="button" className="button" onClick={() => openSlack.mutate()} disabled={openSlack.isPending}>在 Slack 创建 app</button>
        {bot && <button type="button" className="button" onClick={() => reconnect.mutate()} disabled={reconnect.isPending || !bot.enabled}>重新连接</button>}
        {bot && <button type="button" className="button button-danger" onClick={confirmDelete} disabled={remove.isPending}>删除</button>}
      </div>
      {[save, remove, reconnect, openSlack].map((m, i) => m.error && <p key={i} className="error" role="alert">{m.error.message}</p>)}
    </form>
  );
}
