// Film 5's two screens framed (compose_sim.mjs, FILM_DESK_VIEW): the computer's window and the phone each brought up
// big in turn, as what happens is on the one or the other, the window's thread (beside the channel) nearer still while
// it is read: [t, the window's scale, its offset across and down (from where film.html lays it), the phone's picture
// offset across]. Its camera (iduo-slack-desk-sim.cam3d.js) on the same marks.
export default (M) => {
  const slack = [1.85, 71, -244, 1500], thread = [2.2, -779, -427, 1500], phone = [1, -1150, 0, 0], both = [1, 0, 0, 470];
  const S = M.start, R = M['tap=row'], D = M['tap=deploy'], G = M.merged, E = M.end;
  const v = (t, s) => [t, ...s];
  return [v(M.from, slack), v(S + 0.6, slack), v(S + 1.4, thread), v(R - 0.7, thread), v(R + 0.2, phone), v(D + 0.7, phone),
    v(D + 1.5, thread), v(G + 0.2, thread), v(G + 1.0, phone), v(E - 2.2, phone), v(E - 1.3, both)];
};
