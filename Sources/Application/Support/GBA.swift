import _Volatile

// GBAのハードウェアは、決まったアドレスのメモリを読み書きして操作する。
// このファイルはそのアドレスの一覧と、読み書きの最小限の関数だけを持つ。

// MARK: - I/Oレジスタの読み書き (volatileアクセス)
//
// レジスタは「読むたびに値が変わる」「書くこと自体に意味がある」ので、
// コンパイラが読み書きを省略したりまとめたりしないよう volatile でアクセスする。

@inline(__always)
func mmioRead16(_ address: UInt) -> UInt16 {
    VolatileMappedRegister<UInt16>(unsafeBitPattern: address).load()
}

@inline(__always)
func mmioWrite16(_ address: UInt, _ value: UInt16) {
    VolatileMappedRegister<UInt16>(unsafeBitPattern: address).store(value)
}

// MARK: - ビデオメモリへの書き込み
//
// パレット・VRAM・OAM は普通のメモリなので、ポインタで直接書く (volatile より速い)。
// ただし 8bit 単位の書き込みは正しく動かないので、必ず 16bit か 32bit で書く。
// ループが memset/memcpy (8bit 単位で書く) に置き換えられないよう、このターゲットは
// Package.swift で -disable-loop-idiom-memset/-memcpy を付けてコンパイルしている。

@inline(__always)
func videoWrite16(_ address: UInt, _ value: UInt16) {
    UnsafeMutablePointer<UInt16>(bitPattern: address).unsafelyUnwrapped.pointee = value
}

@inline(__always)
func videoWrite32(_ address: UInt, _ value: UInt32) {
    UnsafeMutablePointer<UInt32>(bitPattern: address).unsafelyUnwrapped.pointee = value
}

// MARK: - I/Oレジスタ

enum Reg {
    static let dispcnt: UInt = 0x0400_0000   // ディスプレイ制御
    static let vcount: UInt = 0x0400_0006    // 現在の走査線
    static let bg0cnt: UInt = 0x0400_0008    // 背景0の設定 (背景1〜3は2バイトずつ後ろ)
    static let bg0hofs: UInt = 0x0400_0010   // 背景0の横スクロール (背景1〜3は4バイトずつ後ろ)
    static let bg0vofs: UInt = 0x0400_0012   // 背景0の縦スクロール
    static let keyinput: UInt = 0x0400_0130  // キー入力 (0=押下)
}

// MARK: - メモリ領域

enum Memory {
    static let backgroundPalette: UInt = 0x0500_0000  // 背景用パレット
    static let spritePalette: UInt = 0x0500_0200      // スプライト用パレット
    static let backgroundTiles: UInt = 0x0600_0000    // 背景用タイルの絵
    static let backgroundMaps: UInt = 0x0600_E000     // 背景のタイルの並び (背景1枚につき 0x800 バイト)
    static let spriteTiles: UInt = 0x0601_0000        // スプライト用タイルの絵
    static let oam: UInt = 0x0700_0000                // スプライトの位置や見た目 (OAM)
}

// MARK: - 色

/// GBAの色は 赤・緑・青 それぞれ 0〜31 の15bit
@inline(__always)
func rgb15(_ r: Int, _ g: Int, _ b: Int) -> UInt16 {
    UInt16(truncatingIfNeeded: r | (g &<< 5) | (b &<< 10))
}
