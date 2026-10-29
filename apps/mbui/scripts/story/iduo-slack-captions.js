// Film 5's lines under the picture (compose_sim.mjs, FILM_CAPTIONS): what happens, in a few words, on the same marks as
// its framing (iduo-slack-desk-view.js): [from, to, words].
export default (M) => {
  const S = M.start, P = M.read, D = M['tap=deploy'], E = M.end;
  return [[M.from + 0.2, S + 2.0, 'Ana asks in Slack'], [S + 2.3, S + 3.7, 'still.fail looks into it'],
    [S + 4.0, P - 0.5, 'It needs Lin’s deploy key'], [P, D + 3.0, 'Only Lin’s fingerprint unlocks it'], [D + 3.8, M.answer - 0.3, 'Deploying with Lin’s key'], [M.answer, E - 1.6, 'Fixed, back in the thread']];
};
