import XCTest
@testable import StillFail

final class LocalizationTests: XCTestCase {
    func testExplicitAndSystemLanguageResolution() {
        XCTAssertEqual(L10n.resolvedLanguage("ja", preferredLanguages: ["en-US"]), "ja")
        XCTAssertEqual(L10n.resolvedLanguage("system", preferredLanguages: ["zh-TW"]), "zh-Hant")
        XCTAssertEqual(L10n.resolvedLanguage("system", preferredLanguages: ["zh-CN"]), "zh-Hans")
        XCTAssertEqual(L10n.resolvedLanguage("system", preferredLanguages: ["es-MX"]), "es")
        XCTAssertEqual(L10n.resolvedLanguage("invalid", preferredLanguages: ["fr-FR"]), "en")
    }

    func testLocalizedStringsAndArgumentOrder() {
        XCTAssertEqual(L10n.text("新建会话", language: "en"), "New chat")
        XCTAssertEqual(L10n.text("模型", language: "ja"), "モデル")
        XCTAssertEqual(L10n.text("设置", language: "ko"), "설정")
        XCTAssertEqual(L10n.text("设置", language: "es"), "Ajustes")
        XCTAssertEqual(L10n.text("添加账号", language: "zh-Hant"), "添加帳號")
        XCTAssertEqual(L10n.formatted("%@邀请你加入「%@」", arguments: ["Ava", "Team"], language: "en"), "Ava invited you to “Team”")
        XCTAssertEqual(L10n.formatted("%lld 个节点 · %lld 人", arguments: [Int64(2), Int64(4)], language: "en"), "2 nodes · 4 members")
        XCTAssertEqual(L10n.text("Unknown user content", language: "ja"), "Unknown user content")
    }

    func testEveryLanguageHasTheSameCatalogKeysAndFormatArguments() throws {
        let english = try table(language: "en")
        XCTAssertGreaterThan(english.count, 200)
        for language in L10n.supportedLanguages {
            let localized = try table(language: language)
            XCTAssertEqual(Set(localized.keys), Set(english.keys), "Incomplete \(language) catalog")
            for (key, value) in localized {
                XCTAssertEqual(formatArguments(in: key), formatArguments(in: value), "Invalid format arguments for \(language): \(key)")
            }
        }
    }

    func testProjectedMetadataKeepsUserContentUnchanged() {
        XCTAssertEqual(L10n.projected("要你帮忙：请选择 medium", language: "en"), "Needs your help: 请选择 medium")
        XCTAssertEqual(L10n.projected("出问题：额度用完", language: "en"), "Failed: Quota exhausted")
        XCTAssertEqual(L10n.projected("macOS · 8 核 · 32 GB · 已运行 3 天", language: "en"), "macOS · 8 cores · 32 GB · Uptime: 3 days")
        XCTAssertEqual(L10n.projected("调用 3 次 · 输入 2K（缓存 50%） · 输出 50", language: "en"), "3 calls · Input 2K (cached 50%) · Output 50")
        XCTAssertEqual(L10n.projected("GPT-6 · medium", language: "ja"), "GPT-6 · 中")
        XCTAssertEqual(L10n.projected("每周只剩 5%", language: "en"), "Weekly: 5% left")
        XCTAssertEqual(L10n.projected("读取 2 个文件、编辑 3 个文件", language: "en"), "Read 2 files, Edited 3 files")
        XCTAssertEqual(L10n.projected("读取 foo、bar.swift · 共 2 项", language: "en"), "Read foo、bar.swift · 2 items total")
        XCTAssertEqual(L10n.projected("Unrecognized metadata", language: "es"), "Unrecognized metadata")
    }

    private func table(language: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "\(language).lproj"))
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String])
    }

    private func formatArguments(in string: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(lld|ld|d|@|f)"#)
        let source = string as NSString
        return expression.matches(in: string, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range(at: 1)) }.sorted()
    }
}
