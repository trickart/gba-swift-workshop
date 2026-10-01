// プレイヤーが操作する鳥。

struct Bird {
    /// 上端の位置 (1/256 ピクセル)
    var y = Config.birdStartY * 256
    /// 縦の速さ (1/256 ピクセル/フレーム)。プラスが下向き。
    var velocity = 0

    /// 上端の位置 (ピクセル)
    var pixelY: Int { y >> 8 }

    /// 当たり判定に使う四角形。絵の端には透明な余白があるので、絵より少し小さくしてある。
    var hitbox: Rect {
        Rect(x: Config.birdX + 2, y: pixelY + 3, width: 12, height: 10)
    }

    var isOnGround: Bool {
        hitbox.y + hitbox.height >= Config.groundY
    }

    /// 羽ばたく: それまでの速さに関係なく、上向きの速さにする
    mutating func flap() {
        velocity = Config.flapVelocity
    }

    /// 1フレームぶん動かす
    mutating func update() {
        velocity = min(velocity + Config.gravity, Config.maxFallSpeed)
        y += velocity

        // 画面の上には出られない
        if y < 0 {
            y = 0
            velocity = 0
        }
        // 地面より下には行かない
        let lowestY = (Config.groundY - 13) * 256
        if y > lowestY {
            y = lowestY
            velocity = 0
        }
    }

    /// ゲーム開始前: その場でふわふわ上下する
    mutating func hover(frame: Int) {
        let step = (frame / 4) % 16
        let offset = step < 8 ? step : 15 - step
        y = (Config.birdStartY + offset) * 256
        velocity = 0
    }

    func draw() {
        Sprites.draw(Art.bird, x: Config.birdX, y: pixelY)
    }
}
