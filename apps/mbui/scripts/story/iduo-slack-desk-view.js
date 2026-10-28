// Film 5's two screens framed (compose_sim.mjs, FILM_DESK_VIEW): the computer's window and the phone each brought up
// big in turn, as what happens is on the one or the other: [t, the window's scale, its offset across and down (from
// where film.html lays it), the phone's picture offset across]. Its camera (iduo-slack-desk-sim.cam3d.js) on the same
// marks.
export default (M) => {
  const slack = [1.85, 71, -244, 1500], phone = [1, -1150, 0, 0], both = [1, 0, 0, 470];
  const R = M['tap=row'], A = M.answer, G = M.merged;
  const v = (t, s) => [t, ...s];
  return [v(M.from, slack), v(R - 0.5, slack), v(R + 0.3, phone), v(A + 0.2, phone), v(A + 0.9, slack), v(G - 0.1, slack),
    v(G + 0.8, both)];
};
