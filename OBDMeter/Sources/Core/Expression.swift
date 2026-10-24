import Foundation

struct ExpressionError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// カスタム PID の換算式。応答データの 1 バイト目を A、2 バイト目を B … として書く。
/// 例: (A*256+B)/4、A-40、signed(A)*0.5、signed16(A*256+B)/10、bit(A,3)
/// 演算子: + - * / % ( ) 、関数: abs min max signed signed16 bit round floor。0x1F のような 16 進も書ける
final class Expression {
    let source: String
    private let root: ExprNode
    /// 式が参照する最大バイト数
    let requiredBytes: Int

    private init(source: String, root: ExprNode, requiredBytes: Int) {
        self.source = source
        self.root = root
        self.requiredBytes = requiredBytes
    }

    func evaluate(_ data: [Int]) throws -> Double {
        if data.count < requiredBytes {
            throw ExpressionError("応答が \(data.count) バイトしかありません (式は \(requiredBytes) バイト必要)")
        }
        let v = root.eval(data)
        if v.isNaN || v.isInfinite { throw ExpressionError("計算結果が数値になりません (0 で割った可能性)") }
        return v
    }

    static func compile(_ source: String) throws -> Expression {
        if source.trimmingCharacters(in: .whitespaces).isEmpty { throw ExpressionError("式が空です") }
        let p = ExprParser(source)
        let node = try p.parseExpression()
        try p.expectEnd()
        return Expression(source: source, root: node, requiredBytes: p.maxVar + 1)
    }
}

private indirect enum ExprNode {
    case num(Double)
    case variable(Int)
    case unary(Character, ExprNode)
    case binary(Character, ExprNode, ExprNode)
    case call(String, [ExprNode])

    func eval(_ d: [Int]) -> Double {
        switch self {
        case .num(let v): return v
        case .variable(let i): return i < d.count ? Double(d[i]) : .nan
        case .unary(let op, let a): return op == "-" ? -a.eval(d) : a.eval(d)
        case .binary(let op, let a, let b):
            let x = a.eval(d), y = b.eval(d)
            switch op {
            case "+": return x + y
            case "-": return x - y
            case "*": return x * y
            case "/": return x / y
            case "%": return x.truncatingRemainder(dividingBy: y)
            default: return .nan
            }
        case .call(let name, let args):
            let v = args.map { $0.eval(d) }
            switch name {
            case "abs": return Swift.abs(v[0])
            case "min": return v.min() ?? .nan
            case "max": return v.max() ?? .nan
            case "round": return v[0].rounded()
            case "floor": return v[0].rounded(.down)
            case "signed":
                guard v[0].isFinite else { return .nan }
                let x = Int(v[0]) & 0xFF
                return Double(x >= 0x80 ? x - 0x100 : x)
            case "signed16":
                guard v[0].isFinite else { return .nan }
                let x = Int(v[0]) & 0xFFFF
                return Double(x >= 0x8000 ? x - 0x10000 : x)
            case "bit":
                guard v[0].isFinite, v[1].isFinite else { return .nan }
                return Double((Int64(v[0]) >> Int64(v[1])) & 1)
            default: return .nan
            }
        }
    }
}

private final class ExprParser {
    private let s: [Character]
    private var i = 0
    var maxVar = -1

    private let arity: [String: ClosedRange<Int>] = [
        "abs": 1...1, "min": 2...8, "max": 2...8, "round": 1...1, "floor": 1...1,
        "signed": 1...1, "signed16": 1...1, "bit": 2...2,
    ]

    init(_ source: String) { s = Array(source) }

    private func skip() { while i < s.count && s[i].isWhitespace { i += 1 } }
    private func peek() -> Character? { skip(); return i < s.count ? s[i] : nil }
    private func fail(_ msg: String) -> ExpressionError { ExpressionError("\(msg) (\(i + 1) 文字目)") }

    func expectEnd() throws { if let c = peek() { throw fail("「\(c)」が余分です") } }

    func parseExpression() throws -> ExprNode {
        var left = try parseTerm()
        while true {
            guard let c = peek(), c == "+" || c == "-" else { return left }
            i += 1
            left = .binary(c, left, try parseTerm())
        }
    }

    private func parseTerm() throws -> ExprNode {
        var left = try parseUnary()
        while true {
            guard let c = peek(), c == "*" || c == "/" || c == "%" else { return left }
            i += 1
            left = .binary(c, left, try parseUnary())
        }
    }

    private func parseUnary() throws -> ExprNode {
        if let c = peek(), c == "-" || c == "+" {
            i += 1
            return .unary(c, try parseUnary())
        }
        return try parsePrimary()
    }

