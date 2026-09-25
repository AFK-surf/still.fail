// A connect's Slack app, edited from ember: name, description, colour, icon and
// permissions are written into the app's manifest with the workspace's app
// configuration token. When permissions change, Slack asks a person to approve
// them; that is the only step left in Slack.
import { useStation } from "../station.tsx";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ExternalLink, ImageUp, ShieldCheck } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { useApi, keys, type ConnectView, type SlackAppLinks, type SlackAppSettings, type SlackGroup } from "../api.ts";
import { useToast } from "../toast.tsx";
import { Button, Field, ICON, Section, SwitchRow } from "../ui.tsx";

/** Permission groups in plain words; mirrors SLACK_GROUPS on the server. */
const GROUPS: Record<SlackGroup, { label: string; description: string }> = {
  base: { label: "读取和回复消息", description: "被 @ 时收到消息，读取所在频道、私信和群聊的消息并回复。必须开启。" },
  public: { label: "在没加入的公开频道发言", description: "不用先邀请，也能在公开频道回复。" },
  dm: { label: "主动发私信", description: "给人或多人开启私信对话。" },
  customize: { label: "用别的名字和头像发消息", description: "每条消息可以换显示名和头像。" },
  files: { label: "读写文件", description: "读取消息里的附件，上传截图、日志等文件。" },
  reactions: { label: "表情回应、置顶和书签", description: "用表情标记进度，置顶消息，管理频道书签。" },
  channels: { label: "创建和管理频道", description: "建频道、邀请成员，知道有人加入或新建频道。" },
  people: { label: "查看成员资料", description: "读取邮箱、个人资料、用户组、工作区信息和自定义表情。" },
  extras: { label: "链接预览、提醒和状态", description: "展开链接、设置提醒、读取勿扰和通话状态。" },
};

export function SlackAppSection({ connect }: { connect: ConnectView }) {
  const api = useApi();
  const station = useStation();
  const app = useQuery({ queryKey: keys.slackApp(station.id, connect.id), queryFn: () => api.slackApp(connect.id), staleTime: 60_000 });
  const links = app.data?.links;
  return (
    <Section title="Slack app" description="在这里改 app 的名字、图标和权限，ember 会写进 Slack 的 app 配置。"
      actions={links && <a className="btn btn-ghost" href={links.settings} target="_blank" rel="noopener"><ExternalLink {...ICON} />在 Slack 打开</a>}>
      {app.isPending ? <div className="card"><p className="muted">正在读取 Slack 上的配置…</p></div>
        : app.isError ? <div className="card"><p className="field-error">{app.error.message}</p></div>
        : app.data.state === "no_app" ? <div className="card"><p className="muted">{app.data.error ? `找不到这个连接的 Slack app（${app.data.error}）。换上有效的 token 后再来。` : "连上 Slack 之后，就可以在这里修改它的 app。"}</p></div>
        : app.data.state === "no_config_token" ? <ConfigTokenCard />
        : app.data.state === "error" ? (
          <div className="card">
            <p className="field-error" role="alert">读不到 app 配置：{app.data.error}</p>
            <ConfigTokenForm replacing />
          </div>
        )
        : <AppForm key={JSON.stringify(app.data.settings)} connect={connect} settings={app.data.settings} links={app.data.links} />}
    </Section>
  );
}

function ConfigTokenCard() {
  return (
    <div className="card">
      <p className="card-lead">修改 app 需要一个 Slack 的 App 配置 token。每个工作区设置一次，所有连接共用。</p>
      <ConfigTokenForm />
    </div>
  );
}

function ConfigTokenForm({ replacing }: { replacing?: boolean }) {
  const api = useApi();
  const client = useQueryClient();
  const toast = useToast();
  const [token, setToken] = useState("");
  const save = useMutation({
    mutationFn: () => api.putConfigToken(token),
    onSuccess: () => { setToken(""); toast("已保存配置 token"); void client.invalidateQueries({ queryKey: ["slack-app"] }); },
  });
  return (
    <>
      <ol className="steps">
        <li>
          <span>打开 Slack 的 app 列表，在页面最下方「Your App Configuration Tokens」点 Generate Token，选这个工作区。</span>
          <a className="btn btn-secondary" href="https://api.slack.com/apps" target="_blank" rel="noopener"><ExternalLink {...ICON} />打开 app 列表</a>
        </li>
        <li>复制生成的 <strong>Refresh Token</strong>（以 xoxe-1- 开头）粘贴到下面。ember 会自己续期，不用再管它。</li>
      </ol>
      <Field label="Refresh Token" htmlFor="config-refresh" error={save.error?.message}>
        <div className="input-row">
          <input id="config-refresh" className="input mono" type="password" autoComplete="off" spellCheck={false} value={token}
            onChange={(e) => setToken(e.target.value.trim())} placeholder="xoxe-1-…" />
          <Button variant="primary" disabled={!token} busy={save.isPending} onClick={() => save.mutate()}>{replacing ? "换成这个" : "保存"}</Button>
        </div>
      </Field>
    </>
  );
}

