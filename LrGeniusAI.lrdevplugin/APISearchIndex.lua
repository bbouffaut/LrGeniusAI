-- LrGeniusAI server API wrapper.
-- Provides functions to interact with the configured remote search index server.

SearchIndexAPI = {}

local function baseUrl()
    local url = prefs.serverBaseUrl
    if Util.nilOrEmpty(url) then
        return nil
    end
    url = Util.trim(url)
    if url:sub(-1) == "/" then
        url = url:sub(1, -2)
    end
    return url
end

local function endpointUrl(endpoint)
    local url = baseUrl()
    if not url then
        return nil, "Server base URL is not configured"
    end
    return url .. endpoint
end

local function serverRequestHeaders(extraHeaders)
    local headers = {
        { field = "apikey", value = tostring(prefs.serverApiKey or "") },
    }

    if extraHeaders ~= nil then
        for _, header in ipairs(extraHeaders) do
            table.insert(headers, header)
        end
    end

    return headers
end

local function safePhotoCall(photo, callback, context)
    if photo == nil then return nil end

    local success, value = pcall(callback)
    if success then
        return value
    end

    log:warn("Lightroom photo metadata call failed" .. (context and (" (" .. context .. ")") or "") .. ": " .. tostring(value))
    return nil
end

local function safeRawMetadata(photo, key)
    return safePhotoCall(photo, function()
        return photo:getRawMetadata(key)
    end, "raw:" .. tostring(key))
end

local function safeFormattedMetadata(photo, key)
    return safePhotoCall(photo, function()
        return photo:getFormattedMetadata(key)
    end, "formatted:" .. tostring(key))
end

local function safePluginProperty(photo, key)
    return safePhotoCall(photo, function()
        return photo:getPropertyForPlugin(_PLUGIN, key)
    end, "plugin:" .. tostring(key))
end

local function nonEmpty(value)
    if value == nil then
        return false
    end

    local text = tostring(value)
    if Util and Util.trim then
        text = Util.trim(text)
    end

    return text ~= ""
end

local function formatCaptureTime(value)
    if value == nil then return nil end
    if type(value) == "number" then
        if value <= 0 then return nil end
        local success, formatted = pcall(function()
            return LrDate.timeToW3CDate(value)
        end)
        if success and formatted ~= nil and tostring(formatted) ~= "" then
            return tostring(formatted)
        end
        return nil
    end
    if type(value) == "table" then
        return nil
    end

    local text = tostring(value)
    if Util and Util.trim then
        text = Util.trim(text)
    end

    if text == "" or text == "--" or text == "---" then
        return nil
    end

    local lowered = string.lower(text)
    if lowered == "unknown" or lowered == "none" or lowered == "nil" then
        return nil
    end

    return text
end

local function textValue(value)
    if value == nil or type(value) == "table" then
        return nil
    end

    local text = tostring(value)
    if Util and Util.trim then
        text = Util.trim(text)
    end

    if text == "" or text == "--" or text == "---" then
        return nil
    end

    local lowered = string.lower(text)
    if lowered == "unknown" or lowered == "none" or lowered == "nil" then
        return nil
    end

    return text
end

local function leafName(path)
    local text = textValue(path)
    if not text then
        return nil
    end

    local success, name = pcall(function()
        return LrPathUtils.leafName(text)
    end)
    if success then
        return textValue(name)
    end

    return nil
end

local function normalizedMetadataKey(key)
    return string.gsub(string.lower(tostring(key or "")), "[^%w]", "")
end

local function metadataTableValue(metadata, key)
    if type(metadata) ~= "table" then
        return nil
    end

    if metadata[key] ~= nil then
        return metadata[key]
    end

    local loweredKey = string.lower(key)
    local normalizedKey = normalizedMetadataKey(key)
    for metadataKey, value in pairs(metadata) do
        if type(metadataKey) == "string" then
            local loweredMetadataKey = string.lower(metadataKey)
            local normalizedCandidateKey = normalizedMetadataKey(metadataKey)
            if loweredMetadataKey == loweredKey
                or normalizedCandidateKey == normalizedKey
                or string.find(normalizedCandidateKey, normalizedKey, 1, true) ~= nil then
                return value
            end
        end
    end

    return nil
end

local function metadataLookupValue(metadataLookup, accessorName, key)
    if type(metadataLookup) ~= "table" then
        return nil
    end

    local source = metadataLookup[accessorName]
    if type(source) ~= "table" then
        return nil
    end

    return metadataTableValue(source, key)
end

local function dynamicFilenameFromMetadata(metadata, sourcePrefix)
    if type(metadata) ~= "table" then
        return nil, nil
    end

    for key, value in pairs(metadata) do
        local normalizedKey = normalizedMetadataKey(key)
        local looksLikeFilename =
            normalizedKey == "filename"
            or normalizedKey == "filenamewithoutextension"
            or normalizedKey == "preservedfilename"
            or (string.find(normalizedKey, "file", 1, true) ~= nil
                and string.find(normalizedKey, "name", 1, true) ~= nil)

        if looksLikeFilename then
            local filename = textValue(value)
            if filename then
                return filename, sourcePrefix .. ":" .. tostring(key)
            end
        end
    end

    return nil, nil
end

local function photoFilename(photo, fallbackPath, metadataLookup)
    local keys = { "fileName", "filename", "preservedFileName", "com.adobe.filename" }

    for _, key in ipairs(keys) do
        local filename = textValue(metadataLookupValue(metadataLookup, "formatted", key))
        if filename then
            return filename, "batch-formatted:" .. key
        end

        local filename = textValue(safeFormattedMetadata(photo, key))
        if filename then
            return filename, "formatted:" .. key
        end
    end

    local formattedMetadata = safeFormattedMetadata(photo, nil)
    for _, key in ipairs(keys) do
        local filename = textValue(metadataTableValue(formattedMetadata, key))
        if filename then
            return filename, "formatted-all:" .. key
        end
    end

    local rawMetadata = safeRawMetadata(photo, nil)
    local rawPath = metadataLookupValue(metadataLookup, "raw", "path")
        or metadataTableValue(rawMetadata, "path")
        or safeRawMetadata(photo, "path")
    local filename = leafName(rawPath)
    if filename then
        return filename, "raw:path"
    end

    local filenameSource
    filename, filenameSource = dynamicFilenameFromMetadata(metadataLookup and metadataLookup.formatted, "batch-formatted-dynamic")
    if filename then
        return filename, filenameSource
    end

    filename, filenameSource = dynamicFilenameFromMetadata(metadataLookup and metadataLookup.raw, "batch-raw-dynamic")
    if filename then
        return filename, filenameSource
    end

    filename = leafName(fallbackPath)
    if filename then
        return filename, "fallback:path"
    end

    return "", "empty"
