local function safeLoc(key)
    if LOC then
        return LOC(key)
    end
    return key:match("=([^=]*)$") or key
end

return {
    metadataFieldsForPhotos = {
        {
            id = 'aiLastRun',
            title = safeLoc("$$$/lrc-ai-assistant/AIMetadataProvider/aiLastRun=Last AI run"),
            dataType = 'string',
            readOnly = true,
            searchable = true,
            browsable = true,
        },
        {
            id = 'aiModel',
            title = safeLoc("$$$/lrc-ai-assistant/AIMetadataProvider/aiModel=AI model"),
            dataType = 'string',
            readOnly = true,
            searchable = true,
            browsable = true,
        },
        {
            id = 'photoContext',
            title = safeLoc("$$$/lrc-ai-assistant/AIMetadataProvider/photoContext=Photo context"),
            dataType = 'string',
            readOnly = false,
            searchable = true,
            browsable = true,
        },
        {
            id = 'keywords',
            title = safeLoc("$$$/lrc-ai-assistant/AIMetadataProvider/keywords=AI Keywords"),
            dataType = 'string',
            readOnly = true,
            searchable = true,
            browsable = true,
        },
    },

    schemaVersion = 23,
    updateFromEarlierSchemaVersion = function (catalog, previousSchemaVersion, progressScope)
        catalog:assertHasPrivateWriteAccess("AIMetadataProvider.updateFromEarlierSchemaVersion")
        -- No-op: avoid side effects during schema update.
    end,
}
