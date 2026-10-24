// A tool call in the execution history, drawn by what it is rather than as its arguments' JSON: a command as a command,
// an edit as a diff, a file written as highlighted code, a plan as a list; anything else as its fields, one to a row.
// What each call and result is, read into parts, is the core's (client/core-ts/src/tool-step.ts); here they are drawn.
import type { ReactNode } from "react";
import { Code, Prose } from "./Prose.tsx";
import * as css from "./ToolStep.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import { t } from "./i18n.ts";
import { toolCall, toolResult, type ToolPart } from "../../client/core-ts/src/tool-step.ts";

function Lines({ rows }: { rows: [string, string][] }) {
  return (
    <pre className={css.diff}>
      {rows.map(([mark, text], i) => <div key={i} className={css.diffLine} data-mark={mark === " " ? undefined : mark}>{text || " "}</div>)}
    </pre>
  );
}

/** One part, as it is drawn. */
function Part({ part }: { part: ToolPart }): ReactNode {
  switch (part.kind) {
    case "code": return <div className={`${css.block} ${conversationCss.markdown}`}><Code text={part.text} language={part.lang} /></div>;
    case "facts":
      return (
        <div className={css.facts}>
          {part.items.map((f) => <span key={f.key} className={css.fact}>{f.plain || f.value === undefined ? f.key : <>{f.key} <b>{f.value}</b></>}</span>)}
        </div>
      );
    case "path": return <div className={css.path}><span>{part.path}</span>{part.extra && <span className={css.pathExtra}>{part.extra}</span>}</div>;
    case "diff": return <Lines rows={part.rows} />;
    case "markdown": return <div className={`${css.prose} ${conversationCss.markdown}`}><Prose>{part.text}</Prose></div>;
    case "plan":
      return (
        <ul className={css.plan}>
          {part.items.map((it, i) => (
            <li key={i} data-status={it.status}><span className={css.planMark} aria-hidden="true">{it.status === "completed" ? "✓" : it.status === "in_progress" ? "›" : "·"}</span>{it.text}</li>
          ))}
        </ul>
      );
    case "fields":
      return (
        <dl className={css.fields}>
          {part.rows.map((r) => (
            <div key={r.key} className={css.field}>
              <dt>{r.key}</dt>
              <dd>{r.form === "long" ? <div className={css.long}>{r.value}</div> : r.form === "json" ? <pre className={css.json}>{r.value}</pre> : <span className={css.value}>{r.value}</span>}</dd>
            </div>
          ))}
        </dl>
      );
    case "lead": return <div className={css.lead}>{part.text}</div>;
    case "none": return <div className={css.none}>{part.text}</div>;
    case "output": return <pre className={css.output}>{part.text}</pre>;
    case "json": return <pre className={css.json}>{part.text}</pre>;
  }
}

/** What a call asked for. `said`: its description already shows as the step's name. */
export function ToolCall({ name, call, said }: { name: string; call: string; said: boolean }) {
  const parts = toolCall(name, call, said, t);
  return parts.length ? <>{parts.map((p, i) => <Part key={i} part={p} />)}</> : null;
}

/** What a call gave back. */
export function ToolResult({ name, call, result, failed }: { name: string; call: string; result: string; failed: boolean }) {
  const parts = toolResult(name, call, result, failed, t);
  // (nothing came back: said alone, outside the result's block)
  if (parts.length === 1 && parts[0]?.kind === "none") return <Part part={parts[0]} />;
  const red = parts.some((p) => p.kind === "output" && p.failed);
  return <div className={css.result} data-failed={red || undefined}>{parts.map((p, i) => <Part key={i} part={p} />)}</div>;
}
