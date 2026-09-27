#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ $# != 1 || ! -f $1 ]]; then
    echo "Usage: bash $0 /path/to/Ternary-Bonsai-2-27B-PTQ1_0.gguf" >&2
    exit 1
fi
[[ -f "$ROOT/tooling/linux-server-path" ]] || { echo 'Run bash build/build_linux.sh first.' >&2; exit 1; }
IFS= read -r SERVER < "$ROOT/tooling/linux-server-path"
[[ $SERVER == "$ROOT"/vendor/linux-*/build-linux/bin/llama-server && -x $SERVER ]] || { echo 'Built server is missing. Rerun bash build/build_linux.sh.' >&2; exit 1; }
CTX=${BONSAI_CTX:-8192}
PORT=${BONSAI_PORT:-8080}
[[ $CTX =~ ^[1-9][0-9]*$ ]] || { echo 'BONSAI_CTX must be a positive integer.' >&2; exit 1; }
[[ $PORT =~ ^[1-9][0-9]{0,4}$ ]] && (( PORT <= 65535 )) || { echo 'BONSAI_PORT must be between 1 and 65535.' >&2; exit 1; }
echo "Starting on http://127.0.0.1:$PORT (API: /v1). Ctrl-C stops the server."
exec "$SERVER" -m "$1" -ngl 99 -fa on -c "$CTX" --spec-type none \
    --jinja --host 127.0.0.1 --port "$PORT"
