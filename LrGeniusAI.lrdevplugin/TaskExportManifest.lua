-- TaskExportManifest.lua
-- Exports a "Style Match" manifest as JSON: one row per photo with catalog
-- identifiers, file metadata, a develop-rendered preview JPEG and the full
-- develop-settings snapshot. The manifest is consumed by the external
-- bootstrap script that seeds /style-match/index on the server.

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
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        local number = tonumber(value)
        if number ~= nil then
            return number
        end
    end
    return nil
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
    local value = photo:getRawMetadata("dateTimeOriginalISO8601")
    if type(value) == "number" and value > 0 then
        local ok, formatted = pcall(function() return LrDate.timeToW3CDate(value) end)
        if ok and formatted ~= nil then
            return formatted
        end
    end
    return trimmed(photo:getFormattedMetadata("dateTimeOriginal"))
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

local function buildManifestRow(photo, catalogId, previewPath)
    local filePath = photo:getRawMetadata("path")
    local fileName = trimmed(photo:getFormattedMetadata("fileName")) or fileLeafName(filePath)
    local latitude, longitude = gpsOf(photo)

    local developSettings = {}
    local ok, settings = pcall(function() return photo:getDevelopSettings() end)
    if ok and type(settings) == "table" then
        developSettings = settings
    else
        log:warn("Style Match manifest: getDevelopSettings failed for " .. tostring(fileName) .. ": " .. tostring(settings))
    end

    local hasEdits, localCount = StyleWhitelist.hasEdits(developSettings)

    return {
        catalog_id = catalogId,
        lrc_local_id = tostring(photo.localIdentifier or ""),
        uuid = tostring(photo:getRawMetadata("uuid") or ""),
        file_path = filePath,
        file_name = fileName,
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
        local_adjustments = localCount,
        description = descriptionOf(photo),
    }
end

