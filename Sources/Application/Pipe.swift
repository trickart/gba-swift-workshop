// 上下ひと組の土管。間の隙間を鳥がくぐる。

struct Pipe {
    static let width = 32

    /// 左端の位置 (1/256 ピクセル)
    var x: Int
    /// 隙間の上端の位置 (ピクセル)
    var gapY: Int
    /// 鳥がもう通り過ぎたか (得点を二重に数えないため)
    var isPassed = false

    /// 左端の位置 (ピクセル)
    var pixelX: Int { x >> 8 }
    /// 隙間の下端の位置 (ピクセル)
    var gapBottom: Int { gapY + Config.pipeGap }

    /// box が上下どちらかの土管に重なっているか
    func hits(_ box: Rect) -> Bool {
        // 画面の上に飛び出してもすり抜けられないよう、上の土管はずっと上まで続いていることにする
        let top = Rect(x: pixelX, y: gapY - 1000, width: Pipe.width, height: 1000)
        let bottom = Rect(x: pixelX, y: gapBottom, width: Pipe.width, height: 1000)
        return box.intersects(top) || box.intersects(bottom)
    }

    func draw() {
        // スプライトは最大でも 32x64 なので、口のある絵と胴体だけの絵を縦につないで長い土管にする。
        // priority を 2 にして地面 (背景1) の奥に置き、地面より下の部分を隠す。

        // 上の土管: 口が下を向くように上下反転し、隙間の上端から上へ伸ばす
        Sprites.draw(Art.pipeEnd, x: pixelX, y: gapY - 64, flipY: true, priority: 2)
        Sprites.draw(Art.pipeBody, x: pixelX, y: gapY - 128, priority: 2)

        // 下の土管: 隙間の下端から下へ伸ばす
        Sprites.draw(Art.pipeEnd, x: pixelX, y: gapBottom, priority: 2)
        Sprites.draw(Art.pipeBody, x: pixelX, y: gapBottom + 64, priority: 2)
    }
}
