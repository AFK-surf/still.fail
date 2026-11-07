// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// origin: FreeBSD /usr/src/lib/msun/src/e_logf.c
// origin: FreeBSD /usr/src/lib/msun/src/s_log1pf.c
//
// Conversion to float by Ian Lance Taylor, Cygnus Support, ian@cygnus.com.
//
//
// ====================================================
// Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
//
// Developed at SunPro, a Sun Microsystems, Inc. business.
// Permission to use, copy, modify, and distribute this
// software is freely granted, provided that this notice
// is preserved.
// ====================================================
//

///|
pub fn ln(x : Double) -> Double {
  let l1 = 6.666666666666735130e-01 // 3FE55555 55555593
  let l2 = 3.999999999940941908e-01 // 3FD99999 9997FA04
  let l3 = 2.857142874366239149e-01 // 3FD24924 94229359
  let l4 = 2.222219843214978396e-01 // 3FCC71C5 1D8E78AF
  let l5 = 1.818357216161805012e-01 // 3FC74664 96CB03DE
  let l6 = 1.531383769920937332e-01 // 3FC39A09 D078C69F
  let l7 = 1.479819860511658591e-01 // 3FC2F112 DF3E5244
  if x < 0.0 {
    return @double.not_a_number
  } else if x.is_nan() || x.is_inf() {
    return x
  } else if x == 0.0 {
    return @double.neg_infinity
  }
  let (f1, ki) = frexp(x)
  let (f, k) = if f1 < SQRT2 / 2.0 {
    (f1 * 2.0 - 1.0, (ki - 1).to_double())
  } else {
    (f1 - 1.0, ki.to_double())
  }
  let s = f / (2.0 + f)
  let s2 = s * s
  let s4 = s2 * s2
  let t1 = s2 * (l1 + s4 * (l3 + s4 * (l5 + s4 * l7)))
  let t2 = s4 * (l2 + s4 * (l4 + s4 * l6))
  let r = t1 + t2
  let hfsq = 0.5 * f * f
  k * LN2_HI - (hfsq - (s * (hfsq + r) + k * LN2_LO) - f)
}

///|
pub fn log2(x : Double) -> Double {
  let (f, e) = frexp(x)
  if f == 0.5 {
    return e.to_double() - 1.0
  }
  ln(f) / LN2 + e.to_double()
}
