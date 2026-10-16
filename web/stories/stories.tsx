// Each story: a part of the app in one state, on made-up data (data.ts, the site's demo core). People open them in the
// gallery (`pnpm stories`); test/browser/stories.mjs opens every one, takes its steps and measures it (docs/ui-panels.md).
// A story is the whole app (`app`, the site's demo, the steps taking it to the state) or one part drawn alone (`render`).
// A new part of the app gets a story here, and so is measured.
import { useEffect, useState, type ReactNode } from "react";
import { SystemBubbles } from "../src/SystemBubbles.tsx";
import { StationUpdate } from "../src/StationUpdate.tsx";
import { Reader } from "../src/drive/Reader.tsx";
import { Tile } from "../src/pages/Notifications.tsx";
import { PermissionRow } from "../src/pages/Permissions.tsx";
import { Player } from "../src/drive/Player.tsx";
import { DrivePreview } from "../src/mobile/Drive.tsx";
import { useToast } from "../src/toast.tsx";
import { ComposerExtras } from "../src/Chat.tsx";
import type { Draft, Pending } from "../src/draft.ts";
import * as composerCss from "../src/styles/composer.css.ts";
import {
  AgentMark, Button, Choices, Confirm, CopyCommand, Dialog, Empty, Field, IconButton, Loading, Menu, ModelLogo, PanelButton, PanelGroup,
  PanelHead, PanelIconButton, PanelRow, PanelText, Pill, RuntimeTags, Section, Segmented, Select, SkeletonRows, StatusDot, StatusText,
  Switch, SwitchRow, Tip,
} from "../src/ui.tsx";
import { Archive, Bell, Close, Copy, Download, Edit, Folder, Plus, Refresh, Search, Trash } from "../src/icons.tsx";
import * as controlsCss from "../src/styles/controls.css.ts";
import { vars } from "../src/styles/tokens.css.ts";
import { AT, apk, clips, folder, note, novel, picture } from "./data.ts";

/**
 * What takes a story to its state, as the tests do it (Playwright's selectors); shown beside it in the gallery. `hold`:
 * a finger held on the middle of it as long as a long press, then lifted.
 */
export interface Step { click?: string; rightClick?: string; hover?: string; key?: string; move?: [number, number]; text?: string; hold?: string }
export interface Story {
  id: string;
  group: string;
  title: string;
  /** The whole app (the site's demo), taken to the state by its steps. */
  app?: boolean;
  /** One part, drawn alone. */
  render?: () => ReactNode;
  steps?: Step[];
  /** In a phone's window (wide by default). */
  phone?: boolean;
  /** Shows the changelog's news (the notices' bubble). */
  news?: boolean;
}

const at = (name: string) => ({ ...AT, path: name });
const ANTHROPIC = { id: "anthropic", name: "Anthropic" };
const OPENAI = { id: "openai", name: "OpenAI" };
const noop = () => undefined;

/** A part drawn alone on the app's ground, the whole window its room. */
const stage = (node: ReactNode) => <div style={{ position: "relative", width: "100%", height: "100vh", overflow: "hidden", background: vars.canvas, color: vars.text }}>{node}</div>;
/** Parts side by side on a page of the app: sections of them, each named. */
const sheet = (sections: [string, ReactNode][]) => stage(
  <div style={{ display: "grid", alignContent: "start", gap: 20, padding: 32, maxWidth: 880, overflowY: "auto", height: "100%", boxSizing: "border-box" }}>
    {sections.map(([title, body]) => <Section key={title} title={title}><div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 12 }}>{body}</div></Section>)}
  </div>,
);
/** A small panel as it opens, drawn in place (controls.css.ts popover). */
const panel = (body: ReactNode, card = false) => (
  <div className={card ? `${controlsCss.popover} ${controlsCss.panelCard}` : controlsCss.popover} style={{ position: "static", width: 280, animation: "none" }}>{body}</div>
);

