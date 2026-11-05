Each package contains one deliberate panic. A Wasm panic leaves the instance
without unwinding its MoonBit scopes, and the test runner continues in that
instance. Separate test executables make every prohibited operation exercise its
own guard and keep successful view tests independent of a terminated calculation.

Run all six with `moon test --target wasm-gc --release src/view/faults/*/`.
They are also selected by the framework test script's default package set.
