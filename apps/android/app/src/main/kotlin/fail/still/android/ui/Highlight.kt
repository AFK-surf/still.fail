// Code blocks coloured as the web colours them (shiki's vitesse theme): comments,
// strings, numbers, keywords, function names. A light tokenizer rather than a
// grammar per language: it knows how common languages write comments and
// strings, and one list of keywords; a block with no language stays plain.
package fail.still.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle

private class Palette(val comment: Color, val string: Color, val number: Color, val keyword: Color, val function: Color, val punct: Color)

private val LIGHT = Palette(Color(0xFFA0ADA0), Color(0xFFB56959), Color(0xFF2F798A), Color(0xFF1E754F), Color(0xFF59873A), Color(0xFF999999))
private val DARK = Palette(Color(0xFF758575), Color(0xFFC98A7D), Color(0xFF4C9A91), Color(0xFF4D9375), Color(0xFF80A665), Color(0xFF666666))

private val KEYWORDS = setOf(
    "if", "else", "elif", "for", "while", "do", "done", "then", "fi", "case", "esac", "in", "return", "break", "continue", "switch", "default",
    "function", "fn", "func", "def", "fun", "class", "struct", "enum", "interface", "trait", "impl", "type", "object", "module", "package",
    "import", "from", "export", "as", "use", "mod", "pub", "private", "public", "protected", "internal", "static", "final", "const", "let",
    "var", "val", "mut", "new", "delete", "try", "catch", "finally", "throw", "throws", "raise", "except", "with", "yield", "await", "async",
    "match", "when", "where", "true", "false", "null", "nil", "none", "None", "True", "False", "undefined", "this", "self", "super", "and",
    "or", "not", "is", "lambda", "pass", "local", "echo", "export", "set", "unset", "readonly", "sudo", "select", "insert", "update",
    "create", "table", "values", "into", "join", "on", "group", "by", "order", "limit", "void", "int", "bool", "string", "float", "double",
)

/** Languages that start comments with `#` rather than `//`. */
private val HASH = setOf("sh", "bash", "zsh", "shell", "console", "python", "py", "ruby", "rb", "yaml", "yml", "toml", "perl", "r", "make", "makefile", "dockerfile", "conf", "ini")

private val NUMBER = Regex("\\b(0x[0-9a-fA-F_]+|\\d[\\d_]*(\\.\\d+)?([eE][+-]?\\d+)?)\\b")
private val WORD = Regex("[A-Za-z_][A-Za-z0-9_]*")

fun highlight(code: String, language: String?, dark: Boolean): AnnotatedString {
    if (language == null || language == "text" || language == "plain" || language == "txt") return AnnotatedString(code)
    val p = if (dark) DARK else LIGHT
    val hash = language in HASH
    val slash = !hash || language == "php"
    return buildAnnotatedString {
        var i = 0
        fun colored(color: Color, until: Int) { withStyle(SpanStyle(color = color)) { append(code, i, until) }; i = until }
        while (i < code.length) {
            val c = code[i]
            val rest = code.length
            when {
                hash && c == '#' && (i == 0 || code[i - 1].isWhitespace()) -> colored(p.comment, code.indexOf('\n', i).let { if (it < 0) rest else it })
                slash && code.startsWith("//", i) -> colored(p.comment, code.indexOf('\n', i).let { if (it < 0) rest else it })
                slash && code.startsWith("/*", i) -> colored(p.comment, code.indexOf("*/", i + 2).let { if (it < 0) rest else it + 2 })
                language in setOf("sql", "lua", "haskell", "hs") && code.startsWith("--", i) -> colored(p.comment, code.indexOf('\n', i).let { if (it < 0) rest else it })
                c == '"' || c == '\'' || c == '`' -> {
                    var j = i + 1
                    while (j < rest && code[j] != c && !(code[j] == '\n' && c != '`')) j += if (code[j] == '\\') 2 else 1
                    colored(p.string, minOf(rest, j + 1))
                }
                c.isDigit() && (i == 0 || !code[i - 1].isLetterOrDigit() && code[i - 1] != '_') -> {
                    val m = NUMBER.matchAt(code, i)
                    if (m != null) colored(p.number, m.range.last + 1) else { append(c); i++ }
                }
                (c in 'A'..'Z' || c in 'a'..'z' || c == '_') -> {
                    val m = WORD.matchAt(code, i)!!
                    val end = m.range.last + 1
                    when {
                        m.value in KEYWORDS -> colored(p.keyword, end)
                        end < rest && code[end] == '(' -> colored(p.function, end)
                        else -> { append(m.value); i = end }
                    }
                }
                c in "{}[]()<>;,.:=+-*/%!&|^~?" -> colored(p.punct, i + 1)
                else -> { append(c); i++ }
            }
        }
    }
}
