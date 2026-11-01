-- StyleWhitelist.lua
-- Key classification for the "Style Match" feature.
--
-- The develop-settings table returned by photo:getDevelopSettings() mixes three
-- very different kinds of adjustments:
--   * style keys   - the look of the photo (contrast, tone curve, colour grading,
--                    HSL, grain, vignette, ...). Transferred by default.
--   * scene keys   - capture-dependent values (exposure, whites/blacks, WB).
--                    Transferred only when the user explicitly opts in.
--   * local keys   - masks, crops, retouch, lens corrections. NEVER transferred,
--                    they are stripped from every snapshot.
--
-- The classification is a draft: the definitive key list is refined empirically
-- with styleMatchDiffDevelopSettings() in Lightroom (see StyleMatchSpike.lua).

StyleWhitelist = {}

-- Keys transferred with the style by default.
StyleWhitelist.STYLE_KEY_LIST = {
    "Contrast2012",
    "Highlights2012",
    "Shadows2012",
    "Clarity2012",
    "Texture",
    "Dehaze",
    "Vibrance",
    "Saturation",
    "ParametricShadows",
    "ParametricDarks",
    "ParametricLights",
    "ParametricHighlights",
    "ParametricShadowSplit",
    "ParametricMidtoneSplit",
    "ParametricLightSplit",
    "ParametricHighlightSplit",
    "ToneCurvePV2012",
    "ToneCurvePV2012Red",
    "ToneCurvePV2012Green",
    "ToneCurvePV2012Blue",
    "SplitToningHighlightHue",
    "SplitToningHighlightSaturation",
    "SplitToningBalance",
    "SplitToningShadowHue",
    "SplitToningShadowSaturation",
    "SharpenAmount",
    "SharpenRadius",
    "SharpenDetail",
    "SharpenEdgeMasking",
    "NoiseReductionAmount",
    "NoiseReductionDetail",
    "NoiseReductionColor",
    "ColorNoiseReduction",
    "ColorNoiseReductionDetail",
    "ColorNoiseReductionSmoothness",
    "PostCropVignetteAmount",
    "PostCropVignetteMidpoint",
    "PostCropVignetteFeather",
    "PostCropVignetteRoundness",
    "PostCropVignetteStyle",
    "PostCropVignetteContrast",
    "PostCropVignetteHighlightContrast",
    "GrainAmount",
    "GrainSize",
    "GrainFrequency",
    "CameraProfile",
    "LookName",
    "LookAmount",
    "ConvertToGrayscale",
    "ShadowTint",
    "HighlightTint",
}

-- Prefix-matched style families: colour grading, per-colour HSL and B&W mix.
StyleWhitelist.STYLE_PREFIXES = {
    "ColorGrade",
    "Hue",
    "Saturation",
    "Luminance",
    "GrayMix",
}

-- Keys that depend on the scene, not on the look. Opt-in only.
StyleWhitelist.SCENE_KEY_LIST = {
    "Exposure2012",
    "Whites2012",
    "Blacks2012",
    "WhiteBalance",
    "Temperature",
    "Tint",
}

-- Keys that must never leave the catalog. Stripped from every snapshot.
StyleWhitelist.LOCAL_KEY_LIST = {
    "LocalAdjustments",
}

StyleWhitelist.LOCAL_PREFIXES = {
    "Crop",
    "Perspective",
    "Orientation",
    "RetouchInfo",
    "AutoLateralCA",
    "Correction",
}

