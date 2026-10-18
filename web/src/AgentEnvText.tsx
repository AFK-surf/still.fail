// A station's variables for its agents as written (docs/agent-env.md): a .env file's lines in a field, coloured as the
// core reads them (name, value, comment), a line it cannot take in red and what is wrong said under the field. The
// core keeps the draft (agentEnvForm) and saves it; both layouts (cloud/StationPage.tsx, mobile/Stations.tsx) show it.
import { Fragment, useEffect, useId, useState } from "react";
import { useCall, useTopic } from "./core/react.ts";
import type { AgentEnvDraft } from "./core/shapes.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { useDoing } from "./doing.ts";
import { t } from "./i18n.ts";
import * as css from "./AgentEnvText.css.ts";

const PLACEHOLDER = "HTTPS_PROXY=http://127.0.0.1:7890\nNO_PROXY=localhost,.internal";

/** The core's draft of a station's variables, opened while the page shows it; what is typed shown at once. */
export function useAgentEnvForm(station: string) {
  const form = useId();
  const call = useCall();
  const act = useAct();
  useEffect(() => {
    act(call("agentEnv.form.open", { station, form }), t("web-pages.stations.agentEnvRead"));
    return () => { act(call("agentEnv.form.drop", { station, form }), t("web-pages.stations.agentEnvClose")); };
  }, [call, station, form, act]);
  const d = useTopic<AgentEnvDraft | null>({ topic: "agentEnvForm", station, form }).value ?? null;
  // What was typed, until the core has it (the field never waits on it).
  const [typed, setTyped] = useState<string | null>(null);
  useEffect(() => { if (typed !== null && d?.text === typed) setTyped(null); }, [d?.text, typed]);
  const saving = useDoing("agentEnv.form.save", { station, form });
  const text = typed ?? d?.text ?? "";
  const edit = (next: string) => {
    setTyped(next);
    act(call("agentEnv.form.edit", { station, form, input: { text: next } }), t("web-pages.stations.agentEnvEdit"));
  };
  const reset = () => { setTyped(null); act(call("agentEnv.form.edit", { station, form, input: { reset: true } }), t("web-pages.stations.agentEnvEdit")); };
  const save = () => act(call("agentEnv.form.save", { station, form }), t("web-pages.stations.agentEnvSave"), t("web-pages.profiles.saved"));
  // Read as it is now: the core's lines once it has what is shown.
  const read = d && d.text === text ? d : null;
  const canSave = !!d && d.dirty && !d.pending && !saving && read !== null && read.errors === 0;
  return { d, text, read, edit, reset, save, saving, canSave };
}

/** The field, coloured, and what is wrong under it. `fieldClass`: the layout's field (its box, border and ground). */
export function AgentEnvText({ form, fieldClass, label }: { form: ReturnType<typeof useAgentEnvForm>; fieldClass: string; label: string }) {
  const { text, read } = form;
  const problems = read?.lines.flatMap((l, i) => (l.problem ? [{ n: i + 1, problem: l.problem, error: l.error }] : [])) ?? [];
  return (
    <>
      <div className={css.stack}>
        <pre className={`${fieldClass} ${css.colours}`} aria-hidden>
          {read ? read.lines.map((l, i) => (
            <Fragment key={i}>
              {i > 0 && "\n"}
              {l.parts.map((p, j) => <span key={j} className={l.error ? css.wrong : (css[p.kind as "name" | "value" | "comment" | "other"] ?? css.other)}>{p.text}</span>)}
            </Fragment>
          )) : text}
          {/* Room for a last line that is empty. */}
          {"\n "}
        </pre>
        <textarea className={`${fieldClass} ${css.field}`} spellCheck={false} autoCapitalize="off" autoComplete="off" autoCorrect="off" aria-label={label}
          value={text} placeholder={PLACEHOLDER} onChange={(e) => form.edit(e.target.value)} />
      </div>
      {problems.length > 0 && (
        <ul className={css.problems}>
          {problems.map((p) => <li key={p.n} className={css.problem} data-error={p.error || undefined}>{t("web-pages.stations.agentEnvLine", { line: p.n, problem: p.problem })}</li>)}
        </ul>
      )}
    </>
  );
}
