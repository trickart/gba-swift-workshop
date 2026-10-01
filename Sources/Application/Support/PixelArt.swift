// 文字で描いた絵 (ASCIIアート) を、GBAのタイル形式に変換して VRAM に書き込む。
//
// 絵の1文字が1ピクセル。どの文字がどの色かはパレットで決まる (Art.swift の Palette)。
// パレットにない文字 ('.' など) は透明になる。

/// パレットの1色。symbol の文字を絵の中に書くと、その色になる。
struct PaletteColor {
    let symbol: UInt8
    let color: UInt16

    /// r, g, b はそれぞれ 0〜31
    init(_ symbol: Unicode.Scalar, r: Int, g: Int, b: Int) {
        self.symbol = UInt8(ascii: symbol)
        self.color = rgb15(r, g, b)
    }
}

enum PixelArt {
    /// 文字コード → パレット番号 (0は透明)
    static var paletteIndex = [UInt8](repeating: 0, count: 128)

    /// パレットをハードウェアに書き込み、文字との対応を覚える
    static func register(_ palette: [PaletteColor]) {
        precondition(palette.count <= 15, "パレットに入る色は15色まで")
        for (i, entry) in palette.enumerated() {
            let offset = UInt(i + 1) * 2
            videoWrite16(Memory.backgroundPalette + offset, entry.color)
            videoWrite16(Memory.spritePalette + offset, entry.color)
            paletteIndex[Int(entry.symbol)] = UInt8(i + 1)
        }
    }

    /// 絵を 8x8 ピクセルのタイルに切り分けて、address から順に書き込む。
    /// タイルは左上から右へ、端まで行ったら次の段へ、の順に並ぶ。
    static func upload(
        _ art: StaticString, width: Int, height: Int, repeatingLastRow: Bool, to address: UInt
    ) {
        precondition(width % 8 == 0 && height % 8 == 0, "絵の幅と高さは8の倍数")

        // 1. 文字を1つずつ読んで、ピクセルごとのパレット番号にする
        var pixels = [UInt8](repeating: 0, count: width * height)
        var x = 0
        var y = 0
        for i in 0..<art.utf8CodeUnitCount {
            let character = art.utf8Start[i]
            if character == UInt8(ascii: "\n") {
                x = 0
                y += 1
            } else {
                if x < width && y < height && character < 128 {
                    pixels[y * width + x] = paletteIndex[Int(character)]
                }
                x += 1
            }
        }
        if repeatingLastRow {
            let lastRow = min(y, height - 1)
            for row in (lastRow + 1)..<height {
                for column in 0..<width {
                    pixels[row * width + column] = pixels[lastRow * width + column]
                }
            }
        }

        // 2. タイルごとに書き込む。1ピクセル4bitなので、横8ピクセルがちょうど32bitになる
        var destination = address
        for tileY in 0..<(height / 8) {
            for tileX in 0..<(width / 8) {
                for row in 0..<8 {
                    let start = (tileY * 8 + row) * width + tileX * 8
                    var bits: UInt32 = 0
                    for column in 0..<8 {
                        bits |= UInt32(pixels[start + column]) << UInt32(column * 4)
                    }
                    videoWrite32(destination, bits)
                    destination += 4
                }
            }
        }
    }
}
