// Which product the words are for. The same code is two products: still.fail, and monoid (the company's, its cloud on
// monoid.build: cloud/deploy.py CLOUDS). The catalog says still.fail; where the cloud is another product's, its words say
// that product's name instead (`branded`), as the core, the station, the cloud and the apps read them. Hosts
// (app.still.fail) and what agents are told stay as they are.

export interface Product {
  /** Its name. */
  name: string;
  /** Its test channel's (still.fail's on youdid.wtf, monoid's on monoid.zone). */
  test: string;
}

export const STILLFAIL: Product = { name: "still.fail", test: "youdid.wtf" };

/** Each product other than still.fail: the domains its clouds are on, its names. */
const PRODUCTS: { zones: string[]; product: Product }[] = [
  { zones: ["monoid.build", "monoid.zone"], product: { name: "monoid", test: "monoid.zone" } },
];

/** The product whose cloud is at `origin` (a URL, or a bare host): still.fail's for any other, a local cloud's too. */
export function productOf(origin: string): Product {
  let host = origin;
  try {
    host = new URL(origin).hostname;
  } catch {
    // (a bare host)
  }
  return PRODUCTS.find((p) => p.zones.some((zone) => host === zone || host.endsWith("." + zone)))?.product ?? STILLFAIL;
}

/** The name still.fail standing alone (not a host or an address: app.still.fail, https://still.fail, noreply@still.fail, still.fail.app). */
const NAME = /(?<![\w./@-])still\.fail(?![\w-]|\.\w)/g;

/** `text` with still.fail's name `product`'s. */
export function branded(text: string, product: Product): string {
  return product === STILLFAIL || !text.includes("still.fail") ? text : text.replace(NAME, product.name);
}
