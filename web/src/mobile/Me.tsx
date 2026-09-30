// You, on a narrow screen, as the Android app has it (apps/android/…/screens/Me.kt): who is signed in, which accounts
// and how it looks (workspaces are switched from their name on Home, ./Workspaces.tsx).
import { useRowPicture, type RowPicture } from "../rowLead.ts";
import { signIn, signOut, useAccounts } from "../cloud/accounts.ts";
import { useAppearance, type Appearance } from "../theme.ts";
import { CAN_NOTIFY, setNotify, useNotifyState } from "../notify.ts";
import { useApp } from "./app.tsx";
import { Avatar, Card, LargeTitle, ListCard, ListRow, SectionHeader, Seg, TopBack } from "./parts.tsx";
import { Devices } from "./WorkspacePage.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./Me.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as connectsCss from "./Connects.css.ts";

const THEMES: [Appearance, string][] = [["system", "跟随系统"], ["light", "浅色"], ["dark", "深色"]];
/** Whose pictures lead a chat's row (../rowLead.ts). */
const PICTURES: [RowPicture, string][] = [["auto", "自动"], ["agents", "Agent 为主"], ["people", "人为主"]];

export function MeScreen() {
  const app = useApp();
  const accounts = useAccounts() ?? [];
  const [appearance, setAppearance] = useAppearance();
  const [picture, setPicture] = useRowPicture();
  const me = app.entry.account;
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label="会话" onBack={app.pop} />
      <LargeTitle small="设置" big="我" />
      <Card>
        <span className={css.mMe}>
          <Avatar id={me.email} name={me.name || me.email} size={46} picture={me.picture} />
          <span><b>{me.name || me.email}</b><span className={listsCss.mRowNote}>{me.email} · Google</span></span>
        </span>
      </Card>
      <SectionHeader title="外观" start={24} />
      <div className={`${css.mPadX12} ${css.mSegBlock}`}>
        <Seg options={THEMES.map(([, label]) => label)} selected={Math.max(0, THEMES.findIndex(([v]) => v === appearance))} onSelect={(i) => setAppearance(THEMES[i]![0])} height={36} fill />
      </div>
      <SectionHeader title="列表头像" start={24} />
      <div className={`${css.mPadX12} ${css.mSegBlock}`}>
        <Seg options={PICTURES.map(([, label]) => label)} selected={Math.max(0, PICTURES.findIndex(([v]) => v === picture))} onSelect={(i) => setPicture(PICTURES[i]![0])} height={36} fill />
      </div>
      <Notify />
      <SectionHeader title="登录的地方" start={24} />
      <Devices />
      {/* Accounts: signing out is per account, as on the web (with one account it is just 退出登录), and another can be added. */}
      <SectionHeader title="账号" start={24} />
      <ListCard>
        {accounts.map((a) => (
          <ListRow key={a.sub}>
            <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{a.email}</span>
            <button type="button" className={css.mSignOut} onClick={() => {
              signOut(a.sub).then(() => { if (accounts.length > 1) app.toast(`已退出 ${a.email}`); app.home(); }, (e: unknown) => app.toast(`没能退出：${e instanceof Error ? e.message : String(e)}`));
            }}>{accounts.length > 1 ? "退出" : "退出登录"}</button>
          </ListRow>
        ))}
        <ListRow onClick={() => void signIn()}><span className={`${partsCss.mAccent} ${listsCss.mRowTitle}`}>＋ 登录另一个 Google 账号</span></ListRow>
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
  const note = state === "denied" ? "浏览器拦下了通知，要在浏览器的网站设置里打开" : "agent 做完、需要处理、出错，或者有人说话时提醒你";
  return (
    <>
      <SectionHeader title="通知" start={24} />
      <ListCard>
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
      </ListCard>
    </>
  );
}
