// You, on a narrow screen, as the Android app has it (apps/android/…/screens/Me.kt): who is signed in, which accounts
// and workspaces, how it looks.
import { signIn, signOut, useAccounts } from "../cloud/accounts.ts";
import { useWorkspaces } from "../cloud/api.ts";
import { Check } from "../icons.tsx";
import { useAppearance, type Appearance } from "../theme.ts";
import { useApp } from "./app.tsx";
import { Avatar, Card, LargeTitle, ListCard, ListRow, SectionHeader, Seg, TopBack } from "./parts.tsx";

const THEMES: [Appearance, string][] = [["system", "跟随系统"], ["light", "浅色"], ["dark", "深色"]];

export function MeScreen() {
  const app = useApp();
  const accounts = useAccounts() ?? [];
  const workspaces = useWorkspaces().value ?? [];
  const [appearance, setAppearance] = useAppearance();
  const me = app.entry.account;
  return (
    <div className="m-screen m-scroll">
      <TopBack label="会话" onBack={app.pop} />
      <LargeTitle small="设置" big="我" />
      <Card>
        <span className="m-me">
          <Avatar id={me.email} name={me.name || me.email} size={46} picture={me.picture} />
          <span><b>{me.name || me.email}</b><span className="m-row-note">{me.email} · Google</span></span>
        </span>
      </Card>
      {/* One line per workspace: the name gives way with an ellipsis; which account it is under shows only when there are several. */}
      <SectionHeader title="Workspace" start={24} />
      <ListCard>
        {workspaces.flatMap((a) => a.workspaces.map((w) => (
          <ListRow key={`${a.account.sub}/${w.id}`} onClick={() => app.replace(`/w/${w.id}`)}>
            <span className="m-grow m-row-text"><span className="m-row-title">{w.name}</span>{accounts.length > 1 && <span className="m-row-note">{a.account.email}</span>}</span>
            {w.id === app.entry.id && <Check size={14} className="m-accent" />}
          </ListRow>
        )))}
      </ListCard>
      <SectionHeader title="外观" start={24} />
      <div className="m-pad-x-12 m-seg-block">
        <Seg options={THEMES.map(([, label]) => label)} selected={Math.max(0, THEMES.findIndex(([v]) => v === appearance))} onSelect={(i) => setAppearance(THEMES[i]![0])} height={36} fill />
      </div>
      {/* Accounts: signing out is per account, as on the web (with one account it is just 退出登录), and another can be added. */}
      <SectionHeader title="账号" start={24} />
      <ListCard>
        {accounts.map((a) => (
          <ListRow key={a.sub}>
            <span className="m-grow m-row-title">{a.email}</span>
            <button type="button" className="m-sign-out" onClick={() => {
              signOut(a.sub).then(() => { if (accounts.length > 1) app.toast(`已退出 ${a.email}`); app.home(); }, (e: unknown) => app.toast(`没能退出：${e instanceof Error ? e.message : String(e)}`));
            }}>{accounts.length > 1 ? "退出" : "退出登录"}</button>
          </ListRow>
        ))}
        <ListRow onClick={() => void signIn()}><span className="m-accent m-row-title">＋ 登录另一个 Google 账号</span></ListRow>
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}
