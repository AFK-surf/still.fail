// Every tool a station declares, for the tests that hold something of the whole list (what it weighs:
// test/tools-weight.test.ts, which also holds, by reading the source, that this list is the station's; which of them a
// session speaks by: test/speaks.test.ts). A declaration is what its factory gives, whatever it is given, so the list
// is made of every factory src/sessions/agents.ts and the parts' modules call, with nothing behind them: no tool is run.
import { PHONE_SEND, adbTools, phoneTools } from "../src/adb/tool.ts";
import { browserTools } from "../src/browser/tool.ts";
import { deviceTools } from "../src/devices/tool.ts";
import { feishuTools } from "../src/feishu/tool.ts";
import { loginTools } from "../src/logins/tool.ts";
import { rigTools } from "../src/rigs/tool.ts";
import { searchTools } from "../src/search/tool.ts";
import { archiveTools } from "../src/tools/archive.ts";
import { chatTools } from "../src/tools/chat.ts";
import { computerTools } from "../src/tools/computer.ts";
import { feedbackTools } from "../src/tools/feedback.ts";
import { forwardTools } from "../src/tools/forward.ts";
import { jobTools } from "../src/tools/jobs.ts";
import type { Tool } from "../src/tools/mcp.ts";
import { permissionTools } from "../src/tools/permissions.ts";
import { relayTools } from "../src/tools/relays.ts";
import { remoteTools } from "../src/tools/remote.ts";
import { retireTools } from "../src/tools/retire.ts";
import { screenTools } from "../src/tools/screen.ts";
import { workspaceSizeTools } from "../src/tools/workspace-size.ts";
import { vaultTools } from "../src/vault/tool.ts";

/// Every tool a station declares to a session, where it declares the most (a stable station of still.fail cloud, which
/// has the feedback tools too): those of src/sessions/agents.ts, then the parts' (their modules' `parts.tools(…)`), each
/// factory given nothing, since a declaration reads none of it.
export function stationTools(): Tool[] {
  const none = {} as any;
  return [
    ...chatTools(none),
    ...archiveTools(none),
    ...remoteTools(none),
    ...workspaceSizeTools(none, none),
    ...jobTools(none, () => null),
    ...screenTools(none, () => null),
    ...permissionTools(null, () => null),
    ...computerTools(none),
    ...forwardTools(none),
    ...relayTools(none),
    ...phoneTools(none, async () => ""),
    { ...PHONE_SEND, run: async () => "" },
    ...adbTools(() => []),
    ...browserTools(none),
    ...deviceTools(none),
    ...feedbackTools(none, () => null, () => null),
    ...feishuTools(() => undefined, () => false),
    ...loginTools(none),
    ...retireTools(none),
    ...rigTools(none),
    ...searchTools(none),
    ...vaultTools(none, () => null, none),
  ];
}