/** Crops an image to a centred square and scales it to 1024 px, the size Slack wants (512–2000). */
async function toIcon(file: File): Promise<string> {
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const side = Math.min(image.naturalWidth, image.naturalHeight);
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 1024;
    canvas.getContext("2d")!.drawImage(image, (image.naturalWidth - side) / 2, (image.naturalHeight - side) / 2, side, side, 0, 0, 1024, 1024);
    return canvas.toDataURL("image/png");
  } finally {
    URL.revokeObjectURL(url);
  }
}

function AppForm({ connect, settings, links }: { connect: ConnectView; settings: SlackAppSettings; links: SlackAppLinks }) {
  const api = useApi();
  const station = useStation();
  const toast = useToast();
  const client = useQueryClient();
  const [draft, setDraft] = useState(settings);
  const [icon, setIcon] = useState<string | null>(null);
  const [iconError, setIconError] = useState<string | null>(null);
  const [approve, setApprove] = useState(false);
  const file = useRef<HTMLInputElement>(null);
  useEffect(() => setDraft(settings), [settings]);

  const changed = (Object.keys(settings) as (keyof SlackAppSettings)[]).filter((k) => JSON.stringify(settings[k]) !== JSON.stringify(draft[k]));
  const dirty = changed.length > 0 || icon !== null;
  const apply = useMutation({
    mutationFn: () => api.putSlackApp(connect.id, {
      ...Object.fromEntries(changed.map((k) => [k, draft[k]])),
      ...(icon ? { icon } : {}),
    }),
    onSuccess: (result) => {
      setIcon(null);
      setIconError(result.iconError);
      setApprove(result.permissionsUpdated);
      toast(result.permissionsUpdated ? "已更新，还需要在 Slack 同意新权限" : "已更新 Slack app");
      void client.invalidateQueries({ queryKey: keys.slackApp(station.id, connect.id) });
    },
  });
  const set = <K extends keyof SlackAppSettings>(key: K, value: SlackAppSettings[K]) => setDraft({ ...draft, [key]: value });

  return (
    <div className="card slack-app">
      {approve && (
        <div className="callout" data-tone="blue" role="status">
          <ShieldCheck {...ICON} />
          <span>权限变了，Slack 需要你同意一次才会生效。</span>
          <a className="btn btn-primary" href={links.install} target="_blank" rel="noopener" onClick={() => setApprove(false)}>去 Slack 同意</a>
        </div>
      )}
      <div className="slack-app-top">
        <button type="button" className="icon-drop" onClick={() => file.current?.click()} aria-label="上传图标"
          style={{ background: draft.backgroundColor || undefined }}>
          {icon ? <img src={icon} alt="新图标" /> : <><ImageUp {...ICON} size={20} /><span>上传图标</span></>}
        </button>
        <input ref={file} type="file" accept="image/png,image/jpeg,image/webp" hidden onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) void toIcon(f).then(setIcon, () => setIconError("读不了这张图片"));
        }} />
        <div className="field-grid slack-app-names">
          <Field label="App 名字" htmlFor="app-name">
            <input id="app-name" className="input" value={draft.name} onChange={(e) => set("name", e.target.value)} />
          </Field>
          <Field label="在消息里显示的名字" htmlFor="app-display">
            <input id="app-display" className="input" value={draft.displayName} onChange={(e) => set("displayName", e.target.value)} />
          </Field>
        </div>
      </div>
      {iconError && <p className="field-error" role="alert">{iconError}</p>}
      <Field label="简介" htmlFor="app-desc" hint="显示在 app 资料卡上，最多 140 字。">
        <input id="app-desc" className="input" maxLength={140} value={draft.description} onChange={(e) => set("description", e.target.value)} />
      </Field>
      <div className="field-grid">
        <Field label="背景色" htmlFor="app-color" hint="图标后面的底色。">
          <div className="input-row">
            <input type="color" className="color-swatch" aria-label="选择背景色" value={draft.backgroundColor || "#7a2e0e"} onChange={(e) => set("backgroundColor", e.target.value)} />
            <input id="app-color" className="input mono" spellCheck={false} value={draft.backgroundColor} onChange={(e) => set("backgroundColor", e.target.value)} placeholder="#7a2e0e" />
          </div>
        </Field>
      </div>
      <Field label="权限" hint="关掉的权限会从 app 上移除；打开新的权限需要在 Slack 同意一次。">
        <div className="switch-list">
          {(Object.keys(GROUPS) as SlackGroup[]).map((g) => (
            <SwitchRow key={g} title={GROUPS[g].label} description={GROUPS[g].description} disabled={g === "base"}
              checked={draft.groups[g] ?? false} onChange={(v) => set("groups", { ...draft.groups, [g]: v })} />
          ))}
        </div>
      </Field>
      {apply.error && <p className="field-error" role="alert">{apply.error.message}</p>}
      <div className="card-actions">
        {dirty && <Button variant="ghost" onClick={() => { setDraft(settings); setIcon(null); }}>还原</Button>}
        <Button variant="primary" disabled={!dirty} busy={apply.isPending} onClick={() => apply.mutate()}>应用到 Slack</Button>
      </div>
    </div>
  );
}
