(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)
  ;; This probe's diagnostic output is ASCII only.
  (func (export "print_char") (param $c i32)
    (i32.store (i32.const 0) (i32.const 16))
    (i32.store (i32.const 4) (i32.const 1))
    (i32.store8 (i32.const 16) (local.get $c))
    (drop (call $write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8))))
  ;; Timing belongs to the outer benchmark, never to layout or model code.
  (func (export "now") (result f64)
    (if (call $clock (i32.const 1) (i64.const 1000) (i32.const 24))
      (then unreachable))
    (f64.div (f64.convert_i64_u (i64.load (i32.const 24))) (f64.const 1000000))))
