// An agent's checklist as its transcript says it: the calls of the tools it keeps one with, read in order. A tool that
// says the list whole replaces it (Claude Code's TodoWrite, `todos: [{content, status, activeForm}]`; Codex's
// update_plan, `plan: [{step, status}]`); Claude Code's task tools change it an item at a time (TaskCreate adds one,
// whose id its result says, `Task #3 created successfully: …`; TaskUpdate sets one's status or subject, `deleted`
// takes it out; 2.1.310 offers them in place of TodoWrite unless CLAUDE_CODE_ENABLE_TASKS is off). An ACP runtime says
// its plan apart (agents/acp.ts `planOfAcp`). What a history and an agent's card show of it (sessions/live.ts).
import type { PlanItem } from "../agents/runtime.ts";
import type { TimelineEntry } from "./transcript.ts";

/// The tools whose calls say the list whole.
const WHOLE = new Set(["TodoWrite", "update_plan"]);
/// The tools that change it an item at a time.
const CREATE = "TaskCreate";
const UPDATE = "TaskUpdate";
/// The calls a checklist is kept with: read whole, never cut short (read/transcript.ts).
export const isPlanTool = (tool: string) => WHOLE.has(tool) || tool === CREATE || tool === UPDATE;

/// Where reading a transcript's checklist stands: its items (a task tool's with its id once its result said it), and
/// the task tools' calls whose result has not come yet, by call id.
export type PlanState = { items: (PlanItem & { id?: string })[]; creating: Map<string, PlanItem & { id?: string }> };

export const noPlan = (): PlanState => ({ items: [], creating: new Map() });

/// The items as told: what and where each stands.
export const planItems = (state: PlanState): PlanItem[] => state.items.map(({ text, status }) => ({ text, status }));

const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);
const parse = (text: string): Record<string, unknown> | null => {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
};

/// A list said whole as checklist items (null: it says none).
function wholeList(args: Record<string, unknown>): PlanItem[] | null {
  const list = Array.isArray(args.todos) ? args.todos : Array.isArray(args.plan) ? args.plan : null;
  if (list === null) return null;
  return list
    .filter((t): t is Record<string, unknown> => t !== null && typeof t === "object")
    .map((t) => ({ text: str(t.content) ?? str(t.step) ?? "", status: str(t.status) ?? "pending" }))
    .filter((t) => t.text !== "");
}

/// Reads `entries` (in order, whole) into `state`; whether its items changed. A call whose input does not read as JSON
/// changes nothing.
export function readPlan(state: PlanState, entries: TimelineEntry[]): boolean {
  let changed = false;
  for (const e of entries) {
    if (e.subagent === true) continue;
    if (e.kind === "tool_result") {
      const made = e.callId === undefined ? undefined : state.creating.get(e.callId);
      if (made === undefined) continue;
      state.creating.delete(e.callId!);
      const id = /^Task #(\S+) created/.exec(e.text)?.[1];
      if (id !== undefined) made.id = id;
      else if (e.ok === false) {
        state.items = state.items.filter((i) => i !== made);
        changed = true;
      }
      continue;
    }
    if (e.kind !== "tool_call" || e.tool === undefined || !isPlanTool(e.tool)) continue;
    const args = parse(e.text);
    if (args === null) continue;
    if (WHOLE.has(e.tool)) {
      const list = wholeList(args);
      if (list === null) continue;
      state.items = list;
      state.creating.clear();
      changed = true;
    } else if (e.tool === CREATE) {
      const subject = str(args.subject);
      if (subject === undefined || subject === "") continue;
      const item = { text: subject, status: "pending" };
      state.items = [...state.items, item];
      if (e.callId !== undefined) state.creating.set(e.callId, item);
      changed = true;
    } else {
      const id = str(args.taskId) ?? (typeof args.taskId === "number" ? String(args.taskId) : undefined);
      const at = id === undefined ? -1 : state.items.findIndex((i) => i.id === id);
      if (at < 0) continue;
      const status = str(args.status);
      if (status === "deleted") state.items = state.items.filter((_, i) => i !== at);
      else {
        const was = state.items[at]!;
        state.items = state.items.map((item, i) => (i === at ? { ...was, ...(status !== undefined ? { status } : {}), ...(str(args.subject) ? { text: args.subject as string } : {}) } : item));
      }
      changed = true;
    }
  }
  return changed;
}

/// Whether an entry says the list whole (what came before it no longer counts).
export const saysWhole = (e: TimelineEntry) => e.kind === "tool_call" && e.subagent !== true && e.tool !== undefined && WHOLE.has(e.tool);
