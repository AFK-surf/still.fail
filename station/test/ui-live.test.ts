// The computer tool on a real app through the real agent-desktop (screens/ui.ts, `processUi`): an editor started, its
// tree read, its text field found by its ref, a line set into it by ref and read back from the tree the action answers
// with. Only where a desktop can be driven and agent-desktop is given: STILLFAIL_UI_LIVE=1 and STILLFAIL_AGENT_DESKTOP
// (the pipeline's ui-windows job on GitHub's Windows, where the station's own agent-desktop.exe runs as here; on a Mac
// whose terminal has Accessibility, by hand). The editor: Notepad on Windows, TextEdit on macOS.
import assert from "node:assert/strict";
import { test } from "node:test";
import { ScreenHub } from "../src/screens/hub.ts";
import type { ScreenSource } from "../src/screens/source.ts";
import { processUi } from "../src/screens/ui.ts";
import { Computer, type Timers } from "../src/tools/computer.ts";

const binary = process.env.STILLFAIL_AGENT_DESKTOP;
const live = process.env.STILLFAIL_UI_LIVE === "1" && !!binary;
const windows = process.platform === "win32";
const editor = windows ? { launch: "notepad", app: /notepad(\.exe)?/i } : { launch: "TextEdit", app: /TextEdit/ };

const timers: Timers = {
  later: (ms, f) => {
    const t = setTimeout(f, ms);
    return () => clearTimeout(t);
  },
};

test("a real editor: its tree, a line set into its text by ref, read back from the tree the action answers with", { skip: !live && "STILLFAIL_UI_LIVE=1 and STILLFAIL_AGENT_DESKTOP are not set" }, async () => {
  const ui = processUi(binary!);
  const desktop: ScreenSource = { id: "desktop", kind: "desktop", title: () => "desktop", size: () => ({ width: 0, height: 0 }), open: () => Promise.reject(new Error("no pictures here")), ui };
  const hub = new ScreenHub();
  hub.add(desktop);
  const computer = new Computer({ hub, base: () => null, name: (s) => s, timers });
  const say = (r: { content: { type: string; text?: string }[] }) => r.content.map((c) => c.text ?? "").join("\n");
  const launched: any = await ui(["launch", editor.launch, "--timeout", "30000"]);
  assert.equal(launched.ok, true, JSON.stringify(launched));
  try {
    // Its name as the apps running say it (Windows': its executable's, notepad.exe), as an agent takes it.
    const apps = say(await computer.act("t", { screen: "desktop", action: "tree" }));
    const app = apps.slice(apps.indexOf(":") + 1).split(",").map((a) => a.trim()).find((a) => editor.app.test(a));
    assert.ok(app, apps);
    // An editor with several windows (documents it reopened) is refused with them to choose from, as an agent is: the
    // first is taken.
    const read = (window?: string) => computer.act("t", { screen: "desktop", action: "tree", app, ...(window ? { window } : {}) });
    const tree = say(
      await read().catch((error: Error) => {
        const window = /"id":"([^"]+)"/.exec(error.message)?.[1];
        if (!/AMBIGUOUS_TARGET/.test(error.message) || !window) throw error;
        return read(window);
      }),
    );
    const field = /^\s*(e\d+) (?:textfield|textarea|document|edit)\b/m.exec(tree);
    assert.ok(field, `no text field in\n${tree}`);
    const line = `still.fail tree ${Date.now()}`;
    const after = say(await computer.act("t", { screen: "desktop", action: "set", ref: field[1], text: line }));
    assert.ok(after.includes(line), `the line is not in the tree read again:\n${after}`);
  } finally {
    await ui(["close-app", windows ? "notepad.exe" : "TextEdit", "--force"]);
  }
});
