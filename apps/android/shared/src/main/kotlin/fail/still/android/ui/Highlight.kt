// Code blocks coloured as the web colours them: Shiki with its dual themes, vitesse-light and vitesse-dark
// (web/src/Prose.tsx). Not a grammar per language as Shiki has, but a light tokenizer that knows how the common
// languages write comments, strings and numbers, and, per language family, which words vitesse draws as control words
// (green), which as declarations and operators (red), and whether plain names are variables (brown) or plain text; the
// colours below are the theme's, token for token as Shiki gives them (checked against `codeToTokens` on samples of each
// family). Dark takes each light colour's vitesse-dark twin ([DARK], the pairs Shiki gives the same tokens).
package fail.still.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle

/** vitesse-light's colours (its tokenColors), by what they colour. */
private object V {
    val text = Color(0xFF393A34)
    val comment = Color(0xFFA0ADA0)
    val punct = Color(0xFF999999)
    val string = Color(0xFFB56959)
    val quote = Color(0x77B56959)
    val number = Color(0xFF2F798A)
    /** keyword, keyword.control, constant.language (true, None), entity.name.tag */
    val control = Color(0xFF1E754F)
    /** storage (function, const, class), keyword.operator, null, undefined */
    val storage = Color(0xFFAB5959)
    val function = Color(0xFF59873A)
    val variable = Color(0xFFB07D48)
    /** constant, variable.language (this, self), an option (-x) */
    val constant = Color(0xFFA65E2B)
    val type = Color(0xFF2E8F82)
    /** property names, support (builtins as print, echo) */
    val property = Color(0xFF998418)
    val propertyQuote = Color(0x77998418)
    /** a diff's lines added and removed, a hunk's range (Shiki's own diff colours) */
    val added = Color(0xFF22863A)
    val removed = Color(0xFFB31D28)
    val range = Color(0xFF6F42C1)
}

/** vitesse-dark's colour for each of vitesse-light's (Shiki's `--shiki-dark` beside the light colour, same token). */
private val DARK = mapOf(
    V.text to Color(0xEEDBD7CA), V.comment to Color(0xDD758575), V.punct to Color(0xFF666666),
    V.string to Color(0xFFC98A7D), V.quote to Color(0x77C98A7D), V.number to Color(0xFF4C9A91),
    V.control to Color(0xFF4D9375), V.storage to Color(0xFFCB7676), V.function to Color(0xFF80A665),
    V.variable to Color(0xFFBD976A), V.constant to Color(0xFFC99076), V.type to Color(0xFF5DA994),
    V.property to Color(0xFFB8A965), V.propertyQuote to Color(0x77B8A965),
    V.added to Color(0xFF85E89D), V.removed to Color(0xFFFDAEB7), V.range to Color(0xFFB392F0),
)

/** How a family of languages is written and coloured. */
private class Lang(
    val control: Set<String>,
    val storage: Set<String>,
    /** constant.language drawn green (true, false, None). */
    val green: Set<String> = setOf("true", "false"),
    /** constant.language drawn red (null, undefined in TypeScript). */
    val red: Set<String> = emptySet(),
    val builtins: Set<String> = emptySet(),
    val types: Set<String> = emptySet(),
    /** Plain names are variables (brown), as TypeScript, Rust and Go have them; else plain text. */
    val variables: Boolean = false,
    /** Brackets, commas and colons in the text colour (Kotlin's grammar leaves them unscoped); else grey. */
    val plainPunct: Boolean = false,
    /** Quotes in the string's colour, not the fainter one. */
    val solidQuotes: Boolean = false,
    val hash: Boolean = false,
    val slash: Boolean = true,
    val dashDash: Boolean = false,
    val caseless: Boolean = false,
)