end

local CATALOG_RAW_EXIF_KEYS = {
    "uuid",
    "path",
    "fileFormat",
    "fileSize",
    "width",
    "height",
    "dimensions",
    "croppedDimensions",
    "shutterSpeed",
    "aperture",
    "exposureBias",
    "flash",
    "isoSpeedRating",
    "focalLength",
    "focalLength35mm",
    "dateTimeOriginalISO8601",
    "dateTimeOriginal",
    "dateTimeDigitizedISO8601",
    "dateTimeDigitized",
    "dateTimeISO8601",
    "dateTime",
    "rating",
    "pickStatus",
    "colorNameForLabel",
    "gps",
    "gpsAltitude",
    "gpsImgDirection",
}

local CATALOG_FORMATTED_EXIF_KEYS = {
    "fileName",
    "preservedFileName",
    "copyName",
    "folderName",
    "fileSize",
    "fileType",
    "dimensions",
    "croppedDimensions",
    "exposure",
    "shutterSpeed",
    "aperture",
    "brightnessValue",
    "exposureBias",
    "flash",
    "exposureProgram",
    "meteringMode",
    "isoSpeedRating",
    "focalLength",
    "focalLength35mm",
    "lens",
    "subjectDistance",
    "dateTimeOriginal",
    "dateTimeDigitized",
    "dateTime",
    "cameraMake",
    "cameraModel",
    "cameraSerialNumber",
    "artist",
    "software",
    "gps",
    "gpsAltitude",
    "gpsImgDirection",
}

local function jsonSafeMetadataValue(value)
    if value == nil then
        return nil
    end

    local valueType = type(value)
    if valueType == "number" or valueType == "boolean" then
        return value
    end

    if valueType == "string" then
        return textValue(value)
    end

    if valueType == "table" then
        local result = {}
        for key, item in pairs(value) do
            local safeValue = jsonSafeMetadataValue(item)
            if safeValue ~= nil then
                result[tostring(key)] = safeValue
            end
        end
        if next(result) ~= nil then
            return result
        end
        return nil
    end

    return textValue(tostring(value))
end

local function addCatalogMetadataValue(target, key, value)
    local safeValue = jsonSafeMetadataValue(value)
    if safeValue ~= nil then
        target[key] = safeValue
    end
end

local function readCatalogMetadataValues(photo, accessorName, keys, metadataLookup)
    local metadata = {}
    for _, key in ipairs(keys) do
        local lookupValue = metadataLookupValue(metadataLookup, accessorName, key)
        if lookupValue ~= nil then
            addCatalogMetadataValue(metadata, key, lookupValue)
        elseif accessorName == "raw" then
            addCatalogMetadataValue(metadata, key, safeRawMetadata(photo, key))
        else
            addCatalogMetadataValue(metadata, key, safeFormattedMetadata(photo, key))
        end
    end

    if next(metadata) ~= nil then
        return metadata
    end

    return nil
end

local function readCatalogMetadataTable(photo, accessorName, metadataLookup)
    local lookupSource = metadataLookup and metadataLookup[accessorName]
    if type(lookupSource) == "table" and next(lookupSource) ~= nil then
        return jsonSafeMetadataValue(lookupSource)
    end

    local metadata
    if accessorName == "raw" then
        metadata = safeRawMetadata(photo, nil)
    else
        metadata = safeFormattedMetadata(photo, nil)
    end

    local safeMetadata = jsonSafeMetadataValue(metadata)
    if type(safeMetadata) == "table" and next(safeMetadata) ~= nil then
        return safeMetadata
    end

    return nil
end

local function dynamicCaptureTimeFromMetadata(metadata, sourcePrefix)
    if type(metadata) ~= "table" then
        return nil, nil
    end

    for key, value in pairs(metadata) do
        local normalizedKey = normalizedMetadataKey(key)
        local looksLikeCaptureTime =
            normalizedKey == "capturedate"
            or normalizedKey == "capturetime"
            or normalizedKey == "capturetimestamp"
            or normalizedKey == "datetimeoriginal"
            or normalizedKey == "datetimeoriginaliso8601"
            or normalizedKey == "originaldatetime"
            or (string.find(normalizedKey, "capture", 1, true) ~= nil
                and string.find(normalizedKey, "date", 1, true) ~= nil)

        if looksLikeCaptureTime then
            local formatted = formatCaptureTime(value)
            if formatted then
                return formatted, sourcePrefix .. ":" .. tostring(key)
            end
        end
    end

    return nil, nil
end

local function catalogCaptureTime(photo, metadataLookup)
    local rawKeys = {
        "dateTimeOriginalISO8601",
        "dateTimeOriginal",
        "dateTimeISO8601",
        "dateTime",
    }

    for _, key in ipairs(rawKeys) do
        local value = formatCaptureTime(metadataLookupValue(metadataLookup, "raw", key))
            or formatCaptureTime(safeRawMetadata(photo, key))
        if value then
            return value, (metadataLookupValue(metadataLookup, "raw", key) ~= nil and "batch-lightroom-raw:" or "lightroom-raw:") .. key
        end
    end

    local formattedKeys = {
        "dateTimeOriginal",
        "dateTime",
        "dateCreated",
    }

    for _, key in ipairs(formattedKeys) do
        local value = formatCaptureTime(metadataLookupValue(metadataLookup, "formatted", key))
            or formatCaptureTime(safeFormattedMetadata(photo, key))
        if value then
            return value, (metadataLookupValue(metadataLookup, "formatted", key) ~= nil and "batch-lightroom-formatted:" or "lightroom-formatted:") .. key
        end
    end

    local dynamicRawValue, dynamicRawSource = dynamicCaptureTimeFromMetadata(
        metadataLookup and metadataLookup.raw,
        "batch-lightroom-raw-dynamic"
    )
    if dynamicRawValue then
        return dynamicRawValue, dynamicRawSource
    end

    local dynamicFormattedValue, dynamicFormattedSource = dynamicCaptureTimeFromMetadata(
        metadataLookup and metadataLookup.formatted,
        "batch-lightroom-formatted-dynamic"
    )
    if dynamicFormattedValue then
        return dynamicFormattedValue, dynamicFormattedSource
    end

    return "", "empty"