    private func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    private func parsePrimary() throws -> ExprNode {
        guard let c = peek() else { throw fail("式が途中で終わっています") }
        if c == "(" {
            i += 1
            let n = try parseExpression()
            if peek() != ")" { throw fail("「)」がありません") }
            i += 1
            return n
        }
        if c.isNumber || c == "." { return try parseNumber() }
        if c.isLetter {
            let start = i
            while i < s.count && isIdent(s[i]) { i += 1 }
            let word = String(s[start..<i])
            if peek() == "(" {
                let name = word.lowercased()
                guard let range = arity[name] else { i = start; throw fail("関数「\(word)」は使えません") }
                i += 1
                var args: [ExprNode] = []
                if peek() != ")" {
                    args.append(try parseExpression())
                    while peek() == "," { i += 1; args.append(try parseExpression()) }
                }
                if peek() != ")" { throw fail("「)」がありません") }
                i += 1
                if !range.contains(args.count) { throw fail("\(name) の引数の数が違います") }
                return .call(name, args)
            }
            if word.count == 1, let ch = word.uppercased().first, ch >= "A", ch <= "Z" {
                let idx = Int(ch.asciiValue ?? 65) - 65
                if idx > maxVar { maxVar = idx }
                return .variable(idx)
            }
            i = start
            throw fail("「\(word)」は使えません (変数は A〜Z の 1 文字)")
        }
        throw fail("「\(c)」は使えません")
    }

    private func parseNumber() throws -> ExprNode {
        let start = i
        if i + 1 < s.count && s[i] == "0" && (s[i + 1] == "x" || s[i + 1] == "X") {
            i += 2
            let hs = i
            while i < s.count && Hex.isHexChar(s[i]) { i += 1 }
            if i == hs { throw fail("16 進数が不正です") }
            return .num(Double(Int64(String(s[hs..<i]), radix: 16) ?? 0))
        }
        while i < s.count && (s[i].isNumber || s[i] == ".") { i += 1 }
        guard let v = Double(String(s[start..<i])) else { i = start; throw fail("数値が不正です") }
        return .num(v)
    }
}

/// 2 値ランプの点灯条件。計測値を x として書く。
/// 例: x >= 100、x > 90 && x < 110、x < 11.5 || x > 14.8、abs(x) > 5
final class Condition {
    private let root: CondNode

    private init(_ root: CondNode) { self.root = root }

    func test(_ x: Double) -> Bool { root.eval(x) != 0 }

    static func compile(_ source: String) throws -> Condition {
        if source.trimmingCharacters(in: .whitespaces).isEmpty { throw ExpressionError("条件式が空です") }
        let p = CondParser(source)
        let node = try p.parseOr()
        try p.expectEnd()
        return Condition(node)
    }

    /// 書き方が誤っていれば理由、正しければ nil
    static func check(_ source: String) -> String? {
        do { _ = try compile(source); return nil } catch { return error.localizedDescription }
    }
}

private final class CondNode {
    let f: (Double) -> Double
    init(_ f: @escaping (Double) -> Double) { self.f = f }
    func eval(_ x: Double) -> Double { f(x) }
}

private final class CondParser {
    private let s: [Character]
    private var i = 0

    init(_ source: String) { s = Array(source) }

    private func skip() { while i < s.count && s[i].isWhitespace { i += 1 } }
    private func fail(_ msg: String) -> ExpressionError { ExpressionError("\(msg) (\(i + 1) 文字目)") }
    private func b(_ v: Bool) -> Double { v ? 1 : 0 }

    private func startsWith(_ token: String, at pos: Int, ignoreCase: Bool = false) -> Bool {
        let t = Array(token)
        if pos + t.count > s.count { return false }
        for k in 0..<t.count {
            let a = s[pos + k], c = t[k]
            if ignoreCase {
                if a.lowercased() != c.lowercased() { return false }
            } else if a != c { return false }
        }
        return true
    }

    /// 記号またはキーワード (前後が英字でないもの) を読めたら進める
    private func accept(_ token: String) -> Bool {
        skip()
        if !startsWith(token, at: i, ignoreCase: true) { return false }
        if let first = token.first, first.isLetter {
            let end = i + token.count
            if end < s.count && (s[end].isLetter || s[end].isNumber || s[end] == "_") { return false }
        }
        i += token.count
        return true
    }

    func expectEnd() throws {
        skip()
        if i < s.count { throw fail("「\(s[i])」が余分です") }
    }

    func parseOr() throws -> CondNode {
        var a = try parseAnd()
        while accept("||") || accept("or") {
            let l = a, r = try parseAnd()
            a = CondNode { x in (l.eval(x) != 0 || r.eval(x) != 0) ? 1 : 0 }
        }
        return a
    }

