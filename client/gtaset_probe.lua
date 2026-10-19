-- GEÇİCİ ARAŞTIRMA ARACI — GTA'nın kendi ayarlarını LOE menüsünden DEĞİŞTİREBİLİR miyiz? (v2)
--
--   /loe_gtaset : otomatik test (~45 sn). GTA ayar menüsü görünür açılır:
--     1) Audio'ya iner, satır listesine girer; ilk satırların ayar kimliklerini okur (menuUniqueID).
--     2) Yazma yolu A (kök metod, oyunun tuş işleyişinin kullandığı): SET_COLUMN_INPUT_EVENT(1, sol) → satır 0 (SFX).
--     3) Yazma yolu B (girdi): aşağı + sol tuşu → satır 1 (Music).
--     4) Menüyü kapatır, profil farkını ölçer (GetProfileSetting anlık mı, kapanınca mı güncelleniyor?).
--     5) Değişiklik olduysa menüyü yeniden açıp iki adımı aynı yollarla tersine çevirir (sağ), yine ölçer.
--     6) Graphics satırlarının ayar kimliklerini okur (yalnızca vurgu, değer değiştirmez).
--
-- Yalnızca Config.GfxProbe.ace yetkisi olanlar çalıştırabilir (sunucu doğrular). Sonuç sunucuda resource klasörüne
-- gfxprobe_*.json olarak yazılır. Araştırma bitince bu dosya, server/main.lua'daki karşılığı ve Config.GfxProbe kaldırılır.

LoeProbe = { active = false }   -- client/main.lua: true iken ESC yakalama döngüsü yerleşik menüye dokunmaz

local P = Config.GfxProbe or {}
if P.enabled ~= true then return end

local PROFILE_MAX = 1200
local MAX_LOG = 4000
local SETTINGS_MENU = (Config.Native and Config.Native.settings and Config.Native.settings.menu) or 'FE_MENU_VERSION_LANDING_MENU'

-- Kontrol kimlikleri (INPUT_FRONTEND_*), girdi grubu 2 (önceki testte menüyü hareket ettiren grup)
local G = 2
local C_DOWN, C_LEFT, C_RIGHT, C_ACCEPT, C_BACK = 187, 189, 190, 201, 202
-- com.rockstargames.ui.game.GamePadConstants
local DPAD_LEFT, DPAD_RIGHT = 10, 11

-- Ayar sütunu (columnList.1) `state` değeri kategoriye özel grafiği gösterir: 2 = Audio, 5 = Graphics
local SET = 'currentPage.columnList.1'
local STATE_AUDIO, STATE_GFX = '2', '5'

local log, t0, busy = {}, 0, false

local function now() return GetGameTimer() - t0 end

