// Unzipping (inflate.mbt) and hashing (sha256.mbt) against what Python's gzip, zlib and hashlib make of the same.

///|
test "a short text, in deflate's fixed codes" {
  let out = @zip.gunzip(@codec.from_base64("H4sIAAAAAAAC/8tIzcnJ11HIQKKsFAz8FQxzPAFXvYeJGwAAAA==")).unwrap()
  assert_eq(out, b"hello, hello, hello: 0O 1lI")
  assert_eq(@zip.crc32(out), 2307374423U)
}

///|
test "nothing gzipped" {
  assert_eq(@zip.gunzip(@codec.from_base64("H4sIAAAAAAAC/wMAAAAAAAAAAAA=")).unwrap().length(), 0)
}

///|
test "a longer text, in a block's own codes: as long and with the hash Python's said" {
  let gz = @codec.from_base64(
    (
  #|H4sIAAAAAAAC/23bzQ3kynUG0D2jqBBYvyTDMSQLECBBgOTF5OGFo3AIzkbKw2c00836W9bXwDzWTNW953bznecZ/vS3v/81hPN44hP+8V9//s
  #|tfwo8Qjzvf4U//8WeLHyEdV73Cv/73f/75f/9t/SPko10t/OFvf/zPn8sfoRz1qb/+oB//DupRY/n8ab+idpScP3/kr+g6ck3dn/srvY90xfcP
  #|/xU+R3zO7r/wK43nEc9n+O/8/iAeZ7qH/9rvD9LxlO9eQszH3T47CbEc1/3dR4j1uM5uFyG2o6VuDyFeRy3jDkK8j9KG5w/xOfI9Pn1I55Ge+d
  #|FDikeK83OHlI6Yr/kv6ucH+Thrm/6ufubleK46/3X9/KAe9/PZUkjtuONnPyFdx5W7zYR0H62+OwnpOerVbSPk8yj3sIeQ41HOYQMhpyOn+elD
  #|zkcq06OHXI7Y5ucOuR7nXZZ/5ZDbcZ55+UcO+TqelNa/rp8f3cddfm8p5Oe42mc/oZwO9buZUKJD/e4klORMD9sIJTvT/R5CKY70sIFQqvM8PX
  #|0ozXmeHj2U64hxfe5Q7uPM840QP8dTlzvh7p3O9OZS+CQ637+3FKpbfb77CdWlTt/NhOpOl3cnoVbHut9GqM2p7vcQqgt9ThsI1X1O49OH6jqX
  #|6dFDOx3m5blDi87ycpVDS07y5k74xJ2O66Xwgeudf28ptOpwf/cTWnO2v5sJ7TrK0+8kNNc6dtsIzaXO/R7C5UqXcQPhik70PZW95Dwvjx4ul/
  #|mcnztcrnJarnK4XORSNpXvag513lS+6zra/d1SuFzu87OfcLna6buZcLvYudtJuKNz3W0j3MmpHvcQ7uxQDxsItwsdx6cPt+uc50cPd3Oa5+cO
  #|93Xc1+Yqh/s+rieule92p+O5qXyP650+WwqPy10++wlPcra7zYQnO9rvTsLjWp/dNsLjUqdhD+FxpcuwgfBcx9nmpw/PfTz39OjhcZnP+bn1N3
  #|c5rnfZB65yXhucD5JzfW2LXzyzQ/57W1bFGf9sytIF73q2wP3uOrbgOtLYr2X3EYduLXqOc+zV2rG7PTdqqas9d2mpm13WHfggO9rLxZYXJ3vt
  #|dj5wx8+yq4RRK6+fVm7lund9XHAf+W3i1s+Rug6OEeQxtG+Rqz70bpGbPjduaXbUx30Ii5M+bUKKIM+yA7lbHpdbLnfJ8671+eg+ao2bshj19f
  #|Lp60R0OvudBHX0/HZ0azd/aOciF7/v5ZLi5A8ijLr4M3VxoVs/tXChS7/2b7k7XxYZRm28tY0NNfR6bXGotZdnq0NNvsSOhzp8zp0PixvQAVFv
  #|j9cgRI39fAYi6upnnI2opT95QqJ+fk/9HEFPZ35hYtTJ2704Merp7dxBMeruNW2kGPX5UnZUjDp+/nZ8y+YKfLEY9frU93qJUtA1eoFC0Hd5fj
  #|ZljC1eZtYY+7uMTZbmLlYA5s4udf3zgkaOdN43aoxafbk2bIyafn72btTDj/xp/1bKwbf3mwIUg67xC4wfXdcXGDvGli9TBoZ+L1IExmYvUwLm
  #|Ti81isxtXmoeuTeCjLp9PVdCRn2/pI0hIwHkvEVkZIH0sYCV2aSDgABjXgVYKwUdAQQKwdD/RQaRofmLTCNz55dSy9T2hQrA3PPNXK5/WjkZtf
  #|5SVk9GCMhtC0pSd/R3ooxgkD4wsFIOXhVYKwYvCawNJoMHRAaSHgMSZWCQgFFREZgUIFQCJgEIDSlr95ebVK7FlgkB8rPi0pac9p0uExSkvONl
  #|ooP46sDa1PKVgSXgvCow6CoFvQgkCkGvAYkyMElAaE4ZFSAzrEwCECoAS/cXu/5pgWZCgFx20jSPH6ltqJmgIN47ayY6OL86sFQOvjKwVAx6FU
  #|iMLJ0IBEaVXgMSlhklIFMERgXIlIBFAGLjy9z9pWaYa1Gn0ua8b9SZWCCdG3UmKIhpr07HxS34qDORwfOVgaU5plOBQCnoRCBQCEYNyJSBQQIi
  #|E8yogJAIoMwCkALN3P2lrn/cqDMhQMqrOhMLxLpRZ4KC89qqM9HB89GBlXLQyUCgGLwqsDbMdCIIiQbaoAGRSWaQgEgRmBUgVQImAQgVgLn7S0
  #|03bVVnQoB4r+pMLBDPrTo1iuNMO3UmOng+OgiJDO5XBtbmm6v7BpII2iACkULQa0CiDAwSEJlqJgUITTaTAIRAs3Z/uesfF3UmBIh5VWdigbPs
  #|1Jmg4Gk7dSY6uF8dWCsHXxlYKgavCqyVgl4EEtNMrwGJiWaSgFARGBUgUwLS/N2k7p/y+uWkzh/r+u0kApzX9utJFnie3feTUPDE7ReUdHDn9x
  #|tKMrjq+xUlFbRr/I6SbJ7+S0oaqL0GQiKBMkpApgiMCpCZbBYBiE03c/eXuv7nos6EAGfaqDOxwFM26kxQcLe9OhMdXB8dWCkHXxmETAWtU4FA
  #|KehEIDDNjBqQmWgGCYggZlSATAmYBSBVAObuLzXh1I06jY3Hc63qzCxwPxt1Zii4z6064dsl+Kgzk0HrZCAw37wqsDbWdCIQKASDBkTKwCABkS
  #|IwK0BqspkEIDTdzN0/uEpO/KrOjABPXNWZWeDOW3V6NEd/p85MB+2jAyvOeWVgrRi8KrBWCgYRiEwzvQYkJppBAiFTQJwUIFQCJgEIFYC1+8td
  #|/7KoMyPA3VZ1Zha47p06jeBO/k6dmQ7aqwNr5eArA0vzzauCkIkg9yKQIE2vAYkyMElAqAiMCpCZbCYBCE03S/cXY82zqDMjwB136lScjitv1J
  #|mhoNWdOjMd1K8OLA06XxlYKga9CiRKQScCgULQa0BiohklIDPVjAqQKQGLAMQKwNz9pa5/WdSZEeCqz+5nHpPOtVFnhoL67NWZ6aB+dGClHHxl
  #|YGm+6VQgMNZ0IhAgzagBmTIwSECkCIwKCEDt1M/qzLr/PXd/qQnn3qgTT5z4VZ2ZBVraqDNDQS1bdSr3LsFHnZkMcicDgWLwqsBaKehEEDINxE
  #|EDIhPNIAGRqWZWgBRlJgEIFYC5+0td/7yqMyNAq6s6MwvUa6vODAXl2akz00H56CBkMsivDKwVg1cF1saaNv7yTQNnrwGJMjBIQKQITAoQKgGT
  #|AISmm7X7y00496LOjADtXNVZWKDGnTp5z8nfqbPQQX51YG3Q+crAEnBeFVgrBb0IJApBrwGJiWaSgNBUMypAhjKTAIJ/F2d+UWfR+dvyW77Y5S
  #|87dRYWKG2jzgIF+d6ps9BB/urAUjn4ysBSMehVIDHWdCIQmGZ6DYRCAvcoAZkiMCpApgQsAhCbbubuLzXhLD/si+Hm2ajTwOe4b9RZoCDnvToL
  #|HaSPDqwMOtf7KzkVnHf/MzkRnGf/OzkNPGn+oVwZKOMv5RRwtemncgJo9/Jbue7fzuXHcp2/pt2v5QhQyubnchbIbaPOAgXp2qrTn+MSfNRZyC
  #|B2MhAoBq8KrI01nQgEpplBAyKWGSQgUgRmBUiVgEkAQtPN3P1D0fnL+pO/3JRzr+osLJDPrToLFKS0U6cx2i34qLOQwfnKwNp886rAWikYRCBS
  #|CHoNSJSBQQKB1pz7SZ2FAOokACHQrN1f7vovv/+LXf68qrOwQKo7daohTv5OnYUOzlcH1srBVwaWisGrglCI4O5FIDHN9BqQmGgmCQgVgVEBMi
  #|VgEoBQAVi6v9iEs7wMIDbl3Dt1FhZI50adBQpi2qmz0MH51YGlQecrA0vzTa8CCdl0IhAoBL0GJMrAKAGZqWZUgMxkswhADDRz95e6/subAaEg
  #|QEobdfKD475RZ4GCs+3VWejg+ejASjn4ysBSMehUIFAKOhEITDOjBmQmmkECIkVgVECwdupndVbdP8/dX2rC2bwj4ANTzrWqs7LA+dTdq0aqQN
  #|yqs9LB89GBlUGnk4HAfPOqwJpsOhGESgNt0IBIGRgkIFIEZgVITTaTAISmm7n7S13/9R0BucufVnVWFjjLVp0VCp62UyeaHfdHB6GSwfXKwFox
  #|eFVgrRQMIhCZZnoNSEw01/jOJQXkSQFCJWASgFABWLu/3ISzvCMgNuVcqzorCzz3Tp0VCp5zp85KB/erA2vl4CsDS/PNqwJrY00vAolC0GtAog
  #|xMEhAqAqMCZCabSQCh6v5x6f5irFneERC7/HGnzsoCT96o01Tm6O/UWeng+urAknO+MrBUDHoVSJSCTgQC00yvgcAGTv6ozkoBaVSATAlYBCBW
  #|AObuL3X9l3cExKactlGnk+q4b9RZoeA+9+qsdHB9dGClHHxlECoV1E4FAmNNJwIB0owakCkDgwREisCoAJnJZhaA1HQzd38p1mzeEfCByx9XdV
  #|YWuPPuLU0ouMr+NU06aO37niYZ1Lt/UZMK6tm9qUkEJfWvatJALuO7miSQ2vSypqnmXt7WJIB4zq9r6v7n3P1D1fmf9R0BuSmnruqsLHBdW3VW
  #|KGjPTp0uv1vwUWclg/rKwNp886rA2lgziECENL0GJMrAIIFQKSBOChAqAZMAhKabtfvLTTjLOwJil/9c1VlZ4Eo7dVYoaGWnzkoH9dWBtUHnKw
  #|NLxeBVQWhEkHsRSBSCXgMSE80kAaGpZlSADGUmAQgVgKX7i13/5R0BsSmn7tTZWKBdG3Xq/0d9dupsdFC/OrBUDr4ysFQMehVIjDWdCASmmV4D
  #|EmVglIBMERgVIFMCFgGITTdz95eacJZ3BEJDgPZs1NlYoMWNOhsU1LxXZ6OD8tGBlUHnKwNLwOlUIFAKOhEIFIJRAzITzSABkalmVEBoBHDPAp
  #|AqAHP3l7r+m3cEfODyl1WdRgDnfaPOBgXl3qqz0UH56MBKOehkIFAMXhVYG2s6EQQ9x9kf1NlI4BkkIFIEZgVIlYBJAELTzdz9pSac9R0BOdw8
  #|qzobC9S4VWeDgpLj9nV3E89HB6GRQXplYG2+eVVgrRQMIhApBL0GJMrAIAGRqabN/68PAVyTAIQKwNr95a7/8o6A2OUvqzobC5S6U2eDgnzt1G
  #|mocgledTYySF8ZWCoGrwqsjTW9CCSmmV4DEpaZJCBUBEYFyJSASQCh6f5t6f5iE87yjoDYlHPv1NlYoJwbdTpdjv5OnY0O0lcHlgadrwwszTe9
  #|CiRKQScCgULQayA0ErhHCchMNaMCZCabRQBioJm7v9T1X94RELv8eaPOxgK5btTZoCBde3U2OogfHVgpB18ZBPOo89+psxHB04lAYJoZNSAz0Q
  #|wSECkCowJkSsAsAKkCMHd/qQln846AD0w596pOveX4fy/yp07bNwAA
    ),
  )
  let out = @zip.gunzip(gz).unwrap()
  assert_eq(out.length(), 14299)
  assert_eq(@zip.sha256(out), "d3d71d0bccdde270e0eaebdd8659a8703392f402ad634cad6a726d5c4d1acca9")
  // damaged: a byte of it changed, or cut short
  let bad = gz.to_fixedarray()
  bad[1000] = (bad[1000].to_int() ^ 0x55).to_byte()
  assert_true(@zip.gunzip(Bytes::from_fixedarray(bad)) is None)
  assert_true(@zip.gunzip(gz[0:gz.length() - 100].to_owned()) is None)
  assert_true(@zip.gunzip(b"not gzip at all, not at all") is None)
}

