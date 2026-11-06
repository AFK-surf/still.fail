// One-off CI diagnostic: keep the production test and deadline, and capture a stack of a long-running snapshot.
import { readFileSync, writeFileSync } from "node:fs";

const path = "station/src/screens/ui.ts";
const source = readFileSync(path, "utf8");
const before = '      const child = spawn(binary, args, { stdio: ["ignore", "pipe", "ignore"], windowsHide: true });';
const after = `      const started = Date.now();
      const child = spawn(binary, args, { stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
      const diagnostic = args[0] === "snapshot" ? setTimeout(() => {
        if (!child.pid || child.exitCode !== null) return;
        const dump = process.env.RUNNER_TEMP + "/agent-desktop-" + child.pid + ".dmp";
        console.error("snapshot process past 4000 ms; collecting native stack", child.pid, dump);
        const capture = spawn(process.env.DIAG_PROCDUMP!, ["-accepteula", "-ma", String(child.pid), dump], { stdio: "inherit", windowsHide: true });
        capture.once("error", (e) => console.error("dump failed", e));
      }, 4000) : undefined;
      child.stderr.setEncoding("utf8").on("data", (s: string) => console.error("agent-desktop", s));
      child.once("close", (status) => {
        if (diagnostic !== undefined) clearTimeout(diagnostic);
        console.error("agent-desktop", JSON.stringify(args), "exit", status, "elapsed ms", Date.now() - started);
      });`;
if (source.split(before).length !== 2) throw new Error("expected one processUi spawn");
writeFileSync(path, source.replace(before, after));
