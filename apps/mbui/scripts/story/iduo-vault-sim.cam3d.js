// Film 3.s camera (a key typed into the vault) from the iPhone Duo simulator (compose_sim.mjs, FILM_CAM; the film
// from a later mark, FILM_FROM): the phone open from the first, coming nearer, the whole inner screen in view throughout.
const i = (x, y) => [-7.9 + x / 951 * 15.8, -5.55 + (1 - y / 669) * 11.1];
export default (M) => {
  const c = (t, d, p, yaw = 0, pitch = 0) => [t, d, ...p, yaw, pitch];
  return [c(M.from, 19, i(475, 334), -10, 4), c(M.from + 1.4, 17, i(475, 334)), c(M.end - 1.2, 17, i(475, 334)),
    c(M.end - 0.1, 20, i(475, 334), -12, 5)];
};
