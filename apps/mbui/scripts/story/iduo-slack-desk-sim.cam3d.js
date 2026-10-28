// Film 5's camera with a computer's window beside the phone (FILM_DESK): the folded phone's outer screen near while it
// is the one in use (iduo-slack-desk-view.js brings it to the middle), far while the window is, the two side by side at
// the end.
const o = (x, y) => [.247 + x / 466 * 8.18, -5.6 + (1 - y / 678) * 11.9];
export default (M) => {
  const R = M['tap=row'], D = M['tap=deploy'], G = M.merged, E = M.end;
  const c = (t, d, p, yaw = 0, pitch = 0) => [t, d, ...p, yaw, pitch];
  return [c(M.from, 30, o(233, 339)), c(R - 0.7, 30, o(233, 339)), c(R + 0.2, 17, o(233, 339), -3, 2), c(D + 0.7, 17, o(233, 339)),
    c(D + 1.5, 30, o(233, 339)), c(G + 0.2, 30, o(233, 339)), c(G + 1.0, 17, o(233, 339), -3, 2), c(E - 2.2, 17, o(233, 339)),
    c(E - 1.3, 30, o(233, 339)), c(E - 0.1, 32, o(233, 339), -6, 3)];
};
