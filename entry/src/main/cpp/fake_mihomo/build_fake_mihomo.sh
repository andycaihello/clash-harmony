#!/bin/bash
# build_fake_mihomo.sh — 编译功能性 fake mihomo adapter
#
# 用法:
#   ./build_fake_mihomo.sh                    # 为当前平台编译（本地测试）
#   ./build_fake_mihomo.sh x86_64             # 为 OHOS x86_64 模拟器编译
#   ./build_fake_mihomo.sh arm64-v8a          # 为 OHOS ARM64 真机编译
#
# 输出: libmihomo_ohos.so 被复制到对应 ABI 的 prebuilt 目录

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAKE_SRC="$SCRIPT_DIR/fake_mihomo.c"
PREBUILT_DIR="$SCRIPT_DIR/../prebuilt"

TARGET_ABI="${1:-$(uname -m)}"
case "$TARGET_ABI" in
    x86_64|arm64|arm64-v8a) ;;
    *)
        echo "Usage: $0 [x86_64|arm64-v8a]"
        echo "Default: current platform ($(uname -m))"
        ;;
esac

OUT_DIR="$PREBUILT_DIR/$TARGET_ABI"
mkdir -p "$OUT_DIR"
OUT_SO="$OUT_DIR/libmihomo_ohos.so"

# 检测 OHOS NDK
OHOS_NDK="${OHOS_NDK:-}"
if [ -z "$OHOS_NDK" ] && [ -d "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native" ]; then
    OHOS_NDK="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"
fi

if [ -n "$OHOS_NDK" ] && [ "$TARGET_ABI" != "$(uname -m)" ]; then
    # OHOS 交叉编译
    echo "[fake_mihomo] Cross-compiling for OHOS $TARGET_ABI using NDK: $OHOS_NDK"

    case "$TARGET_ABI" in
        x86_64)   OHOS_TRIPLE="x86_64-linux-ohos" ;;
        arm64-v8a) OHOS_TRIPLE="aarch64-linux-ohos" ;;
    esac

    CLANG="$OHOS_NDK/llvm/bin/${OHOS_TRIPLE}-clang"
    SYSROOT="$OHOS_NDK/sysroot"

    if [ ! -f "$CLANG" ]; then
        echo "[fake_mihomo] ERROR: OHOS clang not found at $CLANG"
        echo "  Install DevEco Studio or set OHOS_NDK env var."
        exit 1
    fi

    "$CLANG" \
        -target "$OHOS_TRIPLE" \
        --sysroot="$SYSROOT" \
        -O2 -Wall -fPIC -shared \
        -fvisibility=hidden \
        -pthread \
        -o "$OUT_SO" \
        "$FAKE_SRC"

else
    # 本地编译（macOS/Linux 测试）
    echo "[fake_mihomo] Building for local platform ($TARGET_ABI)"

    cc -O2 -Wall -fPIC -shared \
        -fvisibility=hidden \
        -pthread \
        -o "$OUT_SO" \
        "$FAKE_SRC"
fi

echo "[fake_mihomo] Built: $OUT_SO"

# 验证导出符号
if command -v nm &>/dev/null; then
    echo "[fake_mihomo] Exported symbols:"
    nm -gU "$OUT_SO" 2>/dev/null | grep Mihomo || nm -g "$OUT_SO" 2>/dev/null | grep "T _Mihomo" || echo "  (check with: nm -g $OUT_SO | grep Mihomo)"
fi

# 检查文件
if [ -f "$OUT_SO" ]; then
    SIZE=$(ls -lh "$OUT_SO" | awk '{print $5}')
    echo "[fake_mihomo] Size: $SIZE"
    echo "[fake_mihomo] Ready. Rebuild HAP to include the functional adapter."
else
    echo "[fake_mihomo] ERROR: Build failed"
    exit 1
fi
