// The made-up workspace's devices (设备: the core's `devices` topic, devices.mbt) and the `device.*` calls changing
// them: 门口摄像头 on Willow (a whole station: every chat's), the viewer's; 开发板 on build-box (the viewer's station
// that only runs tasks), one chat using it and one asking; 陈's phone, lent to Willow. settings-stations-devices: the
// stations' list with them; place-stations-devices: the stations' place on a wide frame; settings-station-devices:
// Willow's page, its 设备 section.

///|
priv struct DevicesFixture {
  /// the ids taken off
  removed : Array[String]
  /// added since: (station, name, kind, target)
  added : Array[(String, String, String, String)]
  /// 免批准 on the board
  mut open : Bool
}

///|
let fx_devices : DevicesFixture = { removed: [], added: [], open: false }

///|
/// Whether the fixture's `mode` is one with the made-up devices in it.
fn devices_fixture_mode(mode : String) -> Bool {
  mode.has_suffix("-devices") || mode.has_prefix("settings-station-tasks")
}

///|
/// As a run starts.
fn devices_fixture_reset() -> Unit {
  fx_devices.removed.clear()
  fx_devices.added.clear()
  fx_devices.open = false
}

///|
fn fx_device(
  id : String,
  name : String,
  kind : String,
  target : String,
  via : String,
  station : String,
  station_name : String,
  mine : Bool,
  owner : (String, String),
  open : Bool,
  grants : Array[Json],
  requests : Array[Json],
  baud? : Int = 0,
) -> Json {
  let out : Array[(String, Json)] = [
    ("id", str(id)),
    ("name", str(name)),
    ("kind", str(kind)),
    ("target", str(target)),
    ("via", str(via)),
    ("station", str(station)),
    ("stationName", str(station_name)),
    ("owner", str(owner.0)),
    ("ownerEmail", str(owner.0)),
    ("ownerName", str(owner.1)),
    ("mine", Json::boolean(mine)),
    ("online", Json::boolean(true)),
    ("open", Json::boolean(open)),
    ("ownOpen", Json::boolean(via == "rig" && open)),
    ("grants", Json::array(grants)),
    ("requests", Json::array(requests)),
  ]
  if baud > 0 {
    out.push(("baud", Json::number(baud.to_double())))
  }
  obj(out)
}

///|
/// The `devices` topic of the made-up workspace.
fn devices_fixture_topic() -> Json {
  let lin = ("lin@example.com", "林")
  let all : Array[Json] = [
    fx_device("0a1b2c3d4e5f6071", "门口摄像头", "tcp", "192.168.1.20:554", "station", "st1", "Willow", true, lin, true, [], []),
    fx_device(
      "1b2c3d4e5f607182",
      "开发板",
      "serial",
      "/dev/ttyUSB0",
      "rig",
      "aa11",
      "build-box",
      true,
      lin,
      fx_devices.open,
      [
        obj([
          ("request", str("r-12")),
          ("station", str("st1")),
          ("stationName", str("Willow")),
          ("session", str("s-c1")),
          ("chat", str("CHAT/1")),
          ("title", str("刷新固件")),
          ("by", str("zhou@example.com")),
          ("timeoutKind", str("idle")),
          ("timeoutSeconds", Json::number(3600.0)),
          ("exp", Json::number(2.0e9)),
          ("until", Json::number(1.9e9)),
          ("whole", Json::boolean(false)),
        ]),
      ],
      [],
      baud=9600,
    ),
    fx_device("2c3d4e5f60718293", "陈 的 Pixel 8", "adb", "192.168.1.31:5555", "phone", "st1", "Willow", false, ("chen@example.com", "陈"), false, [], []),
  ]
  for i, a in fx_devices.added {
    all.push(fx_device("ff" + i.to_string(), a.1, a.2, a.3, "station", a.0, "Willow", true, lin, true, [], []))
  }
  obj([("app", Json::boolean(true)), ("devices", Json::array(all.filter(fn(d) { !fx_devices.removed.contains(text(Some(d), "id")) })))])
}

///|
/// A `device.*` call answered, the made-up devices changed as the core would say them next; None: not one of them.
fn devices_fixture_call(name : String, p : Json?) -> Result[Json, Json]? {
  match name {
    "device.add" => {
      fx_devices.added.push((text(p, "station"), text(p, "name"), text(p, "kind"), text(p, "target")))
      fx_changed()
      Some(Ok(obj([])))
    }
    "device.remove" => {
      fx_devices.removed.push(text(p, "device"))
      fx_changed()
      Some(Ok(obj([])))
    }
    "device.setOpen" => {
      fx_devices.open = flag(p, "open")
      fx_changed()
      Some(Ok(obj([])))
    }
    _ => None
  }
}
