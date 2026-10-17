// The core for this app's UI: the web's client (web/src/core/client.ts) and its React hooks (react.ts) over a channel
// to the core's engine in native code (modules/stillfail-core) instead of a worker. Started once, before anything
// renders (app/_layout.tsx imports this first).
import * as ExpoCrypto from "expo-crypto";
import * as Device from "expo-device";
import { StillfailCore } from "../../modules/stillfail-core";
import { CoreClient, type Channel, type Opener } from "../../../../web/src/core/client.ts";
import { setCore } from "../../../../web/src/core/react.ts";
import { BETA, CLOUD_ORIGIN } from "../build";
import { deviceLocale } from "../i18n";

// Hermes has no Web Crypto: the pages' ids (crypto.randomUUID) and the web modules' random bytes from expo-crypto.
const g = globalThis as { crypto?: Partial<Crypto> };
if (g.crypto?.randomUUID == null || g.crypto?.getRandomValues == null) {
  g.crypto = {
    ...(g.crypto ?? {}),
    randomUUID: () => ExpoCrypto.randomUUID() as `${string}-${string}-${string}-${string}-${string}`,
    getRandomValues: <T extends ArrayBufferView | null>(array: T): T => ExpoCrypto.getRandomValues(array as unknown as Uint8Array) as unknown as T,
  };
}

function base64(text: string): Uint8Array {
  const bin = globalThis.atob(text);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** One channel: the engine is the process's, started once; a new channel is a new client of it. */
const opener: Opener = (onMessage, onFail) => {
  const listening = StillfailCore.addListener("message", ({ json, bytes }) => {
    let message: Record<string, unknown>;
    try {
      message = JSON.parse(json);
    } catch (e) {
      onFail(`the core said what is not JSON: ${String(e)}`);
      return;
    }
    if (bytes !== undefined) message.bytes = base64(bytes);
    onMessage(message);
  });
  StillfailCore.start(CLOUD_ORIGIN, BETA);
  const channel: Channel = {
    post: (message) => StillfailCore.post(JSON.stringify(message)),
    close: () => listening.remove(),
  };
  return channel;
};

export const client = new CoreClient(opener, { onFault: (e) => console.warn("still.fail core:", e) });
setCore(client);

// What this device is, said once: the core decides what follows from it (a phone; the name it signs in as). The core
// knows web, desktop and android apps (client/core-ts/src/prefs.ts `device`): an iPhone says android until it knows iOS.
client
  .call("client.device", { app: "android", build: "rn-0.1", model: `${Device.manufacturer ?? ""} ${Device.modelName ?? ""}`.trim(), locale: deviceLocale() })
  .catch(() => undefined);
