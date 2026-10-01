@ GBA 起動コード (crt0、Multibootイメージ用)
@
@ イメージの構成 (配置は linker/gba.ld が保証。EWRAM 0x02000000 を起点):
@   0x00       エントリ (.crt0.start: 起動コードへのブランチ命令。
@              カートリッジとして焼かれた場合に BIOS がここへ飛んでくる)
@   0x04-0xBF  ヘッダ (.gba_rom_header: Swift側 ROMHeader.swift で定義)
@   0xC0-0xEF  Multibootスタブ (.crt0.entry 先頭):
@              0xC0  Multibootエントリ (BIOS は転送完了後 0x020000C0 へ飛ぶ)
@              0xC4  ブートモード (BIOS が書き込む: 1=JoyBus 2=通常 3=マルチプレイ)
@              0xC5  スレーブ番号 (BIOS が書き込む)
@              0xC6-0xDF 予約
@              0xE0  JoyBusエントリ
@   0xF0-      起動コード (_startup):
@              スタック設定 → (カートリッジ起動ならEWRAMへ自己コピー) →
@              startupMain (Swift側: .dataコピー/.bssクリア/main)

    .section .crt0.start, "ax"
    .arm
    .align 2
    .global _start
_start:
    b       _startup

    .section .crt0.entry, "ax"
    .arm
    .align 2
    @ --- Multibootヘッダ拡張部 (0xC0〜0xEF) ---
    @ レイアウトを固定するため、_startup までを同じセクションに置く。
    @ 注意: 0xC0 のブランチ先を 0xE0/0xE4 にすると mGBA が Multiboot
    @ イメージとして認識しない (古いツールチェーン対策の除外ルール) ため、
    @ _startup は 0xF0 に置いている。
_multiboot_entry:
    b       _startup            @ 0xC0
    .byte   0                   @ 0xC4 ブートモード (BIOS が上書き)
    .byte   0                   @ 0xC5 スレーブ番号 (BIOS が上書き)
    .space  0xE0 - 0xC6         @ 0xC6-0xDF 予約
    b       _startup            @ 0xE0 JoyBusエントリ
    .space  0xF0 - 0xE4         @ 0xE4-0xEF パディング

    .global _startup
_startup:
    @ スタック設定 (BIOSデフォルトと同じ値を明示的に再設定)
    @
    @ 実BIOSからの正規起動ではBIOSが同じ値を設定済みなので冗長だが、
    @ エントリに飛んでくる経路はそれだけではない:
    @   - フラッシュカートのメニューやチェーンローダーが自分のスタック/
    @     CPU状態のまま分岐してくる
    @   - ゲーム自身が先頭へ分岐して再起動する
    @   - BIOS後の状態を再現しないエミュレータ
    @ どの経路でも同じ初期状態を保証するために再設定する (devkitARMの
    @ gba_crt0.s と同じ慣習)。SP_irq はバンクレジスタなので、IRQモードに
    @ 切り替えて設定するこの手順が唯一の初期化手段。BIOSのIRQディスパッチは
    @ ユーザーハンドラを呼ぶ前に SP_irq へ退避するため、割り込みを使うなら必須。
    @ 0xD2/0xDF は I/F ビット (0x80/0x40) を含む: ローダーが割り込み有効の
    @ まま飛んできても、初期化中は IRQ/FIQ 禁止を確定させる。
    mov     r0, #0xD2           @ IRQモード, IRQ/FIQ禁止
    msr     cpsr_c, r0
    ldr     sp, =0x03007FA0
    mov     r0, #0xDF           @ システムモード, IRQ/FIQ禁止
    msr     cpsr_c, r0
    ldr     sp, =0x03007F00

    @ カートリッジ (0x08000000) から起動された場合は、イメージ全体を
    @ リンク先の EWRAM へコピーしてから続きを実行する。
    @ Multiboot で転送された場合はすでに EWRAM 上にいるのでスキップされる。
    @ adr は PC 相対なので「今実行しているアドレス」が得られる。
    adr     r0, _startup        @ 実行時アドレス
    ldr     r1, =_startup       @ リンク時アドレス (EWRAM)
    cmp     r0, r1
    beq     .Lin_ewram
    ldr     r2, =__image_start
    sub     r3, r1, r2          @ _startup のイメージ先頭からのオフセット
    sub     r0, r0, r3          @ 実行時のイメージ先頭
    ldr     r3, =__image_end
.Lcopy_image:
    ldr     r4, [r0], #4
    str     r4, [r2], #4
    cmp     r2, r3
    blo     .Lcopy_image
    ldr     pc, =_startup       @ EWRAM 上のコピーへ移る (再び比較して一致)
.Lin_ewram:

    @ 以降の初期化 (.data コピー / .bss クリア / main 呼び出し) はすべて
    @ Swift 側 (Sources/Application/Support/Startup.swift) で行う。戻らない。
    @ リンカシンボルのアドレスは Swift の @_extern だと .data 内のアンカーに
    @ 実体化されてしまう (コピー前の .data は読めない) ため、ここでイメージ内に
    @ テーブルとして持ち、そのポインタを引数で渡す。
    ldr     r0, =_startup_table
    b       startupMain

    .align 2
