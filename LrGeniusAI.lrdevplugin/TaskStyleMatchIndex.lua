-- TaskStyleMatchIndex.lua
-- "Index for Style Match...": pushes the selected photos (or the current view
-- when nothing is selected) straight to the server's /style-match/index
-- endpoint — no manifest file, no bootstrap script.
--
-- This is the interactive counterpart of the bootstrap flow: same per-photo
-- render (current look → CLIP) and metadata, one HTTP call per photo.
-- The neutral render (HSV colour signal) is not reachable from Lua; those rows
-- land with color_histogram = NULL and are backfilled by the next bootstrap run
-- (plan §2.4 / §3.6).
--
-- Re-running is safe: the server upserts by (catalog_id, lrc_local_id).

local LARGE_SCOPE_CONFIRM = 200

local function scopeLabel(scope)
    if scope == "selected" then
        return LOC "$$$/LrGeniusAI/StyleMatchIndex/ScopeSelected=selected photos"
    end
    return LOC "$$$/LrGeniusAI/StyleMatchIndex/ScopeView=current view"
end

local function resolveScope()
    local catalog = LrApplication.activeCatalog()
    local selected = catalog:getTargetPhotos()
    if selected and #selected > 0 then
        return "selected", #selected
    end
    local photos, status = PhotoSelector.getPhotosInScope("view")
    if photos == nil then
        return nil, 0, status
    end
    return "view", #photos
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("StyleMatchIndexTask", function(context)
        if not Util.waitForServerDialog() then return end

        local scope, count, scopeError = resolveScope()
        if scope == nil then
            LrDialogs.message(
                LOC "$$$/LrGeniusAI/StyleMatchIndex/NoScopeTitle=Nothing to index",
                LOC "$$$/LrGeniusAI/StyleMatchIndex/NoScopeMessage=Select photos (or open a folder/collection) and try again."
            )
            log:trace("Style Match index: no scope (" .. tostring(scopeError) .. ")")
            return
        end

        if count == 0 then
            LrDialogs.message(
                LOC "$$$/LrGeniusAI/StyleMatchIndex/NoPhotosTitle=No photos",
                LOC "$$$/LrGeniusAI/StyleMatchIndex/NoPhotosMessage=No photos found in the current selection/view."
            )
            return
        end

        if scope == "view" and count > LARGE_SCOPE_CONFIRM then
            local choice = LrDialogs.confirm(
                LOC "$$$/LrGeniusAI/StyleMatchIndex/LargeScopeTitle=Index many photos?",
                LOC("$$$/LrGeniusAI/StyleMatchIndex/LargeScopeMessage=This will index ^1 photos from the current view. Each photo is rendered and uploaded; this can take a while. Continue?", count),
                LOC "$$$/LrGeniusAI/StyleMatchIndex/Continue=Index",
                LOC "$$$/LrGeniusAI/common/Cancel=Cancel"
            )
            if choice ~= "ok" then
                return
            end
        end

        local photos = PhotoSelector.getPhotosInScope(scope == "selected" and "selected" or "view")
        if photos == nil or #photos == 0 then
            return
        end

        local catalogId = StyleWhitelist.catalogId()
        local progressScope = LrProgressScope({
            title = LOC("$$$/LrGeniusAI/StyleMatchIndex/ProgressTitle=Indexing ^1 photos for Style Match...", #photos),
            functionContext = context,
        })

        -- Render and upload in batches: each batch is rendered once, then
        -- every photo is pushed and its temp JPEG deleted. Interleaving keeps
        -- the temp folder bounded and makes server-side activity start after
        -- the first batch instead of after the whole set is rendered.
        local BATCH_SIZE = 10
        local indexed, failed, skipped = 0, 0, 0
        local failures = {}

        for batchStart = 1, #photos, BATCH_SIZE do
            if progressScope:isCanceled() then
                break
            end

            local batchEnd = math.min(batchStart + BATCH_SIZE - 1, #photos)
            local batch = {}
            for index = batchStart, batchEnd do
                table.insert(batch, photos[index])
            end

            progressScope:setCaption(
                LOC("$$$/LrGeniusAI/StyleMatchIndex/RenderBatch=Rendering previews ^1-^2 of ^3...",
                    batchStart, batchEnd, #photos)
            )
            local previewPaths = StyleMatchCommon.exportPreviews(batch, progressScope, 0, 0)

            for offset, photo in ipairs(batch) do
                if progressScope:isCanceled() then
                    break
                end

                local photoName = tostring(photo:getFormattedMetadata("fileName") or photo.localIdentifier)
                local index = batchStart + offset - 1

                progressScope:setCaption(
                    LOC("$$$/LrGeniusAI/StyleMatchIndex/UploadProgress=Indexing ^1 of ^2: ^3...", index, #photos, photoName)
                )

                local previewPath = previewPaths[photo]
                if previewPath == nil then
                    skipped = skipped + 1
                    table.insert(failures, photoName .. ": render failed")
                    log:warn("Style Match: render failed for " .. photoName)
                else
                    local ok, err = LrTasks.pcall(function()
                        local row = StyleMatchCommon.buildIndexRow(photo, catalogId, previewPath)
                        local response = SearchIndexAPI.styleMatchIndexPhoto(row.uuid, previewPath, {
                            catalog_id = row.catalog_id,
                            lrc_local_id = row.lrc_local_id,
                            filename = row.filename,
                            capture_time = row.capture_time,
                            develop_settings = row.develop_settings,
                            has_edits = row.has_edits,
                            description = row.description,
                            -- Server-side rawpy extracts the neutral render
                            -- from the original, so no bootstrap run is needed
                            -- for the colour signal. Disable with
                            -- prefs.styleMatchUploadOriginals = false.
                            original_path = (prefs.styleMatchUploadOriginals ~= false) and row.file_path or nil,
                            timeout = 300,
                        })
                        if response == nil then
                            error("server did not confirm indexing", 0)
                        end
                    end)
                    if ok then
                        indexed = indexed + 1
                        log:info("Style Match: indexed " .. photoName)
                    else
                        failed = failed + 1
                        table.insert(failures, photoName .. ": " .. tostring(err))
                        log:warn("Style Match: index failed for " .. photoName .. ": " .. tostring(err))
                    end
                    pcall(function() LrFileUtils.delete(previewPath) end)
                end

                progressScope:setPortionComplete((batchStart + offset - 1) / #photos, 1)
                LrTasks.yield()
            end
        end

        progressScope:done()

        log:info("Style Match index: indexed=" .. indexed .. " failed=" .. failed .. " skipped=" .. skipped
            .. " scope=" .. scope .. " catalog=" .. tostring(catalogId))

        local message = LOC(
            "$$$/LrGeniusAI/StyleMatchIndex/Summary=Indexed ^1 photo(s) from ^2. ^3 failed, ^4 skipped.\n\nColour matching is computed on the server from each photo's original file (disable with the styleMatchUploadOriginals preference).",
            indexed, scopeLabel(scope), failed, skipped
        )
        if #failures > 0 then
            local preview = table.concat(failures, "\n", 1, math.min(#failures, 5))
            message = message .. "\n\n" .. preview
        end

        if failed > 0 or skipped > 0 then
            LrDialogs.message(
                LOC "$$$/LrGeniusAI/StyleMatchIndex/DoneWithErrorsTitle=Style Match indexing finished with errors",
                message,
                "warning"
            )
        else
            LrDialogs.message(
                LOC "$$$/LrGeniusAI/StyleMatchIndex/DoneTitle=Style Match indexing complete",
                message
            )
        end
    end)
end)
