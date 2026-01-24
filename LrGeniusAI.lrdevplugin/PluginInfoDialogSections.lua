PluginInfoDialogSections = {}

local function ensureGlobals()
    _G.LrPrefs = _G.LrPrefs or import 'LrPrefs'
    _G.LrView = _G.LrView or import 'LrView'
    _G.LrTasks = _G.LrTasks or import 'LrTasks'
    _G.LrDialogs = _G.LrDialogs or import 'LrDialogs'
    _G.LrHttp = _G.LrHttp or import 'LrHttp'
    _G.LrShell = _G.LrShell or import 'LrShell'

    _G.prefs = _G.prefs or _G.LrPrefs.prefsForPlugin()
    _G.log = _G.log or import 'LrLogger' ('LrGeniusAI')
    _G.log:enable('logfile')

    if not _G.Defaults then require "Defaults" end
    if not _G.Util then require "Util" end
    if not _G.PromptConfigProvider then require "PromptConfigProvider" end
    if not _G.SearchIndexAPI then require "APISearchIndex" end

    if _G.prefs.logging == nil then _G.prefs.logging = true end
    if _G.prefs.perfLogging == nil then _G.prefs.perfLogging = false end
    if _G.prefs.geminiApiKey == nil then _G.prefs.geminiApiKey = "" end
    if _G.prefs.chatgptApiKey == nil then _G.prefs.chatgptApiKey = "" end
    if _G.prefs.generateTitle == nil then _G.prefs.generateTitle = true end
    if _G.prefs.generateKeywords == nil then _G.prefs.generateKeywords = true end
    if _G.prefs.generateCaption == nil then _G.prefs.generateCaption = true end
    if _G.prefs.generateAltText == nil then _G.prefs.generateAltText = true end
    if _G.prefs.reviewAltText == nil then _G.prefs.reviewAltText = false end
    if _G.prefs.reviewCaption == nil then _G.prefs.reviewCaption = false end
    if _G.prefs.reviewTitle == nil then _G.prefs.reviewTitle = false end
    if _G.prefs.reviewKeywords == nil then _G.prefs.reviewKeywords = false end
    if _G.prefs.enableValidation == nil then _G.prefs.enableValidation = true end
    if _G.prefs.showCosts == nil then _G.prefs.showCosts = true end
    if _G.prefs.generateLanguage == nil then _G.prefs.generateLanguage = Defaults.defaultGenerateLanguage end
    if _G.prefs.replaceSS == nil then _G.prefs.replaceSS = false end
    if _G.prefs.exportSize == nil then _G.prefs.exportSize = Defaults.defaultExportSize end
    if _G.prefs.exportQuality == nil then _G.prefs.exportQuality = Defaults.defaultExportQuality end
    if _G.prefs.showPreflightDialog == nil then _G.prefs.showPreflightDialog = true end
    if _G.prefs.showPhotoContextDialog == nil then _G.prefs.showPhotoContextDialog = true end
    if _G.prefs.task == nil then _G.prefs.task = Defaults.defaultTask end
    if _G.prefs.systemInstruction == nil then _G.prefs.systemInstruction = "" end
    if _G.prefs.submitKeywords == nil then _G.prefs.submitKeywords = true end
    if _G.prefs.submitGPS == nil then _G.prefs.submitGPS = true end
    if _G.prefs.temperature == nil then _G.prefs.temperature = Defaults.defaultTemperature end
    if _G.prefs.useKeywordHierarchy == nil then _G.prefs.useKeywordHierarchy = true end
    if _G.prefs.useTopLevelKeyword == nil then _G.prefs.useTopLevelKeyword = true end
    if _G.prefs.prompts == nil then _G.prefs.prompts = { Default = Defaults.defaultSystemInstruction } end
    if _G.prefs.prompt == nil then _G.prefs.prompt = "Default" end
    if _G.prefs.ollamaBaseUrl == nil then _G.prefs.ollamaBaseUrl = "http://localhost:11434" end
    if _G.prefs.useLocalServer == nil then _G.prefs.useLocalServer = false end
    if _G.prefs.serverBaseUrl == nil then _G.prefs.serverBaseUrl = "http://127.0.0.1:19819" end
    if _G.prefs.serverDbPath == nil then _G.prefs.serverDbPath = "" end
    if _G.prefs.licenseKey == nil then _G.prefs.licenseKey = "" end
    if _G.prefs.periodicalUpdateCheck == nil then _G.prefs.periodicalUpdateCheck = false end
    if _G.prefs.submitFolderName == nil then _G.prefs.submitFolderName = false end
    if _G.prefs.useLightroomKeywords == nil then _G.prefs.useLightroomKeywords = false end
