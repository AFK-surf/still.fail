// The camera of film 1 from the iPhone Duo simulator (compose_sim.mjs), by its marks (s): [t, dist, x, y, yaw, pitch],
// looking at (x, y) of the open phone (its units: the inner screen 15.8 x 11.1 about the middle; folded, the outer
// screen on the right half) from dist away. o(x, y) a point of the outer screen (466 x 678 points), i(x, y) of the
// inner (951 x 669).
const o = (x, y) => [.247 + x / 466 * 8.18, -5.6 + (1 - y / 678) * 11.9];
const i = (x, y) => [-7.9 + x / 951 * 15.8, -5.55 + (1 - y / 669) * 11.1];
export default (M) => {
  const U = M.unfold3d;
  const c = (t, d, p, yaw = 0, pitch = 0) => [t, d, ...p, yaw, pitch];
  // (the whole screen in use always in view: where the finger goes is seen, not only what it does)
  return [
    c(0, 20, o(233, 339), -8, 4), c(M['tap=发消息'] - .3, 18, o(233, 339), -4, 2), c(M['tap=发消息'] + .6, 17, o(233, 339)),
    c(M['tap=send'] + .1, 17, o(233, 339)), c(M['kb-down'] + .5, 17, o(233, 339)), c(M.working + .6, 17, o(233, 339)),
    c(M.answer - .3, 17, o(233, 339)), c(M.answer + .6, 17, o(233, 339)), c(U - .3, 17, o(233, 339)),
    c(U + 1.1, 19, i(475, 334), -10, 4), c(U + 1.6, 18, i(475, 334), -4, 2), c(U + 2.6, 17, i(475, 334)),
    c(M.pic - .1, 17, i(475, 334)), c(M.pic + .6, 17, i(475, 334)), c(M.back + .2, 17, i(475, 334)),
    c(M.scroll + .8, 17, i(475, 334)), c(M['tap=合并'] - .2, 16.5, i(490, 360)), c(M['tap=合并'] + .4, 16.5, i(490, 360)),
    c(M.merged + .3, 16.5, i(490, 360)), c(M.end - 1.2, 17, i(475, 334)), c(M.end - 0.1, 20, i(475, 334), -12, 5),
  ];
};
