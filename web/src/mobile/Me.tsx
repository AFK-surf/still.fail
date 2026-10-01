// The account on a narrow screen, as the Android app has it (apps/android/…/screens/Me.kt), from the card atop settings
// (./Settings.tsx): who is signed in, the accounts on this device, and where it is signed in.
import { signIn, signOut, useAccounts } from "../cloud/accounts.ts";
import { useApp } from "./app.tsx";
import { Avatar, Card, LargeTitle, ListCard, ListRow, SectionHeader, TopBack } from "./parts.tsx";
import { Devices } from "./WorkspacePage.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./Me.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as partsCss from "./styles/parts.css.ts";

export function MeScreen() {
  const app = useApp();
  const accounts = useAccounts() ?? [];
  const me = app.entry.account;
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label="设置" onBack={app.pop} />
      <LargeTitle small="" big="账号" />
      <Card>
        <span className={css.mMe}>
          <Avatar id={me.email} name={me.name || me.email} size={46} picture={me.picture} />
          <span><b>{me.name || me.email}</b><span className={listsCss.mRowNote}>{me.email} · Google</span></span>
        </span>
      </Card>
      {/* Accounts: signing out is per account, as on the web (with one account it is just 退出登录), and another can be added. */}
      <SectionHeader title="这台设备上的账号" start={24} />
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
      <SectionHeader title="登录的地方" start={24} />
      <Devices />
      <div style={{ height: 30 }} />
    </div>
  );
}
