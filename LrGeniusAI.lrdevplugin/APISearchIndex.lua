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

local function safePhotoCall(photo, callback)
    if photo == nil then return nil end

    local success, value = pcall(callback)
    if success then
        return value
    end

    return nil
end

local function safeRawMetadata(photo, key)
    return safePhotoCall(photo, function()
        return photo:getRawMetadata(key)
    end)
end

local function safeFormattedMetadata(photo, key)
    return safePhotoCall(photo, function()
        return photo:getFormattedMetadata(key)
    end)
end

local function safePluginProperty(photo, key)
    return safePhotoCall(photo, function()
        return photo:getPropertyForPlugin(_PLUGIN, key)
    end)
end

local function nonEmpty(value)
    return value ~= nil and tostring(value) ~= ""
end

local function formatPhotoDate(value)
    if value == nil then return nil end
    if type(value) == "number" then
        return LrDate.timeToW3CDate(value)
    end
    return tostring(value)
end

local function photoFilename(photo, fallbackPath)
    local filename = safeFormattedMetadata(photo, "fileName")
    if nonEmpty(filename) then
        return tostring(filename)
    end

    local path = safeRawMetadata(photo, "path")
    if not nonEmpty(path) then
        path = fallbackPath
    end
    if nonEmpty(path) then
        return LrPathUtils.leafName(tostring(path))
    end

    return ""
end

local function photoDate(photo)
    return formatPhotoDate(safeRawMetadata(photo, "dateTime")) or safeFormattedMetadata(photo, "dateTime") or ""
end

local function photoExif(photo)
    local exif = {}
    local fields = {
        { "camera_make", "cameraMake" },
        { "camera_model", "cameraModel" },
        { "lens", "lens" },
        { "iso_speed_rating", "isoSpeedRating" },
        { "aperture", "aperture" },
        { "shutter_speed", "shutterSpeed" },
        { "focal_length", "focalLength" },
        { "exposure_bias", "exposureBias" },
        { "flash", "flash" },
        { "metering_mode", "meteringMode" },
        { "file_format", "fileFormat" },
    }

    for _, field in ipairs(fields) do
        local value = safeFormattedMetadata(photo, field[2]) or safeRawMetadata(photo, field[2])
        if nonEmpty(value) then
            exif[field[1]] = value
        end
    end

    if next(exif) ~= nil then
        return exif
    end

    return nil
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
    local photoName = LrPathUtils.leafName(photo:getFormattedMetadata('fileName'))
    local catalog = LrApplication.activeCatalog()

    EXPORT_SETTINGS.LR_export_destinationPathPrefix = tempDir
   
    local exportSession = LrExportSession({
        photosToExport = { photo },
        exportSettings = EXPORT_SETTINGS
    })

    for _, rendition in exportSession:renditions() do
        local success, path = rendition:waitForRender()
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
            local photoName = LrPathUtils.leafName(photo:getFormattedMetadata('fileName'))
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
--   - photos_date string: Capture date sent to the index
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
    local filename = nonEmpty(options.filename) and options.filename or LrPathUtils.leafName(filepath)
    local photosDate = nonEmpty(options.photos_date) and options.photos_date or (options.date_time or "")
    
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
    addMimeValue(mimeChunks, "photos_date", photosDate)
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

    if options.date_time then
        table.insert(mimeChunks, { name = "date_time", value = options.date_time })
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
        log:trace("Successfully retrieved photo data for UUID: " .. uuid)
        return result
    else
        log:warn("Photo data not found for UUID: " .. uuid)
        return nil
    end
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
                local filename = photoFilename(photo)
                
                -- Export photo as JPEG
                local exportedPhotoPath = SearchIndexAPI.exportPhotoForIndexing(photo)
                
                if exportedPhotoPath ~= nil then

                    -- Prepare analysis options with photo-specific context
                    local photoOptions = {}
                    for k, v in pairs(options) do
                        photoOptions[k] = v
                    end

                    photoOptions.filename = filename
                    photoOptions.photos_date = photoDate(photo)
                    photoOptions.ai_model = aiModelValue(photoOptions, photo)

                    local exif = photoExif(photo)
                    if exif then
                        photoOptions.exif = exif
                    end

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


                    if options.submit_date_time then
                        local datetime = photo:getRawMetadata("dateTime")
                        if datetime ~= nil and type(datetime) == "number" then
                            photoOptions.date_time = LrDate.timeToW3CDate(datetime)
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

    for i, photo in ipairs(photosToProcess) do
        if photo ~= nil then 
            if progressScope:isCanceled() then
                break
            end

            local metadata = {
                uuid = safeRawMetadata(photo, "uuid") or "",
                filename = photoFilename(photo),
                photos_date = photoDate(photo),
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

            local exif = photoExif(photo)
            if exif then
                metadata.exif = exif
            end

            table.insert(metadataBatch, metadata)

            if #metadataBatch >= batchSize or i == numPhotos then
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
