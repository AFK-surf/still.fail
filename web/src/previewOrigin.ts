declare const __PREVIEW_ORIGIN__: string;

/** Where a station's web services are shown (cloud/src/preview.ts): the preview host the page names with
 * <meta name="stillfail-preview" content="<origin>"> (a self-hosted cloud's, named as it runs: cloud/selfhost/static.ts),
 * else the one this build was made for. Only for the page's own modules: it reads the build's constant as it loads. */
export const PREVIEW_ORIGIN = document.querySelector<HTMLMetaElement>('meta[name="stillfail-preview"]')?.content || __PREVIEW_ORIGIN__;
