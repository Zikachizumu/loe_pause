-- GEÇİCİ ARAŞTIRMA ARACI — GTA'nın kendi ayarlarını LOE menüsünden DEĞİŞTİREBİLİR miyiz?
--
--   /loe_gtaset : otomatik test (~25 sn). GTA ayar menüsünü açar, Audio kategorisine iner ve SFX seviyesini bir adım
--                 artırıp geri alır. İki yol denenir:
--                   1) AS yolu: ayar sütununun kendi metodları (SET_HIGHLIGHT + SET_INPUT_EVENT). Fareyle ok tıklaması da
--                      aynı kodu çalıştırır: satır stepVal(±1) → setPref → oyuna SET_PAUSE_MENU_PREF.
--                   2) Girdi yolu: sütuna Enter ile girip sağ/sol tuşu (SetControlValueNextFrame).
--                 Her adımda GetProfileSetting farkı kaydedilir (değer anında mı, menü kapanınca mı güncelleniyor?).
--                 Sonda Graphics kategorisinde video belleği metninin okunup okunamadığına bakar (değer değiştirmez).
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
local C_DOWN, C_UP, C_LEFT, C_RIGHT, C_ACCEPT, C_BACK = 187, 188, 189, 190, 201, 202
-- com.rockstargames.ui.game.GamePadConstants
local DPAD_LEFT, DPAD_RIGHT = 10, 11

-- Sayfadaki sütunlar: 0 = kategori listesi (PAUSE_MENU_FREE_MODE), 1 = ayar satırları (PAUSE_MENU_SETTINGS)
local CAT = 'currentPage.columnList.0'
local SET = 'currentPage.columnList.1'
-- Ayar sütununun `state` değeri kategoriye özel grafiği gösterir: 2 = Audio, 5 = Graphics (önceki test: 1,0,0,2,0,0,5,4)
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
-- Dönüş değeri olan çağrı. undefined dönen çağrı hiç "hazır" olmaz → 'timeout'.
local function sfRead(path, ints)
    local okB, started = pcall(BeginScaleformMovieMethodOnFrontend, path)
    if not okB then return nil, nil, 'ERR ' .. tostring(started) end
    if not started then return nil, nil, 'begin-false' end
    for _, v in ipairs(ints or {}) do pcall(ScaleformMovieMethodAddParamInt, v) end
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

-- Dönüş değeri beklenmeyen çağrı (metodu çalıştırır)
local function sfDo(path, ints)
    local okB, started = pcall(BeginScaleformMovieMethodOnFrontend, path)
    if okB and started then
        for _, v in ipairs(ints or {}) do pcall(ScaleformMovieMethodAddParamInt, v) end
        pcall(EndScaleformMovieMethod)
    end
    add('sfdo', { p = path, args = ints, started = okB and started == true })
    return okB and started == true
end

local function readStr(path, ints)
    local s, i, st = sfRead(path, ints)
    add('path', { p = path, args = ints, s = s, i = i, st = st })
    return s, i, st
end

-- Menünün o anki durumu (kategori/satır seçimi, sütun durumu, odak)
local last = {}
local function look(tag)
    local d = { tag = tag, active = IsPauseMenuActive(), fe = GetPauseMenuState() }
    local function put(key, path, ints)
        local s, i, st = sfRead(path, ints)
        d[key] = st == 'ok' and (s ~= nil and s ~= '' and s or i) or st
    end
    put('cat', CAT .. '.model.getCurrentSelection', { 0 })
    put('row', SET .. '.model.getCurrentSelection', { 0 })
    put('col0', 'GET_COLUMN_SELECTION', { 0 })
    put('col1', 'GET_COLUMN_SELECTION', { 1 })
    put('state', SET .. '.state.toString')
    put('focus', SET .. '.columnIsFocused.toString')
    add('look', d)
    last = d
    return d
end

