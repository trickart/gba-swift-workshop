// ゲームの色と絵。
//
// 絵は文字で描いてある。1文字が1ピクセルで、どの文字がどの色になるかは Palette.colors で決まる。
// '.' は透明。文字を書き換えてビルドし直せば、見た目がそのまま変わる。

enum Palette {
    /// 空の色 (何も描かれていない場所の色)。赤・緑・青はそれぞれ 0〜31。
    static let sky = rgb15(13, 23, 30)

    /// 絵に使える色。左の文字を絵の中に書くと、その色になる。入れられるのは15色まで。
    static let colors = [
        PaletteColor("k", r: 3, g: 3, b: 5),      // 黒 (輪郭)
        PaletteColor("w", r: 31, g: 31, b: 31),   // 白
        PaletteColor("y", r: 31, g: 26, b: 5),    // 黄
        PaletteColor("o", r: 31, g: 15, b: 3),    // オレンジ
        PaletteColor("r", r: 28, g: 7, b: 6),     // 赤
        PaletteColor("l", r: 19, g: 29, b: 10),   // 明るい緑
        PaletteColor("g", r: 11, g: 23, b: 6),    // 緑
        PaletteColor("G", r: 5, g: 15, b: 5),     // 暗い緑
        PaletteColor("s", r: 27, g: 24, b: 15),   // 砂
        PaletteColor("d", r: 22, g: 18, b: 9),    // 暗い砂
        PaletteColor("c", r: 25, g: 29, b: 31),   // 雲のふち
        PaletteColor("h", r: 15, g: 26, b: 20),   // 遠くの丘
    ]
}

enum Art {
    // MARK: - スプライト (動くもの)

    static let bird = SpriteImage(
        width: 16, height: 16,
        """
        ................
        ................
        ......kkkkkk....
        ....kkyyyykwwk..
        ...kyyyyykwwwwk.
        ..kyyyyyykwwwkwk
        .kkkkyyyykwwwkwk
        kwwwwkyyyykwwwwk
        kwwwwwkyyyykkkkk
        kywwwykyyykooook
        .kyyykyyykokkkkk
        ..kkkyyyyykooook
        ....kkyyyyykkkk.
        ......kkkkk.....
        ................
        ................
        """)

    /// 土管の口。絵より下の行は、最後の行 (胴体) の繰り返しになる。
    static let pipeEnd = SpriteImage(
        width: 32, height: 64, repeatingLastRow: true,
        """
        kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk
        kllllgglggggggggggggggggGGGGGGGk
        kllllgglggggggggggggggggGGGGGGGk
        kllllgglggggggggggggggggGGGGGGGk
        kllllgglggggggggggggggggGGGGGGGk
        kllllgglggggggggggggggggGGGGGGGk
        kllllgglggggggggggggggggGGGGGGGk
        kllllgglggggggggggggggggGGGGGGGk
        kllllgglggggggggggggggggGGGGGGGk
        kllllgglggggggggggggggggGGGGGGGk
        kllllgglggggggggggggggggGGGGGGGk
        kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk
        ..kGGGGGGGGGGGGGGGGGGGGGGGGGGk..
        ..klllgglggggggggggggggGGGGGGk..
        """)

    /// 土管の胴体。1行の絵を縦に繰り返している。
    static let pipeBody = SpriteImage(
        width: 32, height: 64, repeatingLastRow: true,
        """
        ..klllgglggggggggggggggGGGGGGk..
        """)

    // MARK: - 背景 (動かないもの)

    /// 地面。絵より下の行は、最後の行 (砂) の繰り返しになる。
    static let ground = TileImage(
        width: 8, height: 24, repeatingLastRow: true,
        """
        kkkkkkkk
        llllllll
        llllgggg
        lllggggl
        llggggll
        lgggglll
        ggggllll
        gggllllg
        GGGGGGGG
        dddddddd
        ssssssss
        """)

    static let cloud = TileImage(
        width: 32, height: 16,
        """
        ................................
        ..........cccc..................
        ........ccwwwwcc................
        ......ccwwwwwwwwcc....cccc......
        ....ccwwwwwwwwwwwwccccwwwwcc....
        ...cwwwwwwwwwwwwwwwwwwwwwwwwc...
        ..cwwwwwwwwwwwwwwwwwwwwwwwwwwc..
        ..cwwwwwwwwwwwwwwwwwwwwwwwwwwc..
        ...ccwwwwwwwwwwwwwwwwwwwwwwcc...
        .....cccccccccccccccccccccc.....
        """)

    /// 遠くの丘。絵より下の行は、最後の行の繰り返しになる。
    static let hills = TileImage(
        width: 32, height: 16, repeatingLastRow: true,
        """
        ................................
        ................................
        .........hhhh...................
        .......hhhhhhhh.........hhh.....
        .....hhhhhhhhhhhh.....hhhhhhh...
        ...hhhhhhhhhhhhhhhh.hhhhhhhhhhh.
        .hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh
        hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh
        """)

    // MARK: - 予備の絵 (ゲーム本体では未使用。改造に使える)

    /// 羽を上げた鳥
    static let birdWingUp = SpriteImage(
        width: 16, height: 16,
        """
        ................
        ................
        ......kkkkkk....
        ....kkyyyykwwk..
        .kkkkyyyykwwwwk.
        kwwwwkyyykwwwkwk
        kwwwwwkyykwwwkwk
        kywwwykyyykwwwwk
        .kyyykyyyyykkkkk
        ..kkkyyyyykooook
        ...kyyyyykokkkkk
        ...kyyyyyykooook
        ....kkyyyyykkkk.
        ......kkkkk.....
        ................
        ................
        """)

    /// 羽を下げた鳥
    static let birdWingDown = SpriteImage(
        width: 16, height: 16,
        """
        ................
        ................
        ......kkkkkk....
        ....kkyyyykwwk..
        ...kyyyyykwwwwk.
        ..kyyyyyykwwwkwk
        ..kyyyyyykwwwkwk
        .kyyyyyyyykwwwwk
        .kkkkkyyyyykkkkk
        kwwwwwkyyykooook
        kwwwwkyyykokkkkk
        .kwwkyyyyykooook
        ..kkkkyyyyykkkk.
        ......kkkkk.....
        ................
        ................
        """)

    static let coin = SpriteImage(
        width: 8, height: 8,
        """
        ..kkkk..
        .kyyyyk.
        kywyyyok
        kywyyyok
        kyyyyyok
        kyyyyook
        .kooook.
        ..kkkk..
        """)
}
