-- GEÇİCİ ARAŞTIRMA ARACI — GTA'nın kendi ayarlarını LOE menüsünden yönetme (v7)
--
-- Bulgular: yazma çalışıyor (kök SET_COLUMN_INPUT_EVENT ve sol/sağ tuşu); GetProfileSetting yalnızca menü kapanınca
-- güncelleniyor; satır kimliği menuUniqueID'den okunuyor. Gizli menü (SuppressFrontendRenderingThisFrame) tuş işlemiyor
-- ama kök SET_INPUT_EVENT ile geziniyor (v5). NUI odağı tuşları engelliyor, NUI örtüsü GTA menüsünün altında kalıyor (v4).
--
--   /loe_gtaset : (~25 sn) GTA menüsü hiç görünmeden: Audio'ya in, satırlara gir (MENU_SHIFT_DEPTH), çağrılar arası
--                 güvenli beklemeyi ölç, SFX'i bir adım azalt, çık, kapat, ölç; sonra aynı yolla geri al.
--                 v6: gizli gezinme ve giriş/çıkış çalışıyor; art arda (14 ms) gelen ikinci gezinme yutuluyor.
--
-- Yalnızca Config.GfxProbe.ace yetkisi olanlar çalıştırabilir (sunucu doğrular). Sonuç sunucuda resource klasörüne
-- gfxprobe_*.json olarak yazılır. Araştırma bitince bu dosya, server/main.lua'daki karşılığı ve Config.GfxProbe kaldırılır.

LoeProbe = { active = false }   -- client/main.lua: true iken ESC yakalama döngüsü yerleşik menüye dokunmaz

local P = Config.GfxProbe or {}
if P.enabled ~= true then return end

local PROFILE_MAX = 1200
local MAX_LOG = 4000
local SETTINGS_MENU = (Config.Native and Config.Native.settings and Config.Native.settings.menu) or 'FE_MENU_VERSION_LANDING_MENU'


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
local function closeMenu()
    for _ = 1, 40 do
        if not IsPauseMenuActive() then break end
        pcall(SetFrontendActive, false)
        Wait(50)
    end
end

local function send(extra)
    local payload = { kind = 'hidden7', log = log }
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

-- ---------------------------------------------------------------- /loe_gtaset (v6)
-- v5: gizliyken tuş işlemiyor ama kök SET_INPUT_EVENT(aşağı) kategori değiştiriyor ve oyun yeni sayfayı yüklüyor.
-- v6: menü BAŞTAN SONA gizli; yalnızca kök metodlar: SET_INPUT_EVENT (8 yukarı, 9 aşağı, 10 sol, 11 sağ) ve
-- MENU_SHIFT_DEPTH(+1 / -1) (fareyle tıklama da bunu kullanır). Audio'da SFX bir adım sola, menü kapanınca ölçülür,
-- sonra aynı yolla geri alınır.
local DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT = 8, 9, 10, 11
local SFX_PROFILE = 300   -- v2: Audio satır 0 (kimlik 8) ↔ profil 300
local STATE_AUDIO = '2'

-- Kök gezinme: çağır, menuUniqueID değişene kadar (en çok 700 ms) bekle
local function nav(dir, tag)
    local before = val('menuUniqueID.toString')
    local t = GetGameTimer()
    sfDo('SET_INPUT_EVENT', { dir })
    local u
    repeat
        Wait(0)
        u = val('menuUniqueID.toString')
    until u ~= before or GetGameTimer() - t > 700
    add('nav', { tag = tag, dir = dir, from = before, to = u, ms = GetGameTimer() - t })
    return u ~= before
end

local function depth(dir, tag)
    sfDo('MENU_SHIFT_DEPTH', { dir, false, false })
    sleep(500)
    return look(tag)
end