function SwitchDemo({ start, busy, disabled }: { start: boolean; busy?: boolean; disabled?: boolean }) {
  const [on, setOn] = useState(start);
  return <Switch checked={on} onChange={setOn} busy={busy} disabled={disabled} label="开关" />;
}
function SegmentedDemo({ n }: { n: 2 | 3 }) {
  const options = n === 2 ? [{ value: "a", label: "宋体" }, { value: "b", label: "黑体" }] : [{ value: "a", label: "跟随系统" }, { value: "b", label: "浅色" }, { value: "c", label: "深色" }];
  const [v, setV] = useState("a");
  return <Segmented label="选项" options={options} value={v} onChange={setV} />;
}
function SelectDemo() {
  const [v, setV] = useState("opus");
  return <div style={{ width: 240 }}><Select label="模型" value={v} onChange={setV} options={[{ value: "opus", label: "Opus 5.5", hint: "最强" }, { value: "sonnet", label: "Sonnet 5.5" }, { value: "haiku", label: "Haiku 4.5", hint: "最快" }]} /></div>;
}
function ChoicesDemo() {
  const [v, setV] = useState<string>("all");
  return <div style={{ width: 420 }}><Choices label="范围" value={v} onChange={setV} options={[{ value: "all", title: "全部会话", description: "workspace 里所有人的对话" }, { value: "mine", title: "我参与的", description: "只看自己发起或参与的" }]} /></div>;
}
/** What can wait in a composer to be sent, each kind once: a file up, one going up, one that failed, one named by its
 * path, a folder named by its path, pasted words, a folder of the station going as a zip. */
function ComposerCards() {
  const ref = (path: string, dir = false, mode: "path" | "file" = "path") => ({ station: "demo/studio", stationName: "Studio", path, dir, mode });
  const files: Pending[] = [
    { id: "1", name: "合同-2026Q4.pdf", size: 1_468_006, done: { name: "合同-2026Q4.pdf", path: "/u/a.pdf", size: 1_468_006 }, error: null },
    { id: "2", name: "export-1013.csv", size: 22_528_000, sent: 9_000_000, done: null, error: null },
    { id: "3", name: "build.log", size: 4096, done: null, error: "station 没有回应" },
    { id: "4", name: "发版录屏 1014.mp4", size: 50_541_773, done: null, error: null, ref: ref("/Users/lin/Downloads/发版录屏 1014.mp4") },
    { id: "5", name: "设计稿", size: 0, done: null, error: null, ref: ref("/Users/lin/Downloads/设计稿", true) },
    { id: "6", name: "pasted.txt", size: 5120, done: { name: "pasted.txt", path: "/u/p.txt", size: 5120 }, error: null, pasted: { preview: "error: connect ECONNREFUSED 127.0.0.1:5432 at TCPConnectWrap", characters: 5120 } as never },
    { id: "7", name: "acme", size: 0, sent: 0, done: null, error: null, ref: ref("/Users/lin/code/acme", true, "file") },
  ];
  const draft = { quotes: [], files, text: "", starting: false, asFiles: false, remove: noop, setMode: noop, setAsFiles: noop, add: noop, setText: noop, unquote: noop, comment: noop } as unknown as Draft;
  return (
    <div style={{ padding: 40, maxWidth: 820 }}>
      <form className={composerCss.composerBox} data-multiline="" style={{ display: "flex" }}>
        <ComposerExtras draft={draft} focusQuote={null} onFocused={noop} onDone={noop} />
      </form>
    </div>
  );
}

function ToastDemo({ text }: { text: string }) {
  const toast = useToast();
  useEffect(() => { toast(text); }, [toast, text]);
  return null;
}

