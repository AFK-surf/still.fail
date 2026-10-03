// The name the product goes by in what the core says to people (brand.rs): still.fail, or youdid.wtf on the test
// channel. Set once as the core starts, from its host. Only words for people: wire names and links keep still.fail's.

export const STABLE = "still.fail";
export const TEST = "youdid.wtf";

let testChannel = false;

export function setTestChannel(on: boolean): void {
  testChannel = on;
}

export function name(): string {
  return testChannel ? TEST : STABLE;
}
