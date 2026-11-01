-- TaskStyleMatch.lua
-- "Style Match": pick a target photo, ask the server for the most similar photos
-- in this catalog (CLIP + description + colour + GPS) and let the user apply the
-- matched photo's develop settings (style subset only) to the target.

local LrDevelopController = import 'LrDevelopController'

local DEFAULT_TOP_K = 10
local MAX_TOP_K = 25
local FEEDBACK_FILE_NAME = "style-match-feedback.jsonl"

-- Lightroom runs Lua 5.1 (global unpack) while newer interpreters expose table.unpack.
local unpackValues = table.unpack or unpack

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
        return tonumber(value)
    end
    return nil
end

--- Whole-photo count: the matches slider must never show or send a float.
-- Clamps to [1, MAX_TOP_K] and rounds to the nearest integer.
local function matchCountInt(value)
    local number = tonumber(value)
    if number == nil then
        return DEFAULT_TOP_K
    end
    number = math.floor(number + 0.5)
    if number < 1 then
        return 1
    end
    if number > MAX_TOP_K then
        return MAX_TOP_K
    end
    return number
end

--- Integer-only binding for the "Number of matches" slider.
-- With a plain float binding the slider shows 11.999999-ish values and sends a
-- fractional top_k. The transform rounds in BOTH directions, so the knob snaps
-- to whole photos (view -> model) and the readout always renders "12"
-- (model -> view). @param asText boolean render the view value as a string.
local function bindMatchCount(asText)
    return LrView.bind {
        key = "topK",
        transform = function(value, fromModel)
            local rounded = matchCountInt(value)
            if asText and fromModel then
                return tostring(rounded)
            end
            return rounded
        end,
    }
end

local function truncate(text, maxLength)
    if text == nil then
        return nil
    end
    text = tostring(text)
    if #text <= maxLength then
        return text
    end
    return string.sub(text, 1, maxLength - 1) .. "..."
end

local function captureTimeOf(photo)
    local raw = photo:getRawMetadata("dateTimeOriginalISO8601")
    if type(raw) == "number" and raw > 0 then
        local ok, formatted = pcall(function() return LrDate.timeToW3CDate(raw) end)
        if ok and formatted ~= nil then
            return tostring(formatted)
        end
    end
    local text = trimmed(raw)
    if text ~= nil then
        return text
    end
    return trimmed(photo:getFormattedMetadata("dateTimeOriginal"))
end

local function descriptionOf(photo)
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

---
-- Target photo: the Develop module's active photo when in Develop, otherwise the
-- first selected photo in the Library module.
--
local function targetPhoto()
    local photo

    local ok, developTarget = pcall(function()
        if LrDevelopController.getTargetPhoto ~= nil then
            return LrDevelopController.getTargetPhoto()
        end
        return nil
    end)
    if ok and developTarget ~= nil then
        photo = developTarget
    end

    if photo == nil then
        local catalog = LrApplication.activeCatalog()
        local photos = catalog:getTargetPhotos()
        if photos ~= nil then
            photo = photos[1]
        end
    end

    return photo
end