-- Default (as-imported) values, used to decide whether a photo counts as edited.
-- CameraProfile is compared against "Adobe Standard"; a camera-specific profile
-- therefore counts as an edit, which is what we want to report.
StyleWhitelist.DEFAULT_VALUES = {
    Contrast2012 = 0,
    Highlights2012 = 0,
    Shadows2012 = 0,
    Whites2012 = 0,
    Blacks2012 = 0,
    Exposure2012 = 0,
    Clarity2012 = 0,
    Texture = 0,
    Dehaze = 0,
    Vibrance = 0,
    Saturation = 0,
    ParametricShadows = 0,
    ParametricDarks = 0,
    ParametricLights = 0,
    ParametricHighlights = 0,
    ParametricShadowSplit = 25,
    ParametricMidtoneSplit = 50,
    ParametricHighlightSplit = 75,
    ToneCurvePV2012 = "",
    ToneCurvePV2012Red = "",
    ToneCurvePV2012Green = "",
    ToneCurvePV2012Blue = "",
    SplitToningHighlightHue = 0,
    SplitToningHighlightSaturation = 0,
    SplitToningBalance = 0,
    SplitToningShadowHue = 0,
    SplitToningShadowSaturation = 0,
    SharpenAmount = 40,
    SharpenRadius = 1,
    SharpenDetail = 25,
    SharpenEdgeMasking = 0,
    NoiseReductionAmount = 0,
    NoiseReductionDetail = 50,
    NoiseReductionColor = 50,
    ColorNoiseReduction = 25,
    ColorNoiseReductionDetail = 50,
    ColorNoiseReductionSmoothness = 50,
    PostCropVignetteAmount = 0,
    PostCropVignetteMidpoint = 50,
    PostCropVignetteFeather = 50,
    PostCropVignetteRoundness = 0,
    PostCropVignetteStyle = 1,
    PostCropVignetteContrast = 0,
    PostCropVignetteHighlightContrast = 0,
    GrainAmount = 0,
    GrainSize = 25,
    GrainFrequency = 50,
    CameraProfile = "Adobe Standard",
    LookAmount = 100,
    ConvertToGrayscale = false,
    ShadowTint = 0,
    HighlightTint = 0,
    WhiteBalance = "As Shot",
}

-- Sets are built once from the lists above.
local styleKeySet = {}
for _, key in ipairs(StyleWhitelist.STYLE_KEY_LIST) do
    styleKeySet[key] = true
end

local sceneKeySet = {}
for _, key in ipairs(StyleWhitelist.SCENE_KEY_LIST) do
    sceneKeySet[key] = true
end

local localKeySet = {}
for _, key in ipairs(StyleWhitelist.LOCAL_KEY_LIST) do
    localKeySet[key] = true
end

local function startsWith(text, prefix)
    return string.sub(text, 1, #prefix) == prefix
end

local function hasPrefix(key, prefixes)
    for _, prefix in ipairs(prefixes) do
        if startsWith(key, prefix) then
            return true
        end
    end
    return false
end

---
-- Classifies a single develop-settings key.
-- @param key string Develop-settings key name.
-- @return string|nil "local", "style", "scene" or nil when the key is irrelevant.
--
function StyleWhitelist.classify(key)
    if type(key) ~= "string" then
        return nil
    end

    -- Local first: local keys win over any style/scene family.
    if localKeySet[key] or hasPrefix(key, StyleWhitelist.LOCAL_PREFIXES) then
        return "local"
    end
    if styleKeySet[key] then
        return "style"
    end
    if sceneKeySet[key] then
        return "scene"
    end
    if hasPrefix(key, StyleWhitelist.STYLE_PREFIXES) then
        return "style"
    end

    return nil
end

local function sortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl or {}) do
        table.insert(keys, tostring(key))
    end
    table.sort(keys)
    return keys
end

local function subsetForClass(developSettings, wantedClass)
    local subset = {}
    if type(developSettings) ~= "table" then
        return subset
    end

    for _, key in ipairs(sortedKeys(developSettings)) do
        if StyleWhitelist.classify(key) == wantedClass then
            subset[key] = developSettings[key]
        end
    end

    return subset
end

---
-- Returns the style subset of a develop-settings table (safe to transfer by default).
-- @param developSettings table Settings as returned by photo:getDevelopSettings().
-- @return table New table containing only style keys (empty when nothing matches).
--
function StyleWhitelist.styleSubset(developSettings)
    return subsetForClass(developSettings, "style")
end

---
-- Returns the opted-in scene subset (exposure, whites/blacks, white balance).
--
function StyleWhitelist.sceneSubset(developSettings)
    return subsetForClass(developSettings, "scene")
end

---
-- Removes local adjustments (masks, crop, perspective, retouch, lens corrections)
-- from a snapshot and reports how many local keys were dropped.
-- Scene keys are intentionally kept: only local keys are stripped.
-- @param developSettings table Settings as returned by photo:getDevelopSettings().
-- @return table { settings = strippedTable, localCount = number }
--
function StyleWhitelist.stripLocal(developSettings)
    local stripped = {}
    local localCount = 0

    if type(developSettings) ~= "table" then
        return { settings = stripped, localCount = 0 }
    end

    for _, key in ipairs(sortedKeys(developSettings)) do
        if StyleWhitelist.classify(key) == "local" then
            localCount = localCount + 1
        else
            stripped[key] = developSettings[key]
        end
    end

    return { settings = stripped, localCount = localCount }
end

local function valuesEqual(a, b)
    if type(a) == "number" and type(b) == "number" then
        return math.abs(a - b) < 0.000001
    end
    if type(a) == "string" and type(b) == "string" then
        return Util.trim(a) == Util.trim(b)
    end
    return a == b
