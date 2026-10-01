# gba-swift-workshop

「Embedded Swift で GBA のゲームを作ろう！」

生成物は Multiboot イメージ (`build/game.mb.gba`)。カートリッジを使わず、通信ケーブル経由で
EWRAM に転送して実行する形式で、プログラム本体も EWRAM に置かれる。
mGBA はそのまま読み込める。先頭にカートリッジと同じヘッダを持ち、カートリッジとして
起動された場合は crt0 が自分自身を EWRAM へコピーして動くので、ROM として焼いても動く。

## 必要なもの

- Swift 6.4.2 toolchain
  - 6.3.0以降であれば問題ないはず

```sh
swiftly install 6.4.2
swiftly use 6.4.2
```

- 動作確認用エミュレータ (mGBA など)
  - ブラウザで実行できる[mGBA web](https://trickart.github.io/mgba-web/)を用意してます
- 実機確認用
  - GBA本体
  - [GBA-PICO-LINK](https://bzl.booth.pm/items/8533267)もしくは[Game-Boy-Zero-Link-Board](https://github.com/weimanc/game-boy-zero-link-board)
  - **GAMEBOY**通信ケーブル(GBA用ではない)
  - [gba-multiboot-web](https://github.com/trickart/gba-multiboot-web)

## ビルドと実行

```sh
make build   # build/game.mb.gba (Multibootイメージ) を生成
make run     # (インストールされていれば)mGBA で起動
make send    # 実機へ転送 (gba-multiboot-web のアダプタを USB でつないでおく)
make disasm  # ELFの逆アセンブルを表示
make clean
```

コンパイルにも `llvm-objcopy` などのツールにも、swiftly で選択中のツールチェーンを使う
(`swiftly use` で切り替える)。

## ゲームのコード

ゲーム本体は `Sources/Application` の直下にある。

| ファイル | 内容 |
|---|---|
| `Application.swift` | ゲームループ (入力 → 更新 → 描画 を1秒に60回) |
| `Config.swift` | 調整用の数値 (重力、羽ばたきの強さ、スクロール速度、土管の隙間と間隔など) |
| `Art.swift` | 色 (パレット) と絵。絵は文字で描いてあり、1文字が1ピクセル |
| `Game.swift` | ゲームの進行 (開始待ち → プレイ中 → ゲームオーバー)、土管の出現、得点、画面の描画 |
| `Bird.swift` | 鳥の動き (重力と羽ばたき) |
| `Pipe.swift` | 土管の当たり判定と描画 |

改造するときは、まず `Config.swift` の数値を変えてみるのが早いかも

### 単位

GBA には小数を計算する回路がないので、動くものの位置と速さは「1/256 ピクセル」単位の
整数で持っている (256 で 1ピクセル)。大きさや、動かないものの位置はピクセル単位。

### ゲームから使う部品

`Sources/Application/Support` に、GBA のハードウェアを扱う部品がある。
中を読まなくても、次の使い方だけでゲームは改造できる。

```swift
// スプライト (動くもの): 毎フレーム、描きたいものを全部描く。後から描いたものほど手前。
Sprites.draw(Art.bird, x: 56, y: 70)
Sprites.draw(Art.pipeEnd, x: 100, y: 40, flipY: true, priority: 2)
Sprites.draw(Art.bird, x: 56, y: 70, angle: 30)   // 絵の中心を軸に回転 (度、プラスで反時計回り)

// 文字と数字: スプライトと同じく毎フレーム描く。位置は8ピクセル単位 (横30 x 縦20)。
Text.draw("SCORE", x: 1, y: 1)
Text.draw(score, x: 7, y: 1)
Text.drawCentered("GAME OVER", y: 5)

// 背景 (動かないもの): 一度置けば表示され続ける。位置は8ピクセル単位。
let ground = Background(layer: 1)
ground.put(Art.ground, x: 0, y: 17)
ground.scroll(x: 12)

// キー入力
input.isPressed(.a)   // 押した瞬間の1フレームだけ true
input.isHeld(.a)      // 押している間ずっと true

// 乱数、当たり判定、角度
var random = Random(seed: 1)
let y = random.int(in: 16...68)
let hit = Rect(x: 0, y: 0, width: 8, height: 8).intersects(bird.hitbox)
let dx = Angle.cos(45)   // 1/256 単位の整数 (256 で 1.0)

// 空の色を変える (赤・緑・青はそれぞれ 0〜31)
Screen.setSkyColor(rgb15(31, 18, 10))
```

絵を足すときは `Art.swift` に定義を1つ書く。初めて使われたときに VRAM へ読み込まれる。

```swift
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
```

- スプライトの大きさは 8 / 16 / 32 / 64 の組み合わせ (8x64, 16x64, 64x8, 64x16 は不可)。
  背景用の `TileImage` は幅・高さとも 8 の倍数。
- 回転するスプライトは同時に32個まで (ハードウェアの回転パラメータが32組のため)。
- 色はパレットにある文字で指定する。パレットは全体で 15色まで。パレットにない文字は透明。
- 文字に使えるのは 数字・英大文字・一部の記号 (`! * + - . / : ?`)。

### 画面の重なり順

手前から順に、背景0 (文字) → スプライト → 背景1 (地面) → 背景2 (遠景) → 背景3 (未使用) → 空の色。
スプライトは `priority` で背景の間に挟める。土管は `priority: 2` で地面の奥に置いてある。

## ミッションカード

改造のお題。★を1〜2枚やってから、★★か★★★を1枚選ぶのがおすすめ。
どのお題も、変えたら `make run` で動かして確かめる。

### ★ 数値や1行の変更 (3〜5分)

| ミッション | ゴール | 触るところ | おまけ |
|---|---|---|---|
| 夕焼け空 | 空を夕焼けの色にする | `Art.swift` の `Palette.sky` (赤・緑・青は 0〜31) | `Screen.setSkyColor` を使って、時間とともに空の色を変える |
| スピード狂 | 土管が流れる速さを2倍にする | `Config.scrollSpeed` (256 で 1ピクセル/フレーム) | 遠景の速さは `Game.draw` の `distance >> 10` で決まる。変えてみる |
| 操作変更 | 十字キーの上やLボタンでも羽ばたけるようにする | `Game.update` の `input.isPressed(.a)`。ボタン名は `Input.swift` の `Button` | 好きなボタンで羽ばたきの強さを変える |
| 月面モード | ふわふわと飛ぶようにする | `Config.gravity`, `Config.flapVelocity` | Bボタンで通常モードと切り替える |
| 鬼モード | 土管の隙間を狭く、間隔を短くする | `Config.pipeGap`, `Config.pipeSpacing` | 隙間を狭くしすぎると `Config.pipeMargin` との兼ね合いでどうなるか |

### ★★ 小さなロジックの追加 (10分前後)

| ミッション | ゴール | 触るところ | おまけ |
|---|---|---|---|
| だんだん難しく | 得点が増えるほど速くなる | `Game.update` の `let speed = Config.scrollSpeed` を `score` で変える | 隙間も狭くする。土管の隙間は `Pipe` を作るときに決まる |
| 滑空 | Aを押している間はゆっくり落ちる | `input.isHeld(.a)` (押している間 true) と `Bird.update` の落下速度の上限 | 押した瞬間 (`isPressed`) と押している間 (`isHeld`) の違いを確かめる |
| ポーズ | STARTで一時停止と再開 | `Game.State` に状態を足し、`Game.update` と `Game.draw` の `switch` に分岐を足す | 一時停止中は "PAUSE" を表示する |
| 羽ばたき | 上昇中と落下中で鳥の絵を切り替える | `Bird.draw` で `velocity` を見て `Art.birdWingUp` / `Art.birdWingDown` を使い分ける | 速度に関係なく、一定の間隔で3コマをパラパラ切り替える |
| 上を向く | 原作のように、羽ばたくと上を向き、落ちるほど下を向く | `Bird.draw` の `Sprites.draw` に `angle:` を渡す (度、プラスで上向き)。角度は `velocity` から計算する | 地面に落ちたあとも下を向いたままにする |
| 動く土管 | 土管の隙間が上下に動く | `Pipe.gapY` を毎フレーム変える。向きを覚える変数が要る。更新は `Game.updatePipes` から | 土管ごとに動く速さを変える |

### ★★★ ルールの変更 (15〜25分)

| ミッション | ゴール | 触るところ | おまけ |
|---|---|---|---|
| 重力反転 | Bボタンで重力の向きが逆になる | `Bird` に重力の向きを持たせ、`Bird.update` の重力と天井・地面の扱いを変える | 上下反転した鳥の絵は `flipY: true` で描ける |
| 避けゲー化 | 重力をなくし、十字キーの上下で動かす | `Bird.update` から重力を外し、`Game.update` で `input` を見て `bird.y` を変える | 土管を左右にも動かして、動く的にする |
| コイン | 隙間にコインを出し、取ると得点が増える | `Art.coin` と `Rect.intersects`。コインの位置は `Pipe` に持たせると楽 | 取ったときに "+5" などの文字を一瞬出す |
| ライフ制 | 3回まで当たれる。当たった直後は点滅して無敵 | `Game` にライフと無敵時間 (フレーム数) を持たせる。点滅は `frame % 4 < 2` のときだけ描く | ライフを文字や絵で画面に出す |

### 持ち帰り

- シューティング化: Aボタンで弾を撃ち、土管を壊す
- 効果音: GBAのサウンドレジスタを叩く部品を `Support/` に足す (このゲームには音がない)

## 土台の仕組み

| ファイル | 役割 |
|---|---|
| `Sources/Startup/crt0.S` | Swiftでは書けない最小限のアセンブリ: (1) イメージ先頭のエントリ命令と Multiboot スタブ (0xC0 の Multiboot エントリ、BIOS が書き込むブートモード/スレーブ番号、0xE0 の JoyBus エントリ) (2) スタック設定 (バンクレジスタ SP_irq はモード切替でしか初期化できない) (3) カートリッジから起動された場合の EWRAM への自己コピー (4) リンカシンボルのアドレステーブル (5) `b startupMain` (6) 除算ヘルパ (`__aeabi_uidiv[mod]` / `__aeabi_idiv[mod]`、BIOS SWI 0x06 利用、r0/r1 2値返しのABIのため) (7) 64bit 除算ヘルパのシム (`__aeabi_[u]ldivmod`: `Sources/IntegerArithmetic` の Swift 関数を呼び、余りを r2:r3 に積み替える) |
| `Sources/Application/Support/Startup.swift` | 起動処理の本体 `startupMain`: `.data` のEWRAM (イメージ末尾) →IWRAMコピー → `.bss` ゼロクリア → `main` 呼び出し → 停止ループ。セクションアドレスはcrt0.Sのイメージ内テーブルへのポインタで受け取る (`@_extern` でリンカシンボルを参照すると、変数でも関数でもアドレス定数が `.data` 内のアンカーに実体化され、コピー前の `.data` を読む鶏と卵になるため) |
| `Sources/Application/Support/ROMHeader.swift` | ヘッダ 0x04〜0xBF (タイトル等。カートリッジROMと Multiboot で共通の形式) を `@used @section(".gba_rom_header")` 付きのタプル定数として定義。ロゴ領域はゼロフィルにしておき `tools/gbafix.swift` に書き込ませる。リンカスクリプトがエントリ命令直後に配置し、終端が 0xC0 (= Multiboot エントリ、BIOS が転送後にジャンプする 0x020000C0) になることを `ASSERT` で保証する |
| `Sources/Application/Support/GBA.swift` | I/O レジスタとビデオメモリのアドレス、読み書きの関数。レジスタは `_Volatile` モジュール経由、ビデオメモリはポインタで直接書く |
| `Sources/Application/Support/` のそれ以外 | 画面 (`Screen`)、スプライト (`Sprites`)、背景 (`Background`)、文字 (`Text` / `Font`)、絵の変換 (`PixelArt`)、入力 (`Input`)、乱数と当たり判定 (`Utilities`) |
| `linker/gba.ld` | メモリ配置 (Multiboot)。コード/定数はEWRAM (0x02000000) 先頭、`.data`/`.bss` はIWRAM (0x03000000)、ヒープはEWRAM のイメージ直後から末尾 (0x02040000) まで。ヒープが 64KB を切るほどイメージが大きくなるとリンクエラーになる (`__heap_min`) |
| `toolset.json` | SwiftPM に渡すコンパイル/リンクフラグ (`-enable-experimental-feature Embedded`, `-nostdlib`, lld + カスタムリンカスクリプト) |
| `Sources/MemoryPrimitives` | `-nostdlib` で消える libc のメモリ操作関数 (`memset`/`memcpy`/`memmove`/`memcmp`) と ARM EABI の `__aeabi_memcpy`/`__aeabi_memclr` 等の Swift 実装。ARM7TDMI にはアトミック命令がないため `__atomic_*` スタブ (GBAはシングルコアなので通常のload/storeで実装) も提供する |
| `Sources/SoftFloat` | 浮動小数点の ARM EABI ヘルパ (`__aeabi_fadd` / `__aeabi_dmul` / `__aeabi_f2iz` / `__aeabi_h2f` など) と、Swift 標準ライブラリが呼ぶ libm 関数 (`sqrtf` / `floor` / `fmod` / `fma` など) の Swift 実装。Float / Double の演算子は内部で使えない (自分自身の呼び出しになる) ため、すべて UInt64 のビット演算で書いてある。単精度・倍精度・半精度で同じコードを共有する |
| `Sources/IntegerArithmetic` | 64bit 整数のシフト (`__aeabi_llsl` / `__aeabi_llsr` / `__aeabi_lasr`)、除算 (`__udivmoddi4` / `__divmoddi4`)、先頭ゼロ数え (`__clzsi2`、ARMv4T には CLZ 命令がない) の Swift 実装。両オペランドが 32bit に収まる除算は `UInt32` の除算を書くだけで crt0.S 経由の BIOS 除算になる。コンパイラが呼ぶ `__aeabi_uldivmod` / `__aeabi_ldivmod` は商を r0:r1、余りを r2:r3 で同時に返す規約で Swift では表現できないため、crt0.S の薄いシムがこの Swift 関数を呼んで余りをレジスタに積み替える |
| `Sources/HasherSeed` | Hasher がハッシュの種を取るために呼ぶ `arc4random_buf` のスタブ。単純な enum を定義しただけで (自動生成される hashValue から) 参照されるので必須。GBA には乱数源がないので固定の種の xorshift で埋める |
| `Sources/HeapAllocator` | `posix_memalign`/`free` のフリーリストアロケータ (Swiftランタイムのヒープ確保用、EWRAM のイメージ直後〜末尾の約220KBを使用)。`Array` などはこれで動く |

画面は Mode 0 (タイル背景4枚 + スプライト) を使う。
背景とスプライトの絵はどちらも 16色 (4bit) のタイルで、同じパレットを共有している。

ビルドの流れ (Makefile):

1. `swift build --triple armv4t-none-none-eabi --toolset toolset.json` で ELF を生成
   (`crt0.S` は SwiftPM のCファミリーターゲット `Startup` として一緒にアセンブルされる)
2. `llvm-objcopy -O binary` で生の Multiboot イメージに変換
3. `tools/gbafix.swift` (devkitPro の gbafix 相当の Swift スクリプト) がヘッダのロゴ領域と
   補完チェックサム (0xBD) を書き込む

## 制限・メモ

- sin / cos / exp / log / pow などの超越関数は未実装。
- `String` と `Character` は使えない (Unicode のテーブルをリンクしていないため、
  使うと `_swift_stdlib_getGraphemeBreakProperty` などが未定義のリンクエラーになる)。
  文字列は `StaticString` で扱う。
- 配列の範囲外アクセスや整数の桁あふれなどで Swift がトラップすると、画面はそのまま固まる。
- 割り込みは未使用。VBlank同期は VCOUNT のポーリングで行っている。
  BIOSの `VBlankIntrWait` を使う場合は IME/IE/DISPSTAT の設定と 0x03007FFC への
  IRQハンドラ登録が必要。
- 音は未実装。
- Multiboot イメージの転送上限は 256KB 弱 (0x3FF40 バイト)。`linker/gba.ld` のヒープ下限
  (64KB) を守っていれば自然に収まる。mGBA はファイルの内容 (サイズ ≤256KB かつ 0xC0 の
  ブランチ命令) で Multiboot かどうかを判定するので、拡張子は `.mb.gba` でなくてもよい。
  なお 0xC0 のブランチ先が 0xE0/0xE4 だと古いツールチェーン対策で Multiboot と
  見なされないため、crt0 は起動コードを 0xF0 に置いている。