private val TS = Lang(
    control = setOf("if", "else", "for", "while", "do", "return", "break", "continue", "switch", "case", "default", "import", "from", "export",
        "as", "try", "catch", "finally", "throw", "await", "yield", "of", "with", "debugger"),
    storage = setOf("function", "const", "let", "var", "class", "interface", "enum", "type", "namespace", "declare", "abstract", "async",
        "static", "public", "private", "protected", "readonly", "extends", "implements", "new", "delete", "typeof", "instanceof", "in",
        "keyof", "void", "get", "set", "override", "satisfies"),
    red = setOf("null", "undefined"),
    types = setOf("string", "number", "boolean", "any", "unknown", "never", "object", "bigint", "symbol"),
    variables = true,
)
private val PYTHON = Lang(
    control = setOf("if", "elif", "else", "for", "while", "return", "break", "continue", "import", "from", "as", "try", "except", "finally",
        "raise", "with", "yield", "await", "pass", "assert", "match", "case", "del", "global", "nonlocal"),
    storage = setOf("def", "class", "lambda", "async", "and", "or", "not", "in", "is"),
    green = setOf("True", "False", "None"),
    builtins = setOf("print", "len", "range", "str", "int", "float", "dict", "list", "set", "tuple", "open", "isinstance", "super", "sorted",
        "enumerate", "zip", "map", "filter", "min", "max", "sum", "any", "all", "type", "repr", "bool", "input", "abs", "round", "getattr", "setattr", "hasattr"),
    hash = true, slash = false,
)
private val KOTLIN = Lang(
    control = setOf("if", "else", "for", "while", "do", "return", "break", "continue", "when", "try", "catch", "finally", "throw", "package",
        "import", "as", "is", "in", "fun", "val", "var", "class", "object", "interface", "typealias", "true", "false", "this", "super", "where", "by", "constructor", "init"),
    storage = setOf("override", "private", "public", "protected", "internal", "open", "abstract", "final", "data", "sealed", "enum", "inline",
        "suspend", "lateinit", "const", "companion", "operator", "infix", "tailrec", "external", "annotation", "inner", "vararg", "reified", "crossinline", "noinline"),
    red = setOf("null"),
    plainPunct = true, solidQuotes = true,
)
private val RUST = Lang(
    control = setOf("if", "else", "for", "while", "loop", "return", "break", "continue", "match", "use", "mod", "fn", "impl", "pub", "crate",
        "as", "in", "where", "async", "await", "move", "unsafe", "extern", "trait", "type", "dyn"),
    storage = setOf("let", "mut", "struct", "enum", "const", "static", "ref"),
    types = setOf("i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64", "bool", "char", "str"),
    variables = true,
)
private val GO = Lang(
    control = setOf("if", "else", "for", "range", "return", "break", "continue", "switch", "case", "default", "package", "import", "func",
        "var", "const", "type", "struct", "interface", "map", "chan", "go", "defer", "select", "fallthrough", "goto"),
    storage = setOf("string", "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64", "float32", "float64",
        "bool", "byte", "rune", "error", "any"),
    red = setOf("nil"),
    variables = true,
)
private val C_LIKE = Lang(
    control = setOf("if", "else", "for", "while", "do", "return", "break", "continue", "switch", "case", "default", "import", "package",
        "try", "catch", "finally", "throw", "throws", "using", "namespace", "include", "define", "goto", "yield", "await", "guard", "defer", "func", "fun", "fn", "def"),
    storage = setOf("class", "struct", "enum", "interface", "const", "static", "public", "private", "protected", "final", "abstract", "virtual",
        "override", "extends", "implements", "new", "delete", "void", "int", "long", "short", "char", "float", "double", "bool", "boolean",
        "unsigned", "signed", "auto", "let", "var", "val", "typedef", "extern", "inline", "volatile", "sizeof", "instanceof", "async"),
    red = setOf("null", "nil", "nullptr", "NULL"),
)
private val SHELL = Lang(
    control = setOf("if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in", "function", "return", "exit", "select"),
    storage = setOf("export", "local", "declare", "readonly", "unset", "alias"),
    builtins = setOf("echo", "cd", "printf", "read", "source", "set", "shift", "eval", "exec", "test", "trap", "wait", "kill", "pwd", "type", "ulimit", "umask", "true", "false"),
    green = emptySet(),
    hash = true, slash = false,
)
private val SQL = Lang(
    control = setOf("select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete", "create", "table",
        "drop", "alter", "add", "join", "left", "right", "inner", "outer", "on", "group", "by", "order", "having", "limit", "offset", "as",
        "distinct", "union", "all", "in", "is", "like", "between", "exists", "case", "when", "then", "else", "end", "primary", "key", "index",
        "unique", "default", "references", "foreign", "asc", "desc", "with", "returning", "view", "if", "begin", "commit", "rollback"),
    storage = emptySet(),
    green = setOf("true", "false", "null"),
    builtins = setOf("count", "sum", "avg", "min", "max", "coalesce", "length", "lower", "upper", "substr", "replace", "json_extract", "now", "date", "cast", "ifnull", "round"),
    slash = false, dashDash = true, caseless = true,
)
private val DATA = Lang(control = emptySet(), storage = emptySet(), green = setOf("true", "false", "null", "yes", "no", "on", "off", "True", "False", "Null", "NULL", "~"))

