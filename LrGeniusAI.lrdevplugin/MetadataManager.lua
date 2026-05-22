-- MetadataManager.lua
-- Handles reading and writing metadata from/to the Lightroom catalog.

MetadataManager = {}

local function isBlank(value)
    return value == nil or type(value) == "table" or Util.trim(tostring(value)) == ""
end

local function metadataTextValue(value, includeScalar)
    if value == nil then
        return nil
    end
    if includeScalar == nil then
        includeScalar = true
    end

    local valueType = type(value)
    if valueType == "string" then
        return value
    end
    if valueType == "number" or valueType == "boolean" then
        if includeScalar then
            return tostring(value)
        end
        return nil
    end
    if valueType ~= "table" then
        return tostring(value)
    end

    local preferredKeys = {
        "value",
        "text",
        "content",
        "title",
        "caption",
        "alt_text",
        "altText",
        "description",
        "default",
        "en",
    }

    for _, key in ipairs(preferredKeys) do
        local text = metadataTextValue(value[key], true)
        if text ~= nil and Util.trim(text) ~= "" then
            return text
        end
    end

    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    local values = {}
    for _, key in ipairs(keys) do
        local text = metadataTextValue(value[key], false)
        if text ~= nil and Util.trim(text) ~= "" then
            table.insert(values, text)
        end
    end

    if #values > 0 then
        return table.concat(values, "\n")
    end

    return nil
end

local function metadataTextOrEmpty(value)
    return metadataTextValue(value) or ""
end

local function normalizedKeywordName(value)
    local keywordName = metadataTextValue(value)
    if keywordName == nil then
        return nil
    end

    keywordName = Util.trim(keywordName)
    if keywordName == "" or keywordName == "None" or keywordName == "none" then
        return nil
    end

    return keywordName
end

local function sdkPcall(callback)
    if LrTasks and LrTasks.pcall then
        return LrTasks.pcall(callback)
    end

    return pcall(callback)
end

local function safeCreateKeyword(catalog, name, synonyms, includeOnExport, parent, returnExisting)
    local keywordName = normalizedKeywordName(name)
    if keywordName == nil then
        return nil
    end

    local success, keyword = sdkPcall(function()
        return catalog:createKeyword(keywordName, synonyms, includeOnExport, parent, returnExisting)
    end)

    if success then
        return keyword
    end

    log:error("Failed to create keyword '" .. keywordName .. "': " .. tostring(keyword))
    return nil
end

local function safeAddKeyword(photo, keyword, keywordName)
    if keyword == nil then
        return false
    end

    local success, err = sdkPcall(function()
        photo:addKeyword(keyword)
    end)

    if success then
        return true
    end

    log:error("Failed to add keyword '" .. tostring(keywordName or keyword) .. "' to photo: " .. tostring(err))
    return false
end

local function safeSetRawMetadata(photo, key, value)
    local success, err = sdkPcall(function()
        photo:setRawMetadata(key, value)
    end)

    if success then
        return true
    end

    log:error("Failed to set raw metadata '" .. tostring(key) .. "': " .. tostring(err))
    return false
end

local function safeRemoveKeyword(photo, keyword)
    local success, err = sdkPcall(function()
        photo:removeKeyword(keyword)
    end)

    if success then
        return true
    end

    log:error("Failed to remove keyword while replacing catalog keywords: " .. tostring(err))
    return false
end

local function mergeText(catalogValue, backendValue, separator)
    local catalogText = Util.trim(metadataTextOrEmpty(catalogValue))
    local backendText = Util.trim(metadataTextOrEmpty(backendValue))

    if catalogText == "" then return backendText end
    if backendText == "" or catalogText == backendText then return catalogText end
    return catalogText .. separator .. backendText
end

