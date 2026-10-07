-- Ayarları oyuna uygular. Yalnızca FiveM/GTA native'leriyle GERÇEKTEN değiştirilebilen ayarlar buradadır;
-- diğer her şey şemada 'native' satırı olarak işaretlidir ve yerleşik menüye yönlendirir (bkz. README → Kapsam).
--
-- İlke: oyuncunun dokunmadığı (saklı değeri olmayan ve sunucu varsayılanı da şema varsayılanına eşit olan)
-- hiçbir ayara dokunulmaz → diğer resource'larla çakışma riski en aza iner.

Apply = { read = {}, fn = {}, actions = {} }

local AIM  = { assisted_full = 0, assisted_partial = 1, free_assisted = 2, free = 3 }   -- SET_PLAYER_TARGETING_MODE
local VIEW = { near = 0, medium = 1, far = 2, first = 4 }                                -- eCamViewMode (3 = sinematik, kullanılmaz)

local state = { lastVehicle = 0, wasLoggedIn = false, frameThread = false }

--- main.lua tarafından geçersiz kılınır: menü açıkken radar ayarına dokunma (menü radarı kendisi yönetir)
function Apply.menuOpen() return false end

local function ped() return PlayerPedId() end

-- ---------------------------------------------------------------- kare döngüsü (yalnızca gerektiğinde)
local function frameNeeded()
    if Schema.rows['disp.reticle'] and Prefs.get('disp.reticle') == false then return true end
    if Schema.rows['gfx.lod'] and (Prefs.get('gfx.lod') or 1.0) > 1.0 then return true end
    return false
end

function Apply.refreshFrame()
    if state.frameThread or not frameNeeded() then return end
    state.frameThread = true
    CreateThread(function()
        while frameNeeded() do
            if Schema.rows['disp.reticle'] and Prefs.get('disp.reticle') == false then
                HideHudComponentThisFrame(14)                 -- HUD_RETICLE
            end
            local lod = Schema.rows['gfx.lod'] and Prefs.get('gfx.lod') or 1.0
            if lod > 1.0 then OverrideLodscaleThisFrame(lod + 0.0) end
            Wait(0)
        end
        state.frameThread = false
    end)
end

-- ---------------------------------------------------------------- tek tek ayarlar
Apply.fn['aim.mode'] = function(v)
    local mode = AIM[v]
    if mode then SetPlayerTargetingMode(mode) end             -- 'game' → GTA'nın o anki değerine dokunma
end

Apply.fn['cam.foot'] = function(v)
    local mode = VIEW[v]
    if mode and not IsPedInAnyVehicle(ped(), false) then SetFollowPedCamViewMode(mode) end
end

Apply.fn['cam.vehicle'] = function(v)
    local mode = VIEW[v]
    if mode and IsPedInAnyVehicle(ped(), false) then SetFollowVehicleCamViewMode(mode) end
end

Apply.fn['cam.cinematic'] = function(v)
    SetCinematicButtonActive(v == true)
end

Apply.fn['disp.radar'] = function(v)
    if Apply.menuOpen() then return end
    DisplayRadar(v == true)
end

Apply.fn['disp.reticle'] = function() Apply.refreshFrame() end
Apply.fn['gfx.lod']      = function() Apply.refreshFrame() end

Apply.fn['disp.gps'] = function(v)
    local wp = GetFirstBlipInfoId(8)                           -- 8 = waypoint
    if DoesBlipExist(wp) then SetBlipRoute(wp, v == true) end
end

Apply.fn['audio.vehradio'] = function(v)
    local on = v == true
    SetUserRadioControlEnabled(on)
    local veh = GetVehiclePedIsIn(ped(), false)
    if veh ~= 0 then
        SetVehicleRadioEnabled(veh, on)
        if not on then SetVehRadioStation(veh, 'OFF') end
    end
end

-- ---------------------------------------------------------------- pma-voice (varsa)
local function pma(fnName, ...)
    if GetResourceState('pma-voice') ~= 'started' then return nil end
    local args = { ... }
    local ok, res = pcall(function() return exports['pma-voice'][fnName](exports['pma-voice'], table.unpack(args)) end)
    if ok then return res end
    return nil
end

Apply.fn['voice.radio']     = function(v) pma('setRadioVolume', v) end
Apply.fn['voice.call']      = function(v) pma('setCallVolume', v) end
Apply.fn['voice.click_on']  = function(v) pma('setMicClickOnVolume', v) end
Apply.fn['voice.click_off'] = function(v) pma('setMicClickOffVolume', v) end
Apply.fn['voice.clicks']    = function(v) pma('setVoiceProperty', 'micClicks', v == true) end