private fun langOf(language: String): Lang? = when (language) {
    "ts", "tsx", "typescript", "js", "jsx", "javascript", "mjs", "cjs", "mts", "cts", "vue", "svelte" -> TS
    "py", "python", "python3" -> PYTHON
    "kt", "kts", "kotlin" -> KOTLIN
    "rs", "rust" -> RUST
    "go", "golang" -> GO
    "sh", "bash", "zsh", "shell", "console", "shellscript", "fish" -> SHELL
    "sql", "sqlite", "postgres", "postgresql", "mysql" -> SQL
    "json", "jsonc", "json5", "yaml", "yml", "toml" -> DATA
    "html", "xml", "svg", "htm", "css", "scss", "less", "diff", "patch", "markdown", "md" -> null
    else -> C_LIKE
}

private val NUMBER = Regex("(0x[0-9a-fA-F_]+|\\d[\\d_]*(\\.\\d+)?([eE][+-]?\\d+)?)")
private val WORD = Regex("[A-Za-z_$][A-Za-z0-9_$]*!?")

fun highlight(code: String, language: String?, dark: Boolean): AnnotatedString {
    if (language == null || language in setOf("text", "plain", "txt", "plaintext")) return AnnotatedString(code)
    val light = buildAnnotatedString {
        withStyle(SpanStyle(color = V.text)) {
            when (language) {
                "json", "jsonc", "json5" -> data(code, json = true)
                "yaml", "yml" -> yaml(code)
                "toml", "ini", "conf" -> data(code, json = false)
                "html", "htm", "xml", "svg" -> markup(code)
                "css", "scss", "less" -> css(code)
                "diff", "patch" -> diff(code)
                "markdown", "md" -> append(code)
                else -> program(code, langOf(language) ?: C_LIKE, shell = langOf(language) === SHELL)
            }
        }
    }
    if (!dark) return light
    return AnnotatedString(
        light.text,
        light.spanStyles.map { r -> AnnotatedString.Range(r.item.copy(color = DARK[r.item.color] ?: r.item.color), r.start, r.end) },
        light.paragraphStyles,
    )
}

private fun AnnotatedString.Builder.put(code: String, from: Int, until: Int, color: Color?) {
    if (until <= from) return
    if (color == null) append(code, from, until) else withStyle(SpanStyle(color = color)) { append(code, from, until) }
}

private fun lineEnd(code: String, i: Int) = code.indexOf('\n', i).let { if (it < 0) code.length else it }

/** A string from its opening quote at `i`: the quotes fainter than what is between (or `solid`), `${…}` and `{…}` left in it. */
private fun AnnotatedString.Builder.string(code: String, i: Int, color: Color = V.string, quote: Color = V.quote): Int {
    val q = code[i]
    val triple = code.startsWith("$q$q$q", i)
    val open = if (triple) 3 else 1
    var j = i + open
    while (j < code.length) {
        if (code[j] == '\\') { j += 2; continue }
        if (triple && code.startsWith("$q$q$q", j)) break
        if (!triple && code[j] == q) break
        if (code[j] == '\n' && q != '`' && !triple) break
        j++
    }
    val end = minOf(code.length, j)
    val close = if (end < code.length && code[end] != '\n') open else 0
    put(code, i, i + open, quote)
    put(code, i + open, end, color)
    put(code, end, minOf(code.length, end + close), quote)
    return minOf(code.length, end + close)
}

