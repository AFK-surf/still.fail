// The vault for the stories (docs/vault.md): the demo workspace's `vaults` and `vaultItems` topics as the core puts
// them together (client/core-ts/src/views/vault.ts) in each state the page has, what its calls answer (the words once,
// an item opened), and an agent's request for an item as a card in the demo's chat.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { ChatMessage, ChatView, Stamp, VaultItemRow, VaultItemsView, VaultRequest, VaultRow, VaultsView, VaultUse, VaultUsesView } from "../src/core/shapes.ts";

const AT = 1_792_200_000;
const WORDS = "orbit canvas lemon thrive patrol velvet ankle humble glide quarter mosaic ripple sponsor dune fabric wisdom cradle ozone timber jungle echo salute pigeon harbor";

const PERSONAL: VaultRow = {
  id: "v_01JAVAULT", name: "个人", owner: "demo-you", ownerName: "你", mine: true, members: [{ sub: "demo-you", name: "你" }],
  station: "local", stationName: "Studio", items: 4, devices: 2, open: true, keyed: true, missing: 0, recoverable: true,
};
const item = (id: string, name: string, kind: string, modes: string[], hosts: string[] = [], env?: string): VaultItemRow =>
  ({ id, version: 0, at: AT, name, kind, listed: modes.length > 0, modes, hosts, ...(env ? { env } : {}) });
const ITEMS: VaultItemRow[] = [
  item("i_gh", "GitHub token", "token", ["proxy"], ["api.github.com", "uploads.github.com"], "GH_TOKEN"),
  item("i_openai", "OpenAI key", "token", ["proxy"], ["api.openai.com"], "OPENAI_API_KEY"),
  item("i_aliyun", "阿里云控制台", "login", []),
  item("i_deploy", "部署机 SSH 钥匙", "ssh_key", ["ssh"]),
];
/** What each item holds, as `vault.open` answers it. */
const PLAIN: Record<string, { kind: string; name: string; fields: Record<string, string> }> = {
  i_gh: { kind: "token", name: "GitHub token", fields: { value: "ghp_9fK2xQ7LmA4vT8bN1cR6wZ3yH5jD0eP2sG7u" } },
  i_openai: { kind: "token", name: "OpenAI key", fields: { value: "sk-proj-3hX9mQ2vL8kT4nB7cR1wZ6yF5jD0eP" } },
  i_aliyun: { kind: "login", name: "阿里云控制台", fields: { username: "ops@acme.dev", password: "Tq7#mW2!vL9x", totp: "JBSWY3DPEHPK3PXP" } },
  i_deploy: {
    kind: "ssh_key", name: "部署机 SSH 钥匙",
    fields: { private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\nQyNTUxOQAAACBz2Lr9yTqY8a0m3vXc1QeK7wN4pH6sJfU2dR5gB9xZcwAAAJgW0k8yFtJP\n-----END OPENSSH PRIVATE KEY-----\n", public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHPYuv3JOpjxrSbe9dzVB4rvA3ikfqwl9TZ1HmAH3Flz deploy@acme" },
  },
};

export const REQUEST: VaultRequest = {
  id: "r_01JAREQ", vault: PERSONAL.id, vaultName: "个人", item: "i_gh", itemName: "GitHub token", session: "ember:c-demo-safari", chat: "EMBER/1792199000.000100",
  station: "local", mode: "proxy", reason: "重跑 PR #512 失败的 release job", command: "gh run rerun 1846 --failed", hosts: ["api.github.com"], at: AT,
};

/** The page's states, as the core says them. */
export type VaultStory = "web" | "noLock" | "unconfirmed" | "off" | "on" | "locked" | "waiting" | "notKeyed";

function view(story: VaultStory): VaultsView {
  const base: VaultsView = { available: true, locked: true, canSign: true, setUp: true, vaults: [PERSONAL], requests: [], refused: [] };
  switch (story) {
    case "web": return { ...base, available: false, canSign: false, setUp: false, vaults: [{ ...PERSONAL, open: false, keyed: false }], requests: [REQUEST] };
    case "noLock": return { ...base, locked: false, canSign: false, setUp: false, vaults: [] };
    case "unconfirmed": return { ...base, canSign: false, setUp: false, vaults: [] };
    case "off": return { ...base, setUp: false, vaults: [] };
    case "locked": return { ...base, vaults: [{ ...PERSONAL, open: false, missing: 1 }] };
    case "waiting": return { ...base, requests: [REQUEST] };
    case "notKeyed": return { ...base, vaults: [{ ...PERSONAL, open: false, keyed: false }] };
    default: return base;
  }
}

function items(story: VaultStory): VaultItemsView {
  const open = story === "on" || story === "waiting";
  // Locked: the names the listings give, the others' not.
  return { vault: PERSONAL.id, name: "个人", open, items: open ? ITEMS : ITEMS.map((i) => (i.listed ? i : { id: i.id, version: i.version, at: i.at, listed: false, modes: [], hosts: [] })) };
}