local function keywordTableToDisplayString(keywordTable)
    if keywordTable == nil or type(keywordTable) ~= "table" then
        return ""
    end

    local values = {}
    local seen = {}

    local function recurse(tbl, path)
        for key, value in pairs(tbl) do
            if type(value) == "table" then
                local nextPath = Util.deepcopy(path)
                if type(key) ~= "number" then
                    table.insert(nextPath, tostring(key))
                end
                recurse(value, nextPath)
            elseif type(value) == "string" and value ~= "" then
                local keywordPath = Util.deepcopy(path)
                table.insert(keywordPath, value)
                local displayValue = table.concat(keywordPath, " > ")
                if not seen[displayValue] then
                    table.insert(values, displayValue)
                    seen[displayValue] = true
                end
            end
        end
    end

    recurse(keywordTable, {})
    table.sort(values)
    return table.concat(values, "\n")
end

local function getResponseMetadata(response)
    if type(response) ~= "table" or type(response.metadata) ~= "table" then
        return {}
    end

    return response.metadata
end

function MetadataManager.removeTopLevelKeyword(keywordHierarchy, topLevelKeyword)
    if keywordHierarchy == nil or type(keywordHierarchy) ~= "table" then
        return {}
    end
    if isBlank(topLevelKeyword) then
        return keywordHierarchy
    end

    local topLevelName = Util.trim(tostring(topLevelKeyword))
    local cleaned = {}

    local function addArrayValue(target, value)
        for _, existingValue in ipairs(target) do
            if existingValue == value then
                return
            end
        end
        table.insert(target, value)
    end

    local function mergeInto(target, source)
        for key, value in pairs(source) do
            if type(key) == "number" then
                addArrayValue(target, value)
            elseif type(value) == "table" then
                if target[key] == nil or type(target[key]) ~= "table" then
                    target[key] = {}
                end
                mergeInto(target[key], value)
            else
                target[key] = value
            end
        end
    end

    for key, value in pairs(keywordHierarchy) do
        if type(key) == "number" then
            if type(value) ~= "string" or Util.trim(value) ~= topLevelName then
                addArrayValue(cleaned, value)
            end
        elseif tostring(key) == topLevelName then
            if type(value) == "table" then
                mergeInto(cleaned, value)
            end
        elseif type(value) == "table" then
            if cleaned[key] == nil or type(cleaned[key]) ~= "table" then
                cleaned[key] = {}
            end
            mergeInto(cleaned[key], value)
        else
            cleaned[key] = value
        end
    end

    return cleaned
end

function MetadataManager.getCatalogMetadata(photo)
    return {
        title = photo:getFormattedMetadata("title") or "",
        caption = photo:getFormattedMetadata("caption") or "",
        alt_text = photo:getFormattedMetadata("altTextAccessibility") or "",
        keywords = MetadataManager.getPhotoKeywordHierarchy(photo),
    }
end

function MetadataManager.hasCatalogMetadataConflict(photo, response, options)
    options = options or {}
    if response == nil or type(response.metadata) ~= "table" then
        return false
    end

    local catalogMetadata = MetadataManager.getCatalogMetadata(photo)
    local backendMetadata = getResponseMetadata(response)

    if options.applyTitle ~= false
        and not isBlank(catalogMetadata.title)
        and not isBlank(metadataTextValue(backendMetadata.title))
        and Util.trim(catalogMetadata.title) ~= Util.trim(metadataTextOrEmpty(backendMetadata.title)) then
        return true
    end

    if options.applyCaption ~= false
        and not isBlank(catalogMetadata.caption)
        and not isBlank(metadataTextValue(backendMetadata.caption))
        and Util.trim(catalogMetadata.caption) ~= Util.trim(metadataTextOrEmpty(backendMetadata.caption)) then
        return true
    end

    if options.applyAltText ~= false
        and not isBlank(catalogMetadata.alt_text)
        and not isBlank(metadataTextValue(backendMetadata.alt_text))
        and Util.trim(catalogMetadata.alt_text) ~= Util.trim(metadataTextOrEmpty(backendMetadata.alt_text)) then
        return true
    end

    local catalogKeywords = keywordTableToDisplayString(catalogMetadata.keywords)
    local backendKeywords = keywordTableToDisplayString(backendMetadata.keywords)
    if options.applyKeywords ~= false
        and not isBlank(catalogKeywords)
        and not isBlank(backendKeywords)
        and catalogKeywords ~= backendKeywords then
        return true
    end

    return false
