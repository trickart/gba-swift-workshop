// Flappy Bird 風ゲーム「FLAPPY SWIFT」
//
// Aボタンで羽ばたいて、土管の隙間をくぐり抜ける。
//
// ファイルの歩き方:
//   Config.swift  調整用の数値 (重力、速さ、隙間の広さなど)。まずはここから。
//   Art.swift     色と絵
//   Game.swift    ゲームの進行 (開始待ち → プレイ中 → ゲームオーバー)
//   Bird.swift    鳥の動き
//   Pipe.swift    土管の当たり判定と描画
//   Support/      GBAのハードウェアを扱う部品 (読まなくてもゲームは改造できる)

@main
struct Application {
    static func main() {
        Screen.setup(skyColor: Palette.sky, palette: Palette.colors)

        var input = Input()
        var game = Game()

        // ゲームループ: 1秒に60回、これを繰り返す
        while true {
            // 1. 入力を読んで、ゲームを1フレームぶん進める
            input.update()
            game.update(input: input)

            // 2. 画面を書き換えてよいタイミングを待ってから描く
            Screen.waitForVBlank()
            Screen.beginDrawing()
            game.draw()
            Screen.endDrawing()
        }
    }
}
