PluginInfoDialogSections = {}

function PluginInfoDialogSections.startDialog(propertyTable)
    propertyTable.logging = prefs.logging
    propertyTable.perfLogging = prefs.perfLogging
    propertyTable.geminiApiKey = prefs.geminiApiKey
    propertyTable.chatgptApiKey = prefs.chatgptApiKey
    propertyTable.mistralApiKey = prefs.mistralApiKey
    propertyTable.anthropicApiKey = prefs.anthropicApiKey
    propertyTable.openrouterApiKey = prefs.openrouterApiKey
    propertyTable.generateTitle = prefs.generateTitle
    propertyTable.generateCaption = prefs.generateCaption
    propertyTable.generateKeywords = prefs.generateKeywords
    propertyTable.generateAltText = prefs.generateAltText
    
    propertyTable.reviewAltText = prefs.reviewAltText
    propertyTable.reviewCaption = prefs.reviewCaption
    propertyTable.reviewTitle = prefs.reviewTitle
    propertyTable.reviewKeywords = prefs.reviewKeywords

    propertyTable.ai  = prefs.ai
    propertyTable.exportSize = prefs.exportSize
    propertyTable.exportQuality = prefs.exportQuality

    propertyTable.showCosts = prefs.showCosts

    propertyTable.showPreflightDialog = prefs.showPreflightDialog
    propertyTable.showPhotoContextDialog = prefs.showPhotoContextDialog

    propertyTable.submitGPS = prefs.submitGPS
    propertyTable.submitKeywords = prefs.submitKeywords

    propertyTable.task = prefs.task
    propertyTable.systemInstruction = prefs.systemInstruction

    propertyTable.useKeywordHierarchy = prefs.useKeywordHierarchy

    propertyTable.useTopLevelKeyword = prefs.useTopLevelKeyword

    propertyTable.generateLanguage = prefs.generateLanguage
    propertyTable.replaceSS = prefs.replaceSS

    propertyTable.promptTitles = {}
    for title, prompt in pairs(prefs.prompts) do
        table.insert(propertyTable.promptTitles, { title = title, value = title })
    end

    propertyTable.prompt = prefs.prompt
    propertyTable.prompts = prefs.prompts

    propertyTable.selectedPrompt = prefs.prompts[prefs.prompt]

    propertyTable:addObserver('prompt', function(properties, key, newValue)
        properties.selectedPrompt = properties.prompts[newValue]
    end)

    propertyTable:addObserver('selectedPrompt', function(properties, key, newValue)
        properties.prompts[properties.prompt] = newValue
    end)

    propertyTable.ollamaBaseUrl = prefs.ollamaBaseUrl

    propertyTable.serverBaseUrl = prefs.serverBaseUrl or ""
    propertyTable.serverApiKey = prefs.serverApiKey or ""

    propertyTable.licenseKey = prefs.licenseKey

    propertyTable.periodicalUpdateCheck = prefs.periodicalUpdateCheck

    propertyTable.submitFolderName = prefs.submitFolderName

    propertyTable.enableValidation = prefs.enableValidation

    propertyTable.useLightroomKeywords = prefs.useLightroomKeywords
end