/** The station's card for the request, under the agent's post in the chat on show (as station/src/vault/secrets.ts posts it). */
function withCard(chat: ChatView): ChatView {
  const last = [...chat.messages].reverse().find((m) => m.authorKind === "agent");
  if (!last || chat.messages.some((m) => m.card?.vault)) return chat;
  const seq = (chat.messages.at(-1)?.seq ?? 0) + 1;
  const options = [
    { label: "仅本次", detail: "单次有效", recommended: true },
    { label: "本对话 1 小时内", detail: "期间无需再次批准" },
    { label: "拒绝", detail: "通知 agent 已拒绝" },
  ];
  const ask: ChatMessage = {
    ...last, seq, ts: `${Number(last.ts) + 30}`, quotes: [], attachments: [],
    text: "PR 的检查挂在发布那一步，要用 GitHub token 重跑失败的 job。\n\n申请使用「GitHub token」：重跑 PR #512 失败的 release job\n\n命令：`gh run rerun 1846 --failed`\n\n方式：代理（限 api.github.com）",
    options, card: { type: "options", options, assignee: "you@acme.dev", assigneeText: "待你决策", vault: REQUEST.id }, decision: { resolved: false },
  };
  return { ...chat, messages: [...chat.messages, ask] };
}

/** The demo with the vault in state `story`; `card`: the request's card in the chat on show too. */
export function vaultDemo(story: VaultStory, card = false): DemoExtension {
  return {
    topic: (t) => (t.topic === "vaults" ? view(story) : t.topic === "vaultItems" ? items(story) : undefined),
    then: (t, value) => (card && t.topic === "chat" && value && typeof value === "object" && "messages" in value ? withCard(value as ChatView) : undefined),
    call: (name, params) => {
      if (name === "vault.setup") return { words: WORDS, device: "d_demo", stations: ["local"] };
      if (name === "vault.open") {
        const plain = PLAIN[String(params.item)];
        return plain ? { vault: PERSONAL.id, id: params.item, version: 0, plain: { ...plain, domains: [], notes: "" } } : undefined;
      }
      // What changes something answers at once, the page as it was (the stories show states, not what follows).
      if (name.startsWith("vault.")) return {};
      return undefined;
    },
  };
}

// ── the library: the profiles and the secrets in one place (docs/vault.md 一个库) ──

const stamp = (minutes: number, full: string): Stamp => ({ at: (AT - minutes * 60) * 1000, ago: minutes < 60 ? `${minutes} 分钟前` : minutes < 1440 ? `${Math.round(minutes / 60)} 小时前` : `${Math.round(minutes / 1440)} 天前`, full, until: "", past: true });
const use = (minutes: number, full: string, chatTitle: string, mode: string, command?: string, hosts: string[] = [], denied?: boolean): VaultUse =>
  ({ at: stamp(minutes, full), session: "ember:c-demo-safari", station: "local", chatTitle, mode, ...(command ? { command } : {}), hosts, ...(denied ? { denied } : {}) });
const USES: Record<string, VaultUse[]> = {
  i_gh: [
    use(12, "10/17 20:28", "修 Safari 上的登录跳转", "proxy", "gh pr create --fill", ["api.github.com"]),
    use(130, "10/17 18:30", "重跑发布流水线", "proxy", "gh run rerun 1846 --failed", ["api.github.com"]),
    use(1500, "10/16 19:40", "清理过期分支", "proxy", "gh api -X DELETE repos/acme/web/git/refs/heads/old", ["api.github.com"], true),
  ],
  i_deploy: [use(2900, "10/15 20:20", "部署 staging", "ssh", "git push deploy main")],
};
const LIB_ITEMS: VaultItemRow[] = ITEMS.filter((i) => i.id !== "i_openai").map((i) => (USES[i.id] ? { ...i, lastUse: USES[i.id]![0]! } : i));

/** The library `locked` (security mode on, unlocked here) or not (kept in plain text on the station). */
export function libraryDemo(locked: boolean, left = 0): DemoExtension {
  const vaults: VaultsView = locked
    ? { available: true, locked: true, canSign: true, setUp: true, vaults: [PERSONAL], requests: [], refused: [], ...(left ? { plainLeft: left } : {}) }
    : { available: true, locked: false, canSign: false, setUp: true, vaults: [{ ...PERSONAL, recoverable: false }], requests: [], refused: [], plain: true };
  return {
    topic: (t) => {
      if (t.topic === "vaults") return vaults;
      if (t.topic === "vaultItems") return { vault: PERSONAL.id, name: "个人", open: true, items: LIB_ITEMS } satisfies VaultItemsView;
      if (t.topic === "vaultUses") return { item: t.item, uses: USES[t.item] ?? [] } satisfies VaultUsesView;
      return undefined;
    },
    call: (name, params) => vaultDemo("on").call!(name, params),
  };
}
