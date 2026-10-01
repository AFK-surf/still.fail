// Connecting a Slack connect: create the app from ember's manifest, paste the two
// tokens, and see who they belong to before anything is saved.
import { CheckCircle, External } from "./icons.tsx";
import { useEffect, useState } from "react";
import { useCall, useTopic } from "./core/react.ts";
import { useStation } from "./station.tsx";
import { useDoing } from "./doing.ts";
import type { SlackTokenForm, SlackTokensView } from "./core/shapes.ts";
import { useAction, useApi, type SlackIdentity } from "./api.ts";
import { Button, Field, ICON } from "./ui.tsx";
import * as controlsCss from "./styles/controls.css.ts";
import * as css from "./slack.css.ts";
import * as shellCss from "./styles/shell.css.ts";

import { NAME } from "./channel.ts";
export function CreateAppSteps({ name }: { name: string }) {
  const api = useApi();
  const open = useAction(() => api.createAppUrl(name.trim() || NAME), ({ url }) => window.open(url, "_blank", "noopener"));
  return (
    <ol className={controlsCss.steps}>
      <li>
        <span>用 {NAME} 的配置在 Slack 新建一个 app，名字是「{name.trim() || NAME}」。</span>
        <Button icon={External} onClick={() => void open.run()} busy={open.busy}>在 Slack 创建 app</Button>
        {open.error && <p className={controlsCss.fieldError} role="alert">没能打开 Slack：{open.error.message}</p>}
      </li>
      <li>在 app 的 Socket Mode 页生成 App-Level Token（权限已经选好）。</li>
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

/** Checking tokens as the button that goes on is pressed: `then(go)` verifies (unless already verified) and goes on if they are right. */
export interface TokenCheck {
  then(go: () => void): void;
  busy: boolean;
  errors: string[];
  error: string | null;
  /** There is something to check (or, for an existing connect, the stored tokens). */
  ready: boolean;
}

/**
 * The tokens' check. For an existing connect (`connect`), a blank field means "keep the stored token", and the check
 * uses the stored one. An app installed through Slack's OAuth (`install`, its state) has its bot token on the station.
 */
export function useTokenCheck(value: TokenState, onChange: (value: TokenState) => void, { connect, install }: { connect?: string | undefined; install?: string | undefined } = {}): TokenCheck {
  const api = useApi();
  const [errors, setErrors] = useState<string[]>([]);
  const verify = useAction(() => api.verifySlack({ ...(connect ? { connect } : {}), ...(install ? { install } : {}), appToken: value.appToken, botToken: value.botToken }));
  return {
    then(go) {
      if (value.verified) return go();
      void verify.run().then((result) => {
        if (!result) return;
        setErrors(result.errors);
        if (result.errors.length === 0) {
          onChange({ ...value, verified: result.identity });
          go();
        }
      });
    },
    busy: verify.busy,
    errors: value.verified ? [] : errors,
    error: verify.error?.message ?? null,
    ready: Boolean(value.appToken || (!install && value.botToken) || connect),
  };
}

/** The current core owns the draft and its verification. Older desktop cores keep the previous form until updated. */
export function useSlackTokens({ connect, install, form: sharedForm }: { connect?: string | undefined; install?: string | undefined; form?: string } = {}): [TokenState, (patch: Partial<TokenState>) => void, TokenCheck] {
  const station = useStation().address;
  const [ownForm] = useState(() => crypto.randomUUID());
  const form = sharedForm ?? ownForm;
  const call = useCall();
  const address: SlackTokenForm = { station, form };
  const topic = useTopic<SlackTokensView>({ topic: "slackTokens", ...address });
  const [legacyValue, legacySet] = useState<TokenState>(emptyTokens);
  const legacy = useTokenCheck(legacyValue, legacySet, { connect, install });
  const [error, setError] = useState<string | null>(null);
  const [oldCore, setOldCore] = useState(false);
  const busy = useDoing("slack.tokens.verify", { station, form });
  const edit = (input: Record<string, unknown>) => call("slack.tokens.edit", { ...address, input });
  useEffect(() => {
    void edit({ connect: connect ?? null, install: install ?? null }).catch((e: Error & { code?: string }) => {
      if (e.code === "unknown_call") setOldCore(true);
      else setError(e.message);
    });
  }, [station, form, connect, install, call]);
  useEffect(() => () => { void call("slack.tokens.drop", { station, form }).catch(() => undefined); }, [station, form, call]);
  const echo = (patch: Partial<TokenState>) => legacySet((value) => ({ ...value, ...patch, verified: null }));
  if (oldCore) return [legacyValue, echo, legacy];
  // Echo keystrokes immediately in controlled inputs while the worker publishes the authoritative draft.
  const current = topic.value?.appToken === legacyValue.appToken && topic.value?.botToken === legacyValue.botToken;
  const value = { ...legacyValue, verified: current ? topic.value?.verified ?? null : null };
  return [value, (patch) => {
    echo(patch);
    setError(null);
    void edit({ ...patch, ...(patch.verified === null ? { clear: true } : {}) }).catch((e: Error) => setError(e.message));
  }, {
    then(go) {
      if (busy) return;
      setError(null);
      void call("slack.tokens.verify", address).then((verified) => { if (verified) go(); }, (e: Error) => setError(e.message));
    },
    busy, errors: topic.value?.errors ?? [], error: error ?? topic.error?.message ?? null, ready: topic.value?.ready ?? false,
  }];
}

/** Token inputs; checked by the button that goes on (`check`, useTokenCheck), whose failures are said under them. */
export function TokenFields({ value, onChange, masked, install, check }: {
  value: TokenState; onChange(value: Partial<TokenState>): void; masked?: { appToken: string; botToken: string }; install?: string | undefined; check: TokenCheck;
}) {
  const edit = (patch: Partial<TokenState>) => onChange(patch);
  return (
    <div className={css.tokenFields}>
      <Field label="App-Level Token" htmlFor="app-token">
        <input id="app-token" className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} type="password" autoComplete="off" value={value.appToken}
          onChange={(e) => edit({ appToken: e.target.value.trim() })}
          placeholder={masked?.appToken ? `已保存 ${masked.appToken}，留空保持不变` : "xapp-…"} />
      </Field>
      {!install && (
        <Field label="Bot Token" htmlFor="bot-token">
          <input id="bot-token" className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} type="password" autoComplete="off" value={value.botToken}
            onChange={(e) => edit({ botToken: e.target.value.trim() })}
            placeholder={masked?.botToken ? `已保存 ${masked.botToken}，留空保持不变` : "xoxb-…"} />
        </Field>
      )}
      {value.verified && <span className={controlsCss.verifyOk}><CheckCircle {...ICON} />连接到「{value.verified.team}」，bot 是 @{value.verified.botName}</span>}
      {check.errors.length > 0 && <ul className={css.fieldErrorList} role="alert">{check.errors.map((e) => <li key={e}>{e}</li>)}</ul>}
      {check.error && <p className={controlsCss.fieldError} role="alert">{check.error}</p>}
    </div>
  );
}
