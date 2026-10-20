// permissions (docs/remote-screens.md "Grants"): what macOS lets still.fail Helper do on this Mac (Screen Recording and
// Accessibility for its screen, the folders macOS protects for the drive), and a grant asked for: the helper's window up
// on the Mac for it, once in a while as the drive does, with how a person gives it: from wherever they are through the
// screen when it can be seen and driven (its link, to post with need_human), else at the Mac itself.
import { hostname } from "node:os";
import { askWords } from "../helper/files.ts";
import { GRANTS, GrantRefused, type GrantId, type HelperGrants, isGrant } from "../helper/grants.ts";
import { stationLang, tr } from "../ops/i18n.ts";
import type { Tool } from "./mcp.ts";

/// What each grant is, and what goes without it.
const WHAT: Record<GrantId, string> = {
  capture: "Screen Recording: people see this Mac's screen from their still.fail app; the computer tool's screenshots of the desktop",
  control: "Accessibility: people drive this Mac's screen; the computer tool's clicks and typing on the desktop",
  documents: "Documents folder: the drive (people's 文件) reaches ~/Documents",
  desktop: "Desktop folder: the drive reaches ~/Desktop",
  downloads: "Downloads folder: the drive reaches ~/Downloads (and files people drop into the screen land there)",
  removable: "Removable volumes: the drive reaches disks plugged into this Mac",
  network: "Network volumes: the drive reaches network disks mounted on this Mac",
  localNetwork: "Local Network: devices on this Mac's LAN reach the station straight, and it reaches them (the station's own, not still.fail Helper's); without it they go through a relay or a router",
};

export const PERMISSIONS = {
  name: "permissions",
  description:
    "What macOS lets still.fail Helper do on this station's Mac: Screen Recording and Accessibility (people seeing and driving the screen, the computer tool on the desktop) and the folders macOS protects (Documents, Desktop, Downloads, removable and network disks, for people's drive); and the station's own Local Network access (devices on the LAN reaching it straight). Your own commands do not get these. With request, puts the helper's window asking for that one grant up on the Mac (not again while it is up, nor within 3 minutes of being shown) and says how a person gives it: post that with chat_post kind=need_human and end your turn; call this again to see whether it was granted.",
  inputSchema: {
    "type": "object",
    "properties": {
      "request": { "type": "string", "enum": [...GRANTS], "description": "A grant to ask a person for: capture (Screen Recording), control (Accessibility), documents, desktop, downloads, removable, network (network disks), localNetwork (Local Network)" }
    },
    "additionalProperties": false
  },
};

const machine = () => hostname().replace(/\.local$/, "");

/// The grants as macOS has them now, in a line each.
function listed(grants: HelperGrants): string {
  const view = grants.view();
  if (view === null) return "still.fail Helper did not answer, so the grants are not known now.";
  const rows = view.grants.map(({ grant, state }) => `- ${grant} (${WHAT[grant]}): ${state === "granted" ? "granted" : state === "denied" ? (grant === "localNetwork" ? `refused: the LAN is not reached (switched on for ${view.localNetworkName ?? "the station"} in System Settings › Privacy & Security › Local Network, or a firewall)` : "refused before (its window's Allow opens System Settings)") : "not granted"}${view.asking.includes(grant) ? "; its window is up on the Mac now" : ""}`);
  const screen = view.screen
    ? "The screen can be seen and driven: a person can grant the rest from wherever they are, through the screen's link."
    : "The screen cannot be seen and driven: a person grants at the Mac itself.";
  return `still.fail Helper's grants on ${machine()}:\n${rows.join("\n")}\n${screen}`;
}

/// `base`: this station's place in its control plane's pages (`<cloud>/w/<workspace>/s/<station>`), none when it has
/// no pages; `grants`: none where there is no helper (not a Mac).
export function permissionTools(grants: HelperGrants | null, base: () => string | null): Tool[] {
  return [
    {
      ...PERMISSIONS,
      run: async (_session, args) => {
        if (grants === null) return "This station is not a Mac with still.fail Helper: there is nothing to grant here.";
        const asked = args.request;
        if (asked === undefined || asked === "") {
          await grants.refresh(true);
          return listed(grants);
        }
        if (!isGrant(asked)) throw new Error(`no grant ${String(asked)} (there are: ${GRANTS.join(", ")})`);
        let answer;
        try {
          answer = await grants.request(asked, askWords(stationLang()));
        } catch (e) {
          if (e instanceof GrantRefused) throw new Error(tr("en", e.key));
          throw e;
        }
        const name = WHAT[asked].split(":")[0];
        if (asked === "localNetwork" && answer.window === "up") {
          const app = grants.view()?.localNetworkName ?? "the station";
          const link = base();
          const where = answer.screen && link !== null ? `from wherever they are through the screen (post ${link}/screen/desktop on a line of its own with chat_post kind=need_human)` : `at ${machine()} itself (chat_post kind=need_human)`;
          return `System Settings › Privacy & Security › Local Network is open on ${machine()}. A person switches ${app} on there ${where}; it takes once ${app} starts again. End your turn; call permissions again to see whether it was granted.`;
        }
        if (answer.window === "granted") return `${name} is granted already.\n\n${listed(grants)}`;
        if (answer.window === "none") throw new Error("still.fail Helper's window could not be shown on this Mac.");
        if (answer.window === "closed") return `The window asking for ${name} was shown less than 3 minutes ago and closed without it; it is not shown again yet. Ask the person (chat_post kind=need_human) whether they want to grant it, and call this again in a few minutes.`;
        const link = base();
        const folder = asked !== "capture" && asked !== "control" ? ", then Allow in the prompt macOS shows (a folder refused before opens System Settings › Files and Folders instead, to switch it on there)" : ", then drag still.fail Helper into the list System Settings shows";
        const how = answer.screen && link !== null
          ? `The screen can be seen and driven, so a person can grant it from wherever they are: post ${link}/screen/desktop on a line of its own (it shows as the screen's card) with chat_post kind=need_human, asking them to open it and click Allow in the still.fail Helper window${folder}.`
          : `The screen cannot be seen and driven${answer.screen ? " from a link here (this control plane has no pages)" : ""}, so a person has to do it at the Mac itself: post chat_post kind=need_human asking them to go to ${machine()} and click Allow in the still.fail Helper window there${folder}. Their app's station page shows the grants as they change.`;
        return `still.fail Helper's window asking for ${name} is up on ${machine()}. ${how} End your turn; call permissions again to see whether it was granted.`;
      },
    },
  ];
}
