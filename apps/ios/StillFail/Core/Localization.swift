import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"

    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .system: return L10n.text("跟随系统")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .spanish: return "Español"
        }
    }
}

/// One lookup path for UIKit labels, accessibility copy, and formatted UI strings.
/// SwiftUI's locale environment uses the same language selection.
enum L10n {
    static let preferenceKey = "appLanguage"
    static let supportedLanguages = AppLanguage.allCases.filter { $0 != .system }.map(\.rawValue)

    static var selectedLanguage: String { UserDefaults.standard.string(forKey: preferenceKey) ?? "system" }
    static var locale: Locale { locale(for: selectedLanguage) }

    static func resolvedLanguage(_ selection: String, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        if supportedLanguages.contains(selection) { return selection }
        return Bundle.preferredLocalizations(from: supportedLanguages, forPreferences: preferredLanguages).first ?? "en"
    }

    static func locale(for selection: String) -> Locale {
        Locale(identifier: resolvedLanguage(selection))
    }

    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: supportedLanguages.compactMap { language in
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        return (language, bundle)
    })

    static func text(_ key: String, language: String? = nil) -> String {
        let code = resolvedLanguage(language ?? selectedLanguage)
        return (bundles[code] ?? Bundle.main).localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        formatted(key, arguments: arguments)
    }

    static func formatted(_ key: String, arguments: [CVarArg], language: String? = nil) -> String {
        let selection = language ?? selectedLanguage
        return String(format: text(key, language: selection), locale: locale(for: selection), arguments: arguments)
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale))
    }

    /// The shared core currently projects metadata in Chinese. Translate only its
    /// known UI templates; callers must keep message bodies and user names verbatim.
    static func projected(_ value: String, language: String? = nil) -> String {
        let direct = text(value, language: language)
        if direct != value { return direct }
        for prefix in ["要你帮忙：", "做完了：", "在等：", "出问题：", "思考："] where value.hasPrefix(prefix) {
            let suffix = String(value.dropFirst(prefix.count))
            return formatted(prefix + "%@", arguments: [prefix == "出问题：" ? text(suffix, language: language) : suffix], language: language)
        }
        // Most metadata is a model name or a number; avoid regex work for those.
        if !value.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) {
            let parts = value.components(separatedBy: " · ")
            return parts.count > 1 ? parts.map { projected($0, language: language) }.joined(separator: " · ") : direct
        }
        let actions = value.components(separatedBy: "、")
        if actions.count > 1 && actions.allSatisfy({ action in
            let length = (action as NSString).length
            return historyActionPattern?.firstMatch(in: action, range: NSRange(location: 0, length: length)) != nil
        }) {
            return actions.map { projected($0, language: language) }.joined(separator: text("、", language: language))
        }
        let source = value as NSString
        let range = NSRange(location: 0, length: source.length)
        for (expression, key) in metadataPatterns {
            guard let match = expression.firstMatch(in: value, range: range) else { continue }
            let arguments: [CVarArg] = (1..<match.numberOfRanges).map { index in
                let argument = source.substring(with: match.range(at: index))
                if index == 1 && ["%@只剩 %@%%", "%@ %@%%", "%@ · 共 %@ 项"].contains(key) { return projected(argument, language: language) }
                if index == 2 && key == spentWarningKey && argument.hasPrefix("，") {
                    return formatted("，%@", arguments: [projected(String(argument.dropFirst()), language: language)], language: language)
                }
                return argument
            }
            return formatted(key, arguments: arguments, language: language)
        }
        let parts = value.components(separatedBy: " · ")
        if parts.count > 1 { return parts.map { projected($0, language: language) }.joined(separator: " · ") }
        return value
    }

    private static let spentWarningKey = "%@ 能用的账号额度都用完了%@。现在发的消息要等额度恢复才会有回复；也可以换一个模型。"
    private static let historyActionPattern = try? NSRegularExpression(pattern: #"^(?:读取 \d+ 个文件|编辑 \d+ 个文件|搜索 \d+ 次|运行 \d+ 条命令|访问 \d+ 个网页|派出 \d+ 个子 agent|读取 thread \d+ 次|其他 \d+ 项)$"#)

    private static let metadataPatterns: [(NSRegularExpression, String)] = [
        (#"^(.+) 离线$"#, "%@ 离线"),
        (#"^连不上 (.+)，正在重试$"#, "连不上 %@，正在重试"),
        (#"^连不上 (.+)$"#, "连不上 %@"),
        (#"^正在重连 (.+)…$"#, "正在重连 %@…"),
        (#"^正在重连 (.+)$"#, "正在重连 %@"),
        (#"^正在启动 (.+)$"#, "正在启动 %@"),
        (#"^(\d+) 台 station 异常$"#, "%@ 个节点连接异常"),
        (#"^(\d+) 个 agent 在跑$"#, "%@ 个 agent 在跑"),
        (#"^(\d+) 核$"#, "%@ 核"),
        (#"^现在是 (.+)$"#, "现在是 %@"),
        (#"^正在读取 (.+) 的 Profile…$"#, "正在读取 %@ 的账号池…"),
        (#"^指定的账号「(.+)」没有启用 (.+)，改成了自动分配$"#, "指定的账号「%@」没有启用 %@，改成了自动分配"),
        (#"^现在的账号「(.+)」没有启用 (.+)，会自动换一个启用了的$"#, "现在的账号「%@」没有启用 %@，会自动换一个启用了的"),
        (#"^指定的账号没有启用 (.+)，改成了自动分配$"#, "指定的账号没有启用 %@，改成了自动分配"),
        (#"^(.+) 能用的账号额度都用完了(.*?)。现在发的消息要等额度恢复才会有回复；也可以换一个模型。$"#, spentWarningKey),
        (#"^(.*?)只剩 ([\d.]+)%$"#, "%@只剩 %@%%"),
        (#"^(.+) ([\d.]+)%$"#, "%@ %@%%"),
        (#"^共 (\d+) 项$"#, "共 %@ 项"),
        (#"^(.+) · 共 (\d+) 项$"#, "%@ · 共 %@ 项"),
        (#"^读取 (\d+) 个文件$"#, "读取 %@ 个文件"),
        (#"^编辑 (\d+) 个文件$"#, "编辑 %@ 个文件"),
        (#"^搜索 (\d+) 次$"#, "搜索 %@ 次"),
        (#"^运行 (\d+) 条命令$"#, "运行 %@ 条命令"),
        (#"^访问 (\d+) 个网页$"#, "访问 %@ 个网页"),
        (#"^派出 (\d+) 个子 agent$"#, "派出 %@ 个子 agent"),
        (#"^读取 thread (\d+) 次$"#, "读取 thread %@ 次"),
        (#"^其他 (\d+) 项$"#, "其他 %@ 项"),
        (#"^读取 (.+)$"#, "读取 %@"),
        (#"^编辑 (.+)$"#, "编辑 %@"),
        (#"^搜索 (.+)$"#, "搜索 %@"),
        (#"^运行 (.+)$"#, "运行 %@"),
        (#"^访问 (.+)$"#, "访问 %@"),
        (#"^派出 (.+)$"#, "派出 %@"),
        (#"^读取 thread (.+)$"#, "读取 thread %@"),
        (#"^已运行 (\d+) 天 (\d+) 小时$"#, "已运行 %@ 天 %@ 小时"),
        (#"^已运行 (\d+) 天$"#, "已运行 %@ 天"),
        (#"^已运行 (\d+) 小时$"#, "已运行 %@ 小时"),
        (#"^剩 (.+) / (.+)$"#, "剩 %@ / %@"),
        (#"^剩余 (.+)$"#, "剩余 %@"),
        (#"^负载 ([\d.]+)$"#, "负载 %@"),
        (#"^中继 (.+)$"#, "中继 %@"),
        (#"^(.+)中继$"#, "%@中继"),
        (#"^(\d+) 分 (\d+) 秒$"#, "%@ 分 %@ 秒"),
        (#"^(\d+) 小时 (\d+) 分$"#, "%@ 小时 %@ 分"),
        (#"^(\d+) 秒$"#, "%@ 秒"),
        (#"^(\d+) 分钟前$"#, "%@ 分钟前"),
        (#"^(\d+) 秒前$"#, "%@ 秒前"),
        (#"^(\d+) 小时前$"#, "%@ 小时前"),
        (#"^(\d+) 天前$"#, "%@ 天前"),
        (#"^昨天 ([\d:]+)$"#, "昨天 %@"),
        (#"^(\d+)月(\d+)日 ([\d:]+)$"#, "%@月%@日 %@"),
        (#"^(\d+)月(\d+)日$"#, "%@月%@日"),
        (#"^(\d+) 分钟后$"#, "%@ 分钟后"),
        (#"^(\d+) 分钟后恢复$"#, "%@ 分钟后恢复"),
        (#"^(\d+) 小时后$"#, "%@ 小时后"),
        (#"^(\d+) 小时后恢复$"#, "%@ 小时后恢复"),
        (#"^(\d+) 天后$"#, "%@ 天后"),
        (#"^(\d+) 天后恢复$"#, "%@ 天后恢复"),
        (#"^(\d+) 小时$"#, "%@ 小时"),
        (#"^调用 ([\d.]+) 次$"#, "调用 %@ 次"),
        (#"^输入 ([\w.,]+)（缓存 ([\d.]+)%）$"#, "输入 %@（缓存 %@%%）"),
        (#"^输入 ([\w.,]+)$"#, "输入 %@"),
        (#"^输出 ([\w.,]+)$"#, "输出 %@"),
        (#"^([\d.]+) 次$"#, "%@ 次")
    ].compactMap { pattern, key in
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        return (expression, key)
    }

    static func notifyLanguageChanged() {
        NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("still.fail.appLanguageDidChange")
}
