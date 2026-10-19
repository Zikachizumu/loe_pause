-- GEÇİCİ ARAŞTIRMA ARACI — GTA'nın kendi ayarlarını LOE menüsünden yönetme (v4)
--
-- Bulgular: yazma çalışıyor (kök SET_COLUMN_INPUT_EVENT ve sol/sağ tuşu); GetProfileSetting yalnızca menü kapanınca
-- güncelleniyor; satır kimliği menuUniqueID'den okunuyor (tuşla gezinince değişir); SuppressFrontendRenderingThisFrame
-- ile gizlenen menü tuş İŞLEMİYOR (v3).
--
--   /loe_gtaset : (~2 dk) GTA menüsü normal açılır, üstünü NUI'deki tam ekran "Applying GTA settings…" katmanı örter.
--     1) NUI odağı açıkken tuşlar menüyü hareket ettiriyor mu?
--     2) v2'nin Music seviyesinde bıraktığı +1 farkı geri alır (değer hâlâ 1 ise).
--     3) Tüm kategorilere girip yalnızca aşağı tuşuyla satır kimliklerini toplar (değer değiştirmez).
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
local C_DOWN, C_LEFT, C_ACCEPT, C_BACK = 187, 189, 201, 202

-- Ayar sütunu (columnList.1) `state` değeri kategoriye özel grafiği gösterir: 2 = Audio
local SET = 'currentPage.columnList.1'
local STATE_AUDIO = '2'

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

-- Tuşa basmayı taklit eder: değer 2 kare boyunca 1.0, ardından 2 kare bırakılır (art arda basışlar tek basılı
-- tutma sayılmasın)
local function press(control)
    add('press', { control = control })
    for _ = 1, 2 do
        local ok, e = pcall(SetControlValueNextFrame, G, control, 1.0)
        if not ok then add('err', { what = 'press', e = tostring(e) }) end
        Wait(0)
    end
    Wait(0)
    Wait(0)
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

