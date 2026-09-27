// Signing in on a narrow screen, as the Android app has it (apps/android/…/screens/SignIn.kt).
import { useState } from "react";
import { signIn } from "../cloud/accounts.ts";
import { Illustration } from "./parts.tsx";
import "./mobile.css";

export function MobileSignIn() {
  const [busy, setBusy] = useState(false);
  return (
    <div className="m m-sign-in">
      <Illustration name="sign-in" width={300} />
      <h1>让 agent 一直在干活</h1>
      <p>登录后，你所在 workspace 的所有 station 和会话都会出现在这里。</p>
      <button type="button" className="m-google" disabled={busy} onClick={() => { setBusy(true); void signIn().finally(() => setBusy(false)); }}>
        <GoogleDot />{busy ? "正在打开…" : "用 Google 登录"}
      </button>
      <small>多个账号可以都登录，随时切换 workspace。</small>
    </div>
  );
}

function GoogleDot() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
      <path d="M9 9 L9 0 A9 9 0 0 1 18 9 Z" fill="#EA4335" />
      <path d="M9 9 L18 9 A9 9 0 0 1 9 18 Z" fill="#FBBC05" />
      <path d="M9 9 L9 18 A9 9 0 0 1 0 9 Z" fill="#34A853" />
      <path d="M9 9 L0 9 A9 9 0 0 1 9 0 Z" fill="#4285F4" />
    </svg>
  );
}