function PluginInfoDialogSections.sectionsForBottomOfDialog(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share

    return {
        {
            bind_to_object = propertyTable,
            title = "Logging",

            f:row {
                f:static_text {
                    title = Util.getLogfilePath(),
                },
            },
            f:row {
                f:checkbox {
                    value = bind 'logging',
                    enabled = false,
                },
                f:static_text {
                    title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/enableDebugLogging=Enable logging",
                    alignment = 'right',
                },
                f:push_button {
                    title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/ShowLogfile=Show logfile",
                    action = function (button)
                        LrShell.revealInShell(Util.getLogfilePath())
                    end,
                },
                f:push_button {
                    title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/CopyLogToDesktop=Copy logfiles to Desktop",
                    action = function (button)
                        Util.copyLogfilesToDesktop()
                    end,
                },
            },
            f:row {
                f:checkbox {
                    value = bind 'periodicalUpdateCheck',
                },
                f:static_text {
                    title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/periodUpdateCheck=Periodically check for Updates",
                    alignment = 'right',
                },
            },
            f:row {
                f:push_button {
                    title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/UpdateCheck=Check for updates",
                    action = function (button)
                        LrTasks.startAsyncTask(function ()
                            UpdateCheck.checkForNewVersion()
                        end)
                    end,
                },
            },
        },
        {
            title = "CREDITS",
            f:row {
                f:static_text {
                    title = Defaults.copyrightString,
                    width_in_chars = 140,
                    height_in_lines = 20,
                },
            },
        },
    }
end

function PluginInfoDialogSections.sectionsForTopOfDialog(f, propertyTable)

    local bind = LrView.bind
    local share = LrView.share

    propertyTable.models = {}
    
    propertyTable.promptTitleMenu = f:popup_menu {
        items = bind 'promptTitles',
        value = bind 'prompt',
    }

    return {

        {
            bind_to_object = propertyTable,

            title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/header=LrGeniusAI configuration",

            f:row {
                f:push_button {
                    title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/Docs=Read documentation online",
                    action = function(button) 
                        LrHttp.openUrlInBrowser("https://github.com/LrGenius")
                    end,
                },
            },
            f:group_box {
                width = share 'groupBoxWidth',
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/ApiKeys=API keys",
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/GoogleApiKey=Google API key",
                        -- alignment = 'right',
                        width = share 'labelWidth'
                    },
                    f:edit_field {
                        value = bind 'geminiApiKey',
                        width = share 'inputWidth',
                        width_in_chars = 30,
                    },
                    f:push_button {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/GetAPIkey=Get API key",
                        action = function(button) 
                            LrHttp.openUrlInBrowser("https://aistudio.google.com/app/apikey")                           
                        end,
                        width = share 'apiButtonWidth',
                    },
                },
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/ChatGPTApiKey=ChatGPT API key",
                        -- alignment = 'right',
                        width = share 'labelWidth'
                    },
                    f:edit_field {
                        value = bind 'chatgptApiKey',
                        width = share 'inputWidth',
                        width_in_chars = 30,
                    },
                    f:push_button {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/GetAPIkey=Get API key",
                        action = function(button) 
                            LrHttp.openUrlInBrowser("https://platform.openai.com/api-keys")
                        end,
                        width = share 'apiButtonWidth',
                    },
                },
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/MistralApiKey=Mistral AI API key",
                        -- alignment = 'right',
                        width = share 'labelWidth'
                    },
                    f:edit_field {
                        value = bind 'mistralApiKey',
                        width = share 'inputWidth',
                        width_in_chars = 30,
                    },
                    f:push_button {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/GetAPIkey=Get API key",
                        action = function(button)
                            LrHttp.openUrlInBrowser("https://console.mistral.ai/api-keys")
                        end,
                        width = share 'apiButtonWidth',
                    },
                },
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/AnthropicApiKey=Anthropic API key",
                        -- alignment = 'right',
                        width = share 'labelWidth'
                    },
                    f:edit_field {
                        value = bind 'anthropicApiKey',
                        width = share 'inputWidth',
                        width_in_chars = 30,
                    },
                    f:push_button {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/GetAPIkey=Get API key",
                        action = function(button)
                            LrHttp.openUrlInBrowser("https://console.anthropic.com/settings/keys")
                        end,
                        width = share 'apiButtonWidth',
                    },
                },
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/OpenRouterApiKey=OpenRouter API key",
                        -- alignment = 'right',
                        width = share 'labelWidth'
                    },
                    f:edit_field {
                        value = bind 'openrouterApiKey',
                        width = share 'inputWidth',
                        width_in_chars = 30,
                    },
                    f:push_button {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/GetAPIkey=Get API key",
                        action = function(button)
                            LrHttp.openUrlInBrowser("https://openrouter.ai/keys")
                        end,
                        width = share 'apiButtonWidth',
                    },
                },
            },
            f:group_box {
                width = share 'groupBoxWidth',
                title = LOC "$$$/LrGeniusAI/UI/Prompts=Prompts",
                f:row {
                    f:static_text {
                        width = share 'labelWidth',
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/editPrompts=Edit prompts",
                    },
                    propertyTable.promptTitleMenu,
                    f:push_button {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/add=Add",
                        action = function(button)
                            local newName = PromptConfigProvider.addPrompt(propertyTable)
                        end,
                    },
                    f:push_button {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/delete=Delete",
                        action = function(button)
                            PromptConfigProvider.deletePrompt(propertyTable)
                        end,
                    },
                },
                f:row {
                    f:static_text {
                        width = share 'labelWidth',
                        title = LOC "$$$/LrGeniusAI/PromptConfig/PromptField=Prompt",
                    },
                    f:scrolled_view {
                        horizontal_scroller = false,
                        vertical_scroller = true,
                        width = 500,
                        f:edit_field {
                            value = bind 'selectedPrompt',
                            width = 480,
                            height_in_lines = 30,
                            wraps = true,
                            -- enabled = false,
                        },
                    },
                },
            },
            f:group_box {
                width = share 'groupBoxWidth',
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/exportSettings=Export settings",
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/exportSize=Export size in pixel (long edge)",
                    },
                    f:popup_menu {
                        value = bind 'exportSize',
                        items = Defaults.exportSizes,
                    },
                },
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/exportQuality=Export JPEG quality in percent",
                    },
                    f:slider {
                        value = bind 'exportQuality',
                        min = 1,
                        max = 100,
                        integral = true,
                        immediate = true,
                    },
                    f:static_text {
                        title = bind 'exportQuality'
                    },
                },
            },
            f:group_box {
                width = share 'groupBoxWidth',
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/serverSettings=Server settings",
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/serverBaseUrl=Remote server URL",
                        width = share 'labelWidth'
                    },
                    f:edit_field {
                        value = bind 'serverBaseUrl',
                        width = share 'inputWidth',
                        width_in_chars = 30,
                    },
                },
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/serverApiKey=Api Key",
                        width = share 'labelWidth'
                    },
                    f:edit_field {
                        value = bind 'serverApiKey',
                        width = share 'inputWidth',
                        width_in_chars = 30,
                    },
                },
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/serverBaseUrlRequired=Required",
                    },
                },
            },
        },
    }
