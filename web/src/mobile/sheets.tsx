import { useAction } from "../action.ts";
// Sheets that ask something of the viewer, as the Android app's do: whether to go on with what cannot be undone, a
// name, a command to copy.
import { useState, type ReactNode } from "react";
import { Check, Copy } from "../icons.tsx";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { Button, Field } from "./parts.tsx";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as css from "./sheets.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import { t } from "../i18n.ts";

/** Asks before something that cannot be undone; the sheet stays, with what went wrong, until it is done. */
export function confirm(app: MobileApp, spec: { title: string; text: ReactNode; action: string; danger?: boolean; run: () => Promise<unknown> }) {
  app.sheet({ height: 0.36, content: () => <Confirm {...spec} /> });
}

function Confirm({ title, text, action, danger = false, run }: { title: string; text: ReactNode; action: string; danger?: boolean; run: () => Promise<unknown> }) {
  const app = useApp();
  const operation = useAction(run, () => app.sheet(null));
  const { busy } = operation;
  const error = operation.error?.message;
  return (
    <>
      <SheetGrab />
      <SheetHead title={title} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={partsCss.mMuted}>{text}</p>
        {error && <p className={partsCss.mError}>{error}</p>}
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <span data-danger={danger || undefined} className={css.mDangerButton}>
            <Button label={action} primary busy={busy} onClick={() => {
              void operation.run();
            }} />
          </span>
        </div>
      </div>
    </>
  );
}

/** Asks for a line (a name); `run` gets it trimmed. `empty`: an empty line may be given too. */
export function ask(app: MobileApp, spec: { title: string; value: string; placeholder: string; action: string; hint?: string; secret?: boolean; empty?: boolean; run: (value: string) => Promise<unknown> }) {
  app.sheet({ height: 0.42, content: () => <Ask {...spec} /> });
}

function Ask({ title, value: first, placeholder, action, hint, secret = false, empty = false, run }: { title: string; value: string; placeholder: string; action: string; hint?: string; secret?: boolean; empty?: boolean; run: (value: string) => Promise<unknown> }) {
  const app = useApp();
  const [value, setValue] = useState(first);
  const operation = useAction(run, () => app.sheet(null));
  const { busy } = operation;
  const error = operation.error?.message;
  const go = () => {
    void operation.run(value.trim());
  };
  return (
    <>
      <SheetGrab />
      <SheetHead title={title} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        {secret
          ? <input className={listsCss.mField} data-mono type="password" autoComplete="off" spellCheck={false} value={value} placeholder={placeholder} onChange={(e) => setValue(e.target.value.trim())} />
          : <Field value={value} onChange={setValue} placeholder={placeholder} />}
        {hint && <p className={`${partsCss.mSmall} ${partsCss.mMuted}`}>{hint}</p>}
        {error && <p className={partsCss.mError}>{error}</p>}
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={action} primary busy={busy} enabled={(empty || !!value.trim()) && value.trim() !== first} onClick={go} />
        </div>
      </div>
    </>
  );
}

/** A command to run elsewhere, with a button that copies it. */
export function CommandBox({ text }: { text: string }) {
  const app = useApp();
  const [copied, setCopied] = useState(false);
  return (
    <div className={css.mCommand}>
      <code>{text}</code>
      <button type="button" aria-label={copied ? t("common.copied") : t("common.copy")} onClick={() => void navigator.clipboard.writeText(text).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1600); }, () => app.toast(t("web-mobile.sheets.copyFailed")))}>
        {copied ? <Check size={16} /> : <Copy size={16} />}
      </button>
    </div>
  );
}
