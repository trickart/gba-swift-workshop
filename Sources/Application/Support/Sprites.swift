// スプライト: 画面上を自由に動かせる小さな絵。鳥や土管のような「動くもの」に使う。
//
// 使い方は「毎フレーム、描きたいものを全部描く」だけ。描かなかったものは消える。
//     Sprites.draw(Art.bird, x: 56, y: 70)

/// スプライト用の絵。作った時点で VRAM に書き込まれる。
struct SpriteImage {
    let tile: Int
    let width: Int
    let height: Int
    let shape: UInt16
    let size: UInt16

    /// 幅と高さに使えるのは 8, 16, 32, 64 (ただし 8x64, 16x64, 64x8, 64x16 は不可)
    init(width: Int, height: Int, repeatingLastRow: Bool = false, _ art: StaticString) {
        switch (width, height) {
        case (8, 8): (shape, size) = (0, 0)
        case (16, 16): (shape, size) = (0, 1)
        case (32, 32): (shape, size) = (0, 2)
        case (64, 64): (shape, size) = (0, 3)
        case (16, 8): (shape, size) = (1, 0)
        case (32, 8): (shape, size) = (1, 1)
        case (32, 16): (shape, size) = (1, 2)
        case (64, 32): (shape, size) = (1, 3)
        case (8, 16): (shape, size) = (2, 0)
        case (8, 32): (shape, size) = (2, 1)
        case (16, 32): (shape, size) = (2, 2)
        case (32, 64): (shape, size) = (2, 3)
        default: fatalError("スプライトに使えない大きさ")
        }
        self.width = width
        self.height = height
        self.tile = Sprites.nextTile
        let tileCount = (width / 8) * (height / 8)
        precondition(Sprites.nextTile + tileCount <= 1024, "スプライト用タイルがいっぱい")
        Sprites.nextTile += tileCount

        PixelArt.upload(
            art, width: width, height: height, repeatingLastRow: repeatingLastRow,
            to: Memory.spriteTiles + UInt(tile) * 32)
    }
}

enum Sprites {
    /// 同時に表示できるスプライトの数
    static let capacity = 128
    /// 同時に回転できるスプライトの数
    static let rotationCapacity = 32

    /// 次に絵を書き込むタイル番号
    static var nextTile = 0
    /// 次に使うOAMの番号。番号が小さいほど手前に表示されるので、後ろから順に使う
    /// (後から描いたものほど手前になる)
    static var nextSlot = capacity - 1
    /// 次に使う回転パラメータの番号
    static var nextRotationSlot = 0

    static func beginFrame() {
        nextSlot = capacity - 1
        nextRotationSlot = 0
    }

    /// スプライトを1つ描く。x, y は絵の左上の位置 (ピクセル)。
    /// 後から描いたものほど手前に表示される。
    ///
    /// angle は絵の中心を軸にした回転の角度 (度)。プラスで反時計回り (右向きの絵なら上を向く)。
    /// 回転するスプライトは同時に32個まで。
    ///
    /// priority は背景との前後関係で、同じ番号の背景よりは手前、それより小さい番号の背景よりは奥になる。
    /// 1 (初期値) なら文字の奥・背景1の手前、2 なら背景1の奥・背景2の手前。
    static func draw(
        _ image: SpriteImage, x: Int, y: Int,
        flipX: Bool = false, flipY: Bool = false, angle: Int = 0, priority: Int = 1
    ) {
        let rotates = angle % 360 != 0
        // 回転するスプライトは、はみ出した角が切れないよう 2倍の大きさの領域に描く。
        // 領域の中心を絵の中心に合わせるため、左上を幅と高さの半分だけずらす。
        let left = rotates ? x - image.width / 2 : x
        let top = rotates ? y - image.height / 2 : y
        let width = rotates ? image.width * 2 : image.width
        let height = rotates ? image.height * 2 : image.height

        // 画面の外にあるものは描かない
        guard left > -width, left < Screen.width, top > -height, top < Screen.height else {
            return
        }
        guard nextSlot >= 0 else { return }
        if rotates && nextRotationSlot >= rotationCapacity { return }

        var attribute0 = UInt16(truncatingIfNeeded: top) & 0x00FF
        attribute0 |= image.shape &<< 14
        var attribute1 = UInt16(truncatingIfNeeded: left) & 0x01FF
        attribute1 |= image.size &<< 14
        let attribute2 = UInt16(image.tile) | UInt16(priority & 3) &<< 10

        if rotates {
            attribute0 |= 0x0300  // 回転あり、2倍の領域
            attribute1 |= UInt16(nextRotationSlot) &<< 9
            setRotation(slot: nextRotationSlot, angle: angle, flipX: flipX, flipY: flipY)
            nextRotationSlot += 1
        } else {
            if flipX { attribute1 |= 0x1000 }
            if flipY { attribute1 |= 0x2000 }
        }

        let address = Memory.oam + UInt(nextSlot) * 8
        videoWrite16(address, attribute0)
        videoWrite16(address + 2, attribute1)
        videoWrite16(address + 4, attribute2)
        nextSlot -= 1
    }

    /// 回転パラメータを書き込む。
    /// ハードウェアには「画面のピクセルが絵のどこに対応するか」を表す 2x2 行列 (PA PB / PC PD) を
    /// 1/256 単位で渡す。OAM の4つおきのエントリの末尾2バイトに、PA, PB, PC, PD の順に収められている。
    private static func setRotation(slot: Int, angle: Int, flipX: Bool, flipY: Bool) {
        let cos = Angle.cos(angle)
        let sin = Angle.sin(angle)
        let pa = flipX ? -cos : cos
        let pb = flipX ? sin : -sin
        let pc = flipY ? -sin : sin
        let pd = flipY ? -cos : cos

        let address = Memory.oam + UInt(slot) * 32 + 6
        videoWrite16(address, UInt16(truncatingIfNeeded: pa))
        videoWrite16(address + 8, UInt16(truncatingIfNeeded: pb))
        videoWrite16(address + 16, UInt16(truncatingIfNeeded: pc))
        videoWrite16(address + 24, UInt16(truncatingIfNeeded: pd))
    }

    /// このフレームで使わなかったスプライトを隠す
    static func endFrame() {
        var slot = nextSlot
        while slot >= 0 {
            hide(slot)
            slot -= 1
        }
    }

    static func hideAll() {
        for slot in 0..<capacity {
            hide(slot)
        }
    }

    private static func hide(_ slot: Int) {
        videoWrite16(Memory.oam + UInt(slot) * 8, 0x0200)
    }
}
