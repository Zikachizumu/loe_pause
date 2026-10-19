-- GEÇİCİ ARAŞTIRMA ARACI — GTA'nın kendi ayarlarını LOE menüsünden yönetme (v5)
--
-- Bulgular: yazma çalışıyor (kök SET_COLUMN_INPUT_EVENT ve sol/sağ tuşu); GetProfileSetting yalnızca menü kapanınca
-- güncelleniyor; satır kimliği menuUniqueID'den okunuyor (tuşla gezinince değişir). Baştan gizlenen menü tuş işlemiyor
-- (v3); NUI odağı açıkken tuşlar menüye ulaşmıyor ve NUI örtüsü GTA menüsünün altında kalıyor (v4).
--
--   /loe_gtaset : (~1,5 dk) GTA menüsü görünür açılır, hazırlanınca gizlenir:
--     1) Gizliyken tuş ve kök SET_INPUT_EVENT menüyü hareket ettiriyor mu?
--     2) Tüm kategorilere girip yalnızca aşağı tuşuyla satır kimliklerini toplar (değer değiştirmez).
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
local C_DOWN, C_ACCEPT, C_BACK = 187, 201, 202

-- Ayar sütunu (columnList.1) `state` değeri kategoriye özel grafiği gösterir (2 = Audio, 5 = Graphics)
local SET = 'currentPage.columnList.1'

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

-- Dönüş değeri beklenmeyen çağrı (metodu çalıştırır)
local function sfDo(path, args)
    local okB, started = pcall(BeginScaleformMovieMethodOnFrontend, path)
    local ran = okB and started and true or false
    if ran then
        addParams(args)
        pcall(EndScaleformMovieMethod)
    end
    add('sfdo', { p = path, args = args, ran = ran })
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

local function send(extra)
    local payload = { kind = 'walk5', log = log }
    for k, v in pairs(extra or {}) do payload[k] = v end
    local ok, data = pcall(json.encode, payload)
    if not ok or type(data) ~= 'string' then
        say('Could not pack the result: ' .. tostring(data))
        return
    end
    TriggerLatentServerEvent('loe_pause:server:gfxprobe', 200000, data)
    say(('Result sent to the server (%d events, %d KB).'):format(#log, math.ceil(#data / 1024)))
end

-- Gizli mod: menü açık ama ekrana çizilmiyor (SuppressFrontendRenderingThisFrame her karede)
local hidden = false
local function hide(on)
    if on and not hidden then
        hidden = true
        CreateThread(function()
            while hidden do
                SuppressFrontendRenderingThisFrame()
                Wait(0)
            end
        end)
    elseif not on then
        hidden = false
    end
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
    hidden = false
    closeMenu()
    SetTimeout(1000, function() LoeProbe.active = false; busy = false end)
end

-- ---------------------------------------------------------------- /loe_gtaset (v5)
-- v4: NUI odağı açıkken tuşlar GTA menüsüne ulaşmıyor; NUI örtüsü GTA menüsünün ALTINDA kalıyor.
-- v5: menü önce görünür açılıp hazırlanır, SONRA gizlenir → gizliyken (a) tuş, (b) kök SET_INPUT_EVENT çalışıyor mu?
local KEYMAP_UID = '148'   -- Key Bindings: Enter ayrı tuş atama ekranını açar → girilmez
local DPAD_DOWN = 9        -- com.rockstargames.ui.game.GamePadConstants.DPADDOWN

-- Satır listesinden kategori listesine dön (Geri bazen işlenmiyor → en çok 3 deneme)
local function backOut(tag)
    for i = 1, 3 do
        press(C_BACK)
        sleep(700)
        if tostring(look(tag .. i).level) == '1' then return true end
    end
    return false
end

local function hiddenTest()
    phase('hidden-test')
    hide(true)
    sleep(500)
    local a = look('h0').uid
    press(C_DOWN)
    sleep(800)
    local b = look('h1').uid
    sfDo('SET_INPUT_EVENT', { DPAD_DOWN })
    sleep(800)
    local c = look('h2').uid
    hide(false)
    sleep(800)
    local d = look('h3').uid
    local res = { input = a ~= b, root = c ~= b, a = a, b = b, c = c, d = d }
    add('hiddenTest', res)
    return res
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
    if tostring(look('w0').level) ~= '1' and not backOut('wb') then add('err', { what = 'not-on-categories' }) return 0 end
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
                entry.back = backOut('out' .. c)
                if not entry.back then add('cat', entry) add('err', { what = 'stuck-in-rows', at = c }) break end
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

    phase('open')
    if not openSettings() then
        say('Could not open the GTA settings menu.')
        finish()
        send({ failed = 'open' })
        return
    end
    sleep(2500)
    local h = hiddenTest()
    -- Gizliyken tuş çalışıyorsa gezinme de gizli yapılır (gerçek kullanımın provası)
    if h.input then hide(true) end
    local cats = walk()
    hide(false)
    phase('close')
    finish()
    sleep(2500)
    check('final')
    beep()
    say(('Settings walk finished: %d categories, hidden input: %s, hidden root call: %s'):format(cats, tostring(h.input), tostring(h.root)))
    send({ cats = cats, hiddenInput = h.input, hiddenRoot = h.root })
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
