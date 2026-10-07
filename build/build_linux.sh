#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BASE=adfffbe41b2cabcd51fff326ab045662265062bb
ARCH=${BONSAI_CUDA_ARCH:-native}
JOBS=${BONSAI_BUILD_JOBS:-4}

if [[ $(uname -s) != Linux ]]; then
    echo 'This script builds on Linux. On Windows use build/build_windows.ps1.' >&2
    exit 1
fi
for tool in git cmake nvcc c++ sha256sum; do
    command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool. Install Git, CMake >=3.24, a CUDA-compatible C++ compiler, and the CUDA toolkit (nvcc on PATH)." >&2; exit 1; }
done
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || { echo 'BONSAI_BUILD_JOBS must be a positive integer.' >&2; exit 1; }
[[ $ARCH =~ ^(native|[0-9]+(-real|-virtual)?)(\;[0-9]+(-real|-virtual)?)*$ ]] || { echo 'BONSAI_CUDA_ARCH must be native or CUDA architectures such as 89 or 86;89.' >&2; exit 1; }
version=$(cmake --version | head -n 1)
if [[ ! $version =~ ([0-9]+)\.([0-9]+) ]] || (( BASH_REMATCH[1] < 3 || (BASH_REMATCH[1] == 3 && BASH_REMATCH[2] < 24) )); then
    echo "CMake >=3.24 required; found $version" >&2
    exit 1
fi

PATCHES=("$ROOT"/patches/*.patch)
[[ -f ${PATCHES[0]} ]] || { echo 'No bundled patches found.' >&2; exit 1; }
REV=$( { printf '%s\n' "$BASE"; cat "${PATCHES[@]}"; } | sha256sum)
REV=${REV%% *}
SRC="$ROOT/vendor/linux-$REV"
mkdir -p "$ROOT/vendor" "$ROOT/tooling"
if [[ ! -d $SRC ]]; then
    STAGE=$(mktemp -d "$ROOT/vendor/.linux-build.XXXXXX")
    trap 'rm -rf -- "$STAGE"' EXIT
    git -C "$STAGE" init -q
    git -C "$STAGE" remote add origin https://github.com/PrismML-Eng/llama.cpp.git
    git -C "$STAGE" fetch --depth 1 origin "$BASE"
    git -C "$STAGE" checkout --detach FETCH_HEAD
    for patch in "${PATCHES[@]}"; do
        git -C "$STAGE" apply --check "$patch"
        git -C "$STAGE" apply "$patch"
    done
    git -C "$STAGE" diff --binary HEAD > "$STAGE/.git/bonsai-applied.patch"
    mv -- "$STAGE" "$SRC"
    trap - EXIT
fi
if ! git -C "$SRC" diff --binary HEAD | cmp -s - "$SRC/.git/bonsai-applied.patch"; then
    echo "Source changed since setup: $SRC. Preserve your edits and use a separate bundle checkout to rebuild." >&2
    exit 1
fi

# Host compiler for nvcc. CUDA 13.x refuses gcc newer than 15 (Fedora 43 ships 16; issue #5). Two ways through:
#   BONSAI_CUDA_HOST_COMPILER=/usr/bin/g++-15   point nvcc at a supported g++ (preferred; dnf install gcc15-c++ on Fedora)
#   BONSAI_ALLOW_UNSUPPORTED_COMPILER=1          pass nvcc's -allow-unsupported-compiler (works in practice, NVIDIA's "own risk")
# When neither is set and the default g++ is newer than nvcc supports, the script picks the second with a warning.
CUDA_EXTRA=()
if [[ -n ${BONSAI_CUDA_HOST_COMPILER:-} ]]; then
    CUDA_EXTRA+=(-DCMAKE_CUDA_HOST_COMPILER="$BONSAI_CUDA_HOST_COMPILER")
else
    gcc_major=$(c++ -dumpfullversion -dumpversion 2>/dev/null | cut -d. -f1)
    nvcc_major=$(nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9]*\)\..*/\1/p')
    if [[ ${BONSAI_ALLOW_UNSUPPORTED_COMPILER:-} == 1 ]] || { [[ ${nvcc_major:-0} -ge 13 ]] && [[ ${gcc_major:-0} -gt 15 ]]; }; then
        echo "Host g++ $gcc_major is newer than CUDA $nvcc_major supports: building with -allow-unsupported-compiler (set BONSAI_CUDA_HOST_COMPILER to a supported g++ instead if the build misbehaves)." >&2
        CUDA_EXTRA+=(-DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler)
    fi
fi
cmake -S "$SRC" -B "$SRC/build-linux" -DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES="$ARCH" "${CUDA_EXTRA[@]}"
cmake --build "$SRC/build-linux" --target llama-server -j "$JOBS"
[[ -x "$SRC/build-linux/bin/llama-server" ]] || { echo 'Build did not produce llama-server.' >&2; exit 1; }
printf '%s\n' "$SRC/build-linux/bin/llama-server" > "$ROOT/tooling/linux-server-path"
printf '\nBuild complete. Start with:\n  bash "%s/start-linux.sh" /absolute/path/to/Ternary-Bonsai-2-27B-PTQ1_0.gguf\n' "$ROOT"
