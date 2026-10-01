// ゲーム全体の状態と進行。
//
// update() が1フレームぶんゲームを進め、draw() が今の状態を画面に描く。
// どちらも1秒に60回呼ばれる (Application.swift のゲームループを参照)。

struct Game {
    enum State {
        case ready      // 開始待ち
        case playing    // プレイ中
        case gameOver   // ゲームオーバー
    }

    var state = State.ready
    var bird = Bird()
    var pipes: [Pipe] = []
    var score = 0
    var bestScore = 0

    /// 起動してからのフレーム数
    var frame = 0
    /// 進んだ距離 (1/256 ピクセル)。地面と遠景のスクロールに使う。
    var distance = 0
    /// 次の土管を出すまでの残り距離 (1/256 ピクセル)
    var distanceToNextPipe = 0
    /// ゲームオーバーになってからのフレーム数
    var gameOverFrames = 0
    var random = Random(seed: 1)

    let ground = Background(layer: 1)
    let farBackground = Background(layer: 2)

    init() {
        putScenery()
    }

    // MARK: - 更新

    mutating func update(input: Input) {
        frame += 1

        switch state {
        case .ready:
            bird.hover(frame: frame)
            scroll(by: Config.scrollSpeed)
            if input.isPressed(.a) {
                start()
            }

        case .playing:
            if input.isPressed(.a) {
                bird.flap()
            }
            bird.update()

            let speed = Config.scrollSpeed
            scroll(by: speed)
            updatePipes(speed: speed)

            if isBirdHit {
                finish()
            }

        case .gameOver:
            // 鳥は地面まで落ちる。土管と地面は止まる。
            bird.update()
            gameOverFrames += 1
            // 連打でうっかり飛ばさないよう、少し待ってから受け付ける
            if gameOverFrames > 30 && input.isPressed(.a) {
                reset()
            }
        }
    }

    private mutating func start() {
        state = .playing
        // ボタンを押したタイミングを乱数の種にして、土管の並びが毎回変わるようにする
        random = Random(seed: UInt32(frame))
        bird.flap()
    }

    private mutating func finish() {
        state = .gameOver
        gameOverFrames = 0
        bestScore = max(bestScore, score)
    }

    private mutating func reset() {
        state = .ready
        bird = Bird()
        pipes.removeAll()
        score = 0
        distanceToNextPipe = 0
    }

    private mutating func scroll(by speed: Int) {
        // &+= は桁あふれしても止まらない足し算。何時間動かし続けてもクラッシュしない。
        distance &+= speed
    }

    private mutating func updatePipes(speed: Int) {
        for i in pipes.indices {
            pipes[i].x -= speed

            // 鳥が土管を通り過ぎたら得点
            if !pipes[i].isPassed && pipes[i].pixelX + Pipe.width < Config.birdX {
                pipes[i].isPassed = true
                score += 1
            }
        }

        // 画面の左に出ていった土管を片付ける
        pipes.removeAll { $0.pixelX < -Pipe.width }

        // 一定の距離を進むごとに、画面の右端に新しい土管を出す
        distanceToNextPipe -= speed
        if distanceToNextPipe <= 0 {
            distanceToNextPipe += Config.pipeSpacing * 256
            let highest = Config.pipeMargin
            let lowest = Config.groundY - Config.pipeMargin - Config.pipeGap
            pipes.append(Pipe(x: Screen.width * 256, gapY: random.int(in: highest...lowest)))
        }
    }

    private var isBirdHit: Bool {
        if bird.isOnGround {
            return true
        }
        for pipe in pipes where pipe.hits(bird.hitbox) {
            return true
        }
        return false
    }

    // MARK: - 描画

    func draw() {
        ground.scroll(x: distance >> 8)
        // 遠景は地面の 1/4 の速さで流す (遠くのものほどゆっくり動いて見える)
        farBackground.scroll(x: distance >> 10)

        // スプライトは後から描いたものほど手前になる
        for pipe in pipes {
            pipe.draw()
        }
        bird.draw()

        switch state {
        case .ready:
            Text.drawCentered("FLAPPY SWIFT", y: 4)
            // 約0.5秒ごとに点滅
            if frame % 64 < 32 {
                Text.drawCentered("PRESS A", y: 14)
            }

        case .playing:
            Text.drawCentered(score, y: 2)

        case .gameOver:
            Text.drawCentered("GAME OVER", y: 5)
            Text.draw("SCORE", x: 10, y: 8)
            Text.draw(score, x: 17, y: 8)
            Text.draw("BEST", x: 10, y: 10)
            Text.draw(bestScore, x: 17, y: 10)
            if gameOverFrames > 30 {
                Text.drawCentered("PRESS A", y: 14)
            }
        }
    }

    /// 動かない背景を置く。最初に1回だけ呼べば、ずっと表示され続ける。
    private func putScenery() {
        let groundRow = Config.groundY / 8
        for x in 0..<32 {
            ground.put(Art.ground, x: x, y: groundRow)
        }

        for x in stride(from: 0, to: 32, by: 4) {
            farBackground.put(Art.hills, x: x, y: groundRow - 2)
        }
        farBackground.put(Art.cloud, x: 2, y: 3)
        farBackground.put(Art.cloud, x: 12, y: 8)
        farBackground.put(Art.cloud, x: 19, y: 2)
        farBackground.put(Art.cloud, x: 27, y: 6)
    }
}
