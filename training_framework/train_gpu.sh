#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PYTHON="${REPO_ROOT}/.venv/bin/python"
SYSTEM_LIBCUDA="/usr/lib/x86_64-linux-gnu/libcuda.so.470.57.02"

if [[ ! -x "${VENV_PYTHON}" ]]; then
  echo "Missing virtualenv python: ${VENV_PYTHON}" >&2
  exit 1
fi

if [[ ! -f "${SYSTEM_LIBCUDA}" ]]; then
  echo "Missing expected driver library: ${SYSTEM_LIBCUDA}" >&2
  exit 1
fi

export LD_PRELOAD="${SYSTEM_LIBCUDA}${LD_PRELOAD:+:${LD_PRELOAD}}"
export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

cd "${SCRIPT_DIR}"
exec "${VENV_PYTHON}" -m videolua.train --config config.yaml "$@"
