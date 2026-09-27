// Connecting a Slack connect: create the app from ember's manifest, paste the two
// tokens, and see who they belong to before anything is saved.
import { CheckCircle, External } from "./icons.tsx";
import { useState } from "react";
import { useAction, useApi, type SlackIdentity } from "./api.ts";
import { Button, Field, ICON } from "./ui.tsx";

export function CreateAppSteps({ name }: { name: string }) {
  const api = useApi();
  const open = useAction(() => api.createAppUrl(name.trim() || "ember"), ({ url }) => window.open(url, "_blank", "noopener"));
  return (
    <ol className="steps">
      <li>
        <span>用 ember 的配置在 Slack 新建一个 app，名字是「{name.trim() || "ember"}」。</span>
        <Button icon={External} onClick={() => void open.run()} busy={open.busy}>在 Slack 创建 app</Button>
      </li>
      <li>在 app 的 Basic Information 页生成 App-Level Token（权限 Slack 已经勾好）。</li>
      <li>在 Install App 页安装到工作区，复制 Bot User OAuth Token。</li>
      <li>把两个 token 填在下面。</li>
    </ol>
  );
}

export interface TokenState {
  appToken: string;
  botToken: string;
  /** Who the tokens were verified as; null until verified, and reset by any edit. */
  verified: SlackIdentity | null;
}

export const emptyTokens: TokenState = { appToken: "", botToken: "", verified: null };

/**
 * Token inputs with a verify step. For an existing connect (`connect`), a blank field
 * means "keep the stored token", and verification uses the stored one. An app installed through Slack's OAuth
 * (`install`, its state) has its bot token on the station already: only the app-level token is asked for.
 */
export function TokenFields({ value, onChange, connect, masked, install }: {
  value: TokenState; onChange(value: TokenState): void; connect?: string; masked?: { appToken: string; botToken: string }; install?: string | undefined;
}) {
  const api = useApi();
  const [errors, setErrors] = useState<string[]>([]);
  const verify = useAction(() => api.verifySlack({ ...(connect ? { connect } : {}), ...(install ? { install } : {}), appToken: value.appToken, botToken: value.botToken }), (result) => {
    setErrors(result.errors);
    onChange({ ...value, verified: result.errors.length === 0 ? result.identity : null });
  });
  const edit = (patch: Partial<TokenState>) => {
    setErrors([]);
    onChange({ ...value, ...patch, verified: null });
  };
  const hasInput = Boolean(value.appToken || value.botToken || connect);
  return (
    <div className="token-fields">
      <Field label="App-Level Token" htmlFor="app-token">
        <input id="app-token" className="input mono" spellCheck={false} type="password" autoComplete="off" value={value.appToken}
          onChange={(e) => edit({ appToken: e.target.value.trim() })}
          placeholder={masked?.appToken ? `已保存 ${masked.appToken}，留空保持不变` : "xapp-…"} />
      </Field>
      {!install && (
        <Field label="Bot Token" htmlFor="bot-token">
          <input id="bot-token" className="input mono" spellCheck={false} type="password" autoComplete="off" value={value.botToken}
            onChange={(e) => edit({ botToken: e.target.value.trim() })}
            placeholder={masked?.botToken ? `已保存 ${masked.botToken}，留空保持不变` : "xoxb-…"} />
        </Field>
      )}
      <div className="verify-row">
        <Button onClick={() => void verify.run()} busy={verify.busy} disabled={!hasInput}>验证 token</Button>
        {value.verified && (
          <span className="verify-ok"><CheckCircle {...ICON} />连接到「{value.verified.team}」，bot 是 @{value.verified.botName}</span>
        )}
      </div>
      {errors.length > 0 && <ul className="field-error-list" role="alert">{errors.map((e) => <li key={e}>{e}</li>)}</ul>}
      {verify.error && <p className="field-error" role="alert">{verify.error.message}</p>}
    </div>
  );
}