_startup_table:
    .word   _sidata             @ [0] .data 初期値 (EWRAM、イメージ末尾)
    .word   _sdata              @ [1] .data 先頭 (IWRAM)
    .word   _edata              @ [2] .data 終端
    .word   _sbss               @ [3] .bss 先頭
    .word   _ebss               @ [4] .bss 終端

    .pool

@ ---------------------------------------------------------------------------
@ ARM EABI 除算ヘルパ (GBA BIOS の SWI 0x06 Div を利用)
@
@ ARM7TDMIには除算命令がないため、BIOSのソフトウェア除算を使う。
@ SWI 0x06 (Div) は r0=被除数, r1=除数 を受け取り r0=商, r1=余り, r3=|商|
@ を返す。引数順・戻り値とも __aeabi_idivmod のABIとそのまま一致する
@ (SWI 0x07 DivArm は引数が逆順の互換用なので使わない)。
@ ARMステートでは SWI 番号を bits[23:16] に置くため 0x060000 と書く。
@
@ ゼロ除算チェックはしない。Swiftの / % 演算子は呼び出し前に自前で
@ ゼロ除算・オーバーフローのトラップを挿入するため、ここには届かない。

    .section .text.__aeabi_idivmod, "ax"
    .arm
    .align 2
    .global __aeabi_idiv
    .global __aeabi_idivmod
__aeabi_idiv:
__aeabi_idivmod:
    swi     0x060000            @ r0 = n / d, r1 = n % d
    bx      lr

@ BIOS Div は符号付き除算なので、符号なし除算はオペランドが2^31以上の
@ 場合を場合分けして補正する。
@   - n < d               : 商0, 余りn
@   - d >= 2^31 (かつ n>=d): 商は必ず1
@   - n >= 2^31, d < 2^31 : (n>>1)/d を符号付きで計算して2倍し、余りで補正
@   - それ以外             : 両方31bitに収まるのでそのまま SWI 0x06

    .section .text.__aeabi_uidivmod, "ax"
    .arm
    .align 2
    .global __aeabi_uidiv
    .global __aeabi_uidivmod
__aeabi_uidiv:
__aeabi_uidivmod:
    cmp     r0, r1
    movlo   r1, r0              @ n < d: 商0, 余りn
    movlo   r0, #0
    bxlo    lr
    cmp     r1, #0x80000000
    bhs     .Lbig_divisor
    cmp     r0, #0x80000000
    bhs     .Lbig_dividend
    swi     0x060000
    bx      lr
.Lbig_divisor:
    sub     r1, r0, r1          @ n >= d かつ d >= 2^31 → 商は1
    mov     r0, #1
    bx      lr
.Lbig_dividend:
    push    {r4, r5, lr}
    mov     r4, r0              @ r4 = n
    mov     r5, r1              @ r5 = d
    mov     r0, r0, lsr #1
    swi     0x060000            @ r0 = (n >> 1) / d
    mov     r0, r0, lsl #1      @ 商の候補 q = 2 * ((n >> 1) / d)
    mul     r1, r5, r0
    sub     r1, r4, r1          @ r = n - q * d  (0 <= r < 2d)
    cmp     r1, r5
    addhs   r0, r0, #1
    subhs   r1, r1, r5
    pop     {r4, r5, lr}
    bx      lr

@ ---------------------------------------------------------------------------
@ ARM EABI 64bit 除算ヘルパのシム
@
@ __aeabi_uldivmod / __aeabi_ldivmod は「商を r0:r1、余りを r2:r3 で同時に返す」
@ 規約で、Swift の関数では表現できない。本体は Sources/IntegerArithmetic に
@ Swift で書いてあり (__udivmoddi4 / __divmoddi4: 商を返し、余りはポインタ経由)、
@ ここではスタックに余りの置き場を用意して呼び出し、結果を r2:r3 に積み替える。
@   入力: r1:r0 = 被除数, r3:r2 = 除数 (そのまま本体に渡る)
@   第5引数 (余りへのポインタ) は AAPCS の規約どおりスタック先頭 [sp] に置く
@   スタックは 8 バイト境界を保つ (push 8 バイト + 確保 16 バイト)

    .section .text.__aeabi_uldivmod, "ax"
    .arm
    .align 2
    .global __aeabi_uldivmod
__aeabi_uldivmod:
    push    {r4, lr}
    sub     sp, sp, #16
    add     r4, sp, #8          @ 余りの置き場 (sp+8, 8 バイト)
    str     r4, [sp]            @ 第5引数
    bl      __udivmoddi4
    ldr     r2, [sp, #8]
    ldr     r3, [sp, #12]
    add     sp, sp, #16
    pop     {r4, lr}
    bx      lr

    .section .text.__aeabi_ldivmod, "ax"
    .arm
    .align 2
    .global __aeabi_ldivmod
__aeabi_ldivmod:
    push    {r4, lr}
    sub     sp, sp, #16
    add     r4, sp, #8
    str     r4, [sp]
    bl      __divmoddi4
    ldr     r2, [sp, #8]
    ldr     r3, [sp, #12]
    add     sp, sp, #16
    pop     {r4, lr}
    bx      lr
