// Pieces shared by ember cloud's pages: people's avatars and the sign-in page.
import { useState, type ReactNode } from "react";
import { Button } from "../ui.tsx";
import { signIn } from "./accounts.ts";
import { Illustration } from "../brand.tsx";

export function Avatar({ account, size = 24 }: { account: { name: string; email: string; picture: string }; size?: number }) {
  const letter = ([...(account.name || account.email)][0] ?? "?").toUpperCase();
  const [broken, setBroken] = useState(false);
  return account.picture && !broken
    ? <img className="person" src={account.picture} alt="" width={size} height={size} referrerPolicy="no-referrer" onError={() => setBroken(true)} />
    : <span className="person person-letter" style={{ width: size, height: size, fontSize: size * .45 }} aria-hidden="true">{letter}</span>;
}

export function SignInPage({ lead }: { lead?: ReactNode }) {
  return (
    <div className="gate sign-in-page">
      <Illustration name="sign-in" />
      <h1>登录 ember</h1>
      <p>{lead ?? "用 Google 账号登录，管理你的 workspace 和里面的 station。"}</p>
      <Button variant="primary" onClick={() => void signIn()}>使用 Google 账号登录</Button>
    </div>
  );
}
