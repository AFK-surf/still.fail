// Film 2's camera (a picture marked up and sent back) from the iPhone Duo simulator (compose_sim.mjs, FILM_CAM), as
// film 1's (iduo-sim.cam3d.js): [t, dist, x, y, yaw, pitch] by its marks, the whole screen in use always in view.
const o = (x, y) => [.247 + x / 466 * 8.18, -5.6 + (1 - y / 678) * 11.9];
const i = (x, y) => [-7.9 + x / 951 * 15.8, -5.55 + (1 - y / 669) * 11.1];
export default (M) => {
  const U = M.unfold3d;
  const c = (t, d, p, yaw = 0, pitch = 0) => [t, d, ...p, yaw, pitch];
  // (from a later moment, FILM_FROM: the phone open from the first, coming nearer)
  const late = M.from > 0 ? [c(M.from, 19, i(475, 334), -10, 4), c(M.from + 1.4, 17, i(475, 334))] : [];
  if (late.length) {
    return [...late, c(M.mark - .2, 17, i(475, 334)), c(M.offer + .2, 17, i(475, 334)), c(M['tap=send2'] + .6, 17, i(475, 334)),
      c(M.merged + .3, 17, i(475, 334)), c(M.end - 1.2, 17, i(475, 334)), c(M.end - 0.1, 20, i(475, 334), -12, 5)];
  }
  return [
    c(0, 20, o(233, 339), -8, 4), c(M['tap=发消息'] - .3, 18, o(233, 339), -4, 2), c(M['tap=发消息'] + .6, 17, o(233, 339)),
    c(M.answer + .6, 17, o(233, 339)), c(U - .3, 17, o(233, 339)),
    c(U + 1.1, 19, i(475, 334), -10, 4), c(U + 1.6, 18, i(475, 334), -4, 2), c(U + 2.6, 17, i(475, 334)),
    c(M.mark - .2, 17, i(475, 334)), c(M.offer + .2, 17, i(475, 334)),
    c(M['tap=send2'] + .6, 17, i(475, 334)), c(M.merged + .3, 17, i(475, 334)),
    c(M.end - 1.2, 17, i(475, 334)), c(M.end - 0.1, 20, i(475, 334), -12, 5),
  ];
};
