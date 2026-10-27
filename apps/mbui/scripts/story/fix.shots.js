// Film 1's camera and spotlight, by its marks (s): camera [t, zoom, X, Y] (the point of the open device's picture at
// the centre: cl(x, y) a closed screen's point, op(x, y) the open screen's), spotlight [t, x, y, w, h, dim] in screen
// points (none in this one).
const cl = (x, y) => [1100 + 0.89 * (84 + x * 1080 / 411), 24 + 0.89 * (66 + y * 2364 / 900)];
const op = (x, y) => [62 + x * 2076 / 791, 58 + y * 2152 / 820];
export default (M) => {
  const U = M.unfold;
  const c = (t, z, p) => [t, z, ...p];
  return {
    cam: [
      c(0, 1, cl(205, 450)), c(M['tap=发消息'] - .2, 1, cl(205, 450)), c(M['kb-up'] + .5, 1.6, cl(205, 660)),
      c(M['tap=send'] + .1, 1.6, cl(205, 660)), c(M['kb-down'] + .5, 1.15, cl(205, 500)), c(M.working + .6, 1.9, cl(205, 500)),
      c(M.answer - .5, 1.9, cl(205, 500)), c(M.answer + .5, 1.65, cl(240, 410)), c(M.swipe + 1.2, 1.65, cl(240, 410)),
      c(U, 1.05, cl(205, 450)), c(U + 1.1, .98, op(395, 410)), c(U + 1.6, .98, op(395, 410)),
      c(M.pic - .6, 1.3, op(360, 380)), c(M.pic + .1, 1.3, op(360, 380)), c(M.pic + .6, .98, op(395, 410)),
      c(M.back + .2, .98, op(395, 410)), c(M.scroll + 1.0, 1.0, op(395, 410)), c(M['tap=合并'] - .2, 1.45, op(360, 520)),
      c(M['tap=合并'] + .4, 1.45, op(360, 520)), c(M.merged + .3, 1.35, op(420, 560)), c(M.end - 2.6, 1.35, op(420, 560)), c(M.end - 1.6, .98, op(395, 410)),
    ],
    // no spotlight: the camera alone leads the eye
    spot: [
      [0, 0, 0, 411, 900, 0],
    ],
  };
};