local function openHidden()
    hide(true)
    ActivateFrontendMenu(GetHashKey(SETTINGS_MENU), true, -1)
    local deadline = GetGameTimer() + 6000
    while GetGameTimer() < deadline do
        if IsPauseMenuActive() and select(3, sfRead('menuUniqueID.toString')) == 'ok' then
            sleep(300)
            return true
        end
        Wait(0)
    end
    return false
end

-- Gizli açılıştan Audio satırlarına gir. Dönüş: true / hata adı
local function enterAudio(tag)
    if not openHidden() then return 'open' end
    look(tag .. '-opened')
    local found = false
    for i = 0, 12 do
        if look(tag .. '-c' .. i).state == STATE_AUDIO then found = true break end
        nav(DPAD_DOWN, tag .. '-cat')
        sleep(250)
    end
    if not found then return 'no-audio' end
    local e = depth(1, tag .. '-enter')
    if tostring(e.level) ~= '2' then return 'enter' end
    return true
end

local function leave(tag)
    local l = depth(-1, tag .. '-leave')
    hide(false)
    closeMenu()
    return tostring(l.level) == '1'
end

local function run()
    begin()
    base = snap()
    add('profileStart', { list = list(base) })

    -- 1) gir, satırlarda aşağı/yukarı, SFX sola, çık, kapat
    phase('write')
    local sfx0 = GetProfileSetting(SFX_PROFILE)
    local r = enterAudio('w')
    local res = { enter = r, sfx0 = sfx0 }
    if r == true then
        -- v6: aşağıdan hemen sonra (14 ms) gelen yukarı yutuldu → çağrılar arası en kısa güvenli bekleme ölçülür
        local speeds = {}
        for _, gap in ipairs({ 50, 100, 150, 250 }) do
            local ok = 0
            for _ = 1, 3 do
                if nav(DPAD_DOWN, 'spd' .. gap) then ok = ok + 1 end
                sleep(gap)
            end
            speeds[#speeds + 1] = { gap = gap, ok = ok }
        end
        add('speed', { list = speeds })
        sleep(250)
        res.rowUp = nav(DPAD_UP, 'row-up')
        sleep(250)
        -- SFX satırına (kimlik 8) yalnızca aşağı yönle, 250 ms aralıkla git (liste başa döner)
        for _ = 1, 15 do
            if val('menuUniqueID.toString') == '8' then break end
            nav(DPAD_DOWN, 'to-sfx')
            sleep(250)
        end
        res.row0 = val('menuUniqueID.toString')
        res.wrote = sfx0 >= 1 and res.row0 == '8'
        if res.wrote then
            sfDo('SET_INPUT_EVENT', { DPAD_LEFT })
            sleep(700)
        end
        res.left = leave('w')
    else
        hide(false)
        closeMenu()
    end
    sleep(2000)
    check('after-write')
    res.sfx1 = GetProfileSetting(SFX_PROFILE)
    add('write', res)

    -- 2) geri al (yalnızca gerçekten değiştiyse)
    phase('restore')
    local restored = 'not-needed'
    if res.wrote == true and res.sfx1 == sfx0 - 1 then
        sleep(1000)
        local r2 = enterAudio('r')
        if r2 == true and val('menuUniqueID.toString') == '8' then
            sfDo('SET_INPUT_EVENT', { DPAD_RIGHT })
            sleep(700)
            leave('r')
            sleep(2000)
            restored = GetProfileSetting(SFX_PROFILE) == sfx0 and 'ok' or 'not-saved'
        else
            hide(false)
            closeMenu()
            restored = 'failed:' .. tostring(r2)
        end
    end
    add('restore', { result = restored })

    phase('close')
    finish()
    sleep(2500)
    check('final')
    beep()
    local saved = res.wrote == true and res.sfx1 == sfx0 - 1
    say(('Hidden write test: enter=%s, saved=%s, restore=%s'):format(tostring(r), tostring(saved), restored))
    send({ enter = tostring(r), saved = saved, restored = restored })
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
