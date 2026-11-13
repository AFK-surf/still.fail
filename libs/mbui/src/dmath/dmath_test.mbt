///|
test "the same digits on every machine and target: fdlibm's, as MoonBit core's examples have them" {
  inspect(@dmath.sin(2.0), content="0.9092974268256817")
  inspect(@dmath.sin(-5.0), content="0.9589242746631385")
  inspect(@dmath.cos(2.5), content="-0.8011436155469337")
  inspect(@dmath.cos(-5.0), content="0.28366218546322625")
  inspect(@dmath.sin(31415926535897.9323846), content="0.0012091232715481885")
  inspect(@dmath.cos(31415926535897.9323846), content="0.9999992690101899")
  inspect(@dmath.tan(4.0), content="1.1578212823495777")
  inspect(@dmath.exp(1.0), content="2.718281828459045")
  inspect(@dmath.ln(10.0), content="2.302585092994046")
  inspect(@dmath.pow(2.0, 0.5), content="1.4142135623730951")
  inspect(@dmath.atan2(1.0, 1.0), content="0.7853981633974483")
}
