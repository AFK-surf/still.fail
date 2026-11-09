// unicode-vo's Vertical_Orientation (UAX #50, Unicode 11): the ranges in its order, first match wins, 1 where
// a character is upright (U); everything not listed is rotated.
// Written as text (mbui/shape's packed.mbt), not an array literal.

///|
let vo_ranges : FixedArray[Int] = @shape.packed_ints(
  (
    #|^:^:2b:b:2l:l:2R;R;2h;l;2^=^=2^?^?2d^1f^12P`8no82RP:nW;2P[<n_<2\Q@\Q@2PR@RR@2PS@RS@2fS@hS@2TT@TT@2^T@bT@2R
    #|U@RU@2ZV@ZV@2j]@P^@2T^@X^@2P`@R`@2V`@b`@2n`@n`@2Va@Xa@2\a@^a@2la@Vb@2Zb@Zb@2^b@^b@2bb@bb@2lb@lb@2Zc@nc@2Zd
    #|@dd@2hd@jd@2nd@nd@2Pe@bh@2hh@nh@2lQAlQA2XSAZSA2P`A^`A2h`AnaA2XbA`bA2bbAdbA0fbAfbA2jgAdiA2lkAjlA2nlAnlA2RmA
    #|fmA2TnAnoA2PPBTRB2XRBnSB2PTBnUB2PVBn_B2PjBnoB2PPCbQC2PRCn_C2P`C^fC2\gCViC2TaEnbE2PeEbeE2`kEfnE2PoEnoE2PXGn
    #|_G2P`GnmG2PnGnnG2PoGnoG2PPHPPH2RPHTPH0VPH^PH2`PHRQH0TQHVQH2XQHnQH0PRHnRH2PSHPSH0RSHPTH2RTHRTH0TTHTTH2VTHVT
    #|H0XTHXTH2ZTHZTH0\TH\TH2^TH^TH0`TH`TH2bTHbTH0dTHTVH2VVHVVH0XVHTXH2VXHVXH0XXHXXH2ZXHZXH0\XH\XH2^XH^XH0`XHjXH
    #|2lXHlXH0nXHXYH2ZYH\YH0^YHdYH2fYHhYH0jYHnYH2PZHPZH0RZHRZH0TZHTZH2VZHVZH0XZHXZH2ZZHZZH0\ZH\ZH2^ZH^ZH0`ZH`ZH2
    #|bZHbZH0dZHT\H2V\HV\H0X\HT^H2V^HV^H0X^HX^H2Z^HZ^H0\^H\^H2^^H^^H0`^Hj^H2l^Hl^H0n^HX_H2Z_H\_H0^_Hf_H2h_Hh_H0j
    #|_Hn_H2P`H\bH2^bH^bH0`bHnbH2PcHnhH2PiHniH2PjHnkH2PlHnnH2PoHnoH0PPIlQI2nQIn_I2P`I^eI0`eIdgI2fgIngI0PhInoI2PP
    #|JnkV12PlV1noV12PPW1no_22PP`2nXb22PYb2n\b22Pfd2ngd22PPf2nj[32Pk[3no[32PP`3n_l32P`l3n_m32PQo3bQo32dQo3nQo32P
    #|So3`To32PUo3TUo30VUo3^Uo32bUo3lUo30nUo3TVo32^Vo3fVo32hVo3nVo32R`o3R`o30T`o3^`o32``o3b`o30d`o3f`o32h`o3h`o3
    #|0l`o3l`o30n`o3bao32dao3fao30nao3nao30Pbo3Pbo32Rbo3dco32fco3fco30hco3hco32jco3jco30lco3lco32nco3nco30Pdo3Pd
    #|o32Rdo3deo32feo3Pfo30Pno3Tno32Vno3Vno30Xno3^no32Poo3`oo32hoo3joo32PhT4niT42PhZ4noZ42PPh4nRj42PPR5nWS52Png5
    #|nog52PPh5noS62PPT6n_U62PPh6n_h62PPX7n_X72P`X7noX72P`Y7neY72PfY7ngY72PP\7nZ]72PPh7nRh72PSh7nYh72PZh7n_h72P`
    #|h7noh72PPi7RPi70TPi7n_i72P`i7noj72PPk7nTk72PUk7nWk72PXk7n_k72P`k7ngk72Phk7nok72P`l7nol72PPP8n]c:2P^c:n_c:2
    #|P`c:nck:2Pdk:nQl:2PRl:nZW;2P[W;nok;2PPl;nQm;2PRm;joo;2PPP<joo?2PPPl1jooo12PPPP2jooS22
  ),
)

///|
/// unicode-vo's char_orientation is Upright.
fn is_upright(c : Int) -> Bool {
  let mut i = 0
  while i < vo_ranges.length() {
    if c >= vo_ranges[i] && c <= vo_ranges[i + 1] {
      return vo_ranges[i + 2] == 1
    }
    i += 3
  }
  false
}