end

local function batchMetadataForPhoto(batchMetadata, photo)
    if type(batchMetadata) ~= "table" then
        return nil
    end

    local direct = batchMetadata[photo]
    if type(direct) == "table" then
        return direct
    end

    local uuid = safeRawMetadata(photo, "uuid")
    if uuid == nil then
        return nil
    end

    for _, metadata in pairs(batchMetadata) do
        if type(metadata) == "table" and tostring(metadata.uuid or "") == tostring(uuid) then
            return metadata
        end
    end

    return nil
end

local function mergeMetadataTables(primary, secondary)
    local merged = {}
    if type(secondary) == "table" then
        for key, value in pairs(secondary) do
            merged[key] = value
        end
    end
    if type(primary) == "table" then
        for key, value in pairs(primary) do
            merged[key] = value
        end
    end

    if next(merged) ~= nil then
        return merged
    end

    return nil
end

local function batchGetCatalogMetadata(catalog, photos, accessorName, keys)
    local success, metadata = pcall(function()
        if accessorName == "raw" then
            return catalog:batchGetRawMetadata(photos, keys)
        end
        return catalog:batchGetFormattedMetadata(photos, keys)
    end)

    if success and type(metadata) == "table" then
        log:trace(
            "LRC batch " .. accessorName .. " metadata read for " .. tostring(#photos) ..
            " photos with " .. (keys == nil and "all keys" or "explicit keys")
        )
        return metadata
    end

    log:warn(
        "LRC batch " .. accessorName .. " metadata read failed with " ..
        (keys == nil and "all keys" or "explicit keys") .. ": " .. tostring(metadata)
    )
    return {}
end

local function buildCatalogMetadataLookup(photos)
    local catalog = LrApplication.activeCatalog()
    return {
        rawByPhoto = batchGetCatalogMetadata(catalog, photos, "raw", CATALOG_RAW_EXIF_KEYS),
        formattedByPhoto = batchGetCatalogMetadata(catalog, photos, "formatted", CATALOG_FORMATTED_EXIF_KEYS),
        allRawByPhoto = batchGetCatalogMetadata(catalog, photos, "raw", nil),
        allFormattedByPhoto = batchGetCatalogMetadata(catalog, photos, "formatted", nil),
    }
end

local function catalogPhotoMetadata(photo, batchLookup)
    local explicitRaw = batchMetadataForPhoto(batchLookup and batchLookup.rawByPhoto, photo)
    local explicitFormatted = batchMetadataForPhoto(batchLookup and batchLookup.formattedByPhoto, photo)
    local allRawMetadata = batchMetadataForPhoto(batchLookup and batchLookup.allRawByPhoto, photo)
    local allFormattedMetadata = batchMetadataForPhoto(batchLookup and batchLookup.allFormattedByPhoto, photo)

    local metadataLookup = {
        raw = mergeMetadataTables(explicitRaw, allRawMetadata) or {},
        formatted = mergeMetadataTables(explicitFormatted, allFormattedMetadata) or {},
    }

    local originalFilePath = metadataLookupValue(metadataLookup, "raw", "path") or safeRawMetadata(photo, "path")
    local filename, filenameSource = photoFilename(photo, originalFilePath, metadataLookup)
    local captureTimeValue, captureTimeSource = catalogCaptureTime(photo, metadataLookup)
    local rawExif = readCatalogMetadataValues(photo, "raw", CATALOG_RAW_EXIF_KEYS, metadataLookup)
    local formattedExif = readCatalogMetadataValues(photo, "formatted", CATALOG_FORMATTED_EXIF_KEYS, metadataLookup)
    allRawMetadata = readCatalogMetadataTable(photo, "raw", metadataLookup)
    allFormattedMetadata = readCatalogMetadataTable(photo, "formatted", metadataLookup)

    local exif = {
        source = "lightroom_classic_catalog",
        original_path = originalFilePath,
        filename = filename,
        filename_source = filenameSource,
        capture_time = captureTimeValue,
        capture_time_source = captureTimeSource,
        raw = rawExif or {},
        formatted = formattedExif or {},
        all_raw = allRawMetadata or {},
        all_formatted = allFormattedMetadata or {},
    }

    return {
        original_file_path = originalFilePath,
        exif = exif,
        exif_source = "lightroom_classic_catalog",
        filename = filename or "",
        filename_source = filenameSource or "empty",
        capture_time = captureTimeValue,
        capture_time_source = captureTimeSource,
    }
end

local function aiModelValue(options, photo)
    options = options or {}

    if nonEmpty(options.ai_model) then
        return tostring(options.ai_model)
    end

    if nonEmpty(options.provider) and nonEmpty(options.model) then
        return tostring(options.provider) .. "::" .. tostring(options.model)
    end

    if nonEmpty(options.model) then
        return tostring(options.model)
    end

    if nonEmpty(options.provider) then
        return tostring(options.provider)
    end

    local catalogAiModel = safePluginProperty(photo, "aiModel")
    if nonEmpty(catalogAiModel) then
        return tostring(catalogAiModel)
    end

    if photo == nil and nonEmpty(prefs.modelKey) then
        return tostring(prefs.modelKey)
    end

    if photo == nil and nonEmpty(prefs.ai) then
        return tostring(prefs.ai)
    end

    return ""
end

local function addMimeValue(mimeChunks, name, value)
    if value == nil then
        value = ""
    elseif type(value) == "table" then
        value = JSON:encode(value)
    else
        value = tostring(value)
    end

    table.insert(mimeChunks, { name = name, value = value })
end

local function logMultipartPayload(mimeChunks)
    local payload = {}
    for _, chunk in ipairs(mimeChunks) do
        local item = { name = chunk.name }
        if chunk.filePath then
            item.fileName = chunk.fileName
            item.filePath = chunk.filePath
            item.contentType = chunk.contentType
        else
            if chunk.name == "api_key" then
                item.value = "<redacted>"
            else
                item.value = chunk.value
            end
        end
        table.insert(payload, item)
    end

    log:trace("Multipart payload sent to backend: " .. Util.dumpTable(payload))
end

local ENDPOINTS = {
    INDEX = "/index",
    INDEX_BY_REFERENCE = "/index_by_reference",
    INDEX_BASE64 = "/index_base64",
    SEARCH = "/search",
    STATS = "/stats",
    MODELS = "/models",
    GET_IDS = "/get/ids",
    REMOVE = "/remove",
    PING = "/ping",
    IMPORT_METADATA = "/import/metadata",
}

local EXPORT_SETTINGS = {
        LR_export_destinationType = 'specificFolder',
        LR_export_useSubfolder = false,
        LR_format = 'JPEG',
        LR_jpeg_quality = tonumber(prefs.exportQuality) or 60,
        LR_minimizeEmbeddedMetadata = true,
        LR_outputSharpeningOn = false,
        LR_size_doConstrain = true,
        LR_size_maxHeight = tonumber(prefs.exportSize) or 1024,
        LR_size_resizeType = 'longEdge',
        LR_size_units = 'pixels',
        LR_collisionHandling = 'rename',
        LR_includeVideoFiles = false,
        LR_removeLocationMetadata = true,
        LR_embeddedMetadataOption = "all",
    }


-- Forward declarations for private helper functions
local httpStatus
local _request
local _requestMultipart

---
-- Exports a photo to a temporary location for processing.
-- @param photo The Lightroom photo object to export.
-- @return string|nil The path to the exported JPEG file, or nil on failure.
--
function SearchIndexAPI.exportPhotoForIndexing(photo)

    if photo == nil then
        log:error("exportPhotoForIndexing: photo is nil. Probably it got deleted in the meantime.")
        return nil
    end

    local tempDir = LrPathUtils.getStandardFilePath('temp')
    local photoName = photoFilename(photo)
    local catalog = LrApplication.activeCatalog()

    EXPORT_SETTINGS.LR_export_destinationPathPrefix = tempDir
   
    local exportSession = LrExportSession({
        photosToExport = { photo },
        exportSettings = EXPORT_SETTINGS
    })

    for _, rendition in exportSession:renditions() do
        local success, path = rendition:waitForRender()
        if not nonEmpty(photoName) then
            photoName = leafName(path) or "unknown"
        end
        log:trace("Export completed for photo: " .. photoName .. " Success: " .. tostring(success) .. " Path: " .. tostring(path))
        if success then -- Export successful
            return path
        else
            -- Error during export
            log:error("Failed to export photo for indexing. " .. (path or 'unknown error'))
            return nil
        end
    end
end

function SearchIndexAPI.exportPhotosForIndexing(photos)
    if not photos or #photos == 0 then return {} end

    local tempDir = LrPathUtils.getStandardFilePath('temp')

    EXPORT_SETTINGS.LR_export_destinationPathPrefix = tempDir

    local exportSession = LrExportSession({
        photosToExport = photos,
        exportSettings = EXPORT_SETTINGS
    })

    local photoPaths = {}
    local photoIndex = 1
    for _, rendition in exportSession:renditions() do
        local success, path = rendition:waitForRender()
        local photo = photos[photoIndex]
        if photo ~= nil then
            local photoName = photoFilename(photo, path)
            log:trace("Export completed for photo: " .. photoName .. " Success: " .. tostring(success) .. " Path: " .. tostring(path))
            if success then
                photoPaths[photo] = path
            else
                log:error("Failed to export photo for indexing. " .. (path or 'unknown error'))
                photoPaths[photo] = nil
            end
        else
            log:error("Photo is nil in exportPhotosForIndexing, probably it got deleted in the meantime.")
        end
        photoIndex = photoIndex + 1
    end
    return photoPaths
end


---
-- Unified function to analyze and index photos with metadata, quality scores, and embeddings.
-- Replaces the old separate analyze and index workflows.
-- @param uuid string The UUID of the photo.
-- @param filename string The filename of the photo.
-- @param jpeg string The JPEG data of the photo.
-- @param options table Optional parameters for the analysis:
--   - tasks table: Array of tasks to perform (default: {"embeddings", "metadata", "quality"})
--   - provider string: AI provider to use (default: "qwen")
--   - language string: Language for generated content (default: "English")
--   - generate_keywords boolean: Generate keywords (default: true)
--   - generate_caption boolean: Generate caption (default: true)
--   - generate_title boolean: Generate title (default: true)
--   - generate_alt_text boolean: Generate alt text (default: false)
--   - submit_gps boolean: Submit GPS coordinates (default: false)
--   - gps_coordinates table: GPS coordinates {latitude, longitude}
--   - submit_keywords boolean: Submit existing keywords (default: false)
--   - existing_keywords table: Array of existing keywords
--   - submit_folder_names boolean: Submit folder names (default: false)
--   - folder_names string: Folder path
--   - user_context string: Additional context for the photo
--   - filename string: Original photo filename
--   - capture_time string: Capture time sent to the index
--   - ai_model string: AI model label sent to the index
--   - exif table: Optional EXIF data sent to the index
-- @return boolean success, table|string response - Returns success status and response data or error message
---


function SearchIndexAPI.analyzeAndIndexPhoto(uuid, filepath, options)
    if filepath == nil then 
        log:error("JPEG is nil")
        return false, "No image data provided"
    end

    options = options or {}
    local filename = textValue(options.filename)
    if not filename then
        log:error("filename is empty before upload; expected Lightroom catalog filename")
        return false, "filename is required"
    end

    local captureTimeValue = formatCaptureTime(options.capture_time) or ""
    if not nonEmpty(captureTimeValue) then
        log:error("capture_time is empty before upload; expected Lightroom catalog capture time")
        return false, "capture_time is required"
    end
    
    local url, urlErr = endpointUrl(ENDPOINTS.INDEX)
    if not url then
        log:error(urlErr)
        return false, urlErr
    end

    local tasks = options.tasks or {"embeddings", "metadata", "quality"}
    local mimeChunks = {
        { name = "tasks", value = JSON:encode(tasks) },
        { name = "language", value = options.language or prefs.generateLanguage or "English" },
        { name = "replace_ss", value = tostring(options.replace_ss or false) },
        { name = "regenerate_metadata", value = tostring(options.regenerate_metadata ~= false) },
        { name = "keyword_categories", value = JSON:encode(options.keyword_categories or {}) },
    }

    addMimeValue(mimeChunks, "uuid", uuid)
    addMimeValue(mimeChunks, "filename", filename)
    addMimeValue(mimeChunks, "capture_time", captureTimeValue)
    addMimeValue(mimeChunks, "ai_model", aiModelValue(options))

    if options.provider then
        table.insert(mimeChunks, { name = "provider", value = options.provider })
    end

    if options.model then
        table.insert(mimeChunks, { name = "model", value = options.model })
    end

    if options.api_key then
        table.insert(mimeChunks, { name = "api_key", value = options.api_key })
    end

    if options.generate_keywords ~= nil then
        table.insert(mimeChunks, { name = "generate_keywords", value = tostring(options.generate_keywords) })
    end

    if options.generate_caption ~= nil then
        table.insert(mimeChunks, { name = "generate_caption", value = tostring(options.generate_caption) })
    end

    if options.generate_title ~= nil then
        table.insert(mimeChunks, { name = "generate_title", value = tostring(options.generate_title) })
    end

    if options.generate_alt_text ~= nil then
        table.insert(mimeChunks, { name = "generate_alt_text", value = tostring(options.generate_alt_text) })
    end

    if options.submit_gps ~= nil then
        table.insert(mimeChunks, { name = "submit_gps", value = tostring(options.submit_gps) })
    end

    if options.submit_keywords ~= nil then
        table.insert(mimeChunks, { name = "submit_keywords", value = tostring(options.submit_keywords) })
    end

    if options.submit_folder_names ~= nil then
        table.insert(mimeChunks, { name = "submit_folder_names", value = tostring(options.submit_folder_names) })
    end

    if options.user_context then
        table.insert(mimeChunks, { name = "user_context", value = options.user_context })
    end

    if options.gps_coordinates then
        table.insert(mimeChunks, { name = "gps_coordinates", value = JSON:encode(options.gps_coordinates) })
    end

    if options.existing_keywords then
        table.insert(mimeChunks, { name = "existing_keywords", value = JSON:encode(options.existing_keywords) })
    end

    if options.folder_names then
        table.insert(mimeChunks, { name = "folder_names", value = options.folder_names })
    end

    if options.prompt then
        table.insert(mimeChunks, { name = "prompt", value = options.prompt })
    end

    if options.exif then
        addMimeValue(mimeChunks, "exif", options.exif)
    end

    table.insert(mimeChunks, {
        name = "image",
        fileName = filename,
        filePath = filepath,
        contentType = "image/jpeg",
    })
    
    log:trace("Analyzing and indexing photo: " .. filename .. " with tasks: " .. table.concat(tasks, ", "))
    logMultipartPayload(mimeChunks)

    local response, err = _requestMultipart(url, mimeChunks, 720)

    if not response then
        log:error("Failed to analyze/index photo: " .. tostring(err))
        return false, err or "Unknown error"
    end

    -- Check response status
    if response.status == "processed" then
        local success_count = response.success_count or 0
        local failure_count = response.failure_count or 0
        
        if success_count > 0 then
            log:trace("Successfully processed photo: " .. filename)
            return true, response
        else
            log:error("Photo processing failed: " .. filename)
            return false, response.error or "Processing failed"
        end
    else
        log:error("Unexpected response status: " .. tostring(response.status))
        return false, "Unexpected response status"
    end
end




---
-- Builds a URL with optional query parameters.
--
local function buildUrlWithParams(baseUrl, params)
    local queryParts = {}
    for key, value in pairs(params) do
        if value ~= nil then
            table.insert(queryParts, key .. "=" .. tostring(value))
        end
    end
    
    if #queryParts > 0 then
        return baseUrl .. "?" .. table.concat(queryParts, "&")
    else
        return baseUrl
    end
end

function SearchIndexAPI.searchIndex(searchTerm, qualitySort, photosToSearch, minPertinenceScore)
    local params = {
        term = searchTerm,
        quality_sort = qualitySort,
        min_pertinence_score = minPertinenceScore,
    }

    local url, urlErr = endpointUrl(ENDPOINTS.SEARCH)
    if not url then
        log:error(urlErr)
        return nil, urlErr
    end

    if photosToSearch and #photosToSearch > 0 then
        -- Perform a scoped search via POST
        local uuids = {}
        for _, photo in ipairs(photosToSearch) do
            table.insert(uuids, photo:getRawMetadata("uuid"))
        end

        local body = {
            term = searchTerm,
            uuids = uuids,
            min_pertinence_score = minPertinenceScore,
        }
        local postUrl = buildUrlWithParams(url, params)

        log:trace("Searching index via POST (scoped): " .. postUrl)
        return _request('POST', postUrl, body)
    else
        -- Perform a global search via GET
        local getUrl = buildUrlWithParams(url, params)
        log:trace("Searching index via GET (global): " .. getUrl)
        return _request('GET', getUrl)
    end
end

function SearchIndexAPI.getStats()
    local url, urlErr = endpointUrl(ENDPOINTS.STATS)
    if not url then
        log:error(urlErr)
        return nil, urlErr
    end
    return _request('GET', url)
end

function SearchIndexAPI.getAllIndexedPhotoUUIDs(requireEmbeddings)
    local url, urlErr = endpointUrl(ENDPOINTS.GET_IDS)
    if not url then
        log:error(urlErr)
        return nil, urlErr
    end
    -- If requireEmbeddings is true, only get UUIDs with real embeddings
    if requireEmbeddings then
        url = url .. "?has_embedding=true"
    end
    return _request('GET', url)
end

local function normalizePhotoDataResponse(result, requestedUuid)
    if type(result) ~= "table" then
        return nil
    end

    if result.metadata ~= nil or result.quality ~= nil then
        return result
    end

    if type(result.photos) ~= "table" then
        return result
    end

    local selectedPhoto = nil
    for _, photoData in ipairs(result.photos) do
        if type(photoData) == "table" and tostring(photoData.uuid or "") == tostring(requestedUuid or "") then
            selectedPhoto = photoData
            break
        end
    end

    if selectedPhoto == nil and #result.photos == 1 then
        selectedPhoto = result.photos[1]
    end

    if type(selectedPhoto) ~= "table" then
        return nil
    end

    local normalized = Util.deepcopy(selectedPhoto)
    normalized.status = result.status
    normalized.count = result.count
    return normalized
end

---
-- Retrieves metadata and quality scores for a photo by UUID.
-- @param uuid The UUID of the photo to retrieve.
-- @return table|nil Response containing metadata and quality fields, or nil on error.
-- Response structure:
--   {
--     status = "success",
--     uuid = "...",
--     metadata = { title = "...", caption = "...", keywords = {...}, alt_text = "..." },
--     quality = { overall_score = 0.8, composition_score = 0.9, ... }
--   }
-- Also accepts the backend collection envelope:
--   { status = "success", count = 1, photos = { { uuid = "...", metadata = {...}, quality = {...} } } }
--
function SearchIndexAPI.getPhotoData(uuid)
    if not uuid then
        log:error("getPhotoData: UUID is required")
        return nil
    end
    
    local url, urlErr = endpointUrl("/get")
    if not url then
        log:error(urlErr)
        return nil
    end
    local body = { uuid = uuid }
    
    log:trace("Retrieving photo data for UUID: " .. uuid)
    
    local result, err = _request('POST', url, body)
    if err then
        log:error("Failed to retrieve photo data: " .. err)
        return nil
    end
    
    if result and result.status == "success" then
        local normalized = normalizePhotoDataResponse(result, uuid)
        if normalized ~= nil then
            log:trace("Successfully retrieved photo data for UUID: " .. uuid)
            return normalized
        end
    end

    log:warn("Photo data not found for UUID: " .. uuid)
    return nil
end

function SearchIndexAPI.removeUUID(uuid)
    local url, urlErr = endpointUrl(ENDPOINTS.REMOVE)
    if not url then
        ErrorHandler.handleError("Remove UUID failed", urlErr)
        return false
    end
    local body = { uuid = uuid }
    log:trace("Removing UUID: " .. uuid)

    local result, err = _request('POST', url, body)
    if not err then
        return true
    else
        ErrorHandler.handleError("Remove UUID failed", err)
        return false
    end
end

function SearchIndexAPI.removeMissingFromIndex()
    local indexedUUIDs = SearchIndexAPI.getAllIndexedPhotoUUIDs()

    if indexedUUIDs == nil then
        log:warn("Failed to retrieve indexed UUIDs")
        return false
    end

    local catalog = LrApplication.activeCatalog()

    local progressScope = LrProgressScope({
        title = LOC "$$$/LrGeniusAI/SearchIndexAPI/cleaningIndex=Cleaning search index",
        functionContext = nil,
    })

    local total = #indexedUUIDs
    local missingPhotosUUIDs = {}
    for _, uuid in ipairs(indexedUUIDs) do
        progressScope:setPortionComplete(_ - 1, total)
        progressScope:setCaption(LOC "$$$/LrGeniusAI/SearchIndexAPI/cleaningIndexProgress=Cleaning index. Photo ^1/^2", tostring(_), tostring(total))
        if progressScope:isCanceled() then break end

        local photo = catalog:findPhotoByUuid(uuid)
        if photo == nil then
            missingPhotosUUIDs[#missingPhotosUUIDs + 1] = uuid
            log:trace("Photo with UUID " .. uuid .. " not found in catalog, removing from index")
            SearchIndexAPI.removeUUID(uuid)
        end
    end
    progressScope:done()
end

---
-- Analyzes and indexes selected photos with LLM processing (metadata, quality, embeddings).
-- Uses JPEG export instead of thumbnails for better reliability.
-- @param selectedPhotos table Array of LrPhoto objects to process.
-- @param progressScope LrProgressScope Progress scope for UI updates.
-- @param options table Processing options (tasks, provider, language, etc.).
-- @return string status Status: "success", "canceled", "somefailed", or "allfailed".
-- @return number processed Number of photos processed.
-- @return number failed Number of photos that failed.
-- @return table responses Array of response data from the server for each photo.
--
function SearchIndexAPI.analyzeAndIndexSelectedPhotos(selectedPhotos, progressScope, options)
    local numPhotos = #selectedPhotos
    if numPhotos == 0 then
        return "success", 0, 0, {}
    end

    if not SearchIndexAPI.pingServer() then
        return "allfailed", numPhotos, numPhotos, {}
    end

    options = options or {}
    
    progressScope:setCaption(LOC "$$$/LrGeniusAI/AnalyzeAndIndex/ProgressTitle=Processing photos...")
    progressScope:setPortionComplete(0, numPhotos)

    local photoToProcessStack = {}
    for _, photo in ipairs(selectedPhotos) do
        table.insert(photoToProcessStack, photo)
    end
    local catalogMetadataLookup = buildCatalogMetadataLookup(selectedPhotos)

    local maxWorkers = 1 -- tonumber(prefs.indexingParallelTasks) or 2
    local stats = { processed = 0, success = 0, failed = 0 }
    local processedPhotos = {}
    local responses = {}
    local activeWorkers = 0
    local keepRunning = true
    local catalog = LrApplication.activeCatalog()
    
    local analyzeWorker = function()
        while #photoToProcessStack > 0 do
            if progressScope:isCanceled() then break end
            if not keepRunning then break end
            
            local photo = table.remove(photoToProcessStack, 1)
            if photo ~= nil then
                
                local uuid = photo:getRawMetadata("uuid")
                local catalogMetadata = catalogPhotoMetadata(photo, catalogMetadataLookup)
                local filename = catalogMetadata.filename
                log:trace("LRC catalog metadata extracted before JPEG export: " .. Util.dumpTable(catalogMetadata))

                if not nonEmpty(filename) or not nonEmpty(catalogMetadata.capture_time) then
                    stats.failed = stats.failed + 1
                    log:error(
                        "Missing mandatory LRC catalog metadata before JPEG export for UUID " .. tostring(uuid) ..
                        ": filename=" .. tostring(filename) ..
                        ", capture_time=" .. tostring(catalogMetadata.capture_time)
                    )
                else
                    -- Export photo as JPEG only after mandatory LRC metadata has been extracted.
                    local exportedPhotoPath = SearchIndexAPI.exportPhotoForIndexing(photo)

                    if exportedPhotoPath ~= nil then
                        -- Prepare analysis options with photo-specific context
                        local photoOptions = {}
                        for k, v in pairs(options) do
                            photoOptions[k] = v
                        end

                        photoOptions.filename = filename
                        photoOptions.capture_time = catalogMetadata.capture_time
                        photoOptions.ai_model = aiModelValue(photoOptions, photo)

                        if catalogMetadata.exif then
                            photoOptions.exif = catalogMetadata.exif
                        end

                        log:trace(
                            "Resolved fields for photo " .. tostring(filename) ..
                            ": original_file_path=" .. tostring(catalogMetadata.original_file_path) ..
                            ", exif_source=" .. tostring(catalogMetadata.exif_source) ..
                            ", filename_source=" .. tostring(catalogMetadata.filename_source) ..
                            ", capture_time_source=" .. tostring(catalogMetadata.capture_time_source) ..
                            ", capture_time=" .. tostring(catalogMetadata.capture_time)
                        )
                        log:trace("Options for photo " .. filename .. ": " .. Util.dumpTable(photoOptions))

                        -- Add GPS if enabled
                        if options.submit_gps then
                            local gps = photo:getRawMetadata('gps')
                            if gps then
                                photoOptions.gps_coordinates = gps
                            end
                        end

                        -- Add existing keywords if enabled
                        if options.submit_keywords then
                            local keywords = photo:getFormattedMetadata("keywordTagsForExport")
                            if keywords then
                                photoOptions.existing_keywords = keywords
                            end
                        end

                        -- Add folder names if enabled
                        if options.submit_folder_names then
                            local originalFilePath = photo:getRawMetadata("path")
                            if originalFilePath then
                                photoOptions.folder_names = Util.getStringsFromRelativePath(originalFilePath)
                            end
                        end

                        photoOptions.user_context = catalog:getPropertyForPlugin(_PLUGIN, 'photoContext') or ""

                        -- Call unified API to index/analyze
                        local success, indexResponse = SearchIndexAPI.analyzeAndIndexPhoto(uuid, exportedPhotoPath, photoOptions)
                        if success then
                            stats.success = stats.success + 1
                        else
                            stats.failed = stats.failed + 1
                            log:error("Failed to analyze/index photo: " .. filename .. " Error: " .. (indexResponse or "Unknown"))
                        end
                        -- Cleanup temp filename
                        LrFileUtils.delete(exportedPhotoPath)
                    else
                        stats.failed = stats.failed + 1
                        log:error("Failed to read exported photo: " .. filename)
                    end
                end
                

                
                stats.processed = stats.processed + 1
                table.insert(processedPhotos, photo)
                progressScope:setPortionComplete(stats.processed, numPhotos)
                progressScope:setCaption(
                    LOC("$$$/LrGeniusAI/AnalyzeAndIndex/ProcessingPhoto=Processing ^1 successful (^2 total/^3 failed)",
                        stats.success, numPhotos, stats.failed)
                )
            else
                log:error("Photo is nil in analyze worker, probably it got deleted in the meantime.")
            end
        end
        log:trace("Analyze worker thread finished.")
        activeWorkers = activeWorkers - 1
    end

    -- Start worker threads
    for i = 1, maxWorkers do
        LrTasks.startAsyncTask(analyzeWorker)
        log:trace("Started analyze worker #" .. tostring(i))
        activeWorkers = activeWorkers + 1
    end

    -- Monitor workers and server availability
    local notReached = 0
    while activeWorkers > 0 do
        if progressScope:isCanceled() then break end
        if MAC_ENV then
            LrTasks.yield()
        else
            LrTasks.sleep(0.1)
        end
    end

    -- Wait for workers to stop in case of server failure
    if not keepRunning then
        while activeWorkers > 0 do
            if MAC_ENV then
                LrTasks.yield()
            else
                LrTasks.sleep(0.5)
            end
        end
    end

    progressScope:done()

    if progressScope:isCanceled() then
        return "canceled", stats.processed, stats.failed, processedPhotos
    end

    local status
    if stats.failed == 0 then
        status = "success"
    elseif stats.failed >= stats.processed and stats.processed > 0 then
        status = "allfailed"
    else
        status = "somefailed"
    end
    
    return status, stats.processed, stats.failed, processedPhotos
end



function SearchIndexAPI.importMetadataFromCatalog(photosToProcess, progressScope)
    local numPhotos = #photosToProcess
    if numPhotos == 0 then
        return "success", 0, 0
    end

    if not SearchIndexAPI.pingServer() then
        return "allfailed", numPhotos, numPhotos
    end

    local importUrl, urlErr = endpointUrl(ENDPOINTS.IMPORT_METADATA)
    if not importUrl then
        log:error("importMetadataFromCatalog failed: " .. urlErr)
        return "allfailed", numPhotos, numPhotos
    end

    progressScope:setCaption(LOC "$$$/LrGeniusAI/ImportMetadata/ProgressTitle=Importing metadata for photos...")
    progressScope:setPortionComplete(0, numPhotos)

    local stats = { processed = 0, success = 0, failed = 0 }
    local batchSize = 50 -- Send metadata in batches
    local metadataBatch = {}
    local catalogMetadataLookup = buildCatalogMetadataLookup(photosToProcess)

    for i, photo in ipairs(photosToProcess) do
        if photo ~= nil then 
            if progressScope:isCanceled() then
                break
            end

            local catalogMetadata = catalogPhotoMetadata(photo, catalogMetadataLookup)
            local metadata = {
                uuid = safeRawMetadata(photo, "uuid") or "",
                filename = catalogMetadata.filename,
                capture_time = catalogMetadata.capture_time,
                ai_model = aiModelValue(nil, photo),
                caption = photo:getFormattedMetadata("caption"),
                title = photo:getFormattedMetadata("title"),
                keywords = MetadataManager.removeTopLevelKeyword(
                    MetadataManager.getPhotoKeywordHierarchy(photo),
                    prefs.topLevelKeyword
                ),
                alt_text = photo:getFormattedMetadata("altTextAccessibility"),
                ai_rundate = safePluginProperty(photo, "aiLastRun") or ""
            }

            if catalogMetadata.exif then
                metadata.exif = catalogMetadata.exif
            end

            log:trace(
                "Import metadata resolved fields for photo " .. tostring(metadata.filename) ..
                ": original_file_path=" .. tostring(catalogMetadata.original_file_path) ..
                ", exif_source=" .. tostring(catalogMetadata.exif_source) ..
                ", filename_source=" .. tostring(catalogMetadata.filename_source) ..
                ", capture_time_source=" .. tostring(catalogMetadata.capture_time_source) ..
                ", capture_time=" .. tostring(catalogMetadata.capture_time)
            )

            table.insert(metadataBatch, metadata)

            if #metadataBatch >= batchSize or i == numPhotos then
                log:trace("Metadata import payload sent to backend: " .. Util.dumpTable({ metadata_items = metadataBatch }))
                local response = _request('POST', importUrl, { metadata_items = metadataBatch })
                if response ~= nil and response.status == "processed" then
                    stats.success = stats.success + #metadataBatch
                else
                    stats.failed = stats.failed + #metadataBatch
                    log:error("Failed to import metadata batch: " .. (response and response.error or "Unknown error"))
                end
                metadataBatch = {} -- Clear the batch
            end

            stats.processed = stats.processed + 1
            progressScope:setPortionComplete(stats.processed, numPhotos)
            progressScope:setCaption(
                LOC("$$$/LrGeniusAI/ImportMetadata/Processing=Importing metadata... ^1/^2 (^3 failed)",
                    stats.processed, numPhotos, stats.failed)
            )
        else
            log:error("Photo is nil in importMetadataFromCatalog, probably it got deleted in the meantime.")
        end
    end

    progressScope:done()

    if progressScope:isCanceled() then
        return "canceled", stats.processed, stats.failed
    end

    local status
    if stats.failed == 0 then
        status = "success"
    elseif stats.failed >= stats.processed and stats.processed > 0 then
        status = "allfailed"
    else
        status = "somefailed"
    end

    return status, stats.processed, stats.failed
end



function SearchIndexAPI.pingServer()
    local url = endpointUrl(ENDPOINTS.PING)
    if not url then
        return false
    end
    local result, hdrs = LrHttp.get(url, serverRequestHeaders())
    if httpStatus(hdrs) == 200 and result == "pong" then
        return true
    else
        return false
    end
end

httpStatus = function(hdrs)
    if type(hdrs) == "number" then
        return hdrs
    end
    if type(hdrs) == "table" then
        return hdrs.status
    end
    return nil
end

_requestMultipart = function(url, mimeChunks, timeout)
    local result, hdrs = LrHttp.postMultipart(url, mimeChunks, serverRequestHeaders(), timeout)
    local status = httpStatus(hdrs)

    if status ~= nil and status >= 200 and status < 300 then
        if result and #result > 0 then
            return JSON:decode(result)
        end
        return {} -- Return an empty table for successful but empty responses
    else
        local err_msg = "API request failed. HTTP status: " .. tostring(status or hdrs or 'unknown')
        if result and #result > 0 then
            local decoded_err = JSON:decode(result)
            if decoded_err and decoded_err.error then
                err_msg = err_msg .. " - " .. decoded_err.error
            else
                err_msg = err_msg .. " Response: " .. result
            end
        end
        log:error(err_msg)
        return nil, err_msg
    end
end

_request = function(method, url, body, timeout)
    local result, hdrs
    local bodyString = (body and type(body) == 'table') and JSON:encode(body) or nil
    local headers = serverRequestHeaders({
        { field = "Content-Type", value = "application/json" },
    })

    if method == 'GET' then
        result, hdrs = LrHttp.get(url, serverRequestHeaders(), timeout)
    elseif method == 'POST' then
        result, hdrs = LrHttp.post(url, bodyString or "", headers, 'POST', timeout)
    elseif method == 'PUT' then
        result, hdrs = LrHttp.post(url, bodyString or "", headers, 'PUT', timeout)
    elseif method == 'DELETE' then
        result, hdrs = LrHttp.post(url, bodyString or "", headers, 'DELETE', timeout)
    else
        local err = "Unsupported HTTP method: " .. method
        log:error(err)
        return nil, err
    end

    local status = httpStatus(hdrs)

    if status ~= nil and status >= 200 and status < 300 then
        if result and #result > 0 then
            return JSON:decode(result)
        end
        return {} -- Return an empty table for successful but empty responses
    else
        local err_msg = "API request failed. HTTP status: " .. tostring(status or hdrs or 'unknown')
        if result and #result > 0 then
            local decoded_err = JSON:decode(result)
            if decoded_err and decoded_err.error then
                err_msg = err_msg .. " - " .. decoded_err.error
            else
                err_msg = err_msg .. " Response: " .. result
            end
        end
        log:error(err_msg)
        return nil, err_msg
    end
end


function SearchIndexAPI.getMissingPhotosFromIndex(requireEmbeddings)
    -- If requireEmbeddings is true, we only get photos that have real embeddings
    -- (excluding metadata-only entries with dummy embeddings)
    local indexedUUIDs, err = SearchIndexAPI.getAllIndexedPhotoUUIDs(requireEmbeddings)
    if err then
        ErrorHandler.handleError("Failed to retrieve indexed photos", err)
        return false, {}
    end

    local allPhotos = PhotoSelector.getPhotosInScope('all')

    if allPhotos == nil then
        ErrorHandler.handleError("No photos found in catalog", "Something went wrong")
        return false, {}
    end

    local photosToProcess = {}
    
    for i, photo in ipairs(allPhotos) do
        local uuid = photo:getRawMetadata("uuid")
        if not Util.table_contains(indexedUUIDs, uuid) then
            table.insert(photosToProcess, photo)
        end
    end

    return true, photosToProcess
end


function SearchIndexAPI.saveThumbnail(uuid, faceIndex, base64Data)
    local tempDir = LrPathUtils.getStandardFilePath('temp')
    local tempFile = LrPathUtils.child(tempDir, uuid .. "_" .. faceIndex ..  ".jpg")
    local f = io.open(tempFile, "wb")
    if f then
        f:write(LrStringUtils.decodeBase64(base64Data))
        f:close()
        log:trace("Saved face thumbnail to: " .. tempFile)
        return tempFile
    end
    return nil
end
---
-- Retrieves all available multimodal models from all providers.
-- Always filters to vision-capable models only.
-- Dynamically checks Ollama and LM Studio availability on each call.
-- @param openaiApiKey string|nil OpenAI API key for listing ChatGPT models
-- @param geminiApiKey string|nil Gemini API key for listing Gemini models
-- @param mistralApiKey string|nil Mistral API key for listing Mistral models
-- @param anthropicApiKey string|nil Anthropic API key for listing Anthropic models
-- @return table|nil Response from server with format: { models = { qwen = {...}, ollama = {...}, ... } }
function SearchIndexAPI.getModels(openaiApiKey, geminiApiKey, mistralApiKey, anthropicApiKey)
    local url, urlErr = endpointUrl(ENDPOINTS.MODELS)
    if not url then
        log:error("getModels failed: " .. urlErr)
        return nil
    end
    local body = { 
        openai_apikey = openaiApiKey, 
        gemini_apikey = geminiApiKey,
        mistral_apikey = mistralApiKey,
        anthropic_apikey = anthropicApiKey
    }
    local result, err = _request('POST', url, body)
    if err then
        log:error("getModels failed: " .. err)
        return nil
    end
    return result
end