local base = {}
local function check(tag)
    local s = snap()
    add('profile', { tag = tag, diff = diff(base, s) })
    return s
end

-- ---------------------------------------------------------------- menü aç / kapat
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

local function send(extra)
    local payload = { kind = 'write', log = log }
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
    log, t0, last = {}, GetGameTimer(), {}
    LoeProbe.active = true
    -- Güvenlik: test ne olursa olsun 120 sn sonra ESC yakalama geri gelir
    local token = {}
    LoeProbe.token = token
    SetTimeout(120000, function()
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

-- Kategori listesinde aşağı inerek ayar sütununun durumu `want` olana kadar git (en çok `max` adım)
local function gotoState(want, max)
    for step = 0, max do
        if not IsPauseMenuActive() then return false end
        if look('nav' .. step).state == want then return true end
        press(C_DOWN)
        sleep(800)
    end
    return look('navEnd').state == want
end

-- AS yolu: satırı vurgula, bir adım sağa/sola
local function asStep(row, dir, tag)
    sfDo(SET .. '.SET_HIGHLIGHT', { row })
    sleep(150)
    sfDo(SET .. '.SET_INPUT_EVENT', { dir })
    sleep(900)
    look(tag)
    check(tag)
end

-- ---------------------------------------------------------------- /loe_gtaset
local function run()
    begin()
    base = snap()
    add('profileStart', { list = list(base) })

    phase('open')
    if not openSettings() then
        say('Could not open the GTA settings menu.')
        finish()
        send({ failed = 'open' })
        return
    end
    sleep(2500)          -- LANDING_MENU doğrudan Ayarlar sayfasını açar
    look('opened')

    phase('nav-audio')
    local audio = gotoState(STATE_AUDIO, 8)
    add('audio', { found = audio })
    if not audio then
        say('Audio category not found, writes skipped.')
    else
        local catAudio = last.cat

        -- 1) AS yolu (sütuna girmeden): satır 0 = SFX Volume
        phase('as-row0')
        asStep(0, DPAD_RIGHT, 'as0-right')
        asStep(0, DPAD_LEFT, 'as0-left')

        -- 2) Girdi yolu: Enter ile sütuna gir, sağ/sol
        phase('enter')
        press(C_ACCEPT)
        sleep(900)
        look('entered')
        phase('input-row')
        press(C_RIGHT); sleep(900); look('in-right'); check('in-right')
        press(C_LEFT);  sleep(900); look('in-left');  check('in-left')

        -- 3) AS yolu, sütun odaktayken: satır 1 = Music Volume
        phase('as-row1')
        asStep(1, DPAD_RIGHT, 'as1-right')
        asStep(1, DPAD_LEFT, 'as1-left')
        sfDo(SET .. '.SET_HIGHLIGHT', { 0 })
        sleep(300)

        phase('back')
        press(C_BACK)
        sleep(900)
        look('back')
        add('audioCat', { cat = catAudio })

        -- 4) Graphics: video belleği metni okunabiliyor mu? (değer değiştirmez)
        if IsPauseMenuActive() then
            phase('nav-gfx')
            local gfx = gotoState(STATE_GFX, 5)
            add('gfx', { found = gfx })
            if gfx then
                sleep(600)
                phase('gfx-read')
                for _, p in ipairs({
                    { SET .. '.customMC.toString' },
                    { SET .. '.customMC.titleTF.toString' },
                    { SET .. '.customMC.titleTF.text.substr', { 0, 63 } },
                    { SET .. '.customMC.titleTF.htmlText.substr', { 0, 63 } },
                    { SET .. '.vidMemBar.toString' },
                    { SET .. '.model.getCurrentSelection', { 0 } },
                }) do
                    readStr(p[1], p[2])
                end
            end
        end
    end

    phase('close')
    finish()
    sleep(2000)
    check('after-close')
    sleep(3000)
    check('after-close-5s')
    beep()
    say('Settings write test finished.')
    send({ audio = audio })
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
