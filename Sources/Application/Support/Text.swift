// 文字と数字の表示。一番手前の背景 (背景0) に、フォントのタイルを並べて描く。
//
// 位置はタイル単位 (1文字 = 8x8ピクセル) で、画面には横30文字 x 縦20行が入る。
// スプライトと同じく「毎フレーム、表示したいものを全部描く」使い方をする。
//     Text.draw("SCORE", x: 1, y: 1)
//     Text.draw(score, x: 7, y: 1)
// 使える文字は 数字・英大文字・一部の記号 (Font.swift を参照)。小文字は大文字で表示される。

enum Text {
    static let columns = 30
    static let rows = 20

    private static let layer = Background(layer: 0)
    /// 前のフレームで文字を描いた行 (行ごとに1bit)
    private static var usedRows: UInt32 = 0

    /// 前のフレームに描いた文字を消す
    static func beginFrame() {
        for y in 0..<rows where usedRows & (1 << UInt32(y)) != 0 {
            for x in 0..<columns {
                layer.setTile(0, x: x, y: y)
            }
        }
        usedRows = 0
    }

    /// 文字列を描く。x, y は左端の位置 (タイル単位)。
    static func draw(_ text: StaticString, x: Int, y: Int) {
        for i in 0..<text.utf8CodeUnitCount {
            put(text.utf8Start[i], x: x + i, y: y)
        }
    }

    /// 数字を描く。x, y は左端の位置 (タイル単位)。
    static func draw(_ number: Int, x: Int, y: Int) {
        var rest = max(number, 0)
        var column = x + digitCount(of: number) - 1
        repeat {
            put(UInt8(ascii: "0") + UInt8(rest % 10), x: column, y: y)
            rest /= 10
            column -= 1
        } while rest > 0
    }

    /// 文字列を画面の左右中央に描く
    static func drawCentered(_ text: StaticString, y: Int) {
        draw(text, x: (columns - text.utf8CodeUnitCount) / 2, y: y)
    }

    /// 数字を画面の左右中央に描く
    static func drawCentered(_ number: Int, y: Int) {
        draw(number, x: (columns - digitCount(of: number)) / 2, y: y)
    }

    private static func digitCount(of number: Int) -> Int {
        var rest = max(number, 0)
        var count = 1
        while rest >= 10 {
            rest /= 10
            count += 1
        }
        return count
    }

    private static func put(_ character: UInt8, x: Int, y: Int) {
        guard x >= 0, x < columns, y >= 0, y < rows else { return }
        var code = character
        if code >= UInt8(ascii: "a") && code <= UInt8(ascii: "z") {
            code -= 0x20
        }
        guard code >= 0x20, code < 0x60 else { return }
        layer.setTile(Font.image.tile + Int(code - 0x20), x: x, y: y)
        usedRows |= 1 << UInt32(y)
    }
}
