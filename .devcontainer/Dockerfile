# Swift公式イメージ。Embedded Swift の標準ライブラリ (armv4t-none-none-eabi) と
# LLVMツール (ld.lld / llvm-objcopy / llvm-objdump) は同梱されている。足りないのは make だけ
FROM swift:6.4.2

RUN apt-get update \
    && apt-get install -y --no-install-recommends make \
    && rm -rf /var/lib/apt/lists/*