///|
test "stored blocks: two, the first as long as one can be" {
  let data = Bytes::makei(70000, fn(i) { ((i * 37 + 11) % 256).to_byte() })
  let gz : Array[Byte] = [b'\x1f', b'\x8b', b'\x08', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x03']
  let le = fn(v : Int, k : Int) { for i in 0..<k { gz.push(((v >> (8 * i)) & 255).to_byte()) } }
  let mut at = 0
  while at < data.length() {
    let len = if data.length() - at > 65535 { 65535 } else { data.length() - at }
    gz.push((if at + len == data.length() { 1 } else { 0 }).to_byte())
    le(len, 2)
    le(len ^ 0xFFFF, 2)
    for i in 0..<len {
      gz.push(data[at + i])
    }
    at += len
  }
  le(@zip.crc32(data).reinterpret_as_int(), 4)
  le(data.length(), 4)
  let out = @zip.gunzip(Bytes::from_array(gz)).unwrap()
  assert_eq(@zip.sha256(out), "3c43d02a5c493c6c534dda8983b3da6d13cf36f155491e4d6553c0a88f5b817d")
}

///|
test "sha256: the standard's examples" {
  assert_eq(@zip.sha256(b""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  assert_eq(@zip.sha256(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  assert_eq(
    @zip.sha256(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
}
