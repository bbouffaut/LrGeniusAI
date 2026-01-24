#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${ROOT_DIR}/../geniusai-server"
BUILD_DIR="${ROOT_DIR}/build"
PLUGIN_DIR="${BUILD_DIR}/LrGeniusAI.lrplugin"

if [[ ! -d "${SERVER_DIR}" ]]; then
  echo "Missing ${SERVER_DIR}."
  echo "Clone the server repo next to this repo:"
  echo "  git clone https://github.com/bbouffaut/geniusai-server.git"
  exit 1
fi

if [[ ! -d "${SERVER_DIR}/dist" ]]; then
  if ! command -v uv >/dev/null 2>&1; then
    echo "Missing server build at ${SERVER_DIR}/dist and 'uv' is not installed."
    echo "Install uv, then re-run this script:"
    echo "  https://docs.astral.sh/uv/"
    exit 1
  fi

  echo "Building server with uv..."
  pushd "${SERVER_DIR}" >/dev/null

  if [[ -f pyproject.toml ]]; then
    uv sync
  else
    echo "No pyproject.toml found in ${SERVER_DIR}."
    echo "This script expects an uv project with pyproject.toml."
    popd >/dev/null
    exit 1
  fi

  # Ensure pyinstaller is available for the build.
  uv pip install pyinstaller
  KMP_DUPLICATE_LIB_OK=TRUE uv run pyinstaller geniusai_server.spec --noconfirm

  popd >/dev/null
fi

mkdir -p "${PLUGIN_DIR}"

echo "Copying server and model files..."
cp -r "${SERVER_DIR}/dist/"* "${BUILD_DIR}/"

echo "Copying plugin files..."
cp "${ROOT_DIR}/LrGeniusAI.lrdevplugin/"*.lua "${PLUGIN_DIR}/"
cp "${ROOT_DIR}/LrGeniusAI.lrdevplugin/TranslatedStrings_"*.txt "${PLUGIN_DIR}/"

# macOS server binary needs executable permissions
if [[ -f "${BUILD_DIR}/lrgenius-server/lrgenius-server" ]]; then
  chmod +x "${BUILD_DIR}/lrgenius-server/lrgenius-server"
fi

echo "Built plugin at: ${PLUGIN_DIR}"
