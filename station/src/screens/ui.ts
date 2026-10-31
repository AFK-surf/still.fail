// The apps' accessibility trees on the desktop (docs/remote-screens.md, "Agents on a screen"): agent-desktop
// (vercel-labs/agent-desktop, Apache-2.0) reads an app's window as a tree of elements, each acted on by its ref through
// the accessibility API, without the pointer or the keyboard focus (its "headless" delivery). It runs where the
// desktop's apps are and with what they were granted: on macOS in still.fail Helper (its `ui` op, which macOS's
// Accessibility grant is given to), on Windows started by the station itself (a station runs in its person's session).
// Each call is one command and its one JSON envelope (`{ok, data}` or `{ok: false, error: {code, message, suggestion,
// disposition}}`); its trees are put here as text an agent reads at a glance, a line an element.
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { HelperApp } from "../helper/app.ts";
import { wall } from "../ops/fibers.ts";

export const UI_BINARY = "agent-desktop.exe";
/// A command longer than this is ended (agent-desktop's own waits are shorter).
export const UI_LIMIT_MS = 60_000;

/// The release's agent-desktop on Windows: STILLFAIL_AGENT_DESKTOP, or beside the station's code.
export function uiBinary(env: NodeJS.ProcessEnv = process.env): string | null {
  const candidates = [env.STILLFAIL_AGENT_DESKTOP, fileURLToPath(new URL(`./${UI_BINARY}`, import.meta.url))];
  return candidates.find((p) => p && existsSync(p)) ?? null;
}

/// An envelope from what agent-desktop printed: an error envelope when it printed none.
export function envelope(out: string, status: number): unknown {
  try {
    return JSON.parse(out);
  } catch {
    return { ok: false, error: { code: "INTERNAL", message: `agent-desktop printed no answer (exit status ${status})` } };
  }
}

/// agent-desktop in still.fail Helper (macOS).
export function helperUi(helper: HelperApp): (args: string[]) => Promise<unknown> {
  return async (args) => {
    const answer = await helper.request({ op: "ui", args });
    return envelope(typeof answer?.out === "string" ? answer.out : "", Number(answer?.status));
  };
}

/// agent-desktop started by the station (Windows).
export function processUi(binary: string): (args: string[]) => Promise<unknown> {
  return (args) =>
    new Promise((resolve, reject) => {
      const child = spawn(binary, args, { stdio: ["ignore", "pipe", "ignore"], windowsHide: true });
      let out = "";
      const unarm = wall.after(UI_LIMIT_MS, () => child.kill());
      child.stdout.setEncoding("utf8").on("data", (chunk: string) => (out += chunk));
      child.once("error", (error) => (unarm(), reject(error)));
      child.once("close", (status) => (unarm(), resolve(envelope(out, status ?? -1))));
    });
}

type Node = { ref_id?: string; role?: string; name?: string; value?: unknown; description?: string; states?: string[]; children_count?: number; children?: Node[] };

/// A tree as text: a line an element, indented by depth; unnamed containers without a ref leave no line (their
/// children go one level up), nor does a text without a ref saying its parent's name again.
/// `e12 button "Save" = "…" [disabled]`; a ref is its number in the tree's snapshot.
export function treeText(tree: Node): string {
  const lines: string[] = [];
  const walk = (n: Node, depth: number, parent: string) => {
    const ref = n.ref_id ? n.ref_id.slice(n.ref_id.lastIndexOf(":") + 1) : "";
    const name = typeof n.name === "string" ? n.name.trim() : "";
    // A value that is its name again (a text's) says nothing more.
    const valued = n.value !== undefined && n.value !== null && n.value !== "" && String(n.value).trim() !== name;
    const shown = ref !== "" || (name !== "" && (name !== parent || valued || !!n.children?.length)) || valued;
    if (shown) {
      const parts = [ref, n.role ?? ""];
      if (name !== "") parts.push(JSON.stringify(name.length > 200 ? `${name.slice(0, 200)}…` : name));
      if (valued) {
        const v = String(n.value);
        parts.push(`= ${JSON.stringify(v.length > 200 ? `${v.slice(0, 200)}…` : v)}`);
      }
      if (n.states?.length) parts.push(`[${n.states.join(", ")}]`);
      if (typeof n.children_count === "number" && !n.children?.length) parts.push(`(${n.children_count} inside)`);
      lines.push(`${"  ".repeat(depth)}${parts.filter(Boolean).join(" ")}`);
    }
    for (const c of n.children ?? []) walk(c, shown ? depth + 1 : depth, name || parent);
  };
  walk(tree, 0, "");
  return lines.join("\n");
}
