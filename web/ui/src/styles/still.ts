// Motion reduced: the page's root says so (motion.ts followMotion), as this device's setting says or, when it says none,
// as the system asks. A rule for it is a selector under STILL (`${STILL} &`), not `@media (prefers-reduced-motion)`,
// which the setting could not change.
export const STILL = ":root[data-reduced-motion]";