/** The next character that is not a space or tab, from `j`. */
private fun next(code: String, j: Int): Char? {
    var k = j
    while (k < code.length && (code[k] == ' ' || code[k] == '\t')) k++
    return code.getOrNull(k)
}

/** The last character before `j` that is not a space or tab. */
private fun before(code: String, j: Int): Char? {
    var k = j - 1
    while (k >= 0 && (code[k] == ' ' || code[k] == '\t')) k--
    return code.getOrNull(k)
}

private const val OPERATORS = "+-*/%!&|^~?<>="
private const val PUNCT = "{}[]();,.:"

private fun AnnotatedString.Builder.program(code: String, l: Lang, shell: Boolean) {
    var i = 0
    val n = code.length
    // Open brackets: a name and a colon inside braces is a key, inside parentheses a parameter.
    val brackets = ArrayList<Char>()
    var previousWord = ""
    // In a shell: at a command's first word (the start of a line, after | ; && then do).
    var command = true
    var afterColon = false
    while (i < n) {
        val c = code[i]
        when {
            c == '\n' -> { append(c); i++; if (shell) command = true; afterColon = false }
            c == ' ' || c == '\t' || c == '\r' -> { append(c); i++ }
            l.hash && c == '#' && (i == 0 || code[i - 1].isWhitespace()) -> { val e = lineEnd(code, i); put(code, i, e, V.comment); i = e }
            l.slash && code.startsWith("//", i) -> { val e = lineEnd(code, i); put(code, i, e, V.comment); i = e }
            l.slash && code.startsWith("/*", i) -> { val e = code.indexOf("*/", i + 2).let { if (it < 0) n else it + 2 }; put(code, i, e, V.comment); i = e }
            l.dashDash && code.startsWith("--", i) -> { val e = lineEnd(code, i); put(code, i, e, V.comment); i = e }
            c == '"' || c == '\'' || c == '`' -> {
                i = if (l.solidQuotes) string(code, i, V.string, V.string) else string(code, i)
                if (shell) command = false
            }
            shell && c == '$' && i + 1 < n && (code[i + 1].isLetter() || code[i + 1] == '_' || code[i + 1] == '{') -> {
                var j = i + 1
                if (code[j] == '{') j = code.indexOf('}', j).let { if (it < 0) n else it + 1 }
                else while (j < n && (code[j].isLetterOrDigit() || code[j] == '_')) j++
                put(code, i, j, V.variable); i = j; command = false
            }
            shell && c == '-' && (i == 0 || code[i - 1].isWhitespace()) && i + 1 < n && (code[i + 1].isLetter() || code[i + 1] == '-') -> {
                var j = i + 1
                while (j < n && !code[j].isWhitespace() && code[j] !in ";|&)=") j++
                put(code, i, j, V.constant); i = j
            }
            shell && !command && !c.isWhitespace() && c !in ";|&<>()[]" && !code.startsWith("\\\n", i) -> {
                // An argument: Shiki's shell grammar draws words after the command as strings.
                var j = i
                while (j < n && !code[j].isWhitespace() && code[j] !in ";|&<>()[]\"'`$") j++
                if (j == i) j = i + 1
                val word = code.substring(i, j)
                put(code, i, j, if (word.all { it.isDigit() }) V.number else V.string); i = j
            }
            c.isDigit() && (i == 0 || !code[i - 1].isLetterOrDigit() && code[i - 1] != '_') -> {
                val m = NUMBER.matchAt(code, i)
                if (m != null) { put(code, i, m.range.last + 1, V.number); i = m.range.last + 1 } else { append(c); i++ }
            }
            c.isLetter() || c == '_' || (c == '$' && !shell) || (shell && command && (c == '.' || c == '/' || c == '~')) -> {
                var end: Int
                if (shell && command) {
                    end = i
                    while (end < n && !code[end].isWhitespace() && code[end] !in ";|&<>()=\"'`") end++
                } else end = (WORD.matchAt(code, i)?.range?.last ?: i) + 1
                // A name with the macro's bang (Rust's println!) only where the language has them.
                if (l !== RUST && end > i && code[end - 1] == '!') end--
                val word = code.substring(i, end)
                val key = if (l.caseless) word.lowercase() else word
                val nextChar = next(code, end)
                val prev = before(code, i)
                val color: Color? = when {
                    shell && command && end < n && code[end] == '=' -> V.variable.also { command = true }
                    shell && command -> when {
                        key in l.control -> V.control
                        key in l.storage -> V.storage.also { command = false }
                        key in l.builtins -> V.property.also { command = false }
                        else -> V.function.also { command = false }
                    }
                    shell && prev == '=' -> V.variable
                    key in l.control -> V.control
                    key in l.storage -> V.storage
                    key in l.green -> V.control
                    key in l.red -> V.storage
                    word == "this" || word == "self" || word == "Self" -> V.constant
                    previousWord in setOf("function", "def", "fun", "fn", "func") -> V.function
                    previousWord in setOf("class", "interface", "type", "struct", "enum", "trait", "impl", "object", "typealias") -> V.type
                    previousWord in setOf("new", "extends", "implements") -> V.function
                    nextChar == '(' || (l === RUST && word.endsWith("!")) -> if (key in l.builtins) V.property else V.function
                    key in l.types -> V.type
                    afterColon && l !== PYTHON && word[0].isUpperCase() -> V.type
                    l === KOTLIN && word[0].isUpperCase() -> V.type
                    l === TS && word[0].isUpperCase() && nextChar == '<' -> V.type
                    l === RUST && word[0].isUpperCase() -> V.type
                    l === RUST && nextChar == ':' && code.startsWith("::", end) -> V.function
                    l === TS && nextChar == ':' && brackets.lastOrNull() == '{' && prev != '?' -> V.property
                    l.variables -> V.variable
                    else -> null
                }
                put(code, i, end, color)
                previousWord = key
                afterColon = false
                i = end
            }
            c in "([{" -> { brackets += c; put(code, i, i + 1, if (l.plainPunct) null else V.punct); i++; if (shell) command = true }
            c in ")]}" -> { brackets.removeLastOrNull(); put(code, i, i + 1, if (l.plainPunct) null else V.punct); i++ }
            c in OPERATORS || c == ':' -> {
                var j = i
                while (j < n && (code[j] in OPERATORS || code[j] == ':')) j++
                val op = code.substring(i, j)
                val spaced = (i == 0 || code[i - 1].isWhitespace()) && (j >= n || code[j].isWhitespace())
                val color = when {
                    shell -> if (op == "|" || op == "||" || op == ">" || op == ">>" || op == "<") V.storage else V.punct
                    op == "=" || op == ":=" || op == "=>" -> V.punct
                    op == ":" -> if (l === RUST) V.storage else if (l.plainPunct) null else V.punct
                    op == "::" || op == "->" -> if (l === RUST) V.storage else V.punct
                    (op == "<" || op == ">") && !spaced -> if (l.plainPunct) null else V.punct
                    op == "?" && l.plainPunct -> null
                    op == "?" && next(code, j) == ':' -> V.storage
                    else -> V.storage
                }
                put(code, i, j, color)
                afterColon = op == ":" || op == "?:" || op == "->" || op == "):"
                if (shell && (op == "|" || op == "||" || op == "&&" || op == "&")) command = true
                i = j
            }
            c in PUNCT -> {
                put(code, i, i + 1, if (l.plainPunct) null else V.punct); i++
                if (shell && c == ';') command = true
                if (c == ',') afterColon = false
            }
            else -> { append(c); i++ }
        }
    }
}