end


function PluginInfoDialogSections.endDialog(propertyTable)
    prefs.geminiApiKey = propertyTable.geminiApiKey
    prefs.chatgptApiKey = propertyTable.chatgptApiKey
    prefs.mistralApiKey = propertyTable.mistralApiKey
    prefs.anthropicApiKey = propertyTable.anthropicApiKey
    prefs.openrouterApiKey = propertyTable.openrouterApiKey
    prefs.generateCaption = propertyTable.generateCaption
    prefs.generateTitle = propertyTable.generateTitle
    prefs.generateKeywords = propertyTable.generateKeywords
    prefs.generateAltText = propertyTable.generateAltText
    prefs.ai = propertyTable.ai
    prefs.exportSize = propertyTable.exportSize
    prefs.exportQuality = propertyTable.exportQuality

    prefs.reviewCaption = propertyTable.reviewCaption
    prefs.reviewTitle = propertyTable.reviewTitle
    prefs.reviewAltText = propertyTable.reviewAltText
    prefs.reviewKeywords = propertyTable.reviewKeywords

    prefs.showCosts = propertyTable.showCosts

    prefs.showPreflightDialog = propertyTable.showPreflightDialog
    prefs.showPhotoContextDialog = propertyTable.showPhotoContextDialog

    prefs.submitGPS = propertyTable.submitGPS
    prefs.submitKeywords = propertyTable.submitKeywords

    prefs.task = propertyTable.task
    prefs.systemInstruction = propertyTable.systemInstruction

    prefs.useKeywordHierarchy = propertyTable.useKeywordHierarchy

    prefs.useTopLevelKeyword = propertyTable.useTopLevelKeyword

    prefs.generateLanguage = propertyTable.generateLanguage
    prefs.replaceSS = propertyTable.replaceSS

    prefs.prompt = propertyTable.prompt
    prefs.prompts = propertyTable.prompts

    prefs.ollamaBaseUrl = propertyTable.ollamaBaseUrl

    local remoteServerUrl = Util.trim(propertyTable.serverBaseUrl or "")
    if Util.nilOrEmpty(remoteServerUrl) then
        LrDialogs.showError(LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/serverBaseUrlMissing=Remote server URL is required.")
        prefs.serverBaseUrl = ""
    else
        prefs.serverBaseUrl = remoteServerUrl
    end

    prefs.serverApiKey = Util.trim(propertyTable.serverApiKey or "")

    prefs.licenseKey = propertyTable.licenseKey
    
    prefs.logging = propertyTable.logging
    if propertyTable.logging then
        log:enable('logfile')
    else
        log:disable()
    end

    prefs.perfLogging = propertyTable.perfLogging

    prefs.periodicalUpdateCheck = propertyTable.periodicalUpdateCheck

    prefs.submitFolderName = propertyTable.submitFolderName

    prefs.enableValidation = propertyTable.enableValidation

    prefs.useLightroomKeywords = propertyTable.useLightroomKeywords

end