local function send(extra)
    local payload = { kind = 'walk4', log = log }
    for k, v in pairs(extra or {}) do payload[k] = v end
    local ok, data = pcall(json.encode, payload)
    if not ok or type(data) ~= 'string' then
        say('Could not pack the result: ' .. tostring(data))
        return
    end
    TriggerLatentServerEvent('loe_pause:server:gfxprobe', 200000, data)
    say(('Result sent to the server (%d events, %d KB).'):format(#log, math.ceil(#data / 1024)))
end

-- NUI'deki tam ekran örtü (html: #gtaCover). Arkadaki GTA menüsü görünmez, tuşları yine işler.
local covered = false
local function cover(on)
    covered = on == true
    SendNUIMessage({ action = 'cover', on = covered, text = 'Applying GTA settings…' })
end

local function begin()
    log, t0 = {}, GetGameTimer()
    LoeProbe.active = true
    -- Güvenlik: test ne olursa olsun 240 sn sonra ESC yakalama geri gelir
    local token = {}
    LoeProbe.token = token
    SetTimeout(240000, function()
        if LoeProbe.token == token and LoeProbe.active then
            busy = false
            LoeProbe.active = false
        end
    end)
end

local function finish()
    closeMenu()
    if covered then cover(false) end
    SetNuiFocus(false, false)
    SetTimeout(1000, function() LoeProbe.active = false; busy = false end)
end

-- ---------------------------------------------------------------- /loe_gtaset (v4)
-- v3: SuppressFrontendRenderingThisFrame ile gizlenen menü tuşları İŞLEMİYOR. Bu yüzden GTA menüsü normal açılır,
-- üstünü NUI'deki tam ekran katman örter. Gerçek kullanımdaki gibi NUI odağı da açıktır (tuşlar yine çalışıyor mu?).
local MUSIC_PROFILE, MUSIC_ROW_UID = 301, '9'   -- v2: Audio satır 1 (kimlik 9) ↔ profil 301; test onu 0 → 1 yaptı
local KEYMAP_UID = '148'                         -- Key Bindings: Enter ayrı tuş atama ekranını açar → girilmez

-- İlk aşağı basış kategoriyi değiştirdi mi? Değiştirmediyse NUI odağını kapatıp bir kez daha dene.
local function inputCheck()
    phase('input-check')
    local a = look('ic0').uid
    press(C_DOWN)
    sleep(800)
    local b = look('ic1').uid
    local res = { focus = true, ok = a ~= b }
    if not res.ok then
        SetNuiFocus(false, false)
        res.focus = false
        press(C_DOWN)
        sleep(800)
        res.ok = look('ic2').uid ~= b
    end
    add('inputCheck', res)
    return res.ok
end

-- v2'nin bıraktığı Music farkını geri al (yalnızca değer hâlâ 1 ise). Kategori listesindeyken çağrılır.
local function fixMusic()
    phase('fix-music')
    local before = GetProfileSetting(MUSIC_PROFILE)
    add('music', { before = before })
    if before ~= 1 then return 'skip' end
    if not gotoState(STATE_AUDIO, 12, 'fnav') then return 'no-audio' end
    press(C_ACCEPT)
    sleep(900)
    look('fix-entered')
    press(C_DOWN)
    sleep(600)
    local row = look('fix-down').uid
    local done = row == MUSIC_ROW_UID
    if done then
        press(C_LEFT)
        sleep(800)
    end
    press(C_BACK)
    sleep(800)
    add('music', { row = row, pressed = done })
    return done and 'pressed' or 'row-mismatch'
end

-- Tüm kategorilerde satır kimliklerini topla (yalnızca aşağı tuşu; değer değişmez)
local function walkRows(first)
    local ids, times = { first }, {}
    for _ = 1, 40 do
        local t = GetGameTimer()
        press(C_DOWN)
        local u
        repeat
            Wait(0)
            u = val('menuUniqueID.toString')
        until u ~= ids[#ids] or GetGameTimer() - t > 700
        times[#times + 1] = GetGameTimer() - t
        if u == first or u == ids[#ids] then break end   -- başa döndü / ilerlemedi
        ids[#ids + 1] = u
    end
    return ids, times
end

local function walk()
    phase('walk')
    local seen, cats = {}, 0
    for c = 0, 19 do
        if not IsPauseMenuActive() then add('err', { what = 'closed', at = c }) break end
        local cat = look('cat' .. c)
        if seen[tostring(cat.uid)] then break end
        seen[tostring(cat.uid)] = true
        cats = cats + 1
        local entry = { i = c, uid = cat.uid, state = cat.state, mstate = cat.mstate }
        if tostring(cat.uid) ~= KEYMAP_UID then
            press(C_ACCEPT)
            sleep(800)
            local e = look('in' .. c)
            entry.level = e.level
            if tostring(e.level) == '2' then
                entry.rows, entry.ms = walkRows(e.uid)
                press(C_BACK)
                sleep(800)
                entry.backLevel = look('out' .. c).level
            end
        end
        add('cat', entry)
        press(C_DOWN)
        sleep(700)
    end
    return cats
end

local function run()
    begin()
    base = snap()
    add('profileStart', { list = list(base) })
    cover(true)
    SetNuiFocus(true, true)
    sleep(300)

    phase('open')
    if not openSettings() then
        say('Could not open the GTA settings menu.')
        finish()
        send({ failed = 'open' })
        return
    end
    sleep(2500)
    local inputOk = inputCheck()
    local fix, cats = 'not-run', 0
    if inputOk then
        fix = fixMusic()
        cats = walk()
    end
    phase('close')
    finish()
    sleep(2500)
    check('final')
    local music = GetProfileSetting(MUSIC_PROFILE)
    if fix == 'pressed' then fix = music == 0 and 'fixed' or 'not-saved' end
    beep()
    say(('Settings walk finished: %d categories, music fix: %s'):format(cats, fix))
    send({ cats = cats, fix = fix, inputOk = inputOk, music = music })
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
