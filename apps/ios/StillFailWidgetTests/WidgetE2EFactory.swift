// Compiled only by the explicit simulator E2E build. Release widgets always use
// the App Group Keychain and the real cloud origin; they contain no fixture path.
#if WIDGET_E2E
import Foundation
import Darwin

enum WidgetE2EFactory {
    static func seedFromApp() throws {
        guard let root = WidgetFiles.directory else { throw SecureStorageError.unavailable }
        let config = try JSONValue.parse(String(contentsOf: root.appendingPathComponent("widget-e2e.json"), encoding: .utf8))
        let storage = KeychainStorage()
        try storage.set(key: "accounts", value: Data(try config["accounts"].encoded().utf8))
        try storage.set(key: "device", value: Data(config["device"].arrayValue.compactMap { $0.intValue.map(UInt8.init) }))
        try WidgetFiles.select(account: "fixture", workspace: "fixture-w")
        try Data("ready".utf8).write(to: root.appendingPathComponent("widget-e2e-seeded"), options: .atomic)
    }
    static func make(callback: @escaping @Sendable (UInt64, String) -> Void) throws -> any CoreEngine {
        guard let root = WidgetFiles.directory else { throw SecureStorageError.unavailable }
        let config = try JSONValue.parse(String(contentsOf: root.appendingPathComponent("widget-e2e.json"), encoding: .utf8))
        let storage = WidgetCredentials()
        let resource = Bundle.main.url(forResource: "stillfail-widget", withExtension: "js")!
        let script = try String(contentsOf: resource, encoding: .utf8)
        let ips = try config["ips"].encoded()
        // Both ends still use real native QUIC and peer identity checks. Only
        // address discovery is fixed to this isolated fixture's loopback socket.
        let prelude = "const originalCall = __native.call; __native.call = function(id, op, json, bytes) { if (op === 'iroh.connect') { let a = JSON.parse(json); a.addr.ips = \(ips); json = JSON.stringify(a); } originalCall(id, op, json, bytes); };\n"
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("widget-e2e-reader.js")
        try (prelude + script).write(to: scriptURL, atomically: true, encoding: .utf8)
        return try NativeCoreEngine(dataDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("widget-e2e-io"),
            scriptName: "stillfail-widget", scriptURL: scriptURL, storage: storage, cloudOrigin: config.text("origin")) { client, json in
                if let message = try? JSONValue.parse(json), message.objectValue["ok"] != nil {
                    var info = task_vm_info_data_t()
                    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
                    _ = withUnsafeMutablePointer(to: &info) { pointer in
                        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
                    }
                    let record: [String: Any] = ["pid": getpid(), "footprint": info.phys_footprint,
                        "tasks": message["ok"]["chats"]["days"].arrayValue.flatMap { $0["items"].arrayValue }.count]
                    if let data = try? JSONSerialization.data(withJSONObject: record) {
                        try? data.write(to: root.appendingPathComponent("widget-e2e-result.json"), options: .atomic)
                    }
                }
                callback(client, json)
            }
    }
}
#endif
