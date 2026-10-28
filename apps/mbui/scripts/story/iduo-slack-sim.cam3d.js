// Film 5's camera (a chat from Slack picked up on the phone) from the iPhone Duo simulator (compose_sim.mjs, FILM_CAM):
// on the folded phone's outer screen while it is read there, then the inner screen once it opens, each whole in view.
const o = (x, y) => [.247 + x / 466 * 8.18, -5.6 + (1 - y / 678) * 11.9];
const i = (x, y) => [-7.9 + x / 951 * 15.8, -5.55 + (1 - y / 669) * 11.1];
export default (M) => {
  const U = M.unfold3d;
  const c = (t, d, p, yaw = 0, pitch = 0) => [t, d, ...p, yaw, pitch];
  return [c(M.from, 20, o(233, 339), -8, 4), c(M.from + 1.4, 17, o(233, 339), -4, 2), c(U - .3, 17, o(233, 339)),
    c(U + 1.1, 19, i(475, 334), -10, 4), c(U + 1.6, 18, i(475, 334), -4, 2), c(U + 2.6, 17, i(475, 334)),
    c(M.end - 1.2, 17, i(475, 334)), c(M.end - 0.1, 20, i(475, 334), -12, 5)];
};
