// 背景: 8x8ピクセルのタイルを敷き詰めて作る大きな絵。地面や遠景のような「動かないもの」に使う。
//
// 背景は 32x32 タイル (256x256ピクセル) あり、画面にはそのうち 30x20 タイルが映る。
// scroll で全体をずらせる。端まで行くと反対側につながるので、無限にスクロールできる。
// 一度置いたタイルは、置き換えるまでずっと表示される (スプライトと違って毎フレーム描かなくてよい)。

/// 背景用の絵。作った時点で VRAM に書き込まれる。
struct TileImage {
    let tile: Int
    let columns: Int
    let rows: Int

    /// 幅と高さは8の倍数
    init(width: Int, height: Int, repeatingLastRow: Bool = false, _ art: StaticString) {
        columns = width / 8
        rows = height / 8
        tile = Background.nextTile
        precondition(Background.nextTile + columns * rows <= 1024, "背景用タイルがいっぱい")
        Background.nextTile += columns * rows

        PixelArt.upload(
            art, width: width, height: height, repeatingLastRow: repeatingLastRow,
            to: Memory.backgroundTiles + UInt(tile) * 32)
    }
}

struct Background {
    /// 次に絵を書き込むタイル番号 (0番は「何もない」用に空けてある)
    static var nextTile = 1

    /// 背景の番号 (0〜3)。小さいほど手前。0 は文字用 (Text) に使っている。
    let layer: Int

    /// 絵を置く。x, y はタイル単位 (1タイル = 8ピクセル) の左上の位置。
    func put(_ image: TileImage, x: Int, y: Int) {
        for row in 0..<image.rows {
            for column in 0..<image.columns {
                setTile(image.tile + row * image.columns + column, x: x + column, y: y + row)
            }
        }
    }

    /// タイルを1枚置く。0 を置くと何もない状態に戻る。
    func setTile(_ tile: Int, x: Int, y: Int) {
        let index = UInt(y & 31) * 32 + UInt(x & 31)
        videoWrite16(mapAddress + index * 2, UInt16(tile))
    }

    /// 全体を何もない状態にする
    func clear() {
        for i in 0..<UInt(32 * 32) {
            videoWrite16(mapAddress + i * 2, 0)
        }
    }

    /// 全体をずらす (ピクセル単位)。x を増やすと絵は左へ流れる。
    func scroll(x: Int, y: Int = 0) {
        mmioWrite16(Reg.bg0hofs + UInt(layer) * 4, UInt16(truncatingIfNeeded: x))
        mmioWrite16(Reg.bg0vofs + UInt(layer) * 4, UInt16(truncatingIfNeeded: y))
    }

    private var mapAddress: UInt {
        Memory.backgroundMaps + UInt(layer) * 0x800
    }
}
