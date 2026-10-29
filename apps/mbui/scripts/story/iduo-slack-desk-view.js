// Film 5's two screens framed (compose_sim.mjs, FILM_DESK_VIEW): the computer's window and the phone each brought up
// big in turn, as what happens is on the one or the other: the channel's box while Ana types into it (its message, its 👀 and its replies over the box, the thread not open yet), the thread beside
// the channel while the agent answers there, Lin's phone while Lin answers on it, the two side by side at the end:
// [t, the window's scale, its offset across and down (from where film.html lays it), the phone's picture offset across].
// Its camera (iduo-slack-desk-sim.cam3d.js) and lines under the picture (iduo-slack-captions.js) on the same marks.
export default (M) => {
  const box = [2.5, -538, -927, 1500], thread = [3.0, -1406, -545, 1500], phone = [1, -1150, 0, 0], both = [1, 0, 0, 470];
  const S = M.start, P = M.read, D = M['tap=deploy'], E = M.end;
  const v = (t, s) => [t, ...s];
  return [v(M.from, box), v(S + 4.9, box), v(S + 5.6, thread), v(P - 0.5, thread), v(P + 0.2, phone), v(D + 0.8, phone),
    v(D + 1.5, thread), v(E - 2.2, thread), v(E - 1.3, both)];
};
