// Settings on a narrow screen, one page from the gear on Home (as the Android app has it, apps/android/…/screens/
// SettingsHome.kt): who is signed in, then the workspace's (its people, stations, connects, profiles, memory), then this
// device's (how it looks, whether it notifies). Each row says how things stand at its end, what is wrong in red, so the
// page is worth a look before anything is opened.
import type { ReactNode } from "react";
import { useStations, useConnects } from "../api.ts";
import { useWorkspace } from "../cloud/api.ts";
import { ROLE_LABEL } from "../cloud/settings.tsx";
import { Check, ChevronRight } from "../icons.tsx";
import { useRowPicture, type RowPicture } from "../rowLead.ts";
import { useAppearance, type Appearance } from "../theme.ts";
import { CAN_NOTIFY, setNotify, useNotifyState } from "../notify.ts";
import { useApp } from "./app.tsx";
import { Presence } from "./Connects.tsx";
import { quotaTrouble } from "./Profiles.tsx";
import { Avatar, Card, LargeTitle, ListCard, ListRow, SectionHeader, TopBack } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as connectsCss from "./Connects.css.ts";
import * as css from "./Settings.css.ts";

export const THEMES: [Appearance, string][] = [["system", "跟随系统"], ["light", "浅色"], ["dark", "深色"]];
/** Whose pictures lead a chat's row (../rowLead.ts). */
export const PICTURES: [RowPicture, string, string][] = [
  ["auto", "自动", "有人参与时显示人，否则显示 agent"],
  ["agents", "Agent 为主", "总是显示回话的 agent"],
  ["people", "人为主", "总是显示发起的人"],
];

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
      </ListCard>
      <SectionHeader title="这台设备" start={24} />
      <ListCard>
        <GoRow title="外观" value={THEMES.find(([v]) => v === appearance)?.[1]} onClick={at("/settings/appearance")} />
        <Notify />
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}

/** Whether this browser tells about the chats (notify.ts). */
function Notify() {
  const app = useApp();
  const state = useNotifyState();
  if (!CAN_NOTIFY) return null;
  const note = state === "denied" ? "浏览器拦下了通知，要在浏览器的网站设置里打开" : "做完、要处理、出错、有人说话时提醒你";
  return (
    <ListRow onClick={() => {
      if (state === "denied" || state === "unsupported") return;
      void setNotify(state !== "on").then((now) => { if (now === "denied") app.toast("浏览器没有允许通知"); });
    }}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>通知</span>
        <span className={listsCss.mRowNote}>{note}</span>
      </span>
      <span className={connectsCss.mSwitch} data-on={state === "on" || undefined} />
    </ListRow>
  );
}

/** How this device shows still.fail: its theme, and whose pictures lead a chat's row. */
export function AppearanceScreen() {
  const app = useApp();
  const [appearance, setAppearance] = useAppearance();
  const [picture, setPicture] = useRowPicture();
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label="设置" onBack={app.pop} />
      <LargeTitle small="" big="外观" />
      <SectionHeader title="主题" start={24} />
      <ListCard>
        {THEMES.map(([v, label]) => <CheckRow key={v} title={label} on={appearance === v} onClick={() => setAppearance(v)} />)}
      </ListCard>
      <SectionHeader title="会话列表的头像" start={24} />
      <ListCard>
        {PICTURES.map(([v, label, note]) => <CheckRow key={v} title={label} note={note} on={picture === v} onClick={() => setPicture(v)} />)}
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}

function CheckRow({ title, note, on, onClick }: { title: string; note?: string; on: boolean; onClick: () => void }) {
  return (
    <ListRow onClick={onClick}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{title}</span>
        {note && <span className={listsCss.mRowNote}>{note}</span>}
      </span>
      {on && <Check size={18} className={css.mCheck} />}
    </ListRow>
  );
}
