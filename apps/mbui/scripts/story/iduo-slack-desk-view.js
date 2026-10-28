// Film 5's two screens framed (compose_sim.mjs, FILM_DESK_VIEW): the computer's window and the phone each brought up
// big in turn, as what happens is on the one or the other, and what just came in on the window (the thread beside the
// channel) nearer still while it is read: [t, the window's scale, its offset across and down (from where film.html lays
// it), the phone's picture offset across]. Its camera (iduo-slack-desk-sim.cam3d.js) on the same marks.
export default (M) => {
  const slack = [1.85, 71, -244, 1500], thread = [2.2, -779, -427, 1500], phone = [1, -1150, 0, 0], both = [1, 0, 0, 470];
  const R = M["tap=row"], A = M.answer, G = M.merged, F = M.start + 2.0;
  const v = (t, s) => [t, ...s];
  return [v(M.from, slack), v(F - 0.6, slack), v(F + 0.2, thread), v(R - 0.7, thread), v(R + 0.2, phone), v(A + 2.0, phone),
    v(A + 2.8, thread), v(G + 1.2, thread), v(G + 2.0, both)];
};