end

function MetadataManager.showCatalogMetadataConflictDialog(ctx, photo, response, options)
    options = options or {}
    local f = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share

    local catalogMetadata = MetadataManager.getCatalogMetadata(photo)
    local backendMetadata = getResponseMetadata(response)

    local properties = LrBinding.makePropertyTable(ctx)
    properties.catalogTitle = catalogMetadata.title or ""
    properties.backendTitle = metadataTextOrEmpty(backendMetadata.title)
    properties.catalogCaption = catalogMetadata.caption or ""
    properties.backendCaption = metadataTextOrEmpty(backendMetadata.caption)
    properties.catalogAltText = catalogMetadata.alt_text or ""
    properties.backendAltText = metadataTextOrEmpty(backendMetadata.alt_text)
    properties.catalogKeywords = keywordTableToDisplayString(catalogMetadata.keywords)
    properties.backendKeywords = keywordTableToDisplayString(backendMetadata.keywords)
    properties.applyForAllNext = false

    local function valueRows(prefix)
        return f:column {
            spacing = f:control_spacing(),
            f:row {
                f:static_text { title = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/Title=Title", width = share 'labelWidth' },
                f:edit_field { value = bind(prefix .. 'Title'), width_in_chars = 42, height_in_lines = 1, enabled = false },
            },
            f:row {
                f:static_text { title = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/Caption=Caption", width = share 'labelWidth' },
                f:edit_field { value = bind(prefix .. 'Caption'), width_in_chars = 42, height_in_lines = 6, enabled = false },
            },
            f:row {
                f:static_text { title = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/AltText=Alt Text", width = share 'labelWidth' },
                f:edit_field { value = bind(prefix .. 'AltText'), width_in_chars = 42, height_in_lines = 4, enabled = false },
            },
            f:row {
                f:static_text { title = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/Keywords=Keywords", width = share 'labelWidth' },
                f:edit_field { value = bind(prefix .. 'Keywords'), width_in_chars = 42, height_in_lines = 8, enabled = false },
            },
        }
    end

    local dialogView = f:column {
        bind_to_object = properties,
        spacing = f:control_spacing(),
        f:row {
            f:static_text {
                title = photo:getFormattedMetadata('fileName'),
                font = "<system/bold>",
            },
        },
        f:row {
            spacing = f:control_spacing(),
            f:group_box {
                title = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/CatalogValues=Values in catalog",
                valueRows('catalog'),
            },
            f:group_box {
                title = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/BackendValues=Values from backend",
                valueRows('backend'),
            },
        },
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'applyForAllNext',
            },
            f:static_text {
                title = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/ApplyForAllNext=Apply for all next photos",
            },
        },
    }

    local result = LrDialogs.presentModalDialog({
        title = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/WindowTitle=Metadata already exists",
        contents = dialogView,
        actionVerb = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/TakeBackend=Take backend",
        otherVerb = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/Merge=Merge",
        cancelVerb = LOC "$$$/LrGeniusAI/RetrieveMetadata/Conflict/KeepCatalog=Keep catalog",
        resizable = true,
    })

    if result == "ok" then
        return "backend", properties.applyForAllNext
    elseif result == "other" then
        return "merge", properties.applyForAllNext
    end

    return "catalog", properties.applyForAllNext
end

function MetadataManager.mergeCatalogAndBackendMetadata(photo, response, options)
    options = options or {}
    local mergedResponse = Util.deepcopy(response or {})
    mergedResponse.metadata = mergedResponse.metadata or {}

    local catalogMetadata = MetadataManager.getCatalogMetadata(photo)
    local backendMetadata = getResponseMetadata(response)

    if options.applyTitle ~= false then
        mergedResponse.metadata.title = mergeText(catalogMetadata.title, backendMetadata.title, " / ")
    end
    if options.applyCaption ~= false then
        mergedResponse.metadata.caption = mergeText(catalogMetadata.caption, backendMetadata.caption, "\n\n")
    end
    if options.applyAltText ~= false then
        mergedResponse.metadata.alt_text = mergeText(catalogMetadata.alt_text, backendMetadata.alt_text, "\n\n")
    end

    return mergedResponse
end

---
-- Applies the AI-generated metadata to the photo.
-- @param photo The LrPhoto object.
-- @param aiResponse The parsed JSON response from the AI.
-- @param validatedData The data from the review dialog, indicating what to save.
-- @param ai (AiModelAPI instance) The AI model API instance.
--
function MetadataManager.applyMetadata(photo, response, validatedData, options)
    options = options or {}
    log:trace("Applying metadata to photo: " .. photo:getFormattedMetadata('fileName'))
    local catalog = LrApplication.activeCatalog()

    response = response or {}
    local metadata = getResponseMetadata(response)
    local title = metadataTextValue(metadata.title)
    local caption = metadataTextValue(metadata.caption)
    local altText = metadataTextValue(metadata.alt_text)
    local keywords = metadata.keywords

    local saveTitle = options.applyTitle ~= false
    local saveCaption = options.applyCaption ~= false
    local saveAltText = options.applyAltText ~= false
    local saveKeywords = options.applyKeywords ~= false

    -- If review was done, use the validated data
    if validatedData then
        saveTitle = validatedData.saveTitle and options.applyTitle ~= false
        title = metadataTextValue(validatedData.title)
        saveCaption = validatedData.saveCaption and options.applyCaption ~= false
        caption = metadataTextValue(validatedData.caption)
        saveAltText = validatedData.saveAltText and options.applyAltText ~= false
        altText = metadataTextValue(validatedData.altText)
        saveKeywords = validatedData.saveKeywords and options.applyKeywords ~= false
        keywords = validatedData.keywords
    end

    log:trace("Response: " .. Util.dumpTable(response))
    log:trace("validatedData: " .. Util.dumpTable(validatedData))

    log:trace("Saving title, caption, altText, keywords to catalog")
    catalog:withWriteAccessDo(LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/saveTitleCaption=Save AI generated title and caption", function()
        if saveCaption and caption ~= nil and (options.replaceExistingMetadata or caption ~= "") then
            safeSetRawMetadata(photo, 'caption', caption)
        end
        if saveTitle and title ~= nil and (options.replaceExistingMetadata or title ~= "") then
            safeSetRawMetadata(photo, 'title', title)
        end
        if saveAltText and altText ~= nil and (options.replaceExistingMetadata or altText ~= "") then
            safeSetRawMetadata(photo, 'altTextAccessibility', altText)
        end
    end, Defaults.catalogWriteAccessOptions)

    -- Save keywords
    log:trace("Saving keywords to catalog")
    if saveKeywords and keywords ~= nil and type(keywords) == 'table' then
        if options.replaceExistingKeywords and not isBlank(keywordTableToDisplayString(keywords)) then
            catalog:withWriteAccessDo("$$$/lrc-ai-assistant/AnalyzeImageTask/replaceKeywords=Replace catalog keywords", function()
                local existingKeywords = photo:getRawMetadata('keywords') or {}
                for _, keyword in ipairs(existingKeywords) do
                    safeRemoveKeyword(photo, keyword)
                end
            end, Defaults.catalogWriteAccessOptions)
        end

        local topKeyword = nil
        if prefs.useKeywordHierarchy and options.useTopLevelKeyword then
            catalog:withWriteAccessDo("$$$/lrc-ai-assistant/AnalyzeImageTask/saveTopKeyword=Save AI generated keywords", function()
                local topLevelKeyword = normalizedKeywordName(options.topLevelKeyword) or "LrGeniusAI"
                topKeyword = safeCreateKeyword(catalog, topLevelKeyword, { Defaults.topLevelKeywordSynonym }, false, nil, true)
            end)
            -- Keep track of used top-level keywords
            local topLevelKeyword = normalizedKeywordName(options.topLevelKeyword) or "LrGeniusAI"
            if not Util.table_contains(prefs.knownTopLevelKeywords, topLevelKeyword) then
                table.insert(prefs.knownTopLevelKeywords, topLevelKeyword)
            end
        end
        catalog:withWriteAccessDo("$$$/lrc-ai-assistant/AnalyzeImageTask/saveTopKeyword=Save AI generated keywords", function()
            MetadataManager.addKeywordRecursively(photo, keywords, topKeyword)
        end, Defaults.catalogWriteAccessOptions)
    end

    -- Save quality scores
    log:trace("Saving quality scores to catalog")
    if response.quality and type(response.quality) == 'table' and options.applyQuality then
        catalog:withPrivateWriteAccessDo(function()
            log:trace("Saving quality scores to catalog")
            for key, value in pairs(response.quality) do
                --log:trace("Setting property for key: " .. key .. " value: " .. tostring(value))
                photo:setPropertyForPlugin(_PLUGIN, key, tostring(value))
            end
        end, Defaults.catalogWriteAccessOptions)
    end

end

---
-- Recursively adds keywords to a photo, creating parent keywords as needed.
-- @param photo The LrPhoto object.
-- @param keywordSubTable A table of keywords, possibly nested.
-- @param parent The parent LrKeyword object for the current level.
--
function MetadataManager.addKeywordRecursively(photo, keywordSubTable, parent)
    local addKeywords = {}
    for key, value in pairs(keywordSubTable) do
        -- log:trace("Processing keyword key: " .. tostring(key) .. " value: " .. tostring(value))
        local keyword
        if type(value) == 'table' then
            local keywordName = normalizedKeywordName(key)
            if type(key) == 'string' and keywordName ~= nil and prefs.useKeywordHierarchy then
                keyword = safeCreateKeyword(photo.catalog, keywordName, nil, false, parent, true)
            end
            MetadataManager.addKeywordRecursively(photo, value, keyword or parent)
        elseif type(key) == 'string' and normalizedKeywordName(key) ~= nil and prefs.useKeywordHierarchy then
            safeCreateKeyword(photo.catalog, key, nil, false, parent, true)
        elseif type(key) == 'number' then
            local currentParent = prefs.useKeywordHierarchy and parent or nil
            local keywordName = normalizedKeywordName(value)
            if keywordName ~= nil and not Util.table_contains(addKeywords, keywordName) then
                if keywordName == "Ollama" or keywordName == "LMStudio" or keywordName == "Google Gemini" or keywordName == "ChatGPT" or keywordName == "Mistral AI" or keywordName == "Anthropic" or keywordName == prefs.topLevelKeyword then
                    log:trace("Skipping keyword: " .. keywordName .. " as it is reserved.")
                else
                    keyword = safeCreateKeyword(photo.catalog, keywordName, nil, true, currentParent, true)
                    if safeAddKeyword(photo, keyword, keywordName) then
                        table.insert(addKeywords, keywordName)
                    end
                end
            end
        end
    end
end




function MetadataManager.showValidationDialog(ctx, photo, response, options)
    options = options or {}
    local f = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share

    local metadata = getResponseMetadata(response)
    local title = metadataTextValue(metadata.title)
    local caption = metadataTextValue(metadata.caption)
    local altText = metadataTextValue(metadata.alt_text)
    local keywords = metadata.keywords
    local keywordHierarchy = type(keywords) == 'table' and keywords or {}

    local propertyTable = LrBinding.makePropertyTable(ctx)
    propertyTable.skipFromHere = false
    propertyTable.keywordsVal = Util.extractAllKeywords(keywordHierarchy)
    propertyTable.keywordsSel = {}
    propertyTable.title = title or ""
    propertyTable.caption = caption or ""
    propertyTable.altText = altText or ""

    propertyTable.saveKeywords = keywords ~= nil and type(keywords) == 'table' and options.applyKeywords ~= false
    propertyTable.saveTitle = title ~= nil and title ~= "" and options.applyTitle ~= false
    propertyTable.saveCaption = caption ~= nil and caption ~= "" and options.applyCaption ~= false
    propertyTable.saveAltText = altText ~= nil and altText ~= "" and options.applyAltText ~= false
    -- propertyTable.keywordWidth = 50

    local keywordRows = {}
    local keywordLabels = {}

    local keywordCount = 0
    for _, keyword in pairs(propertyTable.keywordsVal) do
        if propertyTable.keywordsSel[_] == nil then -- Prevent duplicates
            propertyTable.keywordsSel[_] = true
            keywordCount = keywordCount + 1
            table.insert(keywordLabels, f:checkbox { value = bind('keywordsSel.' .. _), visible = bind 'saveKeywords' })
            table.insert(keywordLabels, f:edit_field { value = bind('keywordsVal.' .. _), width_in_chars = 15, immediate = true, enabled = bind 'saveKeywords' })
        end
    end

    local rowCount = #keywordLabels / 10 + 1

    for i = 1, rowCount do
        local row = {}
        for j = 1, 10 do
            local index = (i - 1) * 10 + j
            if index <= #keywordLabels then
                table.insert(row, keywordLabels[index])
            end
        end
        table.insert(keywordRows, f:row(row))
    end

    keywordRows.horizontal_scroller = true
    keywordRows.vertical_scroller = true
    keywordRows.height = 250
    keywordRows.width = 1100

    local dialogView = f:column {
        bind_to_object = propertyTable,
        f:row {
            f:static_text {
                title = photo:getFormattedMetadata('fileName'),
                font = "<system/bold>",
            },
            f:catalog_photo {
                photo = photo,
                width = 150,
            },
        },
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'saveKeywords',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SaveKeywords=Save keywords",
                width = share 'labelWidth',
            },
            f:scrolled_view(keywordRows),
        },
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'saveTitle',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SaveTitle=Save title",
                width = share 'labelWidth',
            },
            f:edit_field {
                value = bind 'title',
                -- width_in_chars = 40,
                fill_horizontal = 1,
                height_in_lines = 1,
                enabled = bind 'saveTitle',  -- Enable only if the checkbox is checked
            },
        },
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'saveCaption',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SaveCaption=Save caption",
                width = share 'labelWidth',
            },
            f:edit_field {
                value = bind 'caption',
                fill_horizontal = 1,
                height_in_lines = 10,
                enabled = bind 'saveCaption',  -- Enable only if the checkbox is checked
            },
        },
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'saveAltText',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SaveAltText=Save alt text",
                width = share 'labelWidth',
            },
            f:edit_field {
                value = bind 'altText',
                fill_horizontal = 1,
                height_in_lines = 10,
                enabled = bind 'saveAltText',  -- Enable only if the checkbox is checked
            },
        },
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'skipFromHere'
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SkipFromHere=Save following without reviewing.",
            },
        },
    }

    local dialogContents = f:scrolled_view {
        dialogView,
        fill_horizontal = 1,
        height = 750,
        width = 1000,
        vertical_scroller = true,
        horizontal_scroller = false,
    }

    local result = LrDialogs.presentModalDialog({
        title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/ReviewWindowTitle=Review results" .. (photo and (": " .. photo:getFormattedMetadata('fileName')) or ""),
        otherVerb = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/discard=Discard",
        contents = dialogContents,
    })

    local results = {}
    local validatedKeywords = {}
    if propertyTable.saveKeywords then
        validatedKeywords = Util.rebuildTableFromKeywords(keywordHierarchy, propertyTable.keywordsVal, propertyTable.keywordsSel)
    end

    results.keywords = validatedKeywords
    results.saveKeywords = propertyTable.saveKeywords
    results.title = propertyTable.title
    results.saveTitle = propertyTable.saveTitle
    results.caption = propertyTable.caption
    results.saveCaption = propertyTable.saveCaption
    results.altText = propertyTable.altText
    results.saveAltText = propertyTable.saveAltText
    results.skipFromHere = propertyTable.skipFromHere

    return result, results