export const stories: Story[] = [
  // ── controls ──
  {
    id: "control-buttons", group: "基础控件", title: "按钮",
    render: () => sheet([
      ["按钮", <>
        <Button variant="primary">主要</Button><Button>次要</Button><Button variant="ghost">幽灵</Button>
        <Button variant="danger">危险</Button><Button variant="danger-solid">删除</Button>
        <Button variant="primary" icon={Plus}>带图标</Button><Button busy>处理中</Button><Button disabled>不可用</Button>
      </>],
      ["图标按钮", <>
        <IconButton label="刷新" icon={Refresh} /><IconButton label="搜索" icon={Search} /><IconButton label="编辑" icon={Edit} />
        <IconButton label="删除" icon={Trash} /><IconButton label="处理中" icon={Download} busy /><IconButton label="失败" icon={Download} failed="没连上" />
      </>],
      ["小面板按钮", <>
        <PanelButton tone="accent">看看</PanelButton><PanelButton>普通</PanelButton><PanelButton tone="quiet">次要</PanelButton>
        <PanelButton tone="filled">现在更新</PanelButton><PanelIconButton label="关闭"><Close size={14} /></PanelIconButton>
      </>],
    ]),
  },
  { id: "control-buttons-hover", group: "基础控件", title: "按钮 · 悬停", render: () => sheet([["按钮", <><Button variant="ghost">幽灵</Button><IconButton label="刷新" icon={Refresh} /><PanelButton tone="accent">看看</PanelButton></>]]), steps: [{ hover: "text=幽灵" }] },
  {
    id: "control-fields", group: "基础控件", title: "输入框",
    render: () => sheet([
      ["单行", <div style={{ display: "grid", gap: 12, width: 360 }}>
        <Field label="名字" hint="会显示在侧栏和对话里"><input className={controlsCss.input} defaultValue="Studio" /></Field>
        <Field label="地址" error="这个地址打不开"><input className={controlsCss.input} defaultValue="http://127.0.0.1:3000" /></Field>
        <Field label="空的"><input className={controlsCss.input} placeholder="还没填" /></Field>
      </div>],
      ["多行", <div style={{ width: 420 }}><Field label="说明"><textarea className={controlsCss.input} rows={3} defaultValue={"归档建议：\n超过 7 天没有新消息、也没有在跑的任务"} /></Field></div>],
    ]),
  },
  { id: "control-fields-focus", group: "基础控件", title: "输入框 · 聚焦", render: () => sheet([["单行", <div style={{ width: 360 }}><Field label="名字"><input className={controlsCss.input} defaultValue="Studio" /></Field></div>]]), steps: [{ click: "input" }] },
  { id: "control-segmented", group: "基础控件", title: "分段控件", render: () => sheet([["两项", <SegmentedDemo n={2} />], ["三项", <SegmentedDemo n={3} />]]) },
  { id: "control-choices", group: "基础控件", title: "选项卡片", render: () => sheet([["单选", <ChoicesDemo />]]) },
  {
    id: "control-switches", group: "基础控件", title: "开关",
    render: () => sheet([
      ["开关", <><SwitchDemo start /><SwitchDemo start={false} /><SwitchDemo start busy /><SwitchDemo start={false} disabled /></>],
      ["带说明", <div style={{ width: 420 }}><SwitchRow title="自动归档" description="超过 7 天没动静的对话移到归档" checked onChange={noop} /></div>],
    ]),
  },
  { id: "control-select", group: "基础控件", title: "下拉框", render: () => sheet([["下拉", <SelectDemo />]]) },
  { id: "control-select-open", group: "基础控件", title: "下拉框 · 展开", render: () => sheet([["下拉", <SelectDemo />]]), steps: [{ click: '[role="combobox"]' }] },
  { id: "control-menu-open", group: "基础控件", title: "「…」菜单", render: () => sheet([["菜单", <Menu items={[{ label: "改名", icon: Edit, onSelect: noop }, { label: "复制链接", icon: Copy, onSelect: noop }, "separator", { label: "归档", icon: Archive, onSelect: noop }, { label: "删除", icon: Trash, danger: true, onSelect: noop }]} />]]), steps: [{ click: '[aria-label="更多操作"]' }] },
  { id: "control-tip", group: "基础控件", title: "提示", render: () => sheet([["提示", <Tip label="新建对话"><IconButton label="新建对话" icon={Plus} /></Tip>]]), steps: [{ hover: '[aria-label="新建对话"]' }] },
  {
    id: "control-marks", group: "基础控件", title: "标签、状态和标记",
    render: () => sheet([
      ["标签", <><Pill>普通</Pill><Pill tone="green">在线</Pill><Pill tone="blue">进行中</Pill><Pill tone="amber">等待</Pill><Pill tone="red">失败</Pill><Pill tone="accent">强调</Pill></>],
      ["状态", <><StatusDot state="online" label="在线" /><StatusDot state="busy" label="忙" /><StatusDot state="error" label="出错" /><StatusDot state="offline" label="离线" /><StatusText text="已连接 · 3 分钟前" /></>],
      ["模型和运行时", <><ModelLogo maker={ANTHROPIC} runtime="claude" size={20} /><ModelLogo maker={OPENAI} runtime="codex" size={20} /><AgentMark maker={ANTHROPIC} runtime="claude" badge={undefined} size={28} /><RuntimeTags runtimes={["claude", "codex"]} /></>],
    ]),
  },
  {
    id: "control-states", group: "基础控件", title: "加载、空和命令",
    render: () => sheet([
      ["加载", <div style={{ width: 360, height: 120, position: "relative" }}><Loading fill={false} /></div>],
      ["骨架", <div style={{ width: 420 }}><SkeletonRows count={3} /></div>],
      ["空", <div style={{ width: 420 }}><Empty>还没有对话</Empty></div>],
      ["命令", <div style={{ width: 520 }}><CopyCommand text="curl -fsSL https://still.fail/install.sh | sh" /></div>],
    ]),
  },
  {
    id: "control-panel-parts", group: "基础控件", title: "小面板部件",
    render: () => sheet([
      ["列表", panel(<>
        <PanelHead title="自定义侧边条" note="拖动换位置，点 − 拿掉" />
        <PanelGroup label="对话列表"><PanelRow icon={<Folder size={18} />} label="文件" end={<Plus size={16} />} onClick={noop} /><PanelRow icon={<Archive size={18} />} label="已归档" end={<Plus size={16} />} onClick={noop} /></PanelGroup>
      </>)],
      ["卡片", panel(<><PanelText><b>Studio</b> 有新版本</PanelText><PanelText>更新时会重启 station，正在跑的 agent 会接着跑。</PanelText></>, true)],
    ]),
  },

  { id: "composer-cards", group: "对话", title: "输入框里的附件", render: () => stage(<ComposerCards />) },

  // ── dialogs and toasts ──
  { id: "dialog", group: "弹窗", title: "弹窗", render: () => stage(<Dialog open title="添加 station" description="在要接入的机器上运行这条命令。" onClose={noop} footer={<><Button variant="ghost">取消</Button><Button variant="primary">完成</Button></>}><CopyCommand text="curl -fsSL https://still.fail/install.sh | sh" /></Dialog>) },
  { id: "dialog-wide", group: "弹窗", title: "弹窗 · 宽", render: () => stage(<Dialog open wide title="分享对话" onClose={noop} footer={<Button variant="primary">完成</Button>}><Choices label="范围" value="all" onChange={noop} options={[{ value: "all", title: "全部", description: "workspace 里的所有人" }, { value: "mine", title: "只给我", description: "只有自己能看" }]} /></Dialog>) },
  { id: "dialog-confirm", group: "弹窗", title: "确认", render: () => stage(<Confirm open title="删除「设计稿」？" description="文件夹和里面的文件都会删除，不能恢复。" action="删除" onConfirm={noop} onClose={noop} />) },
  { id: "dialog-confirm-error", group: "弹窗", title: "确认 · 失败", render: () => stage(<Confirm open title="归档这个对话？" description="归档后有新消息会自动恢复。" action="归档" onConfirm={noop} onClose={noop} error="station 没有回应" />) },
  { id: "toast", group: "弹窗", title: "toast", render: () => stage(<ToastDemo text="已复制链接" />) },
  { id: "toast-long", group: "弹窗", title: "toast · 长", render: () => stage(<ToastDemo text="没能上传：http://127.0.0.1:4760/upload 返回 413，文件超过了 station 允许的大小（200 MB）" />) },

  // ── the app (the site's demo) ──
  { id: "app-chat", group: "应用", title: "对话页", app: true },
  { id: "app-chat-history", group: "应用", title: "执行历史", app: true, steps: [{ click: '[aria-label$="的执行历史"]' }] },
  { id: "app-chat-side", group: "应用", title: "对话 · 侧栏打开", app: true, steps: [{ click: '[aria-label="打开侧栏"]' }] },
  { id: "app-sidebar-folded", group: "应用", title: "侧栏收起", app: true, steps: [{ click: '[aria-label="对话"]' }] },
  { id: "app-sidebar-peek", group: "应用", title: "侧栏收起后临时展开", app: true, steps: [{ click: '[aria-label="对话"]' }, { hover: '[aria-label="对话"]' }, { move: [150, 60] }] },
  { id: "app-new-chat", group: "应用", title: "新建对话", app: true, steps: [{ text: "新建对话" }] },
  { id: "app-todo", group: "应用", title: "待处理", app: true, steps: [{ click: '[aria-label="待处理"]' }] },
  { id: "app-files", group: "应用", title: "文件", app: true, steps: [{ click: '[aria-label="文件"]' }] },
  { id: "app-files-home", group: "应用", title: "文件 · 主目录", app: true, steps: [{ click: '[aria-label="文件"]' }, { text: "主目录" }] },
  { id: "app-files-deep", group: "应用", title: "文件 · 主目录下一层", app: true, steps: [{ click: '[aria-label="文件"]' }, { text: "主目录" }, { text: "code" }] },
  { id: "app-files-row-menu", group: "应用", title: "文件 · 文件夹右键", app: true, steps: [{ click: '[aria-label="文件"]' }, { text: "主目录" }, { rightClick: "button:has-text(\"Movies\")" }] },
  { id: "app-chat-files", group: "应用", title: "对话 · Station 文件", app: true, steps: [{ click: '[aria-label="Station 文件"]' }] },
  { id: "app-chat-files-folder", group: "应用", title: "对话 · Station 文件 · 文件夹", app: true, steps: [{ click: '[aria-label="Station 文件"]' }, { text: "Downloads" }] },
  { id: "app-chat-files-menu", group: "应用", title: "对话 · Station 文件 · 右键", app: true, steps: [{ click: '[aria-label="Station 文件"]' }, { text: "Downloads" }, { rightClick: "button:has-text(\"login-375.png\")" }] },
  { id: "app-chat-files-added", group: "应用", title: "对话 · Station 文件 · 发路径", app: true, steps: [{ click: '[aria-label="Station 文件"]' }, { text: "Downloads" }, { rightClick: "button:has-text(\"发版录屏 1014.mp4\")" }, { text: "添加到消息" }] },
  { id: "app-chat-files-card", group: "应用", title: "对话 · 文件卡片悬停", app: true, steps: [{ click: '[aria-label="Station 文件"]' }, { text: "Downloads" }, { rightClick: "button:has-text(\"发版录屏 1014.mp4\")" }, { text: "添加到消息" }, { hover: "text=Studio · 路径" }] },
  { id: "app-station", group: "应用", title: "station", app: true, steps: [{ click: '[aria-label^="Station"]' }] },
  { id: "app-station-mark", group: "应用", title: "station · 选图标", app: true, steps: [{ click: '[aria-label^="Station"]' }, { click: '[aria-label^="给 Studio 选个图标"]' }] },
  { id: "app-profile", group: "应用", title: "Profile", app: true, steps: [{ click: '[aria-label="Profile"]' }] },
  { id: "app-connects", group: "应用", title: "连接", app: true, steps: [{ click: '[aria-label="连接"]' }] },
  { id: "app-usage", group: "应用", title: "用量", app: true, steps: [{ click: '[aria-label="用量"]' }] },

  // ── settings ──
  { id: "settings-appearance", group: "设置", title: "外观", app: true, steps: [{ click: '[aria-label="设置"]' }] },
  { id: "settings-notifications", group: "设置", title: "通知", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "通知" }] },
  { id: "settings-notifications-type", group: "设置", title: "通知 · 展开一个类别", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "通知" }, { click: 'button:has-text("有人说话")' }] },
  {
    id: "settings-notifications-refused", group: "设置", title: "通知 · 系统没允许",
    render: () => stage(<div style={{ display: "grid", gap: 10, padding: 32, maxWidth: 720 }}>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10 }}>
        <Tile way="banner" on={false} action="去系统设置打开" onChange={noop} /><Tile way="badge" on onChange={noop} /><Tile way="dock" on onChange={noop} />
      </div>
    </div>),
  },
  { id: "settings-permissions", group: "设置", title: "权限", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "权限" }] },
  {
    id: "settings-permissions-states", group: "设置", title: "权限 · 各种状态",
    render: () => stage(<div style={{ display: "grid", gap: 10, padding: 32, maxWidth: 720 }}>
      {(["granted", "default", "denied", "unknown"] as const).map((state) => (
        <PermissionRow key={state} icon={Bell} name="通知" purpose="等你决定、出错、有人说话时弹横幅" without="没有它：横幅弹不出来，红点和桌面浮窗照常"
          where="系统设置 → 通知 → still.fail → 允许通知" state={state} onAllow={noop} onOpen={noop} />
      ))}
    </div>),
  },
  { id: "settings-changelog", group: "设置", title: "更新日志", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "更新日志" }] },
  { id: "settings-decisions", group: "设置", title: "自动决策", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "自动决策" }] },
  { id: "settings-memory", group: "设置", title: "记忆", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "记忆" }] },
  { id: "settings-memory-skill", group: "设置", title: "记忆 · 项目", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "acme-web" }] },
  { id: "settings-memory-global", group: "设置", title: "记忆 · 全局", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "合并" }] },
  { id: "settings-workspace", group: "设置", title: "Workspace", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "Workspace · Acme" }] },
  { id: "settings-security", group: "设置", title: "安全", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "安全" }] },

  // ── small panels (docs/ui-panels.md) ──
  { id: "panel-filter", group: "小面板", title: "筛选菜单", app: true, steps: [{ click: '[aria-label^="筛选会话"]' }] },
  { id: "panel-chat-info", group: "小面板", title: "对话信息", app: true, steps: [{ click: '[aria-label="对话信息"]' }] },
  { id: "panel-jobs", group: "小面板", title: "服务和后台任务", app: true, steps: [{ click: '[aria-label="服务和后台任务"]' }] },
  { id: "panel-workspace", group: "小面板", title: "workspace 菜单", app: true, steps: [{ click: '[aria-label="新建 workspace、添加账号"]' }] },
  { id: "panel-rail-menu", group: "小面板", title: "侧边条右键菜单", app: true, steps: [{ rightClick: '[aria-label="文件"]' }] },
  { id: "panel-rail-adder", group: "小面板", title: "侧边条自定义", app: true, steps: [{ rightClick: '[aria-label="文件"]' }, { text: "自定义侧边条" }] },
  { id: "panel-chat-menu", group: "小面板", title: "对话右键菜单", app: true, steps: [{ rightClick: "a:has-text(\"订单导出支持 CSV\")" }] },
  { id: "panel-station-card", group: "小面板", title: "station 卡片", app: true, steps: [{ move: [1, 1] }, { hover: "header >> text=/Studio|这台机器/" }] },
  { id: "panel-switcher", group: "小面板", title: "⌘K", app: true, steps: [{ click: "textarea" }, { key: "ControlOrMeta+k" }] },
  {
    id: "panel-station-update", group: "小面板", title: "station 更新",
    render: () => stage(<div style={{ padding: 24 }}><StationUpdate station="local" notice={{
      tone: "update", text: "Studio 有新版本", label: "有新版本", station: "Studio", detail: "更新时会重启 station，正在跑的 agent 会接着跑",
      from: "0.1.2790", to: "0.1.2925", version: "0.1.2925", canUpdate: true, dismissible: true, open: true,
    }} /></div>),
  },
  {
    id: "panel-station-updating", group: "小面板", title: "station 更新 · 进行中",
    render: () => stage(<div style={{ padding: 24 }}><StationUpdate station="local" notice={{
      tone: "busy", text: "Studio 正在更新", label: "正在更新", station: "Studio", detail: "下载新版本", percent: 42, from: "0.1.2790", to: "0.1.2925", open: true,
    }} /></div>),
  },
  { id: "panel-bubble", group: "小面板", title: "通知气泡", news: true, render: () => stage(<SystemBubbles scope="demo" />) },
  { id: "panel-bubble-hover", group: "小面板", title: "通知气泡 · 悬停按钮", news: true, render: () => stage(<SystemBubbles scope="demo" />), steps: [{ hover: "text=看看" }] },

  // ── files ──
  { id: "reader-txt", group: "文件", title: "阅读器 · 小说", render: () => stage(<Reader at={at(novel.name)} name={novel.name} size={novel.size} mtime={novel.mtime} markdown={false} backLabel="下载" onBack={noop} />) },
  { id: "reader-contents", group: "文件", title: "阅读器 · 目录", render: () => stage(<Reader at={at(novel.name)} name={novel.name} size={novel.size} mtime={novel.mtime} markdown={false} backLabel="下载" onBack={noop} />), steps: [{ click: '[aria-label="目录"]' }] },
  { id: "reader-find", group: "文件", title: "阅读器 · 搜索", render: () => stage(<Reader at={at(novel.name)} name={novel.name} size={novel.size} mtime={novel.mtime} markdown={false} backLabel="下载" onBack={noop} />), steps: [{ click: '[aria-label="搜索"]' }] },
  { id: "reader-layout", group: "文件", title: "阅读器 · 排版", render: () => stage(<Reader at={at(novel.name)} name={novel.name} size={novel.size} mtime={novel.mtime} markdown={false} backLabel="下载" onBack={noop} />), steps: [{ click: '[aria-label="排版"]' }] },
  { id: "reader-md", group: "文件", title: "阅读器 · Markdown", render: () => stage(<Reader at={at(note.name)} name={note.name} size={note.size} mtime={note.mtime} markdown backLabel="下载" onBack={noop} />) },
  { id: "reader-phone", group: "文件", title: "阅读器 · 手机", phone: true, render: () => stage(<Reader at={at(novel.name)} name={novel.name} size={novel.size} mtime={novel.mtime} markdown={false} backLabel="下载" onBack={noop} />) },
  { id: "player", group: "文件", title: "播放器", render: () => stage(<Player at={at(clips[0]!.name)} entry={clips[0]!} siblings={folder} backLabel="下载" onBack={noop} onGo={noop} />), steps: [{ move: [640, 400] }] },
  { id: "player-list", group: "文件", title: "播放器 · 选集", render: () => stage(<Player at={at(clips[0]!.name)} entry={clips[0]!} siblings={folder} backLabel="下载" onBack={noop} onGo={noop} />), steps: [{ click: '[aria-label="选集"]' }, { move: [500, 400] }] },
  { id: "player-phone", group: "文件", title: "播放器 · 手机", phone: true, render: () => stage(<Player at={at(clips[0]!.name)} entry={clips[0]!} siblings={folder} backLabel="下载" onBack={noop} onGo={noop} />) },
  { id: "preview-picture", group: "文件", title: "图片预览", render: () => stage(<DrivePreview at={at(picture.name)} entries={folder} entry={picture} onClose={noop} />), steps: [{ move: [640, 400] }] },
  { id: "preview-unshown", group: "文件", title: "预览 · 不能预览的文件", render: () => stage(<DrivePreview at={at(apk.name)} entries={[...folder, apk]} entry={apk} onClose={noop} />), steps: [{ move: [640, 400] }] },
  { id: "preview-unshown-phone", group: "文件", title: "预览 · 不能预览的文件 · 手机", phone: true, render: () => stage(<DrivePreview at={at(apk.name)} entries={[...folder, apk]} entry={apk} onClose={noop} />) },

  // ── the phone ──
  { id: "phone-chat", group: "手机", title: "对话", app: true, phone: true },
  { id: "phone-chat-pick", group: "手机", title: "对话 · 选取一段", app: true, phone: true, steps: [{ hold: '[data-role="agent"][data-ts] li' }] },
  { id: "phone-home", group: "手机", title: "首页", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }] },
  { id: "phone-agent", group: "手机", title: "agent 名片", app: true, phone: true, steps: [{ click: '[aria-label$="的名片"]' }] },
  { id: "phone-chat-info", group: "手机", title: "对话信息", app: true, phone: true, steps: [{ click: '[aria-label="对话信息"]' }] },
  { id: "phone-files", group: "手机", title: "文件", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="文件"]' }] },
  { id: "phone-profile", group: "手机", title: "Profile", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }] },
  { id: "phone-memory", group: "手机", title: "记忆", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "Studio" }] },
  { id: "phone-memory-skill", group: "手机", title: "记忆 · 项目", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "Studio" }, { text: "acme-web" }] },
];
