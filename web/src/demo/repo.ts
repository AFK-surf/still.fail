// The made-up repository the demo's agent works in (acme-web, the team's frontend): a few files in memory, and the
// tools the agent reaches them with. Nothing runs; edits last as long as the page.
import type { Tool } from "./llm.ts";

const files = new Map<string, string>(Object.entries({
  "README.md": "# acme-web\n\nAcme 的 Web 前端：React 19 + Vite。\n\n## 开发\n\n```sh\npnpm install\npnpm dev\n```\n",
  "package.json": JSON.stringify({
    name: "acme-web", private: true, type: "module",
    scripts: { dev: "vite", build: "vite build", test: "vitest run" },
    dependencies: { react: "^19.1.0", "react-dom": "^19.1.0", "react-router": "^7.9.0" },
    devDependencies: { vite: "^7.1.0", vitest: "^3.2.0", typescript: "^5.9.0" },
    browserslist: ["defaults", "safari >= 15"],
  }, null, 2),
  "src/main.tsx": "import { createRoot } from \"react-dom/client\";\nimport { App } from \"./App.tsx\";\n\ncreateRoot(document.getElementById(\"root\")!).render(<App />);\n",
  "src/App.tsx": "import { BrowserRouter, Route, Routes } from \"react-router\";\nimport { Login } from \"./pages/Login.tsx\";\nimport { Orders } from \"./pages/Orders.tsx\";\n\nexport function App() {\n  return (\n    <BrowserRouter>\n      <Routes>\n        <Route path=\"/login\" element={<Login />} />\n        <Route path=\"/orders\" element={<Orders />} />\n      </Routes>\n    </BrowserRouter>\n  );\n}\n",
  "src/pages/Login.tsx": "import { useState } from \"react\";\nimport { isEmail } from \"../auth/validate.ts\";\n\nexport function Login() {\n  const [email, setEmail] = useState(\"\");\n  const ok = isEmail(email);\n  return (\n    <form>\n      <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder=\"邮箱\" />\n      <button disabled={!ok}>登录</button>\n    </form>\n  );\n}\n",
  "src/pages/Orders.tsx": "export function Orders() {\n  // TODO: 分页\n  return <table>{/* 订单列表 */}</table>;\n}\n",
  "src/auth/validate.ts": "const EMAIL = /^[^@\\s+]+(\\+[^@\\s]+)?@[^@\\s]+\\.[a-z]{2,}$/i;\n\nexport function isEmail(value: string): boolean {\n  return EMAIL.test(value.trim());\n}\n",
  "src/auth/validate.test.ts": "import { expect, test } from \"vitest\";\nimport { isEmail } from \"./validate.ts\";\n\ntest(\"accepts plus addressing\", () => {\n  expect(isEmail(\"lin+test@acme.dev\")).toBe(true);\n});\n",
}));

export const TOOLS: Tool[] = [
  { name: "list_files", description: "List the files of the repository (acme-web), optionally under a directory.", input_schema: { type: "object", properties: { dir: { type: "string", description: "A directory, e.g. src/auth; empty for all." } } } },
  { name: "read_file", description: "Read a file of the repository.", input_schema: { type: "object", properties: { path: { type: "string" } }, required: ["path"] } },
  { name: "search", description: "Search the repository's files for a text (case-insensitive); answers path:line: text.", input_schema: { type: "object", properties: { text: { type: "string" } }, required: ["text"] } },
  { name: "edit_file", description: "Replace text in a file (or create it: old empty and the file missing).", input_schema: { type: "object", properties: { path: { type: "string" }, old: { type: "string" }, new: { type: "string" } }, required: ["path", "old", "new"] } },
];

/** A tool call as the execution panel and the chat's activity line name it (the way Claude Code's tools show). */
export function describe(name: string, input: Record<string, unknown>): { tool: string; hint: string; activity: string } {
  const path = String(input.path ?? input.dir ?? "");
  switch (name) {
    case "list_files": return { tool: "Glob", hint: path || "**/*", activity: `列出 ${path || "文件"}` };
    case "read_file": return { tool: "Read", hint: path, activity: `读取 ${path}` };
    case "search": return { tool: "Grep", hint: String(input.text ?? ""), activity: `搜索 ${String(input.text ?? "")}` };
    case "edit_file": return { tool: "Edit", hint: path, activity: `编辑 ${path}` };
    default: return { tool: name, hint: "", activity: name };
  }
}

/** Runs a tool: its result, and whether it failed. */
export function run(name: string, input: Record<string, unknown>): { result: string; failed: boolean } {
  const path = String(input.path ?? "").replace(/^\.?\//, "");
  switch (name) {
    case "list_files": {
      const dir = String(input.dir ?? "").replace(/^\.?\//, "").replace(/\/$/, "");
      const found = [...files.keys()].filter((f) => !dir || f.startsWith(`${dir}/`));
      return found.length ? { result: found.join("\n"), failed: false } : { result: `没有 ${dir}`, failed: true };
    }
    case "read_file": {
      const text = files.get(path);
      return text === undefined ? { result: `没有这个文件：${path}`, failed: true } : { result: text, failed: false };
    }
    case "search": {
      const needle = String(input.text ?? "").toLowerCase();
      const hits = [...files].flatMap(([f, text]) => text.split("\n").flatMap((line, i) => (line.toLowerCase().includes(needle) ? [`${f}:${i + 1}: ${line}`] : [])));
      return { result: hits.length ? hits.slice(0, 30).join("\n") : "没有找到", failed: false };
    }
    case "edit_file": {
      const old = String(input.old ?? "");
      const next = String(input.new ?? "");
      const text = files.get(path);
      if (text === undefined) {
        if (old) return { result: `没有这个文件：${path}`, failed: true };
        files.set(path, next);
        return { result: `已创建 ${path}`, failed: false };
      }
      if (!text.includes(old)) return { result: `${path} 里找不到要替换的内容`, failed: true };
      files.set(path, text.replace(old, next));
      return { result: "The file has been updated.", failed: false };
    }
    default:
      return { result: `没有这个工具：${name}`, failed: true };
  }
}
