// The name the product goes by in what the core says to people (brand.rs): still.fail, or youdid.wtf in still.fail's
// own app on the test channel. An app of its own that runs this core (still.fail mbui: `client.device`'s `client`)
// calls it still.fail on either channel. Set as the core starts, from its host and what the device said last, and as
// the device says what it is. Only words for people: wire names and links keep still.fail's.

export const STABLE = "still.fail";
export const TEST = "youdid.wtf";

let testChannel = false;
let ownApp = true;

export function setTestChannel(on: boolean): void {
  testChannel = on;
}

/// Whether this core runs in still.fail's own app (no `client` named), not an app of its own.
export function setOwnApp(on: boolean): void {
  ownApp = on;
}

/// still.fail's own app on the test channel (youdid.wtf): named so, and its newer builds its platform's beta feed.
export function testApp(): boolean {
  return testChannel && ownApp;
}

export function name(): string {
  return testApp() ? TEST : STABLE;
}
