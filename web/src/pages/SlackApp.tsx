// A connect's Slack app, edited from ember: name, description, colour, icon and
// permissions are written into the app's manifest with the workspace's app
// configuration token. When permissions change, Slack asks a person to approve
// them; that is the only step left in Slack.
import { useStation } from "../station.tsx";
import { ExternalLink, ImageUp, ShieldCheck } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { useTopic } from "../core/react.ts";
import { useAction, useApi, type ConnectView, type SlackAppLinks, type SlackAppSettings, type SlackAppView, type SlackGroup } from "../api.ts";
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
  const station = useStation();
  // Read from Slack through the station: no topic of the core, so it is read again after a change here.
  // The core reads it, and again after a write to the connect: nothing here reloads it.
  const app = useTopic<SlackAppView>({ topic: "slackApp", station: station.address, connect: connect.id });
  const saved = () => {};
  const links = app.value?.links;
  return (
    <Section title="Slack app" description="在这里改 app 的名字、图标和权限，ember 会写进 Slack 的 app 配置。"
      actions={links && <a className="btn btn-ghost" href={links.settings} target="_blank" rel="noopener"><ExternalLink {...ICON} />在 Slack 打开</a>}>
      {app.error ? <div className="card"><p className="field-error">{app.error.message}</p></div>
        : !app.value ? <div className="card"><p className="muted">正在读取 Slack 上的配置…</p></div>
        : app.value.state === "no_app" ? <div className="card"><p className="muted">{app.value.error ? `找不到这个连接的 Slack app（${app.value.error}）。换上有效的 token 后再来。` : "连上 Slack 之后，就可以在这里修改它的 app。"}</p></div>
        : app.value.state === "no_config_token" ? <ConfigTokenCard onSaved={saved} />
        : app.value.state === "error" ? (
          <div className="card">
            <p className="field-error" role="alert">读不到 app 配置：{app.value.error}</p>
            <ConfigTokenForm replacing onSaved={saved} />
          </div>
        )
        : <AppForm key={JSON.stringify(app.value.settings)} connect={connect} settings={app.value.settings} links={app.value.links} onSaved={saved} />}
    </Section>
  );
}

function ConfigTokenCard({ onSaved }: { onSaved(): void }) {
  return (
    <div className="card">
      <p className="card-lead">修改 app 需要你在这个 Slack 工作区的 App 配置 token。token 只归你用，这台 station 上的其他人看不到。</p>
      <ConfigTokenForm onSaved={onSaved} />
    </div>
  );
}

/**
 * Adds a Slack workspace's app configuration token (by its refresh token); `onSaved` gets the workspace. Pasting the
 * refresh token saves it at once; pasting the access token Slack shows above it says which one is wanted.
 */