--- Exports preview renders in batches (one export session per batch, not per photo).
local function exportPreviews(photos, progressScope, baseProgress, progressSpan)
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
            LOC("$$$/LrGeniusAI/ExportStyleMatchManifest/PreviewProgress=Rendering previews ^1-^2 of ^3...",
                startIndex, math.min(startIndex + PREVIEW_BATCH_SIZE - 1, #photos), #photos)
        )

        -- LrTasks.pcall: the exporter yields; a plain pcall would fail with
        -- "attempt to yield across metamethod/C-call boundary".
        local ok, batchPaths = LrTasks.pcall(function()
            return SearchIndexAPI.exportPhotosForIndexing(batch)
        end)

        if ok and type(batchPaths) == "table" then
            for photo, path in pairs(batchPaths) do
                previewPaths[photo] = path
            end
        else
            log:warn("Style Match manifest: preview export batch failed: " .. tostring(batchPaths))
        end

        local completed = math.min(startIndex + PREVIEW_BATCH_SIZE - 1, #photos)
        progressScope:setPortionComplete(baseProgress + (progressSpan * completed / #photos), 1)
        LrTasks.yield()
    end

    return previewPaths
end

local function pluginVersion()
    local version = _PLUGIN.version
    if type(version) == "table" then
        return string.format("%s.%s.%s", tostring(version.major), tostring(version.minor), tostring(version.revision))
    end
    return tostring(Info.MAJOR) .. "." .. tostring(Info.MINOR) .. "." .. tostring(Info.REVISION)
end

local function chooseManifestPath()
    local defaultFolder = StyleWhitelist.dataDirectory()
    local fileName = string.format("style-match-manifest-%s.json", LrDate.timeToIsoDate(LrDate.currentTime()))

    local ok, chosen = pcall(function()
        return LrDialogs.runOpenPanel({
            title = LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/ChooseFolderTitle=Choose manifest folder",
            prompt = LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/ChooseFolderPrompt=Save Style Match manifest",
            canChooseFiles = false,
            canChooseDirectories = true,
            allowsMultipleSelection = false,
            initialDirectory = defaultFolder,
        })
    end)

    local folder = defaultFolder
    if ok and type(chosen) == "table" and chosen[1] ~= nil then
        folder = chosen[1]
    end

    return LrPathUtils.child(folder, fileName)
end

local function showManifestDialog(ctx)
    local f = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share

    local props = LrBinding.makePropertyTable(ctx)
    props.scope = prefs.styleMatchManifestScope or "view"
    props.includePreviews = prefs.styleMatchManifestPreviews ~= false
    props.includeLocalAdjustments = prefs.styleMatchManifestLocalAdjustments == true

    local contents = f:column {
        bind_to_object = props,
        spacing = f:control_spacing(),
        f:group_box {
            title = LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/ScopeTitle=Photos",
            fill_horizontal = 1,
            f:row {
                f:static_text {
                    title = LOC "$$$/LrGeniusAI/AnalyzeAndIndex/Scope=Scope",
                    width = share "labelWidth",
                },
                f:popup_menu {
                    value = bind "scope",
                    width = 300,
                    items = {
                        { title = LOC "$$$/LrGeniusAI/common/ScopeSelected=Selected photos only", value = "selected" },
                        { title = LOC "$$$/LrGeniusAI/common/ScopeView=Current view", value = "view" },
                        { title = LOC "$$$/LrGeniusAI/AnalyzeAndIndex/ScopeAll=All photos in catalog", value = "all" },
                    },
                },
            },
        },
        f:group_box {
            title = LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/OptionsTitle=Manifest options",
            fill_horizontal = 1,
            f:row {
                f:checkbox {
                    value = bind "includePreviews",
                },
                f:static_text {
                    title = LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/IncludePreviews=Render preview JPEGs (slower, needed for bootstrap indexing)",
                },
            },
            f:row {
                f:checkbox {
                    value = bind "includeLocalAdjustments",
                },
                f:static_text {
                    title = LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/IncludeLocal=Keep local adjustments in the snapshot (debug only)",
                },
            },
        },
    }

    local result = LrDialogs.presentModalDialog {
        title = LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/WindowTitle=Export Style-Match Manifest",
        contents = contents,
        actionVerb = LOC "$$$/LrGeniusAI/common/Start=Start",
        cancelVerb = LOC "$$$/LrGeniusAI/common/Cancel=Cancel",
        resizable = true,
    }

    if result ~= "ok" then
        return nil
    end

    prefs.styleMatchManifestScope = props.scope
    prefs.styleMatchManifestPreviews = props.includePreviews
    prefs.styleMatchManifestLocalAdjustments = props.includeLocalAdjustments

    return props
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("ExportStyleMatchManifestTask", function(context)
        local props = showManifestDialog(context)
        if props == nil then return end

        local photos, status = PhotoSelector.getPhotosInScope(props.scope)
        if photos == nil or #photos == 0 then
            if status == "Invalid view" then
                LrDialogs.message(
                    LOC "$$$/LrGeniusAI/common/InvalidViewTitle=Invalid View",
                    LOC "$$$/LrGeniusAI/common/InvalidViewMessage=The 'Current view' scope only works when a folder or collection is selected."
                )
            else
                LrDialogs.message(
                    LOC "$$$/LrGeniusAI/common/NoPhotosTitle=No Photos Found",
                    LOC "$$$/LrGeniusAI/common/NoPhotosMessage=No photos found in the selected scope."
                )
            end
            return
        end

        local progressScope = LrProgressScope({
            title = LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/ProgressTitle=Building Style Match manifest...",
            functionContext = context,
        })

        -- Previews take most of the time; reserve 70% of the bar for them.
        local previewSpan = props.includePreviews and 0.7 or 0
        progressScope:setCaption(LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/Collecting=Collecting photo metadata...")

        local previewPaths = {}
        if props.includePreviews then
            previewPaths = exportPreviews(photos, progressScope, 0, previewSpan)
        end

        if progressScope:isCanceled() then
            progressScope:done()
            LrDialogs.message(
                LOC "$$$/LrGeniusAI/common/TaskCanceled/Title=Task Canceled",
                LOC "$$$/LrGeniusAI/common/TaskCanceled/Message=The task was canceled by the user."
            )
            return
        end

        local catalogId = StyleWhitelist.catalogId()
        local rows = {}
        local previewFailures = 0

        for index, photo in ipairs(photos) do
            if progressScope:isCanceled() then break end

            local previewPath = previewPaths[photo]
            if props.includePreviews and previewPath == nil then
                previewFailures = previewFailures + 1
            end

            local row = buildManifestRow(photo, catalogId, previewPath)
            if props.includeLocalAdjustments ~= true then
                row.develop_settings = StyleWhitelist.stripLocal(row.develop_settings).settings
            end
            table.insert(rows, row)

            progressScope:setCaption(
                LOC("$$$/LrGeniusAI/ExportStyleMatchManifest/RowProgress=Building manifest ^1/^2...", index, #photos)
            )
            progressScope:setPortionComplete(previewSpan + (1 - previewSpan) * index / #photos, 1)
        end

        progressScope:done()

        local manifest = {
            catalog_id = catalogId,
            generated_at = LrDate.timeToW3CDate(LrDate.currentTime()),
            plugin_version = pluginVersion(),
            count = #rows,
            photos = rows,
        }

        local manifestPath = chooseManifestPath()
        local encoded = JSON:encode(manifest)
        local written, writeError = pcall(function()
            LrFileUtils.writeFile(manifestPath, encoded)
        end)

        if not written then
            ErrorHandler.handleError(
                LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/WriteFailed=Could not write the Style Match manifest",
                tostring(manifestPath) .. ": " .. tostring(writeError)
            )
            return
        end

        log:trace("Style Match manifest written to " .. manifestPath .. " with " .. #rows .. " rows")
        log:trace("Style Match manifest catalog_id: " .. catalogId)

        local message = LOC("$$$/LrGeniusAI/ExportStyleMatchManifest/DoneMessage=Wrote ^1 photo entries to:\n^2", #rows, manifestPath)
        if previewFailures > 0 then
            message = message .. "\n\n" .. LOC(
                "$$$/LrGeniusAI/ExportStyleMatchManifest/PreviewFailures=^1 previews could not be rendered; their preview_path is empty.",
                previewFailures
            )
        end

        LrDialogs.message(
            LOC "$$$/LrGeniusAI/ExportStyleMatchManifest/DoneTitle=Style Match Manifest Exported",
            message
        )

        pcall(function() LrShell.revealInShell(manifestPath) end)
    end)
end)
