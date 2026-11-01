-- StyleMatchSpike.lua
-- TEMPORARY validation harness for the "Style Match" feature.
-- Run it from Library > Plug-in Extras > "Style Match SDK Spike (diagnostics)".
-- It never changes catalog content permanently: any develop settings applied
-- during the run are restored before the task ends.
-- Everything is written to the plugin log (LrGeniusAI.log); a summary dialog
-- lists PASS/FAIL/MISSING per probe. Delete this file and its Info.lua menu
-- entries once the feature has been validated against Lightroom Classic.

local LrDevelopController = import 'LrDevelopController'

local SPIKE_TAG = "STYLE-MATCH SPIKE "
local results = {}

local function addResult(status, name, detail)
    local line = string.format("[%s] %s%s", status, name, detail and (" - " .. tostring(detail)) or "")
    table.insert(results, line)
    log:trace(SPIKE_TAG .. line)
end

local function note(text)
    table.insert(results, "  " .. tostring(text))
    log:trace(SPIKE_TAG .. text)
end

local function sortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl or {}) do
        table.insert(keys, tostring(key))
    end
    table.sort(keys)
    return keys
end

local function countKeys(tbl)
    local count = 0
    for _ in pairs(tbl or {}) do
        count = count + 1
    end
    return count
end

--- Minimal HTTP status reader (APISearchIndex keeps its own copy private).
local function httpStatus(hdrs)
    if type(hdrs) == "number" then
        return hdrs
    end
    if type(hdrs) == "string" then
        return tonumber(string.match(hdrs, "(%d%d%d)"))
    end
    if type(hdrs) == "table" then
        local direct = tonumber(hdrs.status or hdrs.Status or hdrs.statusCode or hdrs.status_code)
        if direct then
            return direct
        end
        for _, header in pairs(hdrs) do
            if type(header) == "table" then
                local field = string.lower(tostring(header.field or header.name or ""))
                local value = tostring(header.value or header[2] or "")
                if field == "status" or field == ":status" or field == "http-status" then
                    local status = tonumber(string.match(value, "(%d%d%d)"))
                    if status then
                        return status
                    end
                end
            end
        end
    end
    return nil
end

local function probeFunctions(label, moduleTable, functionNames)
    if moduleTable == nil then
        addResult("MISSING", label, "module not available")
        return
    end
    for _, functionName in ipairs(functionNames) do
        local exists = type(moduleTable[functionName]) == "function"
        addResult(exists and "OK" or "MISSING", label .. "." .. functionName .. "()")
    end
end

local function probeMethods(label, object, methodNames)
    if object == nil then
        addResult("MISSING", label, "object not available")
        return
    end
    for _, methodName in ipairs(methodNames) do
        local ok, methodType = pcall(function() return type(object[methodName]) end)
        local exists = ok and methodType == "function"
        addResult(exists and "OK" or "MISSING", label .. ":" .. methodName .. "()")
    end
end