end

function PluginInfoDialogSections.startDialog(propertyTable)
    ensureGlobals()

    propertyTable.useClip = prefs.useClip

    propertyTable.clipReady = false
    propertyTable.keepChecksRunning = true
    LrTasks.startAsyncTask(function (context)
            propertyTable.clipReady = SearchIndexAPI.isClipReady()
            while propertyTable.keepChecksRunning  do
                LrTasks.sleep(1)
                propertyTable.clipReady = SearchIndexAPI.isClipReady()
            end
        end
    )
    propertyTable.logging = prefs.logging
    propertyTable.perfLogging = prefs.perfLogging
    propertyTable.geminiApiKey = prefs.geminiApiKey
    propertyTable.chatgptApiKey = prefs.chatgptApiKey
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

    propertyTable:addObserver('useLocalServer', function(properties, key, newValue)
        properties.serverDbPathEnabled = not newValue
        prefs.useLocalServer = newValue
        if SearchIndexAPI and SearchIndexAPI.shutdownServer and SearchIndexAPI.startServer then
            if newValue then
                SearchIndexAPI.shutdownServer()
            else
                SearchIndexAPI.startServer()
            end
        end
    end)

    propertyTable.ollamaBaseUrl = prefs.ollamaBaseUrl

    propertyTable.useLocalServer = prefs.useLocalServer
    propertyTable.serverBaseUrl = prefs.serverBaseUrl
    propertyTable.serverDbPath = prefs.serverDbPath
    propertyTable.serverDbPathEnabled = not prefs.useLocalServer

    propertyTable.licenseKey = prefs.licenseKey

    propertyTable.periodicalUpdateCheck = prefs.periodicalUpdateCheck

    propertyTable.submitFolderName = prefs.submitFolderName

    propertyTable.enableValidation = prefs.enableValidation

    propertyTable.useLightroomKeywords = prefs.useLightroomKeywords
end

function PluginInfoDialogSections.sectionsForBottomOfDialog(f, propertyTable)
    ensureGlobals()
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
    ensureGlobals()

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
                    f:checkbox {
                        value = bind 'useLocalServer',
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/useLocalServer=Use external server",
                    },
                },
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/serverBaseUrl=Server base URL",
                        width = share 'labelWidth'
                    },
                    f:edit_field {
                        value = bind 'serverBaseUrl',
                        width = share 'inputWidth',
                        width_in_chars = 30,
                        enabled = bind 'useLocalServer',
                    },
                },
                f:row {
                    f:static_text {
                        title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/serverDbPath=Local server DB path",
                        width = share 'labelWidth'
                    },
                    f:edit_field {
                        value = bind 'serverDbPath',
                        width = share 'inputWidth',
                        width_in_chars = 30,
                        enabled = bind 'serverDbPathEnabled',
                    },
                },
            },
            f:group_box {
                width = share 'groupBoxWidth',
                f:checkbox {
                    value = bind 'useClip',
                    title = "Use OpenCLIP AI model for advanced search",
                },
                f:group_box {
                    width = share 'groupBoxWidth',
                    title = LOC "Advanced search",
                    f:row {
                        f:checkbox {
                            value = bind 'clipReady',
                            enabled = false,
                            title = "OpenCLIP AI model is ready",
                        },
                        f:push_button {
                            title = "Download now",
                            action = function (button)
                                LrTasks.startAsyncTask(function ()
                                    SearchIndexAPI.startClipDownload()
                                end)
                            end,
                            enabled = bind 'useClip',
                        }
                    },
                }
            },
        },
    }
end


function PluginInfoDialogSections.endDialog(propertyTable)
    local wasUsingLocalServer = prefs.useLocalServer
    prefs.geminiApiKey = propertyTable.geminiApiKey
    prefs.chatgptApiKey = propertyTable.chatgptApiKey
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

    if propertyTable.useLocalServer and not wasUsingLocalServer then
        SearchIndexAPI.shutdownServer()
    end

    prefs.useLocalServer = propertyTable.useLocalServer
    prefs.serverBaseUrl = propertyTable.serverBaseUrl
    prefs.serverDbPath = propertyTable.serverDbPath

    if wasUsingLocalServer and not propertyTable.useLocalServer then
        SearchIndexAPI.startServer()
    end

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

    prefs.useClip = propertyTable.useClip

    propertyTable.keepChecksRunning = false

end
