// Film 5's camera with a computer's window beside the phone (FILM_DESK): the phone near while it is the one in use
// (iduo-slack-desk-view.js brings it to the middle), nearer still on the agent's answer as it comes in, far while the
// window is, the two side by side at the end.
const o = (x, y) => [.247 + x / 466 * 8.18, -5.6 + (1 - y / 678) * 11.9];
const i = (x, y) => [-7.9 + x / 951 * 15.8, -5.55 + (1 - y / 669) * 11.1];
export default (M) => {
  const U = M.unfold3d, R = M['tap=row'], A = M.answer, G = M.merged;
  const c = (t, d, p, yaw = 0, pitch = 0) => [t, d, ...p, yaw, pitch];
  return [c(M.from, 30, o(233, 339)), c(R - 0.7, 30, o(233, 339)), c(R + 0.2, 17, o(233, 339)), c(U - .3, 17, o(233, 339)),
    c(U + 1.1, 19, i(475, 334), -8, 3), c(U + 2.6, 17, i(475, 334)), c(A - 0.2, 17, i(475, 334)), c(A + 0.5, 12.5, i(560, 300)),
    c(A + 1.8, 12.5, i(560, 300)), c(A + 2.6, 36, i(475, 334)), c(G + 1.2, 36, i(475, 334)), c(G + 2.0, 36, i(475, 334)),
    c(M.end - 0.1, 39, i(475, 334), -6, 3)];
};
