///|
/// What `src` logs, a line each (or what it threw).
fn logs(src : String) -> String {
  let r = @js.Realm::new()
  let out = try {
    r.run(src) |> ignore
    r.drain()
    ""
  } catch {
    Throw(v) => "threw " + r.to_display(v)
  }
  (r.log.map(fn(l) { l.view(start_offset=5).to_owned() }).join("\n") + (if out == "" { "" } else { "\n" + out })).trim(chars="\n").to_string()
}

///|
test "values, operators, control flow" {
  inspect(logs("console.log(1 + 2, '3' + 4, 7 / 2, 2 ** 10, -7 % 3, 0.1 + 0.2)"), content="3 34 3.5 1024 -1 0.30000000000000004")
  inspect(logs("let s = 0; for (let i = 0; i < 10; i++) { if (i % 2) continue; s += i } console.log(s)"), content="20")
  inspect(logs("const a = [3, 1, 2]; a.sort(); console.log(a.join('-'), a.map(x => x * 2), typeof a, Array.isArray(a))"), content="1-2-3 2,4,6 object true")
  inspect(logs("let x = null; console.log(x ?? 'd', x?.y, x?.y.z, (1, 2))"), content="d undefined undefined 2")
  inspect(logs("outer: for (const a of [1,2,3]) { for (const b of [1,2,3]) { if (b == 2) continue outer; if (a == 3) break outer; console.log(a, b) } }"), content="1 1\n2 1")
  inspect(logs("switch (2) { case 1: console.log('one'); case 2: console.log('two'); case 3: console.log('three'); break; default: console.log('d') }"), content="two\nthree")
}

///|
test "functions, closures, this, classes" {
  inspect(logs("function mk() { let n = 0; return () => ++n } const f = mk(); f(); f(); console.log(f())"), content="3")
  inspect(logs("const o = { n: 2, get double() { return this.n * 2 }, inc() { this.n++ } }; o.inc(); console.log(o.double)"), content="6")
  inspect(
    logs(
      #|class A { x = 1; constructor(y) { this.y = y } sum() { return this.x + this.y } static make() { return new A(5) } }
      #|class B extends A { constructor() { super(10); this.z = 3 } sum() { return super.sum() + this.z } }
      #|console.log(A.make().sum(), new B().sum(), new B() instanceof A)
      ,
    ),
    content="6 14 true",
  )
  inspect(logs("const {a, b: [c, d = 4], ...rest} = {a: 1, b: [3], e: 5, f: 6}; console.log(a, c, d, JSON.stringify(rest))"), content="1 3 4 {\"e\":5,\"f\":6}")
  inspect(logs("function f(a, b = a + 1, ...more) { return [a, b, more.length].join() } console.log(f(1), f(1, 5, 7, 8))"), content="1,2,0 1,5,2")
  inspect(logs("try { null.x } catch (e) { console.log(e instanceof TypeError, e.message) } finally { console.log('done') }"), content="true Cannot read properties of null (reading 'x')\ndone")
}

///|
test "builtins" {
  inspect(logs("console.log(`a${1 + 1}b`, 'x,y'.split(','), ' t '.trim(), 'ab'.padStart(4, '-'), 'Hello'.replace('l', 'L'))"), content="a2b x,y t --ab HeLlo")
  inspect(logs("console.log((1234567.891).toLocaleString(), (0.256).toLocaleString(undefined, {style: 'percent'}), (3.14159).toFixed(2))"), content="1,234,567.891 26% 3.14")
  inspect(logs("console.log(JSON.stringify({a: [1, {b: 'c'}], d: undefined}), JSON.parse('{\"x\": [1, 2.5]}').x[1])"), content="{\"a\":[1,{\"b\":\"c\"}]} 2.5")
  inspect(logs("const m = new Map([['a', 1]]); m.set('b', 2); console.log(m.size, [...m.keys()].join(), new Set([1, 1, 2]).size)"), content="2 a,b 2")
  inspect(logs("console.log(Math.max(1, 5, 3), Math.round(2.5), Math.floor(-1.5), Object.entries({x: 1}).flat().join())"), content="5 3 -2 x,1")
  inspect(logs("console.log('2026-11-10'.replace(/(\\d+)-(\\d+)-(\\d+)/, '$3/$2/$1'), /^a.c$/i.test('ABC'), 'a1b22c'.match(/\\d+/g).join('|'))"), content="10/11/2026 true 1|22")
  inspect(logs("Promise.resolve(1).then(x => console.log('then', x)); console.log('first')"), content="first\nthen 1")
  inspect(logs("console.log(new Date(Date.UTC(2026, 10, 10)).toISOString())"), content="2026-11-10T00:00:00.000Z")
}

///|
test "a script that runs on is stopped" {
  let r = @js.Realm::new(budget=10000)
  let threw = try {
    r.run("while (true) {}") |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(threw)
}
