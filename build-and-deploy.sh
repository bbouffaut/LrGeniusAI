#!/usr/bin/env bash
# build-and-deploy.sh — package the plugin and install it into Lightroom Classic.
#
# 1. Rebuilds build/LrGeniusAI.lrplugin from LrGeniusAI.lrdevplugin/ (*.lua).
# 2. Mirrors the result into the plugin folder Lightroom loads
#    (Adobe Lightroom Classic.app/Contents/PlugIns/LrGeniusAI.lrplugin) with
#    rsync --delete, so removed/renamed files never linger in the installed copy.
#
# Lightroom reads plugins only at startup: restart (quit/reopen) LRC after this.
#
# Override the install target with ADOBE_PLUGIN_DIR=/path/to/LrGeniusAI.lrplugin
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
PLUGIN_DIR="${BUILD_DIR}/LrGeniusAI.lrplugin"
ADOBE_PLUGIN_DIR="${ADOBE_PLUGIN_DIR:-/Applications/Adobe Lightroom Classic/Adobe Lightroom Classic.app/Contents/PlugIns/LrGeniusAI.lrplugin}"

echo "Cleaning ${BUILD_DIR}..."
rm -rf "${BUILD_DIR}"
mkdir -p "${PLUGIN_DIR}"

echo "Copying plugin files..."
cp "${ROOT_DIR}/LrGeniusAI.lrdevplugin/"*.lua "${PLUGIN_DIR}/"
cp "${ROOT_DIR}/LrGeniusAI.lrdevplugin/TranslatedStrings_"*.txt "${PLUGIN_DIR}/" 2>/dev/null || true

echo "Built plugin at: ${PLUGIN_DIR}"

if [[ ! -d "${ADOBE_PLUGIN_DIR}" ]]; then
    echo "ERROR: Lightroom plugin folder not found: ${ADOBE_PLUGIN_DIR}" >&2
    echo "       Install the plugin once via Lightroom's Plug-in Manager," >&2
    echo "       or set ADOBE_PLUGIN_DIR to the folder Lightroom loads." >&2
    exit 2
fi
if [[ ! -w "${ADOBE_PLUGIN_DIR}" ]]; then
    echo "ERROR: no write access to ${ADOBE_PLUGIN_DIR}" >&2
    exit 3
fi

echo "Deploying to: ${ADOBE_PLUGIN_DIR}"
rsync -a --delete \
    --exclude '.*' \
    "${PLUGIN_DIR}/" "${ADOBE_PLUGIN_DIR}/"

echo "Deployed $(ls -1 "${ADOBE_PLUGIN_DIR}" | wc -l | tr -d ' ') files."
echo "Restart Lightroom Classic to load the new plugin."
