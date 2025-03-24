-- AnimTest Client Script
-- Load the animation list
local Config = {}
dofile("data/animations.lua")

-- State variables
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
local animFilter = nil
local targetPed = nil
local isPreviewPaused = false

-- Scenario to animation mapping
local scenarioToAnim = {
    ["WORLD_HUMAN_SIT_GROUND"] = { dict = "amb_rest_sit@world_human_fire_sit@male@male_a@exit", anim = "exit" },
    ["WORLD_HUMAN_DRINKING"] = { dict = "amb_rest_drunk@prop_human_seat_chair@porch@drinking@male_a@idle_c", anim = "idle_g" },
    -- Add more mappings as needed
}

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

-- Register help command
RegisterCommand("animhelp", function()
    print("AnimTest Commands:")
    print("/animtest - Toggle the AnimTest UI")
    print("/animtarget - Target a specific NPC to monitor its animations")
    print("UI Features: Monitor NPC animations, preview animations, search, filter, save favorites, and export code.")
    print("Hotkeys: F10 to toggle UI, 1-9 to play favorite animations.")
end, false)

-- Register targeted monitoring command
RegisterCommand("animtarget", function()
    local ped = GetTargetedPed()
    if ped then
        targetPed = ped
        print("Targeting NPC: " .. NetworkGetNetworkIdFromEntity(ped))
    else
        targetPed = nil
        print("No NPC targeted")
    end
end, false)

-- Start monitoring NPCs
function StartMonitoring()
    Citizen.CreateThread(function()
        while isMonitoring and isUIOpen do
            if targetPed and DoesEntityExist(targetPed) then
                nearbyPeds = { targetPed }
            else
                nearbyPeds = GetNearbyPeds(10.0)
            end
            local detectedAnims = {}
            for _, ped in ipairs(nearbyPeds) do
                if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                    local dict, anim = GetCurrentPedAnimation(ped)
                    if dict and anim then
                        if animFilter and not dict:lower():find(animFilter:lower()) then
                            goto continue
                        end
                        local pedId = NetworkGetNetworkIdFromEntity(ped)
                        local lastCheck = lastAnimCheck[pedId] or { dict = "", anim = "" }
                        if lastCheck.dict ~= dict or lastCheck.anim ~= anim then
                            lastAnimCheck[pedId] = { dict = dict, anim = anim }
                            table.insert(detectedAnims, { pedId = pedId, dict = dict, anim = anim })
                        end
                    end
                end
                ::continue::
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

-- Get targeted ped
function GetTargetedPed()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local _, hit, endCoords, _, entity = GetShapeTestResult(StartShapeTestRay(coords.x, coords.y, coords.z, coords.x + 10.0, coords.y, coords.z, -1, playerPed, 0))
    if hit and IsEntityAPed(entity) and not IsPedAPlayer(entity) then
        return entity
    end
    return nil
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
        for scenarioName, animData in pairs(scenarioToAnim) do
            if IsPedUsingScenario(ped, scenarioName) then
                return animData.dict, animData.anim
            end
        end
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
function PreviewAnimation(dict, anim, duration)
    if not previewPed then
        SetupPreview()
    end
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(0)
    end
    TaskPlayAnim(previewPed, dict, anim, 1.0, 1.0, duration or 2000, 1, 0.0, false, false, false, "", false)
    SendNUIMessage({ type = 'updatePlaying', anim = anim })

    Citizen.CreateThread(function()
        local endTime = GetGameTimer() + (duration or 2000)
        while GetGameTimer() < endTime do
            if isPreviewPaused then
                Wait(100)
                endTime = GetGameTimer() + (duration or 2000)
            else
                SetRenderTarget(renderTarget, true)
                RenderScriptCams(true, false, 0, true, false)
                DrawSprite("preview_window", "preview_window", 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)
                Wait(0)
            end
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
    PreviewAnimation(data.dict, data.anim, data.duration)
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

RegisterNUICallback('setFilter', function(data, cb)
    animFilter = data.filter == "" and nil or data.filter
    cb('ok')
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

RegisterNUICallback('togglePause', function(data, cb)
    isPreviewPaused = not isPreviewPaused
    cb({ paused = isPreviewPaused })
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
        SetNuiFocus(false, false)
    end
end)