--- Reads photo:getDevelopSettings() and dumps the key names + a representative sample.
local function spikeDevelopSettingsDump(photo)
    local ok, settings = LrTasks.pcall(function() return photo:getDevelopSettings() end)
    if not ok or type(settings) ~= "table" then
        addResult("FAIL", "photo:getDevelopSettings()", tostring(settings))
        return nil
    end

    local keys = sortedKeys(settings)
    addResult("OK", "photo:getDevelopSettings()", tostring(#keys) .. " keys")
    log:trace(SPIKE_TAG .. "develop settings keys: " .. table.concat(keys, ", "))

    local sample = {}
    for _, key in ipairs(keys) do
        local matchesInterest =
            string.find(key, "2012", 1, true) ~= nil
            or string.find(key, "Curve", 1, true) ~= nil
            or string.find(key, "SplitToning", 1, true) ~= nil
            or string.find(key, "Sharpen", 1, true) ~= nil
            or string.find(key, "Noise", 1, true) ~= nil
            or string.find(key, "Grain", 1, true) ~= nil
            or string.find(key, "Vignette", 1, true) ~= nil
            or string.find(key, "ColorGrade", 1, true) ~= nil
            or string.find(key, "WhiteBalance", 1, true) ~= nil
            or string.find(key, "CameraProfile", 1, true) ~= nil
            or string.find(key, "Look", 1, true) ~= nil
            or string.find(key, "Local", 1, true) ~= nil
            or string.find(key, "Crop", 1, true) ~= nil
            or string.find(key, "Perspective", 1, true) ~= nil
        if matchesInterest then
            sample[key] = settings[key]
        end
    end
    log:trace(SPIKE_TAG .. "develop settings sample: " .. Util.dumpTable(sample))

    return settings
end

--- Applies a partial settings table, verifies the readback, then restores every key.
local function spikePartialApply(photo, originalSettings)
    local catalog = LrApplication.activeCatalog()
    local originalContrast = tonumber(originalSettings and originalSettings.Contrast2012) or 0
    local probeValue = (originalContrast == 25) and 26 or 25

    local ok, err = LrTasks.pcall(function()
        catalog:withWriteAccessDo("Style Match Spike: partial apply", function()
            photo:applyDevelopSettings({ Contrast2012 = probeValue }, "Style Match Spike")
        end, Defaults.catalogWriteAccessOptions)
    end)
    if not ok then
        addResult("FAIL", "photo:applyDevelopSettings() inside withWriteAccessDo", tostring(err))
        return
    end
    addResult("OK", "photo:applyDevelopSettings() inside withWriteAccessDo")

    local readOk, after = LrTasks.pcall(function() return photo:getDevelopSettings() end)
    if readOk and type(after) == "table" then
        local applied = tonumber(after.Contrast2012)
        local untouched = tonumber(after.Highlights2012)
        addResult(
            (applied == probeValue) and "OK" or "FAIL",
            "partial apply readback (Contrast2012)",
            "expected " .. tostring(probeValue) .. ", got " .. tostring(applied) ..
            "; Highlights2012 still " .. tostring(untouched)
        )
    else
        addResult("FAIL", "partial apply readback", tostring(after))
    end

    -- Undo stack inspection: no public API is known, so probe for candidates and
    -- report honestly. A single undo step still needs a manual check in the UI.
    probeFunctions("LrDevelopController", LrDevelopController, {
        "getDevelopUndoStepNames",
        "getHistoryStepNames",
        "getTargetPhoto",
        "applySettingsToTarget",
    })
    note("Single-undo-step behaviour must be confirmed manually in Develop (Cmd+Z once).")

    -- Restore the original value so the spike leaves the catalog untouched.
    local restoreOk, restoreErr = LrTasks.pcall(function()
        catalog:withWriteAccessDo("Style Match Spike: restore", function()
            photo:applyDevelopSettings({ Contrast2012 = originalContrast }, "Style Match Spike restore")
        end, Defaults.catalogWriteAccessOptions)
    end)
    addResult(restoreOk and "OK" or "FAIL", "restore original Contrast2012", restoreErr)
end

--- catalog_photo needs a real LrPhoto object; verify the view factory accepts one.
local function spikeCatalogPhotoView(photo)
    local f = LrView.osFactory()
    local ok, viewOrError = pcall(function()
        return f:catalog_photo { photo = photo, width = 120 }
    end)
    addResult(ok and "OK" or "FAIL", "f:catalog_photo { photo = LrPhoto }", ok and "element created" or tostring(viewOrError))
end

--- Resolves a photo by UUID and by a localIdentifier map built from a scope.
local function spikePhotoLookup(photo, uuid)
    local catalog = LrApplication.activeCatalog()

    local ok, found = LrTasks.pcall(function() return catalog:findPhotoByUuid(uuid) end)
    addResult(
        (ok and found ~= nil) and "OK" or "FAIL",
        "catalog:findPhotoByUuid(uuid)",
        ok and (found ~= nil and "resolved to photo" or "returned nil") or tostring(found)
    )

    local localIdentifierApi = catalog.findPhotoByLocalIdentifier
    addResult(
        localIdentifierApi == nil and "OK" or "UNEXPECTED",
        "catalog:findPhotoByLocalIdentifier()",
        localIdentifierApi == nil and "does not exist (as expected)" or "EXISTS - re-evaluate design"
    )

    local localId = tostring(photo.localIdentifier or "")
    addResult(localId ~= "" and "OK" or "FAIL", "photo.localIdentifier", localId)

    local map = {}
    local scopes = { "view", "selected" }
    for _, scope in ipairs(scopes) do
        local photos, status = PhotoSelector.getPhotosInScope(scope)
        if photos and #photos > 0 then
            for _, scopedPhoto in ipairs(photos) do
                map[tostring(scopedPhoto.localIdentifier)] = scopedPhoto
            end
            addResult("OK", "localIdentifier map from PhotoSelector scope '" .. scope .. "'", #photos .. " photos")
            break
        end
        note("scope '" .. scope .. "' returned no photos (" .. tostring(status) .. "); trying next scope")
    end

    if countKeys(map) > 0 then
        local resolved = map[localId]
        addResult(
            resolved ~= nil and "OK" or "FAIL",
            "localIdentifier -> photo map lookup for target",
            resolved ~= nil and "resolved" or "target not in scope"
        )
    else
        addResult("FAIL", "localIdentifier -> photo map", "no photos in any probed scope")
    end
end

--- Exports a photo and posts it as multipart/form-data to the Style Match endpoint.
local function spikeMultipartPost(photo, uuid)
    if Util.nilOrEmpty(prefs.serverBaseUrl) then
        addResult("SKIPPED", "LrHttp multipart POST", "serverBaseUrl not configured")
        return
    end

    local jpegPath = SearchIndexAPI.exportPhotoForIndexing(photo)
    if jpegPath == nil then
        addResult("FAIL", "LrHttp multipart POST", "JPEG export failed")
        return
    end
    addResult("OK", "exportPhotoForIndexing()", jpegPath)

    local baseUrl = Util.trim(prefs.serverBaseUrl)
    if baseUrl:sub(-1) == "/" then
        baseUrl = baseUrl:sub(1, -2)
    end

    local mimeChunks = {
        { name = "uuid", value = tostring(uuid or "") },
        { name = "filename", value = photo:getFormattedMetadata("fileName") or "" },
        { name = "lrc_local_id", value = tostring(photo.localIdentifier or "") },
        { name = "capture_time", value = tostring(photo:getRawMetadata("dateTimeOriginalISO8601") or "") },
        { name = "top_k", value = "3" },
        {
            name = "image",
            fileName = LrPathUtils.leafName(jpegPath),
            filePath = jpegPath,
            contentType = "image/jpeg",
        },
    }

    local ok, body, hdrs = LrTasks.pcall(function()
        return LrHttp.postMultipart(
            baseUrl .. "/style-match/search",
            mimeChunks,
            { { field = "apikey", value = tostring(prefs.serverApiKey or "") } },
            60
        )
    end)

    if not ok then
        addResult("FAIL", "LrHttp multipart POST", tostring(body))
    else
        local status = httpStatus(hdrs)
        local bodyLength = body and #body or 0
        addResult(
            (status ~= nil and status >= 200 and status < 300) and "OK" or "FAIL",
            "LrHttp multipart POST /style-match/search",
            "status " .. tostring(status) .. ", body " .. tostring(bodyLength) .. " bytes"
        )
        if body and bodyLength > 0 then
            log:trace(SPIKE_TAG .. "multipart response (first 2000 chars): " .. tostring(body):sub(1, 2000))
        end
    end

    LrFileUtils.delete(jpegPath)
end

--- Attempts to render an "unedited" version of the photo by overriding export settings.
--- The exact override key is not documented; each candidate is tried and logged.
local function spikeNeutralExport(photo)
    local tempDir = LrPathUtils.getStandardFilePath("temp")
    local neutralFolder = LrPathUtils.child(tempDir, "stylematch_neutral_spike")
    if not LrFileUtils.exists(neutralFolder) then
        LrFileUtils.createDirectory(neutralFolder)
    end

    local neutralSettings = {
        Exposure2012 = 0,
        Contrast2012 = 0,
        Highlights2012 = 0,
        Shadows2012 = 0,
        Whites2012 = 0,
        Blacks2012 = 0,
        Clarity2012 = 0,
        Texture = 0,
        Dehaze = 0,
        Vibrance = 0,
        Saturation = 0,
        WhiteBalance = "As Shot",
        ConvertToGrayscale = false,
    }

    local baseSettings = {
        LR_export_destinationType = "specificFolder",
        LR_export_useSubfolder = false,
        LR_format = "JPEG",
        LR_jpeg_quality = 60,
        LR_minimizeEmbeddedMetadata = true,
        LR_outputSharpeningOn = false,
        LR_size_doConstrain = true,
        LR_size_maxHeight = 1024,
        LR_size_resizeType = "longEdge",
        LR_size_units = "pixels",
        LR_collisionHandling = "overwrite",
        LR_includeVideoFiles = false,
    }

    local candidateKeys = { "LR_developSettings", "LR_developSettingsOverride", "LR_export_developSettings" }
    local anySucceeded = false

    for _, candidateKey in ipairs(candidateKeys) do
        local exportSettings = {}
        for key, value in pairs(baseSettings) do
            exportSettings[key] = value
        end
        exportSettings.LR_export_destinationPathPrefix = neutralFolder
        exportSettings[candidateKey] = neutralSettings

        local ok, renderOk, path = LrTasks.pcall(function()
            local exportSession = LrExportSession({
                photosToExport = { photo },
                exportSettings = exportSettings,
            })
            for _, rendition in exportSession:renditions() do
                return rendition:waitForRender()
            end
            return false, "no rendition produced"
        end)

        if not ok then
            addResult("FAIL", "neutral export override '" .. candidateKey .. "'", tostring(renderOk))
        else
            local fileSize = 0
            if renderOk and path and LrFileUtils.exists(path) then
                local attributes = LrFileUtils.fileAttributes(path)
                fileSize = attributes and attributes.fileSize or 0
            end
            addResult(
                (renderOk and fileSize > 0) and "OK" or "FAIL",
                "neutral export override '" .. candidateKey .. "'",
                "success=" .. tostring(renderOk) .. ", path=" .. tostring(path) .. ", bytes=" .. tostring(fileSize)
            )
            if renderOk and fileSize > 0 then
                anySucceeded = true
                LrFileUtils.delete(path)
            end
        end
    end

    if not anySucceeded then
        note("No export-settings override produced a neutral render. Fallback: send no neutral_image and let the")
        note("server derive colour from the current-look render, or reset/export/restore inside a write gate.")
    end

    if LrFileUtils.exists(neutralFolder) then
        LrFileUtils.delete(neutralFolder)
    end
end

local function exportSettingsReference()
    -- Reference render (current look) for a size comparison with the neutral attempts.
    local photo = LrApplication.activeCatalog():getTargetPhotos()[1]
    if photo == nil then
        return
    end
    local jpegPath = SearchIndexAPI.exportPhotoForIndexing(photo)
    if jpegPath and LrFileUtils.exists(jpegPath) then
        local attributes = LrFileUtils.fileAttributes(jpegPath)
        note("current-look render size: " .. tostring(attributes and attributes.fileSize) .. " bytes")
        LrFileUtils.delete(jpegPath)
    end
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("StyleMatchSpikeContext", function(context)
        results = {}
        addResult("INFO", "Style Match SDK spike started")

        local catalog = LrApplication.activeCatalog()
        local photos = catalog:getTargetPhotos()
        local photo = photos and photos[1]

        if photo == nil then
            LrDialogs.message(
                LOC "$$$/LrGeniusAI/StyleMatchSpike/NoPhotoTitle=Style Match SDK Spike",
                LOC "$$$/LrGeniusAI/StyleMatchSpike/NoPhotoMessage=Select one photo in the Library or Develop module and run the spike again."
            )
            return
        end

        local uuid = photo:getRawMetadata("uuid")
        addResult("INFO", "target photo", tostring(photo:getFormattedMetadata("fileName")) .. " (" .. tostring(uuid) .. ")")

        probeMethods("photo", photo, {
            "getDevelopSettings",
            "applyDevelopSettings",
            "getRenderedDevelopPreview",
            "requestJpegThumbnail",
        })
        probeMethods("catalog", catalog, {
            "findPhotoByUuid",
            "findPhotoByLocalIdentifier",
            "withWriteAccessDo",
        })

        local progressScope = LrProgressScope({
            title = LOC "$$$/LrGeniusAI/StyleMatchSpike/ProgressTitle=Running Style Match SDK spike...",
            functionContext = context,
        })

        progressScope:setPortionComplete(0, 6)

        local originalSettings = spikeDevelopSettingsDump(photo)
        progressScope:setPortionComplete(1, 6)

        if originalSettings ~= nil then
            spikePartialApply(photo, originalSettings)
        end
        progressScope:setPortionComplete(2, 6)

        spikeCatalogPhotoView(photo)
        progressScope:setPortionComplete(3, 6)

        spikePhotoLookup(photo, uuid)
        progressScope:setPortionComplete(4, 6)

        spikeMultipartPost(photo, uuid)
        progressScope:setPortionComplete(5, 6)

        exportSettingsReference()
        spikeNeutralExport(photo)
        progressScope:setPortionComplete(6, 6)
        progressScope:done()

        local summary = {}
        for index, line in ipairs(results) do
            if index > 40 then
                table.insert(summary, LOC("$$$/LrGeniusAI/StyleMatchSpike/MoreLines=... ^1 more lines in the log", #results - 40))
                break
            end
            table.insert(summary, line)
        end

        log:trace(SPIKE_TAG .. "complete:\n" .. table.concat(results, "\n"))

        LrDialogs.message(
            LOC "$$$/LrGeniusAI/StyleMatchSpike/Title=Style Match SDK Spike",
            table.concat(summary, "\n") .. "\n\n" ..
            LOC("$$$/LrGeniusAI/StyleMatchSpike/LogHint=Full output: ^1", Util.getLogfilePath())
        )
    end)
end)
