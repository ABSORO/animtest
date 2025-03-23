-- AnimTest Client Script
local Config = {}
dofile("data/animations.lua") -- Load animations.lua

local isMonitoring = false
local isUIOpen = false
local nearbyPeds = {}
local lastAnimCheck = {}
local previewPed = nil
local previewCam = nil
local renderTarget = nil
local favorites = {}
local cameraPos = { x = 0.0, y = 2.0, z = -998.0 }
local cameraFov = 45.0

-- Register command to toggle UI
RegisterCommand("animtest", function()
    isUIOpen = not isUIOpen
    if isUIOpen then
        SendNUIMessage({ type = 'openUI' })
        SetNuiFocus(true, true)
        if isMonitoring then
            StartMonitoring()
        end
    else
        SendNUIMessage({ type = 'closeUI' })
        SetNuiFocus(false, false)
    end
end, false)

-- Start monitoring NPCs
function StartMonitoring()
    Citizen.CreateThread(function()
        while isMonitoring and isUIOpen do
            nearbyPeds = GetNearbyPeds(10.0)
            local detectedAnims = {}
            for _, ped in ipairs(nearbyPeds) do
                if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                    local dict, anim = GetCurrentPedAnimation(ped)
                    if dict and anim and Config.AnimationUtils.DoesAnimationExist(dict, anim) then
                        local pedId = NetworkGetNetworkIdFromEntity(ped)
                        local lastCheck = lastAnimCheck[pedId] or { dict = "", anim = "" }
                        if lastCheck.dict ~= dict or lastCheck.anim ~= anim then
                            lastAnimCheck[pedId] = { dict = dict, anim = anim }
                            table.insert(detectedAnims, { pedId = pedId, dict = dict, anim = anim })
                        end
                    end
                end
            end
            SendNUIMessage({ type = 'updateDetected', animations = detectedAnims })
            SendNUIMessage({ type = 'updateFPS', fps = math.floor(1 / GetFrameTime()) })
            Wait(500)
        end
    end)
end

-- Get nearby peds
function GetNearbyPeds(radius)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local peds = {}
    local handle, ped = FindFirstPed()
    local success

    repeat
        local pedCoords = GetEntityCoords(ped)
        if Vdist(playerCoords.x, playerCoords.y, playerCoords.z, pedCoords.x, pedCoords.y, pedCoords.z) <= radius then
            table.insert(peds, ped)
        end
        success, ped = FindNextPed(handle)
    until not success

    EndFindPed(handle)
    return peds
end

-- Detect current animation
function GetCurrentPedAnimation(ped)
    for dict, anims in pairs(Config.Animations) do
        for _, anim in ipairs(anims) do
            if IsEntityPlayingAnim(ped, dict, anim, 3) then
                local currentTime = GetEntityAnimCurrentTime(ped, dict, anim)
                if currentTime > 0.0 then
                    return dict, anim
                end
            end
        end
    end
    if IsPedUsingAnyScenario(ped) then
        local scenario = "scenario" -- Placeholder; map scenarios to anims
        return "scenario", scenario
    end
    return nil, nil
end

-- Setup preview window
function SetupPreview()
    local playerPed = PlayerPedId()
    local model = GetEntityModel(playerPed)
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end
    previewPed = CreatePed(model, 0.0, 0.0, -1000.0, 0.0, false, true)
    SetEntityVisible(previewPed, false)
    FreezeEntityPosition(previewPed, true)
    SetEntityCollision(previewPed, false, false)

    previewCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(previewCam, cameraPos.x, cameraPos.y, cameraPos.z)
    PointCamAtEntity(previewCam, previewPed, 0.0, 0.0, 0.0, true)
    SetCamFov(previewCam, cameraFov)
    RenderScriptCams(true, false, 0, true, false)

    renderTarget = CreateRenderTarget("preview_window", 200, 150)
    SetRenderTarget(renderTarget, true)
end

-- Play animation in preview
function PreviewAnimation(dict, anim)
    if not previewPed then
        SetupPreview()
    end
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(0)
    end
    TaskPlayAnim(previewPed, dict, anim, 1.0, 1.0, 2000, 1, 0.0, false, false, false, "", false)
    SendNUIMessage({ type = 'updatePlaying', anim = anim })

    Citizen.CreateThread(function()
        local endTime = GetGameTimer() + 2000
        while GetGameTimer() < endTime do
            SetRenderTarget(renderTarget, true)
            RenderScriptCams(true, false, 0, true, false)
            DrawSprite("preview_window", "preview_window", 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)
            Wait(0)
        end
        ClearPedTasks(previewPed)
    end)
end

-- NUI Callbacks
RegisterNUICallback('toggleMonitoring', function(data, cb)
    isMonitoring = not isMonitoring
    if isMonitoring then
        StartMonitoring()
    end
    cb({ monitoring = isMonitoring })
end)

RegisterNUICallback('previewAnim', function(data, cb)
    PreviewAnimation(data.dict, data.anim)
    cb('ok')
end)

RegisterNUICallback('playAnim', function(data, cb)
    local playerPed = PlayerPedId()
    RequestAnimDict(data.dict)
    while not HasAnimDictLoaded(data.dict) do
        Wait(0)
    end
    TaskPlayAnim(playerPed, data.dict, data.anim, 1.0, 1.0, -1, 1, 0.0, false, false, false, "", false)
    cb('ok')
end)

RegisterNUICallback('addFavorite', function(data, cb)
    table.insert(favorites, { dict = data.dict, anim = data.anim })
    SendNUIMessage({ type = 'updateFavorites', favorites = favorites })
    cb('ok')
end)

RegisterNUICallback('exportAnim', function(data, cb)
    local code = string.format([[
        TaskPlayAnim(ped, "%s", "%s", 1.0, 1.0, -1, 1, 0.0, false, false, false, "", false)
    ]], data.dict, data.anim)
    print("Exported code:\n" .. code)
    cb({ code = code })
end)

RegisterNUICallback('searchAnim', function(data, cb)
    local results = Config.AnimationUtils.SearchAnimations(data.query)
    local formattedResults = {}
    for dict, anims in pairs(results) do
        for _, anim in ipairs(anims) do
            table.insert(formattedResults, { dict = dict, anim = anim })
        end
    end
    cb({ results = formattedResults })
end)

RegisterNUICallback('updateCamera', function(data, cb)
    cameraPos = { x = data.x, y = data.y, z = data.z }
    cameraFov = data.fov
    if previewCam then
        SetCamCoord(previewCam, cameraPos.x, cameraPos.y, cameraPos.z)
        SetCamFov(previewCam, cameraFov)
    end
    cb('ok')
end)

-- Cleanup
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if previewPed then
            DeletePed(previewPed)
        end
        if previewCam then
            DestroyCam(previewCam, false)
        end
        RenderScriptCams(false, false, 0, true, false)
    end
end)