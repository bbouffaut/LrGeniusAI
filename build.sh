#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
PLUGIN_DIR="${BUILD_DIR}/LrGeniusAI.lrplugin"

rm -rf "${BUILD_DIR}"
mkdir -p "${PLUGIN_DIR}"

echo "Copying plugin files..."
cp "${ROOT_DIR}/LrGeniusAI.lrdevplugin/"*.lua "${PLUGIN_DIR}/"
cp "${ROOT_DIR}/LrGeniusAI.lrdevplugin/TranslatedStrings_"*.txt "${PLUGIN_DIR}/"

echo "Built plugin at: ${PLUGIN_DIR}"
