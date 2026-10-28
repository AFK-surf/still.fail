// The Galaxy Z Fold film's camera in 3D (compose3d.mjs, zfold3d), by its marks (s): [t, dist, x, y, yaw, pitch],
// looking at (x, y) of the phone (zfold3d/film.js's units: the inner screen 13.73 x 15.24 about the middle; folded, the
// cover screen 6.57 x 15.34 over the right half) from dist away. o(x, y) a point of the cover screen (411 x 960
// points), i(x, y) of the inner one (750 x 832). The whole of the screen in use always in view.
const OW = 6.57, OH = 15.34, IW = 13.73, IH = 15.24;
const o = (x, y) => [3.58 - OW / 2 + x / 411 * OW, OH / 2 - y / 960 * OH];
const i = (x, y) => [-IW / 2 + x / 750 * IW, IH / 2 - y / 832 * IH];
export default (M) => {
  const U = M.unfold;
  const c = (t, d, p, yaw = 0, pitch = 0) => [t, d, ...p, yaw, pitch];
  return [
    c(0, 30, o(205, 480), -10, 5), c(M['tap=发消息'] - .3, 27, o(205, 480), -5, 2), c(M['tap=发消息'] + .6, 25, o(205, 480)),
    c(M['tap=send'] + .1, 25, o(205, 480)), c(M['kb-down'] + .5, 25, o(205, 480)), c(M.answer + .6, 25, o(205, 480)),
    c(U - .3, 26, o(205, 480), -4, 2), c(U + 1.1, 30, i(375, 416), -10, 4), c(U + 1.6, 28, i(375, 416), -4, 2),
    c(U + 2.6, 27, i(375, 416)), c(M['tap=合并'] + .4, 27, i(375, 416)), c(M.end - 1.2, 27, i(375, 416)),
    c(M.end - 0.1, 32, i(375, 416), -12, 5),
  ];
};