export function ConfigTokenForm({ replacing, onSaved }: { replacing?: boolean; onSaved(teamId: string): void }) {
  const api = useApi();
  const toast = useToast();
  const [token, setToken] = useState("");
  const save = useAction((value: string) => api.addConfigToken(value), ({ teamId }) => { setToken(""); toast("已加上配置 token"); onSaved(teamId); });
  const wrong = token.startsWith("xoxe.xoxp-") ? "这是 Access Token。要的是它下面那个 Refresh Token，以 xoxe-1- 开头。"
    : token && !token.startsWith("xoxe-") ? "Refresh Token 以 xoxe-1- 开头。" : null;
  const ready = token.startsWith("xoxe-1-") && token.length > 20;
  return (
    <ol className="token-guide">
      <li>
        <strong>打开 Slack 的 app 列表</strong>
        <span className="muted">用要放 bot 的那个 Slack 工作区的账号登录。</span>
        <a className="btn btn-primary" href="https://api.slack.com/apps" target="_blank" rel="noopener"><ExternalLink {...ICON} />打开 api.slack.com/apps</a>
      </li>
      <li>
        <strong>生成配置 token</strong>
        <span className="muted">拉到页面最下面的「Your App Configuration Tokens」，点 Generate Token，选这个工作区。</span>
      </li>
      <li>
        <strong>把 Refresh Token 粘贴到这里</strong>
        <span className="muted">Slack 会给两个 token，要下面那个以 xoxe-1- 开头的。ember 会自己续期，以后不用再管。</span>
        <div className="input-row">
          <input className="input mono" type="password" autoComplete="off" spellCheck={false} value={token} aria-label="Refresh Token"
            onChange={(e) => setToken(e.target.value.trim())}
            onPaste={(e) => {
              const pasted = e.clipboardData.getData("text").trim();
              if (pasted.startsWith("xoxe-1-") && pasted.length > 20) { e.preventDefault(); setToken(pasted); void save.run(pasted); }
            }}
            placeholder="xoxe-1-…" />
          <Button variant="primary" disabled={!ready} busy={save.busy} onClick={() => void save.run(token)}>{replacing ? "换成这个" : "加上"}</Button>
        </div>
        {(wrong || save.error) && <p className="field-error" role="alert">{wrong ?? save.error?.message}</p>}
      </li>
    </ol>
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

/** An avatar to start from: a drawing on a background colour of its own (a mono mark is drawn white). */
interface Avatar { id: string; label: string; src: string; bg: string; mono?: boolean }

const BASE = import.meta.env.BASE_URL;

/** The model makers' marks, each on its own colour. */
const MAKERS: Avatar[] = [
  { id: "anthropic", label: "Anthropic", src: `${BASE}models/anthropic.svg`, bg: "#D97757", mono: true },
  { id: "openai", label: "OpenAI", src: `${BASE}models/openai.svg`, bg: "#0D0D0D", mono: true },
  { id: "gemini", label: "Gemini", src: `${BASE}models/gemini.svg`, bg: "#FFFFFF" },
  { id: "deepseek", label: "DeepSeek", src: `${BASE}models/deepseek.svg`, bg: "#FFFFFF" },
  { id: "qwen", label: "Qwen", src: `${BASE}models/qwen.svg`, bg: "#FFFFFF" },
  { id: "zhipu", label: "智谱", src: `${BASE}models/zhipu.svg`, bg: "#FFFFFF" },
  { id: "kimi", label: "Kimi", src: `${BASE}models/kimi.svg`, bg: "#0D0D0D", mono: true },
  { id: "minimax", label: "MiniMax", src: `${BASE}models/minimax.svg`, bg: "#FFFFFF" },
  { id: "xai", label: "xAI", src: `${BASE}models/xai.svg`, bg: "#0D0D0D", mono: true },
];

/** ember's buddy in its many moods (web/public/avatars/index.json). */
let buddies: Promise<Avatar[]> | null = null;
function loadBuddies(): Promise<Avatar[]> {
  buddies ??= fetch(`${BASE}avatars/index.json`).then((r) => r.json() as Promise<{ id: string; label: string; bg: string }[]>)
    .then((list) => list.map((a) => ({ ...a, src: `${BASE}avatars/${a.id}.svg` })), () => []);
  return buddies;
}
function useBuddies(): Avatar[] | null {
  const [list, setList] = useState<Avatar[] | null>(null);
  useEffect(() => { void loadBuddies().then(setList); }, []);
  return list;
}

/** An avatar as the app's icon: 1024 px, its colour behind it, the drawing centred (a maker's mark smaller, in white when mono). */
async function renderAvatar(avatar: Avatar, bg: string, maker: boolean): Promise<string> {
  const image = new Image();
  image.src = avatar.src;
  await image.decode();
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 1024;
  const g = canvas.getContext("2d")!;
  g.fillStyle = bg;
  g.fillRect(0, 0, 1024, 1024);
  const size = maker ? 560 : 880;
  const at = (1024 - size) / 2;
  if (avatar.mono) {
    const mark = document.createElement("canvas");
    mark.width = mark.height = size;
    const m = mark.getContext("2d")!;
    m.drawImage(image, 0, 0, size, size);
    m.globalCompositeOperation = "source-in";
    m.fillStyle = "#FFFFFF";
    m.fillRect(0, 0, size, size);
    g.drawImage(mark, at, at);
  } else {
    g.drawImage(image, at, at, size, size);
  }
  return canvas.toDataURL("image/png");
}

/** The colour an uploaded picture sits on best: the average of its edge. */
function edgeColour(dataUrl: string): Promise<string> {
  return new Promise((resolve) => {
    const image = new Image();
    image.onload = () => {
      const canvas = document.createElement("canvas");
      canvas.width = canvas.height = 32;
      const g = canvas.getContext("2d")!;
      g.drawImage(image, 0, 0, 32, 32);
      const { data } = g.getImageData(0, 0, 32, 32);
      let r = 0, gr = 0, b = 0, n = 0;
      for (let i = 0; i < 32; i++) for (const [x, y] of [[i, 0], [i, 31], [0, i], [31, i]] as const) {
        const at = (y * 32 + x) * 4;
        r += data[at]!; gr += data[at + 1]!; b += data[at + 2]!; n++;
      }
      const hex = (v: number) => Math.round(v / n).toString(16).padStart(2, "0");
      resolve(`#${hex(r)}${hex(gr)}${hex(b)}`.toUpperCase());
    };
    image.onerror = () => resolve("#7A2E0E");
    image.src = dataUrl;
  });
}

/** What a new app starts as: every permission on; its colour and icon come from the first buddy. */
export const NEW_APP: SlackAppSettings = {
  name: "ember", displayName: "ember", description: "Coding agent in your threads (ember)", longDescription: "", backgroundColor: "#F3E3D3",
  groups: Object.fromEntries((Object.keys(GROUPS) as SlackGroup[]).map((g) => [g, true])) as Record<SlackGroup, boolean>,
};

/**
 * An app's look and permissions, by how often each is changed: its avatar and name up front (an avatar picked from
 * ember's buddies or the model makers, or uploaded), then its colour, which follows the avatar until it is set by
 * hand (and can go back); the description on a line; permissions folded. One name: the name in messages follows it,
 * unless set apart on purpose. `fresh`: a new app, which starts from the first buddy.
 */
export function AppFields({ settings, onChange, icon, onIcon, fresh }: {
  settings: SlackAppSettings; onChange(settings: SlackAppSettings): void; icon: string | null; onIcon(icon: string | null, error: string | null): void; fresh?: boolean;
}) {
  const file = useRef<HTMLInputElement>(null);
  const buddyList = useBuddies();
  const [apart, setApart] = useState(settings.displayName !== settings.name);
  const [picked, setPicked] = useState<{ avatar: Avatar; maker: boolean } | { upload: true; bg: string } | null>(null);
  const [colourSet, setColourSet] = useState(!fresh);
  const set = <K extends keyof SlackAppSettings>(key: K, value: SlackAppSettings[K]) => onChange({ ...settings, [key]: value });
  const setName = (name: string) => onChange({ ...settings, name, ...(apart ? {} : { displayName: name }) });
  const recommended = picked ? ("upload" in picked ? picked.bg : picked.avatar.bg) : null;
  const draw = (p: typeof picked, bg: string) => {
    if (p && !("upload" in p)) void renderAvatar(p.avatar, bg, p.maker).then((i) => onIcon(i, null), () => onIcon(null, "画不出这个头像"));
  };
  const pick = (avatar: Avatar, maker: boolean, next = settings) => {
    const p = { avatar, maker };
    setPicked(p);
    const bg = colourSet ? next.backgroundColor : avatar.bg;
    if (bg !== next.backgroundColor) onChange({ ...next, backgroundColor: bg });
    draw(p, bg);
  };
  const colour = (bg: string, byHand: boolean) => {
    setColourSet(byHand);
    set("backgroundColor", bg);
    if (/^#[0-9a-fA-F]{6}$/.test(bg)) draw(picked, bg);
  };
  // A new app starts from the first buddy, on its colour.
  const started = useRef(false);
  useEffect(() => {
    if (!fresh || started.current || icon || !buddyList?.length) return;
    started.current = true;
    pick(buddyList[0]!, false);
  });
  const on = (Object.keys(GROUPS) as SlackGroup[]).filter((g) => settings.groups[g]).length;
  const isPicked = (a: Avatar) => picked !== null && !("upload" in picked) && picked.avatar.id === a.id;
  const tile = (a: Avatar, maker: boolean) => (
    <button key={a.id} type="button" className="avatar-tile" data-picked={isPicked(a) || undefined} title={a.label} aria-label={a.label}
      style={{ background: a.bg }} onClick={() => pick(a, maker)}>
      <img src={a.src} alt="" data-mono={a.mono || undefined} data-maker={maker || undefined} />
    </button>
  );
  return (
    <>
      <div className="app-look">
        <button type="button" className="app-avatar" onClick={() => file.current?.click()} title="上传图片" style={{ background: settings.backgroundColor || undefined }}>
          {icon ? <img src={icon} alt="头像" /> : <span className="app-avatar-empty"><ImageUp {...ICON} size={20} />{fresh ? "上传" : "保持现在的"}</span>}
        </button>
        <input ref={file} type="file" accept="image/png,image/jpeg,image/webp" hidden onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) void toIcon(f).then(async (i) => {
            const bg = await edgeColour(i);
            setPicked({ upload: true, bg });
            onIcon(i, null);
            if (!colourSet) set("backgroundColor", bg);
          }, () => onIcon(null, "读不了这张图片"));
        }} />
        <div className="app-look-main">
          <input id="app-name" className="input app-name-input" aria-label="名字" placeholder="名字" value={settings.name} onChange={(e) => setName(e.target.value)} />
          {apart ? (
            <input id="app-display" className="input" aria-label="在消息里显示的名字" placeholder="在消息里显示的名字" value={settings.displayName} onChange={(e) => set("displayName", e.target.value)} />
          ) : (
            <button type="button" className="text-button app-look-link" onClick={() => setApart(true)}>消息里用别的名字</button>
          )}
          <div className="app-colour">
            <input type="color" className="color-swatch" aria-label="底色" value={/^#[0-9a-fA-F]{6}$/.test(settings.backgroundColor) ? settings.backgroundColor : "#7a2e0e"}
              onChange={(e) => colour(e.target.value.toUpperCase(), true)} />
            <input className="input mono app-colour-hex" aria-label="底色色值" spellCheck={false} value={settings.backgroundColor} onChange={(e) => colour(e.target.value, true)} />
            {recommended && colourSet && recommended.toLowerCase() !== settings.backgroundColor.toLowerCase() && (
              <button type="button" className="text-button" onClick={() => colour(recommended, false)}>用推荐色</button>
            )}
          </div>
        </div>
      </div>
      <div className="avatar-picker">
        <div className="avatar-grid" aria-label="ember 头像">{(buddyList ?? []).map((a) => tile(a, false))}</div>
        <div className="avatar-grid" aria-label="模型厂商">{MAKERS.map((a) => tile(a, true))}</div>
      </div>
      <input id="app-desc" className="input app-desc" aria-label="简介" maxLength={140} placeholder="简介，显示在 app 资料卡上" value={settings.description} onChange={(e) => set("description", e.target.value)} />
      <details className="app-perms">
        <summary>权限 · 开了 {on} / {Object.keys(GROUPS).length} 项</summary>
        <div className="switch-list">
          {(Object.keys(GROUPS) as SlackGroup[]).map((g) => (
            <SwitchRow key={g} title={GROUPS[g].label} description={GROUPS[g].description} disabled={g === "base"}
              checked={settings.groups[g] ?? false} onChange={(v) => set("groups", { ...settings.groups, [g]: v })} />
          ))}
        </div>
      </details>
    </>
  );
}

function AppForm({ connect, settings, links, onSaved }: { connect: ConnectView; settings: SlackAppSettings; links: SlackAppLinks; onSaved(): void }) {
  const api = useApi();
  const toast = useToast();
  const [draft, setDraft] = useState(settings);
  const [icon, setIcon] = useState<string | null>(null);
  const [iconError, setIconError] = useState<string | null>(null);
  const [approve, setApprove] = useState(false);
  useEffect(() => setDraft(settings), [settings]);

  const changed = (Object.keys(settings) as (keyof SlackAppSettings)[]).filter((k) => JSON.stringify(settings[k]) !== JSON.stringify(draft[k]));
  const dirty = changed.length > 0 || icon !== null;
  const apply = useAction(() => api.putSlackApp(connect.id, {
    ...Object.fromEntries(changed.map((k) => [k, draft[k]])),
    ...(icon ? { icon } : {}),
  }), (result) => {
    setIcon(null);
    setIconError(result.iconError);
    setApprove(result.permissionsUpdated);
    toast(result.permissionsUpdated ? "已更新，还需要在 Slack 同意新权限" : "已更新 Slack app");
    onSaved();
  });

  return (
    <div className="card slack-app">
      {approve && (
        <div className="callout" data-tone="blue" role="status">
          <ShieldCheck {...ICON} />
          <span>权限变了，Slack 需要你同意一次才会生效。</span>
          <a className="btn btn-primary" href={links.install} target="_blank" rel="noopener" onClick={() => setApprove(false)}>去 Slack 同意</a>
        </div>
      )}
      <AppFields settings={draft} onChange={setDraft} icon={icon} onIcon={(i, e) => { setIcon(i); setIconError(e); }} />
      {iconError && <p className="field-error" role="alert">{iconError}</p>}
      {apply.error && <p className="field-error" role="alert">{apply.error.message}</p>}
      <div className="card-actions">
        {dirty && <Button variant="ghost" onClick={() => { setDraft(settings); setIcon(null); }}>还原</Button>}
        <Button variant="primary" disabled={!dirty} busy={apply.busy} onClick={() => void apply.run()}>应用到 Slack</Button>
      </div>
    </div>
  );
}
