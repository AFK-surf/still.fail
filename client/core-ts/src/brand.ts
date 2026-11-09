// The name the product goes by in what the core says to people: still.fail, or youdid.wtf in still.fail's
// own app on the test channel; monoid and monoid.zone where its cloud is monoid's (app.monoid.build: the same code,
// another product, cloud/deploy.py CLOUDS). An app of its own that runs this core (still.fail mbui: `client.device`'s
// `client`) calls it by the stable name on either channel. Set as the core starts, from its host (its channel, its
// cloud) and what the device said last, and as the device says what it is. Only words for people: wire names and
// links keep still.fail's.

import { productOf, STILLFAIL, type Product } from "../../i18n/brand.ts";

export const STABLE = "still.fail";
export const TEST = "youdid.wtf";

/// The old per-commit app identity is still sent by installed builds and kept in signed device records. It names
/// this product too; other clients' names are their own.
export function clientName(client: string): string {
  return client === "still.fail mbui" ? product.name : client;
}

let product: Product = STILLFAIL;

/// The cloud the core is on (its origin): its product's names (client/i18n/brand.ts).
export function setCloud(origin: string): void {
  product = productOf(origin);
}

/// The product the core's cloud is, for its words (client/i18n/brand.ts branded).
export function current(): Product {
  return product;
}

let testChannel = false;
let ownApp = true;

export function setTestChannel(on: boolean): void {
  testChannel = on;
}

/// Whether this core runs in the product's own app (no `client` named), not an app of its own.
export function setOwnApp(on: boolean): void {
  ownApp = on;
}

/// The product's own app on the test channel (youdid.wtf, monoid.zone): named so, and its newer builds its platform's beta feed.
export function testApp(): boolean {
  return testChannel && ownApp;
}

export function name(): string {
  return testApp() ? product.test : product.name;
}