local function add(kind, data)
    if #log >= MAX_LOG then return end
    data = data or {}
    data.t, data.k = now(), kind
    log[#log + 1] = data
end

local function say(msg)
    print('[loe_gtaset] ' .. msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local function beep()
    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

local function phase(name)
    add('phase', { name = name })
    print('[loe_gtaset] phase: ' .. name)
end

local function sleep(ms)
    local s = GetGameTimer()
    repeat Wait(0) until GetGameTimer() - s >= ms
end

-- Tuşa basmayı taklit eder: değer 2 kare boyunca 1.0
local function press(control)
    add('press', { control = control })
    for _ = 1, 2 do
        local ok, e = pcall(SetControlValueNextFrame, G, control, 1.0)
        if not ok then add('err', { what = 'press', e = tostring(e) }) end
        Wait(0)
    end
end

-- ---------------------------------------------------------------- profil ayarları (GET_PROFILE_SETTING)
local function snap()
    local s = {}
    pcall(function()
        for id = 0, PROFILE_MAX do
            local v = GetProfileSetting(id)
            if type(v) == 'number' and v ~= 0 then s[id] = v end
        end
    end)
    return s
end

local function diff(a, b)
    local d = {}
    for id = 0, PROFILE_MAX do
        local x, y = a[id] or 0, b[id] or 0
        if x ~= y then d[#d + 1] = { id, x, y } end
    end
    return d
end

local function list(s)
    local out = {}
    for id = 0, PROFILE_MAX do
        if s[id] then out[#out + 1] = { id, s[id] } end
    end
    return out
end

-- ---------------------------------------------------------------- scaleform (oyun "TIMELINE." önekini kendisi ekler)
local function addParams(args)
    for _, v in ipairs(args or {}) do
        if type(v) == 'boolean' then pcall(ScaleformMovieMethodAddParamBool, v)
        else pcall(ScaleformMovieMethodAddParamInt, v) end
    end
end

-- Dönüş değeri olan çağrı. undefined dönen çağrı hiç "hazır" olmaz → 'timeout'.
local function sfRead(path, args)
    local okB, started = pcall(BeginScaleformMovieMethodOnFrontend, path)
    if not okB then return nil, nil, 'ERR ' .. tostring(started) end
    if not started then return nil, nil, 'begin-false' end
    addParams(args)
    local okE, h = pcall(EndScaleformMovieMethodReturnValue)
    if not okE or type(h) ~= 'number' then return nil, nil, 'end' end
    local s = GetGameTimer()
    while GetGameTimer() - s < 250 do
        local okR, r = pcall(IsScaleformMovieMethodReturnValueReady, h)
        if okR and r then
            local o1, str = pcall(GetScaleformMovieMethodReturnValueString, h)
            local o2, int = pcall(GetScaleformMovieMethodReturnValueInt, h)
            return o1 and str or nil, o2 and int or nil, 'ok'
        end
        Wait(0)
    end
    return nil, nil, 'timeout'
end

local function val(path, args)
    local s, i, st = sfRead(path, args)
    if st ~= 'ok' then return st end
    if s ~= nil and s ~= '' then return s end
    return i
end

-- Dönüş değeri beklenmeyen çağrı (metodu çalıştırır)
local function sfDo(path, args)
    local okB, started = pcall(BeginScaleformMovieMethodOnFrontend, path)
    local ran = okB and started and true or false
    if ran then
        addParams(args)
        pcall(EndScaleformMovieMethod)
    end
    add('sfdo', { p = path, args = args, ran = ran, ret = tostring(started) })
    return ran
end

-- Menünün o anki durumu
local function look(tag)
    local d = { tag = tag, active = IsPauseMenuActive(), fe = GetPauseMenuState() }
    d.state = val(SET .. '.state.toString')
    d.focus = val(SET .. '.columnIsFocused.toString')
    d.uid = val('menuUniqueID.toString')
    d.mstate = val('menuState.toString')
    d.level = val('menuLevel.toString')
    add('look', d)
    return d
end

local base = {}
local function check(tag)
    local s = snap()
    add('profile', { tag = tag, diff = diff(base, s) })
    return s
end

-- ---------------------------------------------------------------- menü aç / kapat / gezin
local function openSettings()
    ActivateFrontendMenu(GetHashKey(SETTINGS_MENU), true, -1)
    local deadline = GetGameTimer() + 3000
    while not IsPauseMenuActive() and GetGameTimer() < deadline do Wait(0) end
    return IsPauseMenuActive()
end

local function closeMenu()
    for _ = 1, 40 do
        if not IsPauseMenuActive() then break end
        pcall(SetFrontendActive, false)
        Wait(50)
    end
end

-- Kategori listesinde aşağı inerek ayar sütununun durumu `want` olana kadar git (en çok `max` adım)
local function gotoState(want, max, tag)
    for step = 0, max do
        if not IsPauseMenuActive() then return false end
        if look(tag .. step).state == want then return true end
        press(C_DOWN)
        sleep(800)
    end
    return false
end

local function openAudio(tag)
    if not openSettings() then return false end
    sleep(2500)          -- LANDING_MENU doğrudan Ayarlar sayfasını açar
    return gotoState(STATE_AUDIO, 8, tag)
end

-- Satır listesindeyken i. satırı vurgula (kök metod) ve kimliğini oku. scriptSetUnqID=true → menuUniqueID = satır kimliği
local function rowIds(tag, n)
    local ids = {}
    for i = 0, n - 1 do
        sfDo('SET_COLUMN_HIGHLIGHT', { 1, i, true, false })
        sleep(120)
        ids[#ids + 1] = val('menuUniqueID.toString')
    end
    add('rowIds', { tag = tag, ids = ids })
    sfDo('SET_COLUMN_HIGHLIGHT', { 1, 0, true, false })
    sleep(300)
    return ids
end

local function send(extra)
    local payload = { kind = 'write2', log = log }
    for k, v in pairs(extra or {}) do payload[k] = v end
    local ok, data = pcall(json.encode, payload)
    if not ok or type(data) ~= 'string' then
        say('Could not pack the result: ' .. tostring(data))
        return
    end
    TriggerLatentServerEvent('loe_pause:server:gfxprobe', 200000, data)
    say(('Result sent to the server (%d events, %d KB).'):format(#log, math.ceil(#data / 1024)))
end

local function begin()
    log, t0 = {}, GetGameTimer()
    LoeProbe.active = true
    -- Güvenlik: test ne olursa olsun 150 sn sonra ESC yakalama geri gelir
    local token = {}
    LoeProbe.token = token
    SetTimeout(150000, function()
        if LoeProbe.token == token and LoeProbe.active then
            busy = false
            LoeProbe.active = false
        end
    end)
end

local function finish()
    closeMenu()
    SetTimeout(1000, function() LoeProbe.active = false; busy = false end)
end

-- ---------------------------------------------------------------- /loe_gtaset
local function run()
    begin()
    base = snap()
    add('profileStart', { list = list(base) })

    phase('open')
    local audio = openAudio('nav')
    add('audio', { found = audio })
    if not audio then
        say('Audio category not found, writes skipped.')
        finish()
        send({ audio = false })
        return
    end

    phase('enter')
    press(C_ACCEPT)
    sleep(900)
    look('entered')
    rowIds('audio', 12)

    -- A) kök metod: oyunun kendi tuş işleyişi bu yolu kullanır → sütun SET_INPUT_EVENT → satır stepVal → setPref
    phase('write-as')
    sfDo('SET_COLUMN_INPUT_EVENT', { 1, DPAD_LEFT })
    sleep(1000)
    look('as')
    check('as-live')

    -- B) girdi: bir satır aşağı (Music), sol
    phase('write-input')
    press(C_DOWN)
    sleep(700)
    look('down')
    press(C_LEFT)
    sleep(1000)
    look('input')
    check('input-live')

    phase('back')
    press(C_BACK)
    sleep(1000)
    look('back')
    check('back')

    phase('close')
    closeMenu()
    sleep(2000)
    local closed = check('closed')
    local changed = #diff(base, closed) > 0
    add('changed', { any = changed })

    -- Geri al: aynı iki adım ters yönde (çalışmayan yolun tersi de etkisizdir)
    phase('restore')
    sleep(1000)
    if openAudio('nav2') then
        press(C_ACCEPT)
        sleep(900)
        look('entered2')
        -- Profil yalnızca oyundan çıkınca güncelleniyor olabilir → değişiklik görünmese de her zaman geri al
        sfDo('SET_COLUMN_HIGHLIGHT', { 1, 0, true, false })
        sleep(300)
        sfDo('SET_COLUMN_INPUT_EVENT', { 1, DPAD_RIGHT })
        sleep(800)
        press(C_DOWN)
        sleep(700)
        press(C_RIGHT)
        sleep(900)
        look('restored')
        press(C_BACK)
        sleep(1000)

        -- Graphics satır kimlikleri (yalnızca vurgu)
        phase('gfx-ids')
        if IsPauseMenuActive() and gotoState(STATE_GFX, 5, 'gnav') then
            press(C_ACCEPT)
            sleep(900)
            look('gfx-entered')
            rowIds('graphics', 24)
            press(C_BACK)
            sleep(900)
        end
    else
        add('err', { what = 'reopen' })
    end

    phase('close2')
    finish()
    sleep(2500)
    check('final')
    beep()
    say('Settings write test finished.')
    send({ audio = true, changed = changed })
end

-- ---------------------------------------------------------------- komut (sunucu yetkiyi onaylayınca başlar)
local function request()
    if busy then say('A test is already running.') return end
    if (Apply and Apply.menuOpen and Apply.menuOpen()) or IsPauseMenuActive() then
        say('Close the menu first, then run the command again.')
        return
    end
    busy = true
    TriggerServerEvent('loe_pause:server:gfxprobeAsk', 'write')
    SetTimeout(5000, function()
        if busy and not LoeProbe.active then busy = false end   -- sunucu yanıt vermedi / yetki yok
    end)
end

RegisterNetEvent('loe_pause:client:gfxprobeGo', function(_, allowed)
    if not allowed then
        busy = false
        say('You are not allowed to run this test.')
        return
    end
    CreateThread(function()
        Wait(1200)   -- sohbet / F8 kapansın
        if IsPauseMenuActive() or (Apply and Apply.menuOpen and Apply.menuOpen()) then
            busy = false
            say('Cannot start while a menu is open.')
            return
        end
        local ok, err = pcall(run)
        if not ok then
            add('err', { what = 'run', e = tostring(err) })
            finish()
            say('Test error: ' .. tostring(err))
            send({ error = tostring(err) })
        end
    end)
end)

RegisterNetEvent('loe_pause:client:gfxprobeSaved', function(name)
    if name then say('Saved on the server: ' .. tostring(name)) else say('The server could not save the result.') end
end)

RegisterCommand('loe_gtaset', request, false)
