-- StyleMatchCommon.lua
-- Shared helpers for pushing photos to the server's /style-match/index
-- endpoint: metadata extraction and batched preview export.
--
-- Used by TaskStyleMatchIndex.lua. TaskExportManifest.lua keeps its own copy
-- (it also writes the manifest file); unify only if the row shape changes.

StyleMatchCommon = {}

local PREVIEW_BATCH_SIZE = 25

local function trimmed(value)
    if value == nil or type(value) == "table" then
        return nil
    end
    local text = Util.trim(tostring(value))
    if text == "" or text == "--" or text == "---" then
        return nil
    end
    return text
end

local function numberOrNil(value)
    if value == nil then
        return nil
    end
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    return number
end

local function fileLeafName(path)
    if path == nil then
        return nil
    end
    local ok, name = pcall(function() return LrPathUtils.leafName(path) end)
    if ok then
        return name
    end
    return nil
end

local function captureTimeOf(photo)
    local raw = trimmed(photo:getRawMetadata("dateTimeOriginalISO8601"))
    if raw ~= nil then
        return raw
    end
    local value = photo:getRawMetadata("dateTimeOriginal")
    if value ~= nil then
        local ok, formatted = pcall(function() return LrDate.timeToW3CDate(value) end)
        if ok then
            return formatted
        end
    end
    return nil
end

local function gpsOf(photo)
    local ok, gps = pcall(function() return photo:getRawMetadata("gps") end)
    if not ok or type(gps) ~= "table" then
        return nil, nil
    end
    return numberOrNil(gps.latitude), numberOrNil(gps.longitude)
end

local function descriptionOf(photo)
    -- AI captions are written to the catalog caption field by MetadataManager.
    local description = trimmed(photo:getFormattedMetadata("caption"))
    if description ~= nil then
        return description
    end
    local ok, pluginContext = pcall(function()
        return photo:getPropertyForPlugin(_PLUGIN, "photoContext")
    end)
    if ok then
        return trimmed(pluginContext)
    end
    return nil
end

--- True when the photo carries a non-empty description (AI caption in the
--- catalog caption field, else the plugin's own photoContext). The style-match
--- index is description-driven, so photos without one are never sent.
-- @param photo LrPhoto
-- @return boolean
function StyleMatchCommon.hasDescription(photo)
    return descriptionOf(photo) ~= nil
end

--- Builds the index payload fields for one photo.
-- @param photo LrPhoto
-- @param catalogId string
-- @param previewPath string Path to the exported current-look JPEG.
-- @return table fields ready for SearchIndexAPI.styleMatchIndexPhoto options.
function StyleMatchCommon.buildIndexRow(photo, catalogId, previewPath)
    local filePath = photo:getRawMetadata("path")
    local fileName = trimmed(photo:getFormattedMetadata("fileName")) or fileLeafName(filePath)
    local latitude, longitude = gpsOf(photo)

    local developSettings = {}
    -- LrTasks.pcall, never plain pcall: photo:getDevelopSettings() yields
    -- internally on LrC 15.x, and a plain pcall around yielding code dies with
    -- "Yielding is not allowed within a C or metamethod call" — which silently
    -- shipped an empty settings table (has_edits always false) for every photo.
    local ok, settings = LrTasks.pcall(function() return photo:getDevelopSettings() end)
    if ok and type(settings) == "table" then
        developSettings = settings
    else
        log:warn("Style Match: getDevelopSettings failed for " .. tostring(fileName) .. ": " .. tostring(settings))
    end

    local hasEdits = StyleWhitelist.hasEdits(developSettings)

    return {
        catalog_id = catalogId,
        lrc_local_id = photo.localIdentifier,
        uuid = tostring(photo:getRawMetadata("uuid") or ""),
        filename = fileName,
        file_path = filePath,
        preview_path = previewPath,
        capture_time = captureTimeOf(photo),
        latitude = latitude,
        longitude = longitude,
        camera_make = trimmed(photo:getFormattedMetadata("cameraMake")),
        camera_model = trimmed(photo:getFormattedMetadata("cameraModel")),
        lens = trimmed(photo:getFormattedMetadata("lens")),
        focal_length_mm = numberOrNil(photo:getRawMetadata("focalLength")),
        aperture_f_number = numberOrNil(photo:getRawMetadata("aperture")),
        iso = numberOrNil(photo:getRawMetadata("isoSpeedRating")),
        develop_settings = developSettings,
        has_edits = hasEdits,
        description = descriptionOf(photo),
    }
end

--- Exports current-look previews in batches (one export session per batch).
-- @param photos table Array of LrPhoto.
-- @param progressScope LrProgressScope
-- @param baseProgress number 0-1 start of this phase.
-- @param progressSpan number 0-1 span of this phase.
-- @return table Map photo -> exported path (missing when export failed).
function StyleMatchCommon.exportPreviews(photos, progressScope, baseProgress, progressSpan)
    local previewPaths = {}

    for startIndex = 1, #photos, PREVIEW_BATCH_SIZE do
        if progressScope:isCanceled() then
            break
        end

        local batch = {}
        for index = startIndex, math.min(startIndex + PREVIEW_BATCH_SIZE - 1, #photos) do
            table.insert(batch, photos[index])
        end

        progressScope:setCaption(
            LOC("$$$/LrGeniusAI/StyleMatchIndex/RenderProgress=Rendering previews ^1-^2 of ^3...",
                startIndex, math.min(startIndex + PREVIEW_BATCH_SIZE - 1, #photos), #photos)
        )

        -- LrTasks.pcall (not plain pcall): the exporter yields (LrTasks.pcall
        -- inside LrExportSession), and Lua 5.1 forbids yields across a plain
        -- pcall boundary ("attempt to yield across metamethod/C-call boundary").
        local ok, batchPaths = LrTasks.pcall(function()
            return SearchIndexAPI.exportPhotosForIndexing(batch)
        end)

        if ok and type(batchPaths) == "table" then
            for photo, path in pairs(batchPaths) do
                previewPaths[photo] = path
            end
        else
            log:warn("Style Match: preview export batch failed: " .. tostring(batchPaths))
        end

        local completed = math.min(startIndex + PREVIEW_BATCH_SIZE - 1, #photos)
        progressScope:setPortionComplete(baseProgress + (progressSpan * completed / #photos), 1)
        LrTasks.yield()
    end

    return previewPaths
end

return StyleMatchCommon
