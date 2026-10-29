// Film 5's lines under the picture (compose_sim.mjs, FILM_CAPTIONS): what happens, in a few words, on the same marks as
// its framing (iduo-slack-desk-view.js): [from, to, words].
export default (M) => {
  const S = M.start, P = M.read, D = M['tap=deploy'], E = M.end;
  return [[M.from + 0.2, S + 2.0, 'Ana asks in Slack'], [S + 2.3, S + 3.7, 'still.fail looks into it'],
    [S + 4.0, P - 0.5, 'It needs Lin’s OK'], [P, D + 0.7, 'Lin taps once, on the go'], [D + 1.3, E - 1.6, 'Fixed, back in the thread']];
};