local function showOptionsDialog(ctx, photo)
    local f = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share

    local props = LrBinding.makePropertyTable(ctx)
    props.topK = matchCountInt(prefs.styleMatchTopK)
    props.onlyEdited = prefs.styleMatchOnlyEdited ~= false
    props.useDescription = prefs.styleMatchUseDescription ~= false

    local fileName = photo:getFormattedMetadata("fileName") or tostring(photo.localIdentifier)

    local contents = f:column {
        bind_to_object = props,
        spacing = f:control_spacing(),
        f:group_box {
            title = LOC "$$$/LrGeniusAI/StyleMatch/QueryTitle=Target photo",
            fill_horizontal = 1,
            f:row {
                spacing = f:control_spacing(),
                f:catalog_photo {
                    photo = photo,
                    width = 160,
                },
                f:column {
                    spacing = f:control_spacing(),
                    f:static_text {
                        title = fileName,
                        font = "<system/bold>",
                    },
                    f:static_text {
                        title = LOC "$$$/LrGeniusAI/StyleMatch/QueryHint=Style Match looks for photos in this catalog with a similar look and offers their develop settings.",
                        width_in_chars = 55,
                    },
                },
            },
        },
        f:group_box {
            title = LOC "$$$/LrGeniusAI/StyleMatch/OptionsTitle=Search options",
            fill_horizontal = 1,
            f:row {
                f:static_text {
                    title = LOC "$$$/LrGeniusAI/StyleMatch/TopK=Number of matches:",
                    width = share "labelWidth",
                },
                f:slider {
                    value = bindMatchCount(false),
                    min = 1,
                    max = MAX_TOP_K,
                    immediate = true,
                    width = 220,
                },
                f:static_text {
                    title = bindMatchCount(true),
                    width = 40,
                },
            },
            f:row {
                f:checkbox {
                    value = bind "onlyEdited",
                },
                f:static_text {
                    title = LOC "$$$/LrGeniusAI/StyleMatch/OnlyEdited=Only photos that already have develop edits",
                },
            },
            f:row {
                f:checkbox {
                    value = bind "useDescription",
                },
                f:static_text {
                    title = LOC "$$$/LrGeniusAI/StyleMatch/UseDescription=Use this photo's description (AI caption) as a text signal",
                },
            },
        },
    }

    local result = LrDialogs.presentModalDialog {
        title = LOC "$$$/LrGeniusAI/StyleMatch/WindowTitle=Style Match",
        contents = contents,
        actionVerb = LOC "$$$/LrGeniusAI/common/Search=Search",
        cancelVerb = LOC "$$$/LrGeniusAI/common/Cancel=Cancel",
        resizable = true,
    }

    if result ~= "ok" then
        return nil
    end

    prefs.styleMatchTopK = matchCountInt(props.topK)
    prefs.styleMatchOnlyEdited = props.onlyEdited
    prefs.styleMatchUseDescription = props.useDescription

    return props
end

