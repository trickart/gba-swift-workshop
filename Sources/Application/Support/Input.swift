// キー入力。毎フレーム update() を呼んでから使う。

enum Button: UInt16 {
    case a = 0x0001
    case b = 0x0002
    case select = 0x0004
    case start = 0x0008
    case right = 0x0010
    case left = 0x0020
    case up = 0x0040
    case down = 0x0080
    case r = 0x0100
    case l = 0x0200
}

struct Input {
    private var current: UInt16 = 0
    private var previous: UInt16 = 0

    /// 今のキーの状態を読み込む
    mutating func update() {
        previous = current
        // レジスタは「押されていると0」なので反転して扱う
        current = ~mmioRead16(Reg.keyinput) & 0x03FF
    }

    /// 押している間ずっと true
    func isHeld(_ button: Button) -> Bool {
        current & button.rawValue != 0
    }

    /// 押した瞬間の1フレームだけ true
    func isPressed(_ button: Button) -> Bool {
        current & ~previous & button.rawValue != 0
    }
}
