
local function safeSchemaLog(message)
    local ok, err = pcall(function()
        local LrFileUtils = import 'LrFileUtils'
        local LrPathUtils = import 'LrPathUtils'
        local LrDate = import 'LrDate'
        local logPath = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), "LrGeniusAI-schema.log")
        local line = string.format("%s %s\n", LrDate.timeToUserFormat(LrDate.currentTime()), message or "")
        LrFileUtils.appendToFile(logPath, line)
    end)
    return ok, err
end

safeSchemaLog("MetadataProvider loaded")

return {
    metadataFieldsForPhotos = {
        {
            id = 'aiLastRun',
            title = LOC "$$$/lrc-ai-assistant/AIMetadataProvider/aiLastRun=Last AI run",
            dataType = 'string',
            readOnly = true,
            searchable = true,
            browsable = true,
        },
        {
            id = 'aiModel',
            title = LOC "$$$/lrc-ai-assistant/AIMetadataProvider/aiModel=AI model",
            dataType = 'string',
            readOnly = true,
            searchable = true,
            browsable = true,
        },
        {
            id = 'photoContext',
            title = LOC "$$$/lrc-ai-assistant/AIMetadataProvider/photoContext=Photo context",
            dataType = 'string',
            readOnly = false,
            searchable = true,
            browsable = true,
        },
        {
            id = 'keywords',
            title = LOC "$$$/lrc-ai-assistant/AIMetadataProvider/keywords=AI Keywords",
            dataType = 'string',
            readOnly = true,
            searchable = true,
            browsable = true,
        },
    },

    schemaVersion = 23,
    updateFromEarlierSchemaVersion = function (catalog, previousSchemaVersion, progressScope)
        safeSchemaLog("updateFromEarlierSchemaVersion: " .. tostring(previousSchemaVersion))
        catalog:assertHasPrivateWriteAccess("AIMetadataProvider.updateFromEarlierSchemaVersion")
        if previousSchemaVersion ~= nil and previousSchemaVersion < 23 then
            -- Migration from LrGeniusTagAI (defer UI and work until Init.lua).
            local LrPrefs = import 'LrPrefs'
            local prefs = LrPrefs.prefsForPlugin()
            prefs.pendingImportMetadata = true
        end
    end,
}