/** JSON (keys in the property colour, their quotes fainter) and TOML/INI (`key = value`). */
private fun AnnotatedString.Builder.data(code: String, json: Boolean) {
    var i = 0
    val n = code.length
    while (i < n) {
        val c = code[i]
        when {
            !json && c == '#' -> { val e = lineEnd(code, i); put(code, i, e, V.comment); i = e }
            json && code.startsWith("//", i) -> { val e = lineEnd(code, i); put(code, i, e, V.comment); i = e }
            c == '"' || c == '\'' -> {
                // A key: the string before a colon (JSON).
                var j = i + 1
                while (j < n && code[j] != c && code[j] != '\n') j += if (code[j] == '\\') 2 else 1
                val key = json && next(code, j + 1) == ':'
                i = if (key) string(code, i, V.property, V.propertyQuote) else string(code, i)
            }
            c == '-' || c.isDigit() -> {
                val m = NUMBER.matchAt(code, if (c == '-') i + 1 else i)
                if (m != null) { put(code, i, m.range.last + 1, V.number); i = m.range.last + 1 } else { put(code, i, i + 1, V.punct); i++ }
            }
            c.isLetter() || c == '_' -> {
                var j = i
                while (j < n && (code[j].isLetterOrDigit() || code[j] in "_-.")) j++
                val word = code.substring(i, j)
                val color = when {
                    word in DATA.green -> V.control
                    !json && next(code, j) == '=' -> V.property
                    else -> null
                }
                put(code, i, j, color); i = j
            }
            c in "{}[],:=" -> { put(code, i, i + 1, V.punct); i++ }
            else -> { append(c); i++ }
        }
    }
}

