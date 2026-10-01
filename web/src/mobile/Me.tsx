// The account on a narrow screen, as the Android app has it (apps/android/…/screens/Me.kt), from the card atop settings
// (./Settings.tsx): who is signed in, the accounts on this device, and where it is signed in.
import { useState } from "react";
import { signIn, signOut, useAccounts, type Account } from "../cloud/accounts.ts";
import { useDoing } from "../doing.ts";
import { useApp } from "./app.tsx";
import { Avatar, Card, LargeTitle, ListCard, ListRow, SectionHeader, Spinner, TopBack } from "./parts.tsx";
import { Devices } from "./WorkspacePage.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./Me.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as partsCss from "./styles/parts.css.ts";

export function MeScreen() {
  const app = useApp();
  const accounts = useAccounts() ?? [];
  const me = app.entry.account;
  // Signing in leaves the page for Google's once still.fail has said where: under way until then, or until it fails.
  const [signingIn, setSigningIn] = useState(false);
  const another = () => {
    setSigningIn(true);
    signIn().catch((e: unknown) => { setSigningIn(false); app.toast(`没能登录：${e instanceof Error ? e.message : String(e)}`); });
  };
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
        {accounts.map((a) => <AccountRow key={a.sub} a={a} only={accounts.length === 1} />)}
        <ListRow onClick={signingIn ? undefined : another}>
          <span className={`${partsCss.mAccent} ${listsCss.mRowTitle} ${partsCss.mGrow}`}>＋ 登录另一个 Google 账号</span>{signingIn && <Spinner size={14} />}
        </ListRow>
      </ListCard>
      <SectionHeader title="登录的地方" start={24} />
      <Devices />
      <div style={{ height: 30 }} />
    </div>
  );
}

/** An account on this device, signed out from its row (退出登录 when it is the only one); its spinner while that goes on. */
function AccountRow({ a, only }: { a: Account; only: boolean }) {
  const app = useApp();
  const out = useDoing("auth.signOut", { account: a.sub });
  return (
    <ListRow>
      <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{a.email}</span>
      <button type="button" className={css.mSignOut} disabled={out} aria-busy={out || undefined} onClick={() => {
        signOut(a.sub).then(() => { if (!only) app.toast(`已退出 ${a.email}`); app.home(); }, (e: unknown) => app.toast(`没能退出：${e instanceof Error ? e.message : String(e)}`));
      }}>{out && <Spinner size={13} />}{only ? "退出登录" : "退出"}</button>
    </ListRow>
  );
}
