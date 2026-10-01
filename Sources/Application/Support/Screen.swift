// 画面全体の初期化と、1フレームごとの描画の区切り。
//
// 画面は 240x160。手前から順に次の層が重なっている:
//   背景0 (文字)  >  スプライト  >  背景1  >  背景2  >  背景3  >  空の色
// スプライトは priority を指定すると、背景の間に挟むこともできる (Sprites.draw を参照)。

enum Screen {
    static let width = 240
    static let height = 160

    /// 画面を使えるようにする。最初に1回だけ呼ぶ。
    static func setup(skyColor: UInt16, palette: [PaletteColor]) {
        // 背景0〜3の設定: 番号が小さいほど手前、16色タイル、256x256ピクセル
        for layer in 0..<4 {
            let control = UInt16(layer) | UInt16(28 + layer) &<< 8
            mmioWrite16(Reg.bg0cnt + UInt(layer) * 2, control)
            Background(layer: layer).clear()
            Background(layer: layer).scroll(x: 0, y: 0)
        }
        // 背景タイル0番は「何もない」を表すので透明にしておく
        for i in 0..<8 {
            videoWrite32(Memory.backgroundTiles + UInt(i) * 4, 0)
        }

        PixelArt.register(palette)
        setSkyColor(skyColor)
        Sprites.hideAll()

        // Mode 0、スプライトのタイルは1次元並び、背景0〜3とスプライトを表示
        mmioWrite16(Reg.dispcnt, 0x1F40)
    }

    /// 空の色 (何も描かれていない場所の色) を変える
    static func setSkyColor(_ color: UInt16) {
        videoWrite16(Memory.backgroundPalette, color)
    }

    /// 画面の書き換えに安全なタイミング (VBlank) が始まるまで待つ。
    /// 1秒に60回やってくるので、これがゲームの1フレームの区切りになる。
    static func waitForVBlank() {
        while mmioRead16(Reg.vcount) >= 160 {}
        while mmioRead16(Reg.vcount) < 160 {}
    }

    /// 描画の開始。前のフレームに描いたスプライトと文字を消す。
    static func beginDrawing() {
        Sprites.beginFrame()
        Text.beginFrame()
    }

    /// 描画の終了
    static func endDrawing() {
        Sprites.endFrame()
    }
}