end

local function isKnownDefault(key)
    return StyleWhitelist.DEFAULT_VALUES[key] ~= nil
end

local function matchesDefault(key, value)
    local defaultValue = StyleWhitelist.DEFAULT_VALUES[key]
    if defaultValue == nil then
        -- No known default: treat empty/zero/false as "untouched".
        if value == nil or value == false or value == "" then
            return true
        end
        return type(value) == "number" and math.abs(value) < 0.000001
    end
    return valuesEqual(value, defaultValue)
end

---
-- True when a single key/value pair differs from the as-imported default.
--
function StyleWhitelist.isDefaultValue(key, value)
    return matchesDefault(key, value)
end

---
-- Decides whether a photo has develop edits worth indexing as a style reference.
-- Style and scene keys are compared against their defaults; local adjustments
-- also count as edits (they are reported to the user, just never transferred).
-- @param developSettings table Settings as returned by photo:getDevelopSettings().
-- @return boolean hasEdits, number localAdjustmentCount
--
function StyleWhitelist.hasEdits(developSettings)
    if type(developSettings) ~= "table" then
        return false, 0
    end

    local localCount = 0
    for _, key in ipairs(sortedKeys(developSettings)) do
        local keyClass = StyleWhitelist.classify(key)
        if keyClass == "local" then
            localCount = localCount + 1
        elseif keyClass ~= nil then
            if not matchesDefault(key, developSettings[key]) then
                return true, localCount
            end
        end
    end

    return localCount > 0, localCount
end

---
-- Compares two develop-settings snapshots and returns the names of the keys that
-- changed (present in "after" with a different value, or absent in "before").
-- Used to refine the whitelist empirically inside Lightroom.
-- @param before table Settings captured before the change (may be nil).
-- @param after table Settings captured after the change (may be nil).
-- @return table Sorted array of changed key names.
--
function StyleWhitelist.diffDevelopSettings(before, after)
    if type(after) ~= "table" then
        return {}
    end

    local changed = {}
    for _, key in ipairs(sortedKeys(after)) do
        if type(before) ~= "table" or not valuesEqual(before[key], after[key]) then
            table.insert(changed, key)
        end
    end

    return changed
end

---
-- Stable, plugin-generated catalog identifier. Generated once and persisted in
-- the plugin preferences so the server can scope matches to this catalog.
-- @return string Catalog identifier.
--
function StyleWhitelist.catalogId()
    if not Util.nilOrEmpty(prefs.styleMatchCatalogId) then
        return prefs.styleMatchCatalogId
    end

    math.randomseed(os.time() + math.floor(LrDate.currentTime() % 100000))
    local catalogPath = ""
    pcall(function()
        catalogPath = LrApplication.activeCatalog():getPath() or ""
    end)

    local function segment(count)
        local parts = {}
        for index = 1, count do
            parts[index] = string.format("%02x", math.random(0, 255))
        end
        return table.concat(parts)
    end

    local catalogId = string.format(
        "%s-%s-4%s-%s-%s",
        segment(4),
        segment(2),
        segment(2):sub(2),
        segment(2),
        segment(6)
    )

    prefs.styleMatchCatalogId = catalogId
    log:trace("Style Match: generated catalog id " .. catalogId .. " for catalog " .. catalogPath)
    return catalogId
end

---
-- Directory used for Style Match side files (feedback log, debug dumps).
-- Created on demand; falls back to the system temp folder when the plugin
-- folder is not writable.
-- @return string Directory path.
--
function StyleWhitelist.dataDirectory()
    local directory = LrPathUtils.child(_PLUGIN.path, "data")
    if not LrFileUtils.exists(directory) then
        pcall(function() LrFileUtils.createDirectory(directory) end)
    end
    if LrFileUtils.exists(directory) then
        return directory
    end
    return LrPathUtils.getStandardFilePath("temp")
end

-- Globals used by the task files (TaskExportManifest.lua / TaskStyleMatch.lua).
function styleMatchStyleSubset(developSettings)
    return StyleWhitelist.styleSubset(developSettings)
end

function styleMatchSceneSubset(developSettings)
    return StyleWhitelist.sceneSubset(developSettings)
end

function styleMatchStripLocal(developSettings)
    return StyleWhitelist.stripLocal(developSettings)
end

function styleMatchDiffDevelopSettings(before, after)
    return StyleWhitelist.diffDevelopSettings(before, after)
end

return StyleWhitelist
