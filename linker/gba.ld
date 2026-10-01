/*
 * GBA ベアメタルSwift用リンカスクリプト (Multibootイメージ)
 *
 * Multibootではカートリッジを使わず、プログラム全体を通信ケーブル経由で
 * EWRAM へ転送して実行する。そのためコード/定数も EWRAM に置く。
 * (エミュレータでは .mb ファイルをそのまま読み込める)
 *
 * メモリマップ:
 *   EWRAM 0x02000000  256KB (16bitバス。プログラム本体 + その後ろがヒープ)
 *   IWRAM 0x03000000  32KB  (32bitバス、高速。.data/.bss。上位はBIOSがスタックに使用)
 *
 * IWRAM上位 0x03007E00〜0x03008000 は BIOS デフォルトスタック
 * (SP_usr=0x03007F00, SP_irq=0x03007FA0) と IRQ ベクタ用に空けておく。
 *
 * EWRAM の使い方 (devkitARM の gba_mb.ld と同じ流儀):
 *   0x02000000  イメージ本体 (.text / .rodata / .data の初期値)
 *   __image_end ヒープ先頭 (_heap_start)。イメージの直後からEWRAM末尾まで
 *   0x02040000  ヒープ終端 (_heap_end)
 * ヒープの大きさはイメージの大きさに連動するので、ASSERT で下限を保証する。
 * Multibootの転送上限は 0x3FF40 バイトだが、この下限を守れば自然に収まる。
 */

ENTRY(_start)

MEMORY
{
    ewram (rwx) : ORIGIN = 0x02000000, LENGTH = 256K
    iwram (rwx) : ORIGIN = 0x03000000, LENGTH = 0x7800
}

/* ヒープがこれより小さくなる (= プログラムが肥大化した) らリンクエラーにする */
__heap_min = 64K;

SECTIONS
{
    /* イメージ先頭: エントリ命令 → ヘッダ(Swift定義) → Multibootスタブ+起動コード */
    .text : {
        KEEP(*(.crt0.start))
        KEEP(*(.gba_rom_header))
        __rom_header_end = .;
        KEEP(*(.crt0.entry))
        *(.text .text.*)
        . = ALIGN(4);
    } > ewram

    /* ヘッダは 0x04〜0xBF の188バイトちょうどでなければならない
       (Swift側のタプルのサイズやアラインメントが変わると即座に検出される)。
       Multiboot では BIOS が転送後に 0x020000C0 へジャンプするので、
       .crt0.entry の先頭 (Multibootエントリ) がここに来ることも同時に保証される */
    ASSERT(__rom_header_end == ORIGIN(ewram) + 0xC0,
           "GBA header must end exactly at 0x020000C0 (multiboot entry)")

    .rodata : {
        . = ALIGN(4);
        *(.rodata .rodata.*)
        *(.swift_modhash)
        . = ALIGN(4);
    } > ewram

    /* 初期値付きデータ: 実行時はIWRAM、初期値はイメージ末尾 (EWRAM) に置き
       startupMain がコピーする。EWRAM に直接置けばコピー不要だが、
       32bitバスの IWRAM のほうが速いので今まで通りコピー方式にする */
    .data : {
        . = ALIGN(4);
        _sdata = .;
        *(.data .data.*)
        *(.got .got.*)
        *(.got.plt)
        . = ALIGN(4);
        _edata = .;
    } > iwram AT> ewram
    _sidata = LOADADDR(.data);

    /* ゼロ初期化データ (startupMain がクリアする) */
    .bss (NOLOAD) : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > iwram

    /* イメージ終端 = .data 初期値のロード先の末尾。
       crt0 がカートリッジ起動時に自分自身を EWRAM へコピーする範囲でもある */
    __image_start = ORIGIN(ewram);
    __image_end = ALIGN(_sidata + SIZEOF(.data), 4);

    /* ヒープはイメージの直後から EWRAM 末尾まで */
    _heap_start = __image_end;
    _heap_end = ORIGIN(ewram) + LENGTH(ewram);

    ASSERT(_heap_end - _heap_start >= __heap_min,
           "Multiboot image too large: heap would be smaller than __heap_min")

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.ARM.exidx*)
        *(.ARM.attributes)
        *(.riscv.attributes)
    }
}
