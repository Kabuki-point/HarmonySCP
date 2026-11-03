#!/usr/bin/env bash
# Run with a Linux/macOS HarmonyOS native SDK; output is confined to build/ and entry/libs/x86_64/.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
: "${OHOS_NDK_HOME:?Set OHOS_NDK_HOME to the HarmonyOS SDK native directory}"
work_dir="$repo_dir/build/x86_64-deps"
mkdir -p "$work_dir"
fetch_source() {
    local name=$1 url=$2 digest=$3
    if [[ ! -f "$work_dir/$name.tar.gz" ]]; then
        curl --fail --location "$url" --output "$work_dir/$name.tar.gz"
    fi
    python3 - "$work_dir/$name.tar.gz" "$digest" <<'PY'
import hashlib
import pathlib
import sys
if hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest() != sys.argv[2]:
    raise SystemExit('Source SHA256 mismatch: ' + sys.argv[1])
PY
    if [[ ! -d "$work_dir/$name" ]]; then
        tar -xzf "$work_dir/$name.tar.gz" -C "$work_dir"
    fi
}
fetch_source openssl-3.5.4 https://github.com/openssl/openssl/releases/download/openssl-3.5.4/openssl-3.5.4.tar.gz 967311f84955316969bdb1d8d4b983718ef42338639c621ec4c34fddef355e99
fetch_source libssh2-1.11.1 https://libssh2.org/download/libssh2-1.11.1.tar.gz d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7
export CC="$OHOS_NDK_HOME/llvm/bin/clang"
export AR="$OHOS_NDK_HOME/llvm/bin/llvm-ar"
export RANLIB="$OHOS_NDK_HOME/llvm/bin/llvm-ranlib"
export CFLAGS="--target=x86_64-linux-ohos --sysroot=\"$OHOS_NDK_HOME/sysroot\" -fPIC"
(
    cd "$work_dir/openssl-3.5.4"
    perl Configure linux-x86_64 no-shared no-module no-tests no-asm no-makedepend \
        --prefix="$work_dir/prefix" --libdir=lib
    make -j"${JOBS:-4}" build_libs
    make install_dev
)
cmake -S "$work_dir/libssh2-1.11.1" -B "$work_dir/libssh2-build" \
    -DCMAKE_TOOLCHAIN_FILE="$OHOS_NDK_HOME/build/cmake/ohos.toolchain.cmake" \
    -DOHOS_ARCH=x86_64 -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCRYPTO_BACKEND=OpenSSL -DOPENSSL_INCLUDE_DIR="$work_dir/prefix/include" \
    -DOPENSSL_CRYPTO_LIBRARY="$work_dir/prefix/lib/libcrypto.a" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF \
    -DENABLE_ZLIB_COMPRESSION=OFF -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=TRUE
cmake --build "$work_dir/libssh2-build" -j "${JOBS:-4}"
mkdir -p "$repo_dir/entry/libs/x86_64"
cp "$work_dir/prefix/lib/libcrypto.a" "$repo_dir/entry/libs/x86_64/libcrypto.a"
cp "$work_dir/libssh2-build/src/libssh2.a" "$repo_dir/entry/libs/x86_64/libssh2.a"
