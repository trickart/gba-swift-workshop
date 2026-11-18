TRIPLE := armv4t-none-none-eabi
ELF := .build/$(TRIPLE)/debug/Application
# Multibootイメージ (EWRAMで実行)。mGBAは内容で判別するので拡張子は何でもよいが、
# エミュレータに .gba として関連付けつつ Multiboot だと分かるよう .mb.gba にする
ROM := build/game.mb.gba

# Swiftツールチェーン内のLLVMツール (clang / ld.lld / llvm-objcopy) を使う。
# ツールチェーンは swiftly で選択中のもの (swiftly use で切り替える)。
# swiftly がない環境 (公式Dockerイメージ / Codespaces) では PATH 上の swift と同じ場所を使う
TOOLCHAIN := $(shell swiftly use --print-location 2>/dev/null)
ifneq ($(TOOLCHAIN),)
TCBIN := $(TOOLCHAIN)/usr/bin
else
TCBIN := $(patsubst %/,%,$(dir $(shell command -v swift)))
endif
export PATH := $(TCBIN):$(PATH)

# ヘッダのロゴ領域とチェックサムの書き込みは tools/gbafix.swift で行う
# (ヘッダ 0x04〜0xBF はMultibootイメージでもカートリッジROMと同じ形式)。
GBAFIX := swift tools/gbafix.swift

# 実機への転送は tools/multiboot.swift で行う (gba-multiboot-web のアダプタが必要)。
# アダプタが複数つながっているときは make send PORT=/dev/cu.usbmodemXXXX
MULTIBOOT := swift tools/multiboot.swift
PORT ?=

# Swift 6.4 から既定になった swiftbuild は、ベアメタル向けでも Apple の ld 用の
# オプションでリンクしようとして失敗するので、従来の native ビルドシステムを使う
BUILD_FLAGS := --build-system native --triple $(TRIPLE) --toolset toolset.json

.PHONY: build run send disasm clean

build:
	@mkdir -p build
	swift build $(BUILD_FLAGS) --product Application
	"$(TCBIN)/llvm-objcopy" -O binary $(ELF) $(ROM)
	$(GBAFIX) $(ROM)

# mGBA の起動は macOS のみ。それ以外 (Codespaces など) ではブラウザの mGBA web を案内する
run: build
ifeq ($(shell uname -s),Darwin)
	open -a mGBA $(ROM)
else
	@echo "$(ROM) をダウンロードして mGBA web にドロップしてください:"
	@echo "  https://trickart.github.io/mgba-web/"
endif

send: build
	$(MULTIBOOT) $(ROM) $(if $(PORT),--port $(PORT))

disasm: build
	"$(TCBIN)/llvm-objdump" -d $(ELF) | less

clean:
	swift package $(BUILD_FLAGS) clean
	rm -rf build
