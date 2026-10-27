// The iPhone Duo film's camera in 3D, by its marks (s): [t, dist, x, y, yaw, pitch], looking at (x, y) of the open
// phone (its units: the inner screen 15.8 x 11.1 about the middle; folded, the outer screen on the right half) from
// dist away. o(x, y) a point of the outer screen (466 x 678 points), i(x, y) of the inner (890 x 626).
const o = (x, y) => [.247 + x / 466 * 8.18, -5.6 + (1 - y / 678) * 11.9];
const i = (x, y) => [-7.9 + x / 890 * 15.8, -5.55 + (1 - y / 626) * 11.1];
export default (M) => {
  const U = M.unfold;
  const c = (t, d, p, yaw = 0, pitch = 0) => [t, d, ...p, yaw, pitch];
  return [
    c(0, 20, o(233, 339), -8, 4), c(M['tap=发消息'] - .2, 19, o(233, 339), -4, 2), c(M['kb-up'] + .5, 12.5, o(233, 470)),
    c(M['tap=send'] + .1, 12.5, o(233, 470)), c(M['kb-down'] + .5, 17, o(233, 380)), c(M.working + .6, 11, o(233, 430)),
    c(M.answer - .5, 11, o(233, 430)), c(M.answer + .5, 12, o(240, 300)), c(M.swipe + 1.2, 12, o(240, 300)),
    c(U - .2, 19, o(233, 339), -6, 3), c(U + 1.2, 19, i(445, 313), -10, 4), c(U + 1.6, 18, i(445, 313), -4, 2),
    c(U + 2.4, 14, i(380, 320)), c(M.pic - .1, 14, i(380, 320)), c(M.pic + .6, 17.5, i(445, 313)),
    c(M.back + .2, 17.5, i(445, 313)), c(M.scroll + 1.0, 17, i(445, 313)), c(M['tap=合并'] - .2, 12.5, i(380, 480)),
    c(M['tap=合并'] + .4, 12.5, i(380, 480)), c(M.merged + .3, 13, i(450, 520)), c(M.end - 2.6, 13, i(450, 520)), c(M.end - 1.6, 20, i(445, 313), -12, 5),
  ];
};