end

---
-- Get the keyword hierarchy from the Lightroom catalog.
-- Only keywords with children will be returned.
-- @return A table representing the keyword hierarchy.
function MetadataManager.getCatalogKeywordHierarchy()
    local catalog = LrApplication.activeCatalog()
    local topKeywords = catalog:getKeywords()
    local hierarchy = {}

    local function traverseKeywords(keywords, parentHierarchy)
        for _, keyword in ipairs(keywords) do
            -- if not Util.table_contains(prefs.knownTopLevelKeywords, keyword) and not Util.table_contains(keyword:getSynonyms(), Defaults.topLevelKeywordSynonym) then
                local children = keyword:getChildren()
                if #children > 0 then
                    local keywordEntry = {}
                    parentHierarchy[keyword:getName()] = keywordEntry
                    traverseKeywords(children, keywordEntry)
                end
            -- end
        end
    end

    traverseKeywords(topKeywords, hierarchy)

    -- log:trace("Keyword hierarchy: " .. Util.dumpTable(hierarchy))
    return hierarchy
end

---
-- Get the keyword hierarchy for a specific photo.
-- Returns a multidimensional table containing all the photo's keywords organized under their parent keywords.
-- Leaf keywords (last level) are stored as strings in a numeric array.
-- @param photo The LrPhoto object.
-- @return A table representing the keyword hierarchy for this photo.
function MetadataManager.getPhotoKeywordHierarchy(photo)
    local keywords = photo:getRawMetadata('keywords')
    if not keywords or #keywords == 0 then
        return {}
    end

    local hierarchy = {}
    local processedKeywords = {}

    -- Helper function to build the path from keyword to root
    local function getKeywordPath(keyword)
        local path = {}
        local current = keyword
        while current do
            if not Util.table_contains(prefs.knownTopLevelKeywords, current) then
                table.insert(path, 1, current)
            end
            current = current:getParent()
        end
        return path
    end

    -- Helper function to insert a keyword into the hierarchy following its path
    local function insertKeywordIntoHierarchy(path)
        local currentLevel = hierarchy
        for i, keyword in ipairs(path) do
            local keywordName = keyword:getName()
            
            if i == #path then
                -- Last level: add keyword name as string in numeric array
                if currentLevel[keywordName] == nil then
                    currentLevel[keywordName] = {}
                end
                -- Only add if it doesn't already exist in the array
                local alreadyExists = false
                for _, existingKeyword in ipairs(currentLevel) do
                    if existingKeyword == keywordName then
                        alreadyExists = true
                        break
                    end
                end
                if not alreadyExists then
                    table.insert(currentLevel, keywordName)
                end
            else
                -- Intermediate level: create nested table
                if currentLevel[keywordName] == nil then
                    currentLevel[keywordName] = {}
                end
                currentLevel = currentLevel[keywordName]
            end
        end
    end

    -- Process each keyword and build the hierarchy
    for _, keyword in ipairs(keywords) do
        local keywordName = keyword:getName()
        
        -- Only process each keyword once
        if not processedKeywords[keywordName] then
            processedKeywords[keywordName] = true
            local path = getKeywordPath(keyword)
            insertKeywordIntoHierarchy(path)
        end
    end

    -- log:trace("Photo keyword hierarchy: " .. Util.dumpTable(hierarchy))
    return hierarchy
end