---
-- localIdentifier -> LrPhoto map. Used as a fallback when the server response
-- carries no uuid for a match: catalog:findPhotoByLocalIdentifier does not exist
-- in the SDK, so the only way to resolve a local id is to walk a photo scope.
--
local function buildLocalIdentifierMap()
    local map = {}
    local photos, status = PhotoSelector.getPhotosInScope("all")
    if photos == nil then
        log:warn("Style Match: could not build localIdentifier map (" .. tostring(status) .. ")")
        return map
    end
    for _, photo in ipairs(photos) do
        map[tostring(photo.localIdentifier)] = photo
    end
    log:trace("Style Match: built localIdentifier map with " .. #photos .. " photos")
    return map
end

---
-- Resolves server matches to catalog photos: uuid first, localIdentifier map second.
--
local function resolveMatches(matches)
    local catalog = LrApplication.activeCatalog()
    local localIdMap
    local resolved = {}

    for index, match in ipairs(matches) do
        local photo

        local uuid = trimmed(match.uuid)
        if uuid ~= nil then
            local ok, found = pcall(function() return catalog:findPhotoByUuid(uuid) end)
            if ok then
                photo = found
            end
        end

        if photo == nil and match.lrc_local_id ~= nil then
            if localIdMap == nil then
                localIdMap = buildLocalIdentifierMap()
            end
            photo = localIdMap[tostring(match.lrc_local_id)]
        end

        resolved[index] = photo
        if photo == nil then
            log:trace(
                "Style Match: match " .. tostring(match.file_name) ..
                " (uuid " .. tostring(match.uuid) .. ", local id " .. tostring(match.lrc_local_id) ..
                ") not found in this catalog"
            )
        end
    end

    return resolved
end

local function mergeTables(primary, secondary)
    local merged = {}
    for key, value in pairs(secondary or {}) do
        merged[key] = value
    end
    for key, value in pairs(primary or {}) do
        merged[key] = value
    end
    return merged
end

local function applyDevelopSettingsTo(photo, settings, historyName)
    if photo == nil then
        return false, "No catalog photo resolved for this match"
    end
    if settings == nil or next(settings) == nil then
        return false, "This match has no develop settings to apply"
    end

    local catalog = LrApplication.activeCatalog()
    local keyCount = 0
    for _ in pairs(settings) do
        keyCount = keyCount + 1
    end
    log:trace(
        "Style Match: applying " .. tostring(keyCount) .. " develop setting(s) to the chosen photo "
        .. tostring(photo:getFormattedMetadata("fileName")) .. " (history: " .. tostring(historyName) .. ")"
    )
    -- LrTasks.pcall: withWriteAccessDo yields while waiting for write access.
    local ok, err = LrTasks.pcall(function()
        catalog:withWriteAccessDo(historyName, function()
            photo:applyDevelopSettings(settings, historyName)
        end, Defaults.catalogWriteAccessOptions)
    end)

    if not ok then
        log:error("Style Match: applyDevelopSettings failed for " .. tostring(photo:getFormattedMetadata("fileName")) .. ": " .. tostring(err))
    end

    return ok, err
end

local function openInLoupe(photo)
    if photo == nil then
        return false, "No catalog photo resolved for this match"
    end

    local catalog = LrApplication.activeCatalog()
    local ok, err = LrTasks.pcall(function()
        catalog:withWriteAccessDo("Style Match: show in Loupe", function()
            catalog:setSelectedPhotos(photo, { photo })
        end, Defaults.catalogWriteAccessOptions)
    end)

    if ok then
        pcall(function() LrApplicationView.switchToModule("library") end)
        pcall(function() LrApplicationView.loupeView() end)
    else
        log:error("Style Match: could not select photo in Loupe: " .. tostring(err))
    end

    return ok, err
end

---
-- Appends one feedback line to style-match-feedback.jsonl (local only, no server call).
--
local function writeFeedback(entry)
    local path = LrPathUtils.child(StyleWhitelist.dataDirectory(), FEEDBACK_FILE_NAME)
    local ok, line = pcall(function() return JSON:encode(entry) end)
    if not ok then
        log:warn("Style Match: could not encode feedback entry: " .. tostring(line))
        return false
    end

    local file = io.open(path, "a")
    if file == nil then
        log:warn("Style Match: could not open feedback log " .. path)
        return false
    end
    file:write(line .. "\n")
    file:close()
    log:trace("Style Match feedback written: " .. line)
    return true
end

---
-- Copies the settings JSON to the system clipboard; falls back to a file the user
-- can open when no clipboard command is available.
--
local function copySettingsToClipboard(settingsJson)
    local path = LrPathUtils.child(LrPathUtils.getStandardFilePath("temp"), "style-match-settings.json")
    local written = pcall(function() LrFileUtils.writeFile(path, settingsJson) end)

    if written then
        local command
        if MAC_ENV then
            command = string.format("pbcopy < %q", path)
        else
            command = string.format("clip < %q", path)
        end
        local ok, exitStatus = pcall(function() return os.execute(command) end)
        if ok and (exitStatus == true or exitStatus == 0) then
            return true, path
        end
    end

    return false, path
end

local function describeMatch(match, index)
    local lines = {}

    local score = tonumber(match.score) or 0
    table.insert(lines, string.format("%d. %s  -  %.2f", index, tostring(match.file_name or "?"), score))

    local details = {}
    local captureTime = trimmed(match.capture_time)
    if captureTime ~= nil then
        table.insert(details, captureTime)
    end
    local distanceKm = tonumber(match.distance_km)
    if distanceKm ~= nil then
        table.insert(details, string.format("%.1f km", distanceKm))
    end
    local cameraModel = trimmed(match.camera_model)
    if cameraModel ~= nil then
        table.insert(details, cameraModel)
    end
    if #details > 0 then
        table.insert(lines, table.concat(details, "  |  "))
    end

    local description = trimmed(match.description)
    if description ~= nil then
        table.insert(lines, truncate(description, 110))
    end

    local localAdjustments = numberOrNil(match.local_adjustments)
    if localAdjustments ~= nil and localAdjustments > 0 then
        table.insert(lines, LOC("$$$/LrGeniusAI/StyleMatch/LocalAdjustments=^1 local corrections (not transferred)", localAdjustments))
    end

    return table.concat(lines, "\n")
end

local function showResultsDialog(ctx, queryPhoto, response, matches)
    local f = LrView.osFactory()
    local bind = LrView.bind

    local props = LrBinding.makePropertyTable(ctx)
    for index = 1, #matches do
        props["status" .. index] = ""
    end

    local queryUuid = trimmed(response.query and response.query.uuid) or tostring(queryPhoto:getRawMetadata("uuid") or "")
    local queryFileName = (response.query and response.query.filename) or queryPhoto:getFormattedMetadata("fileName")

    -- Signals / notices
    local signalNames = {}
    local signalsUsed = response.signals_used
    if type(signalsUsed) == "table" then
        for _, signal in ipairs(signalsUsed) do
            table.insert(signalNames, tostring(signal))
        end
    end

    local notices = {}
    local hasColor = false
    for _, signal in ipairs(signalNames) do
        if tostring(signal) == "color" then
            hasColor = true
        end
    end
    if #signalNames > 0 then
        table.insert(notices, LOC("$$$/LrGeniusAI/StyleMatch/SignalsUsed=Signals used: ^1", table.concat(signalNames, ", ")))
    end
    if #signalNames > 0 and not hasColor then
        table.insert(notices, LOC "$$$/LrGeniusAI/StyleMatch/NoColorSignal=Colour comparison was not available for this query; scores rely on the other signals.")
    end
    if response.query and response.query.description_used == false then
        table.insert(notices, LOC "$$$/LrGeniusAI/StyleMatch/NoDescription=No description was used for this query.")
    end
    if type(signalsUsed) ~= "table" then
        table.insert(notices, LOC "$$$/LrGeniusAI/StyleMatch/NoSignalsReported=The server did not report which signals were used.")
    end

    local rows = {}
    for index, match in ipairs(matches) do
        local photo = match.photo

        local stripResult = styleMatchStripLocal(match.develop_settings)
        local styleSettings = styleMatchStyleSubset(stripResult.settings)
        local sceneSettings = styleMatchSceneSubset(stripResult.settings)
        local hasStyleSettings = next(styleSettings) ~= nil

        if not hasStyleSettings then
            -- A row indexed before the develop-settings fix carries an empty
            -- snapshot: say so instead of leaving a silently disabled button.
            props["status" .. index] = LOC "$$$/LrGeniusAI/StyleMatch/NoSettings=No develop settings indexed for this match - re-index it with \"Index for Style Match\"."
        end

        local feedbackBase = {
            ts = LrDate.timeToW3CDate(LrDate.currentTime()),
            query_uuid = queryUuid,
            matched_lrc_id = match.lrc_local_id,
            rank = match.rank or index,
            score = tonumber(match.score) or 0,
        }

        local function recordAction(action)
            local entry = {}
            for key, value in pairs(feedbackBase) do
                entry[key] = value
            end
            entry.action = action
            writeFeedback(entry)
        end

        local thumbnail
        if photo ~= nil then
            thumbnail = f:catalog_photo {
                photo = photo,
                width = 96,
            }
        else
            thumbnail = f:static_text {
                title = LOC "$$$/LrGeniusAI/StyleMatch/NoLocalPhoto=not in catalog",
                width = 96,
            }
        end

        table.insert(rows, f:row {
            spacing = f:control_spacing(),
            thumbnail,
            f:column {
                spacing = 2,
                f:static_text {
                    title = describeMatch(match, index),
                    width_in_chars = 70,
                },
                f:static_text {
                    title = bind("status" .. index),
                    size = "small",
                },
            },
            f:column {
                spacing = 2,
                f:row {
                    f:push_button {
                        title = LOC "$$$/LrGeniusAI/StyleMatch/ApplyStyle=Apply style",
                        enabled = hasStyleSettings,
                        action = function()
                            -- Apply to the QUERY photo (the one the user chose),
                            -- never to the matched photo: the match is only the
                            -- style source, re-applying its own settings to
                            -- itself is a no-op and looked like a dead button.
                            local ok, err = applyDevelopSettingsTo(queryPhoto, styleSettings, LOC "$$$/LrGeniusAI/StyleMatch/HistoryApply=Style Match")
                            if ok then
                                props["status" .. index] = LOC "$$$/LrGeniusAI/StyleMatch/AppliedStyle=Style applied."
                                recordAction("apply_style")
                            else
                                props["status" .. index] = LOC("$$$/LrGeniusAI/StyleMatch/ApplyFailed=Apply failed: ^1", tostring(err))
                            end
                        end,
                    },
                    f:push_button {
                        title = LOC "$$$/LrGeniusAI/StyleMatch/ApplyStyleScene=Apply style + exposure/WB",
                        enabled = hasStyleSettings or next(sceneSettings) ~= nil,
                        action = function()
                            local settings = mergeTables(styleSettings, sceneSettings)
                            -- Same rule: the QUERY photo receives the style;
                            -- the matched photo is only the source.
                            local ok, err = applyDevelopSettingsTo(queryPhoto, settings, LOC "$$$/LrGeniusAI/StyleMatch/HistoryApplyScene=Style Match (style + exposure)")
                            if ok then
                                props["status" .. index] = LOC "$$$/LrGeniusAI/StyleMatch/AppliedStyleScene=Style with exposure/WB applied."
                                recordAction("apply_style_scene")
                            else
                                props["status" .. index] = LOC("$$$/LrGeniusAI/StyleMatch/ApplyFailed=Apply failed: ^1", tostring(err))
                            end
                        end,
                    },
                },
                f:row {
                    f:push_button {
                        title = LOC "$$$/LrGeniusAI/StyleMatch/CopySettings=Copy settings",
                        enabled = hasStyleSettings,
                        action = function()
                            local okEncode, json = pcall(function() return JSON:encode(styleSettings) end)
                            if not okEncode then
                                props["status" .. index] = LOC("$$$/LrGeniusAI/StyleMatch/CopyFailed=Copy failed: ^1", tostring(json))
                                return
                            end
                            local copied, path = copySettingsToClipboard(json)
                            if copied then
                                props["status" .. index] = LOC "$$$/LrGeniusAI/StyleMatch/Copied=Settings copied to the clipboard."
                            else
                                props["status" .. index] = LOC("$$$/LrGeniusAI/StyleMatch/CopiedToFile=Clipboard unavailable - settings written to ^1", tostring(path))
                                pcall(function() LrShell.revealInShell(path) end)
                            end
                            recordAction("copy_settings")
                        end,
                    },
                    f:push_button {
                        title = LOC "$$$/LrGeniusAI/StyleMatch/OpenInLoupe=Open in Loupe",
                        enabled = photo ~= nil,
                        action = function()
                            local ok, err = openInLoupe(photo)
                            if ok then
                                props["status" .. index] = LOC "$$$/LrGeniusAI/StyleMatch/OpenedInLoupe=Selected in the Library module."
                            else
                                props["status" .. index] = LOC("$$$/LrGeniusAI/StyleMatch/OpenFailed=Could not open: ^1", tostring(err))
                            end
                        end,
                    },
                },
            },
        })
    end

    local contents = f:column {
        bind_to_object = props,
        spacing = f:control_spacing(),
        f:static_text {
            title = LOC("$$$/LrGeniusAI/StyleMatch/ResultsHeader=^1 matches for ^2", #matches, tostring(queryFileName)),
            font = "<system/bold>",
        },
        f:static_text {
            title = table.concat(notices, "\n"),
            width_in_chars = 100,
            size = "small",
        },
        f:separator { fill_horizontal = 1 },
        f:column {
            spacing = f:control_spacing(),
            unpackValues(rows),
        },
    }

    LrDialogs.presentModalDialog {
        title = LOC "$$$/LrGeniusAI/StyleMatch/ResultsTitle=Style Match Results",
        contents = contents,
        cancelVerb = LOC "$$$/LrGeniusAI/common/Close=Close",
        resizable = true,
    }
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("StyleMatchTask", function(context)
        if not Util.waitForServerDialog() then return end

        local photo = targetPhoto()
        if photo == nil then
            LrDialogs.message(
                LOC "$$$/LrGeniusAI/StyleMatch/NoTargetTitle=Style Match",
                LOC "$$$/LrGeniusAI/StyleMatch/NoTargetMessage=Select exactly one photo in the Library or Develop module and run Style Match again."
            )
            return
        end

        local props = showOptionsDialog(context, photo)
        if props == nil then return end

        local progressScope = LrProgressScope({
            title = LOC "$$$/LrGeniusAI/StyleMatch/ProgressTitle=Style Match...",
            functionContext = context,
        })

        progressScope:setCaption(LOC "$$$/LrGeniusAI/StyleMatch/RenderingQuery=Rendering the current look...")
        local jpegPath = SearchIndexAPI.exportPhotoForIndexing(photo)
        if jpegPath == nil then
            progressScope:done()
            ErrorHandler.handleError(
                LOC "$$$/LrGeniusAI/StyleMatch/ExportFailed=Could not render the target photo",
                LOC "$$$/LrGeniusAI/StyleMatch/ExportFailedDetails=Lightroom failed to export a JPEG for the selected photo. Check the log for details."
            )
            return
        end

        local options = {
            catalog_id = StyleWhitelist.catalogId(),
            lrc_local_id = tostring(photo.localIdentifier or ""),
            filename = photo:getFormattedMetadata("fileName"),
            capture_time = captureTimeOf(photo),
            top_k = matchCountInt(props.topK),
            filters = { has_edits = props.onlyEdited == true },
        }

        if props.useDescription then
            options.description = descriptionOf(photo)
        end

        log:trace("Style Match query options: " .. Util.dumpTable({
            catalog_id = options.catalog_id,
            lrc_local_id = options.lrc_local_id,
            filename = options.filename,
            capture_time = options.capture_time,
            top_k = options.top_k,
            filters = options.filters,
            has_description = options.description ~= nil,
        }))

        progressScope:setCaption(LOC "$$$/LrGeniusAI/StyleMatch/Searching=Searching this catalog for a similar look...")
        local response, err = SearchIndexAPI.styleMatchSearch(
            photo:getRawMetadata("uuid"),
            jpegPath,
            options
        )

        LrFileUtils.delete(jpegPath)
        progressScope:done()

        if response == nil then
            ErrorHandler.handleError(
                LOC "$$$/LrGeniusAI/StyleMatch/SearchFailed=Style Match search failed",
                tostring(err)
            )
            return
        end

        local matches = response.matches
        if type(matches) ~= "table" or #matches == 0 then
            local message = LOC "$$$/LrGeniusAI/StyleMatch/NoMatchesMessage=No similar photos were found in this catalog. Index more photos, or relax the 'only photos with develop edits' filter."
            if props.onlyEdited then
                message = message .. "\n\n" .. LOC "$$$/LrGeniusAI/StyleMatch/NoMatchesHint=Tip: rerun with the edits filter turned off."
            end
            LrDialogs.message(LOC "$$$/LrGeniusAI/StyleMatch/NoMatchesTitle=No Matches", message)
            return
        end

        local resolved = resolveMatches(matches)
        for index, match in ipairs(matches) do
            match.photo = resolved[index]
        end

        showResultsDialog(context, photo, response, matches)
    end)
end)
