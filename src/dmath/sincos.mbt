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

///|
pub fn sin(x : Double) -> Double {
  if x.is_inf() || x.is_nan() {
    return @double.not_a_number
  }
  let y = [0.0, 0.0]
  let z = 0.0
  if x.abs() <= PI_OVER_4 {
    return __kernel_sin(x, z, 0)
  } else {
    let n = rem_pio2(x, y)
    match n & 3 {
      0 => __kernel_sin(y[0], y[1], 1)
      1 => __kernel_cos(y[0], y[1])
      2 => -__kernel_sin(y[0], y[1], 1)
      _ => -__kernel_cos(y[0], y[1])
    }
  }
}

///|
pub fn cos(x : Double) -> Double {
  if x.is_inf() || x.is_nan() {
    return @double.not_a_number
  }
  let y = [0.0, 0.0]
  let z = 0.0
  if x.abs() <= PI_OVER_4 {
    return __kernel_cos(x, z)
  } else {
    let n = rem_pio2(x, y)
    match n & 3 {
      0 => __kernel_cos(y[0], y[1])
      1 => -__kernel_sin(y[0], y[1], 1)
      2 => -__kernel_cos(y[0], y[1])
      _ => __kernel_sin(y[0], y[1], 1)
    }
  }
}