-- Saklı değer yokken arayüzde pma-voice'un o anki (sunucu varsayılanı) değerini göster
Apply.read['voice.radio']     = function() return pma('getRadioVolume') end
Apply.read['voice.call']      = function() return pma('getCallVolume') end
Apply.read['voice.click_on']  = function() return pma('getMicClickOnVolume') end
Apply.read['voice.click_off'] = function() return pma('getMicClickOffVolume') end

-- ---------------------------------------------------------------- toplu uygulama
local function shouldApply(id)
    local def = Schema.rows[id]
    if not def then return false end
    return Prefs.values[id] ~= nil or Prefs.default(id) ~= def.default
end

function Apply.run(id)
    local fn = Apply.fn[id]
    if fn then pcall(fn, Prefs.get(id)) end
end

function Apply.all()
    for id, fn in pairs(Apply.fn) do
        if shouldApply(id) then pcall(fn, Prefs.get(id)) end
    end
    Apply.refreshFrame()
end

--- Yavaş döngü (500 ms): başka script'lerin geri aldığı ya da oyunun sıfırladığı ayarları yeniden uygular.
function Apply.tick()
    local veh = GetVehiclePedIsIn(ped(), false)

    local aim = Prefs.get('aim.mode')
    if AIM[aim] then SetPlayerTargetingMode(AIM[aim]) end

    if Schema.rows['cam.cinematic'] and Prefs.get('cam.cinematic') == false then
        SetCinematicButtonActive(false)
    end

    if Prefs.get('disp.radar') == false and not Apply.menuOpen() and not IsRadarHidden() then
        DisplayRadar(false)
    end

    if Prefs.get('disp.gps') == false then
        local wp = GetFirstBlipInfoId(8)
        if DoesBlipExist(wp) then SetBlipRoute(wp, false) end
    end

    if Prefs.get('audio.vehradio') == false and veh ~= 0 then
        SetVehicleRadioEnabled(veh, false)
    end

    -- araca yeni bindiysen varsayılan araç kamerasını uygula (sonrasında V ile serbestçe değiştirilebilir)
    if veh ~= 0 and veh ~= state.lastVehicle then
        local mode = VIEW[Prefs.get('cam.vehicle')]
        if mode then SetFollowVehicleCamViewMode(mode) end
    end
    state.lastVehicle = veh
end

CreateThread(function()
    while true do
        Wait(500)
        local logged = LocalPlayer.state.isLoggedIn == true
        if logged and not state.wasLoggedIn then
            Apply.all()
            local mode = VIEW[Prefs.get('cam.foot')]
            if mode then SetFollowPedCamViewMode(mode) end
        end
        state.wasLoggedIn = logged
        if logged then Apply.tick() end
    end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= 'pma-voice' then return end
    Wait(2500)                                                  -- pma-voice kendi varsayılanlarını yükledikten sonra
    for _, id in ipairs({ 'voice.radio', 'voice.call', 'voice.click_on', 'voice.click_off', 'voice.clicks' }) do
        if shouldApply(id) then Apply.run(id) end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- Resource durdurulursa oyuncu değiştirilmiş durumda kalmasın
    SetCinematicButtonActive(true)
    SetUserRadioControlEnabled(true)
    if Prefs.get('disp.radar') == false then DisplayRadar(true) end
end)

-- ---------------------------------------------------------------- eylemler
-- Dönüş: { ok, msg (arayüz metin anahtarı), close (menüyü kapat), values (güncel değerler) }
Apply.actions['rec.start'] = function()
    StartRecording(1)                                            -- 1 = klip kaydı
    return { ok = true, msg = 'rec_started', close = true }      -- menü kayda girmesin
end

Apply.actions['rec.save'] = function()
    StopRecordingAndSaveClip()
    return { ok = true, msg = 'rec_saved' }
end

Apply.actions['rec.discard'] = function()
    StopRecordingAndDiscardClip()
    return { ok = true, msg = 'rec_discarded' }
end

Apply.actions['pref.reset'] = function()
    Prefs.reset({ 'pref.accent', 'pref.dark', 'pref.portrait', 'pref.lang', 'pref.mapReturn' })
    return { ok = true, msg = 'reset_done', values = Prefs.snapshot() }
end