/** YAML: keys in the property colour; plain values are strings to Shiki. */
private fun AnnotatedString.Builder.yaml(code: String) {
    var i = 0
    val n = code.length
    while (i < n) {
        val e = lineEnd(code, i)
        var j = i
        while (j < e && (code[j] == ' ' || code[j] == '\t')) j++
        put(code, i, j, null)
        if (j < e && code[j] == '-' && (j + 1 == e || code[j + 1] == ' ')) {
            put(code, j, j + 1, V.punct); j++
            while (j < e && code[j] == ' ') { append(' '); j++ }
        }
        if (j < e && code[j] == '#') { put(code, j, e, V.comment); j = e }
        val colon = Regex("^[^#'\"]*?:(\\s|$)").find(code.substring(j, e))
        if (colon != null) {
            val k = j + colon.value.trimEnd().length - 1
            put(code, j, k, V.property); put(code, k, k + 1, V.punct); j = k + 1
        }
        while (j < e) {
            val c = code[j]
            when {
                c == ' ' -> { append(c); j++ }
                c == '#' && code[j - 1] == ' ' -> { put(code, j, e, V.comment); j = e }
                c == '"' || c == '\'' -> j = minOf(e, string(code, j))
                else -> {
                    val hashAt = code.indexOf(" #", j).let { if (it < 0 || it > e) e else it }
                    val value = code.substring(j, hashAt).trimEnd()
                    val color = when {
                        value in DATA.green -> V.control
                        NUMBER.matchEntire(value) != null -> V.number
                        value in setOf("|", ">", "|-", ">-", "[]", "{}") -> V.punct
                        else -> V.string
                    }
                    put(code, j, j + value.length, color); j += value.length
                }
            }
        }
        if (e < n) append('\n')
        i = e + 1
    }
}

/** HTML and XML: tags green, attribute names brown, values strings, the brackets grey. */
private fun AnnotatedString.Builder.markup(code: String) {
    var i = 0
    val n = code.length
    while (i < n) {
        when {
            code.startsWith("<!--", i) -> { val e = code.indexOf("-->", i).let { if (it < 0) n else it + 3 }; put(code, i, e, V.comment); i = e }
            code[i] == '<' -> {
                var j = i + 1
                if (j < n && (code[j] == '/' || code[j] == '!' || code[j] == '?')) j++
                put(code, i, j, V.punct)
                var k = j
                while (k < n && (code[k].isLetterOrDigit() || code[k] in "-_:.")) k++
                put(code, j, k, V.control)
                i = k
                while (i < n && code[i] != '>') {
                    val c = code[i]
                    when {
                        c == '"' || c == '\'' -> i = string(code, i)
                        c == '=' || c == '/' || c == '?' -> { put(code, i, i + 1, V.punct); i++ }
                        c.isWhitespace() -> { append(c); i++ }
                        else -> {
                            var e = i
                            while (e < n && !code[e].isWhitespace() && code[e] !in "=>/\"'") e++
                            if (e == i) e = i + 1
                            put(code, i, e, if (i > 0 && code[i - 1] == '=') V.string else V.variable); i = e
                        }
                    }
                }
                if (i < n) { put(code, i, i + 1, V.punct); i++ }
            }
            else -> {
                val e = code.indexOf('<', i).let { if (it < 0) n else it }
                put(code, i, e, null); i = e
            }
        }
    }
}

