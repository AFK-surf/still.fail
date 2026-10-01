// Settings on a narrow screen, one page from the gear on Home (as the Android app has it, apps/android/…/screens/
// SettingsHome.kt): who is signed in, then the workspace's (its people, stations, connects, profiles, memory), then this
// device's (how it looks, whether it notifies). Each row says how things stand at its end, what is wrong in red, so the
// page is worth a look before anything is opened.
import { useState, type ReactNode } from "react";
import { useDoing } from "../doing.ts";
import { useStations, useConnects } from "../api.ts";
import { useWorkspace } from "../cloud/api.ts";
import { ROLE_LABEL } from "../cloud/settings.tsx";
import { ChevronRight } from "../icons.tsx";
import { useAppearance, type Appearance } from "../theme.ts";
import { CAN_NOTIFY, setNotify, useNotifyState } from "../notify.ts";
import { useApp } from "./app.tsx";
import { useChangelog } from "../changelog.ts";
import { Presence } from "./Connects.tsx";
import { quotaTrouble } from "./Profiles.tsx";
import { Avatar, Card, LargeTitle, ListCard, ListRow, SectionHeader, Seg, Spinner, TopBack } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as connectsCss from "./Connects.css.ts";
import * as css from "./Settings.css.ts";

export const THEMES: [Appearance, string][] = [["system", "跟随系统"], ["light", "浅色"], ["dark", "深色"]];

/** A row that opens a page: its name, how things stand (`bad` in red), a chevron. */
export function GoRow({ title, value, bad = false, lead, onClick }: { title: string; value?: ReactNode; bad?: boolean; lead?: ReactNode; onClick: () => void }) {
  return (
    <ListRow onClick={onClick}>
      {lead}
      <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{title}</span>
      {value !== undefined && <span className={`${css.mValue} ${bad ? partsCss.mRed : ""}`}>{value}</span>}
      <ChevronRight size={14} className={partsCss.mSubtle} />
    </ListRow>
  );
}

export function SettingsScreen() {
  const app = useApp();
  const me = app.entry.account;
  const view = useWorkspace(app.entry.id).value;
  const stations = useStations(app.entry.id).value;
  const connects = useConnects(app.entry.id).value;
  const [appearance] = useAppearance();
  const build = useChangelog().value?.build;
  const manager = view?.role === "owner" || view?.role === "admin";
  const waiting = view ? view.added.length + view.invitations.length : 0;
  const online = stations?.filter((s) => s.online).length ?? 0;
  const troubled = stations?.some((s) => !s.online) ?? false;
  const failing = connects?.items.filter((i) => i.connect.presence === "error").length ?? 0;
  const profiles = stations?.flatMap((s) => s.overview?.profiles ?? []) ?? [];
  const short = profiles.filter((p) => p.checkTone === "red" || quotaTrouble(p.quota)).length;
  const at = (path: string) => () => app.push(app.at(path));
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label="会话" onBack={app.pop} />
      <LargeTitle small="" big="设置" />
      <Card onClick={at("/settings/account")}>
        <span className={css.mMe}>
          <Avatar id={me.email} name={me.name || me.email} size={46} picture={me.picture} />
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><b>{me.name || me.email}</b><span className={listsCss.mRowNote}>{me.email}</span></span>
          <ChevronRight size={14} className={partsCss.mSubtle} />
        </span>
      </Card>
      <SectionHeader title={view ? `${view.name} · 你是${ROLE_LABEL[view.role]}` : app.entry.name} start={24} />
      <ListCard>
        <GoRow title="Workspace" value={view ? `${view.members.length} 人${manager && waiting ? ` · ${waiting} 人待加入` : ""}` : undefined} onClick={at("/settings/workspace")} />
        <GoRow title="Station" value={stations ? <>{troubled && <Presence state="error" />}{online}/{stations.length} 在线</> : undefined} onClick={at("/settings/stations")} />
        <GoRow title="连接" bad={failing > 0} value={connects ? (failing ? `${failing} 个出错` : `${connects.items.length} 个`) : undefined} onClick={at("/settings/connects")} />
        <GoRow title="Profile" bad={short > 0} value={stations ? (short ? `${short} 个要处理` : `${profiles.length} 个`) : undefined} onClick={at("/settings/profiles")} />
        <GoRow title="记忆" onClick={at("/settings/memory")} />
        <GoRow title="用量" onClick={at("/settings/usage")} />
      </ListCard>
      <SectionHeader title="这台设备" start={24} />
      <ListCard>
        <GoRow title="外观" value={THEMES.find(([v]) => v === appearance)?.[1]} onClick={at("/settings/appearance")} />
        <Notify />
        <GoRow title="更新日志" value={build != null ? `0.1.${build}` : undefined} onClick={at("/settings/changelog")} />
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}

/** Whether this browser tells about the chats (notify.ts). */
function Notify() {
  const app = useApp();
  const state = useNotifyState();
  // What was asked shows at once, with a spinner, while the browser asks for leave and the core answers (`notify.set`);
  // then how it is, and a word if that is not what was asked.
  const [asked, setAsked] = useState<boolean | null>(null);
  const setting = useDoing("notify.set");
  if (!CAN_NOTIFY) return null;
  const busy = asked !== null || setting;
  const on = asked ?? state === "on";
  const note = state === "denied" ? "浏览器拦下了通知，要在浏览器的网站设置里打开" : "做完、要处理、出错、有人说话时提醒你";
  return (
    <ListRow onClick={busy ? undefined : () => {
      if (state === "denied" || state === "unsupported") return;
      const want = state !== "on";
      setAsked(want);
      setNotify(want).then((now) => {
        if (now === "denied") app.toast("浏览器没有允许通知");
        else if ((now === "on") !== want) app.toast(`没能${want ? "打开" : "关掉"}通知`);
      }, (e: unknown) => app.toast(`没能${want ? "打开" : "关掉"}通知：${e instanceof Error ? e.message : String(e)}`)).finally(() => setAsked(null));
    }}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>通知</span>
        <span className={listsCss.mRowNote}>{note}</span>
      </span>
      {busy && <Spinner size={14} />}
      <span className={connectsCss.mSwitch} data-on={on || undefined} />
    </ListRow>
  );
}

/** How this device shows still.fail: its theme. */
export function AppearanceScreen() {
  const app = useApp();
  const [appearance, setAppearance] = useAppearance();
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label="设置" onBack={app.pop} />
      <LargeTitle small="" big="外观" />
      <SectionHeader title="主题" start={24} />
      <div style={{ padding: "0 12px" }}>
        <Seg options={THEMES.map(([, label]) => label)} selected={Math.max(0, THEMES.findIndex(([v]) => v === appearance))}
          onSelect={(i) => setAppearance(THEMES[i]![0])} height={34} fill />
      </div>
      <div style={{ height: 30 }} />
    </div>
  );
}