    private func parseAnd() throws -> CondNode {
        var a = try parseNot()
        while accept("&&") || accept("and") {
            let l = a, r = try parseNot()
            a = CondNode { x in (l.eval(x) != 0 && r.eval(x) != 0) ? 1 : 0 }
        }
        return a
    }

    private func parseNot() throws -> CondNode {
        skip()
        if startsWith("!", at: i) && !startsWith("!=", at: i) {
            i += 1
            let a = try parseNot()
            return CondNode { x in a.eval(x) == 0 ? 1 : 0 }
        }
        if accept("not") {
            let a = try parseNot()
            return CondNode { x in a.eval(x) == 0 ? 1 : 0 }
        }
        return try parseCompare()
    }

    private func parseCompare() throws -> CondNode {
        let l = try parseSum()
        var op: String? = nil
        for o in [">=", "<=", "==", "!=", ">", "<", "="] where accept(o) { op = o; break }
        guard let o = op else { return l }
        let r = try parseSum()
        switch o {
        case ">=": return CondNode { x in l.eval(x) >= r.eval(x) ? 1 : 0 }
        case "<=": return CondNode { x in l.eval(x) <= r.eval(x) ? 1 : 0 }
        case ">": return CondNode { x in l.eval(x) > r.eval(x) ? 1 : 0 }
        case "<": return CondNode { x in l.eval(x) < r.eval(x) ? 1 : 0 }
        case "!=": return CondNode { x in l.eval(x) != r.eval(x) ? 1 : 0 }
        default: return CondNode { x in l.eval(x) == r.eval(x) ? 1 : 0 }
        }
    }

    private func parseSum() throws -> CondNode {
        var a = try parseTerm()
        while true {
            skip()
            guard i < s.count, s[i] == "+" || s[i] == "-" else { return a }
            let c = s[i]
            i += 1
            let l = a, r = try parseTerm()
            a = c == "+" ? CondNode { x in l.eval(x) + r.eval(x) } : CondNode { x in l.eval(x) - r.eval(x) }
        }
    }

    private func parseTerm() throws -> CondNode {
        var a = try parseUnary()
        while true {
            skip()
            guard i < s.count, s[i] == "*" || s[i] == "/" else { return a }
            let c = s[i]
            i += 1
            let l = a, r = try parseUnary()
            a = c == "*" ? CondNode { x in l.eval(x) * r.eval(x) } : CondNode { x in l.eval(x) / r.eval(x) }
        }
    }

    private func parseUnary() throws -> CondNode {
        skip()
        if i < s.count && s[i] == "-" {
            i += 1
            let a = try parseUnary()
            return CondNode { x in -a.eval(x) }
        }
        if i < s.count && s[i] == "+" { i += 1; return try parseUnary() }
        return try parsePrimary()
    }

    private func parsePrimary() throws -> CondNode {
        skip()
        guard i < s.count else { throw fail("式が途中で終わっています") }
        let c = s[i]
        if c == "(" {
            i += 1
            let a = try parseOr()
            if !accept(")") { throw fail("「)」がありません") }
            return a
        }
        if c.isNumber || c == "." {
            let start = i
            while i < s.count && (s[i].isNumber || s[i] == ".") { i += 1 }
            guard let v = Double(String(s[start..<i])) else { i = start; throw fail("数値が読めません") }
            return CondNode { _ in v }
        }
        if c.isLetter {
            let start = i
            while i < s.count && (s[i].isLetter || s[i].isNumber || s[i] == "_") { i += 1 }
            let name = String(s[start..<i]).lowercased()
            if name == "x" { return CondNode { x in x } }
            skip()
            if !(i < s.count && s[i] == "(") { i = start; throw fail("「\(name)」は使えません (値は x と書きます)") }
            i += 1
            var args = [try parseSum()]
            while accept(",") { args.append(try parseSum()) }
            if !accept(")") { throw fail("「)」がありません") }
            switch name {
            case "abs":
                if args.count != 1 { throw fail("abs の引数は 1 つです") }
                let a = args[0]
                return CondNode { x in Swift.abs(a.eval(x)) }
            case "min":
                if args.count < 2 { throw fail("min の引数は 2 つ以上です") }
                let list = args
                return CondNode { x in list.map { $0.eval(x) }.min() ?? 0 }
            case "max":
                if args.count < 2 { throw fail("max の引数は 2 つ以上です") }
                let list = args
                return CondNode { x in list.map { $0.eval(x) }.max() ?? 0 }
            default:
                i = start
                throw fail("関数「\(name)」は使えません")
            }
        }
        throw fail("「\(c)」は使えません")
    }
}