/** CSS: selectors (classes brown, elements green), properties, numbers with their units red, colours as constants. */
private fun AnnotatedString.Builder.css(code: String) {
    var i = 0
    val n = code.length
    var depth = 0
    while (i < n) {
        val c = code[i]
        val inBlock = depth > 0 && run {
            // Inside a rule's braces, and not in a nested selector (a word followed by `{`).
            val stop = code.indexOfAny(charArrayOf(';', '{', '}'), i)
            stop < 0 || code[stop] != '{'
        }
        when {
            code.startsWith("/*", i) -> { val e = code.indexOf("*/", i + 2).let { if (it < 0) n else it + 2 }; put(code, i, e, V.comment); i = e }
            c == '"' || c == '\'' -> i = string(code, i)
            c == '{' -> { depth++; put(code, i, i + 1, V.punct); i++ }
            c == '}' -> { depth = maxOf(0, depth - 1); put(code, i, i + 1, V.punct); i++ }
            c == '#' && inBlock -> {
                var j = i + 1
                while (j < n && code[j].isLetterOrDigit()) j++
                put(code, i, i + 1, V.punct); put(code, i + 1, j, V.constant); i = j
            }
            (c.isDigit() || (c == '.' && i + 1 < n && code[i + 1].isDigit())) && inBlock -> {
                var j = i
                while (j < n && (code[j].isDigit() || code[j] == '.')) j++
                var u = j
                while (u < n && (code[u].isLetter() || code[u] == '%')) u++
                put(code, i, j, V.number); put(code, j, u, V.storage); i = u
            }
            c.isLetter() || c == '-' || c == '_' -> {
                var j = i
                while (j < n && (code[j].isLetterOrDigit() || code[j] in "-_")) j++
                val word = code.substring(i, j)
                val color = when {
                    inBlock && next(code, j) == ':' -> if (word.startsWith("--")) V.variable else V.property
                    inBlock -> null
                    i > 0 && (code[i - 1] == '.' || code[i - 1] == ':' || code[i - 1] == '#') -> V.variable
                    i > 0 && code[i - 1] == '@' -> V.control
                    else -> V.control
                }
                put(code, i, j, color); i = j
            }
            c == '>' || c == '+' || c == '~' -> { put(code, i, i + 1, if (depth == 0 || !inBlock) V.storage else V.punct); i++ }
            c in ".:;,()@#*[]" -> { put(code, i, i + 1, V.punct); i++ }
            else -> { append(c); i++ }
        }
    }
}

/** A diff as Shiki colours one: removed lines red, added green (their `---`/`+++` marks grey), a hunk's range purple between grey `@@`. */
private fun AnnotatedString.Builder.diff(code: String) {
    var i = 0
    while (i < code.length) {
        val e = lineEnd(code, i)
        when {
            code.startsWith("+++", i) || code.startsWith("---", i) -> {
                put(code, i, i + 3, V.punct); put(code, i + 3, e, if (code[i] == '+') V.added else V.removed)
            }
            code.startsWith("@@", i) -> {
                val close = code.indexOf("@@", i + 2).takeIf { it in 0 until e }
                put(code, i, i + 2, V.punct)
                if (close == null) put(code, i + 2, e, V.range)
                else { put(code, i + 2, close, V.range); put(code, close, close + 2, V.punct); put(code, close + 2, e, null) }
            }
            code.startsWith("+", i) -> put(code, i, e, V.added)
            code.startsWith("-", i) -> put(code, i, e, V.removed)
            else -> put(code, i, e, null)
        }
        if (e < code.length) append('\n')
        i = e + 1
    }
}
