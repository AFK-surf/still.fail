// The iPhone Duo film's camera, by its marks (s): [t, zoom, X, Y], the point of the open device's picture at the
// centre: cl(x, y) a point of the outer screen (466 x 678), op(x, y) of the inner (890 x 626). No spotlight.
const cl = (x, y) => [1546 + 0.982 * (86 + x * 1402 / 466), 46 + 0.982 * (78 + y * 2038 / 678)];
const op = (x, y) => [118 + x * 2857 / 890, 118 + y * 2011 / 626];
export default (M) => {
  const U = M.unfold;
  const c = (t, z, p) => [t, z, ...p];
  return {
    cam: [
      c(0, 1, cl(233, 339)), c(M['tap=发消息'] - .2, 1, cl(233, 339)), c(M['kb-up'] + .5, 1.5, cl(233, 470)),
      c(M['tap=send'] + .1, 1.5, cl(233, 470)), c(M['kb-down'] + .5, 1.1, cl(233, 380)), c(M.working + .6, 1.7, cl(233, 430)),
      c(M.answer - .5, 1.7, cl(233, 430)), c(M.answer + .5, 1.55, cl(240, 300)), c(M.swipe + 1.2, 1.55, cl(240, 300)),
      c(U, 1.0, cl(233, 339)), c(U + 1.1, .9, op(445, 313)), c(M['tap=chats'] + .3, .9, op(445, 313)),
      c(M['tap=chats'] + 1.6, 1.3, op(380, 320)), c(M.pic - .1, 1.3, op(380, 320)), c(M.pic + .6, .9, op(445, 313)),
      c(M.back + .2, .9, op(445, 313)), c(M.scroll + 1.0, .95, op(445, 313)), c(M['tap=合并'] - .2, 1.35, op(380, 480)),
      c(M['tap=合并'] + .4, 1.35, op(380, 480)), c(M.merged + .3, 1.3, op(450, 520)), c(M.end - 2.6, 1.3, op(450, 520)), c(M.end - 1.6, .9, op(445, 313)),
    ],
    spot: [[0, 0, 0, 466, 678, 0]],
  };
};
