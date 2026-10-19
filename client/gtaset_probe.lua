-- GEÇİCİ ARAŞTIRMA ARACI — GTA'nın kendi ayarlarını LOE menüsünden yönetme (v8: eşleştirme)
--
-- Bulgular: GTA ayar menüsü gizliyken (SuppressFrontendRenderingThisFrame) tuş işlemiyor ama kök scaleform metodları
-- çalışıyor: SET_INPUT_EVENT (8/9 gezinme, 10/11 değer) ve MENU_SHIFT_DEPTH(±1) (satırlara gir/çık). Değer menü kapanınca
-- profile yazılıyor (GetProfileSetting); satır kimliği menuUniqueID'den okunuyor; çağrılar arası 50 ms yetiyor (v7).
--
--   /loe_gtaset : (~4-5 dk, GTA menüsü hiç görünmez) Controls, Keyboard/Mouse, Audio, Camera, Display satırlarını
--                 tek tek bir adım değiştirip geri alır; her satırın profil kimliğini ve adım ölçeğini kaydeder.
--
-- Yalnızca Config.GfxProbe.ace yetkisi olanlar çalıştırabilir (sunucu doğrular). Sonuç sunucuda resource klasörüne
-- gfxprobe_*.json olarak yazılır. Araştırma bitince bu dosya, server/main.lua'daki karşılığı ve Config.GfxProbe kaldırılır.

LoeProbe = { active = false }   -- client/main.lua: true iken ESC yakalama döngüsü yerleşik menüye dokunmaz

local P = Config.GfxProbe or {}
if P.enabled ~= true then return end

local PROFILE_MAX = 1200
local MAX_LOG = 6000
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

-- ---------------------------------------------------------------- menü aç / kapat / gezin
local function closeMenu()
    for _ = 1, 40 do
        if not IsPauseMenuActive() then break end
        pcall(SetFrontendActive, false)
        Wait(50)
    end
end

local function send(extra)
    local payload = { kind = 'map8', log = log }
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
    -- Güvenlik: test ne olursa olsun 10 dk sonra ESC yakalama geri gelir
    local token = {}
    LoeProbe.token = token
    SetTimeout(600000, function()
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

-- ---------------------------------------------------------------- /loe_gtaset (v8: satır ↔ profil eşleştirmesi)
-- v7: gizli akış çalışıyor (kök SET_INPUT_EVENT + MENU_SHIFT_DEPTH), değer menü kapanınca profile yazılıyor,
-- çağrılar arası 50 ms yetiyor. v8: Controls, Keyboard/Mouse, Audio, Camera, Display kategorilerinde her satırı bir
-- adım değiştirip menüyü kapatır, profil farkından satırın profil kimliğini ve adım ölçeğini çıkarır, sonra geri alır.
-- Değişmeyen satır (en uçta ya da profile bağlı değil) ters yönle bir kez daha denenir.
local DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT = 9, 10, 11
local GAP = 60
local MAP_CATS = { ['0'] = true, ['1'] = true, ['3'] = true, ['4'] = true, ['5'] = true }

local function uid() return val('menuUniqueID.toString') end
local function opposite(dir) return dir == DPAD_RIGHT and DPAD_LEFT or DPAD_RIGHT end

-- Kök gezinme: çağır, menuUniqueID değişene kadar bekle. Menü meşgulken (ör. satırlara girip çıktıktan hemen sonra)
-- çağrı yutulabiliyor (v8 ilk deneme) → en çok 3 deneme. Yalnızca başarısızlık kaydedilir.
local function nav(dir, tag)
    local before = uid()
    for try = 1, 3 do
        local t = GetGameTimer()
        pcall(BeginScaleformMovieMethodOnFrontend, 'SET_INPUT_EVENT')
        pcall(ScaleformMovieMethodAddParamInt, dir)
        pcall(EndScaleformMovieMethod)
        local u
        repeat
            Wait(0)
            u = uid()
        until u ~= before or GetGameTimer() - t > 400
        if u ~= before then
            if try > 1 then add('navRetry', { tag = tag, tries = try }) end
            return true
        end
        sleep(150)
    end
    add('navFail', { tag = tag, dir = dir, at = before })
    return false
end

local function level() return tostring(val('menuLevel.toString')) end

-- Satırlara gir (+1) / çık (-1). Seviye değiştikten sonra menü kısa süre gezinmeyi yutuyor → 400 ms bekle (v7'de 500 ms
-- beklemeyle sorun yoktu)
local function depth(dir)
    sfDo('MENU_SHIFT_DEPTH', { dir, false, false })
    local want = dir > 0 and '2' or '1'
    local t = GetGameTimer()
    repeat Wait(0) until level() == want or GetGameTimer() - t > 800
    sleep(400)
    return level() == want
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

-- Önce kapat, SONRA gizlemeyi bırak (menü bir kare bile görünmesin)
local function shut()
    closeMenu()
    hide(false)
end

-- Açılışta Controls seçili; kategori listesinde aşağı inerek `cat`'e git
local function gotoCat(cat)
    for _ = 0, 14 do
        if uid() == cat then return true end
        nav(DPAD_DOWN, 'cat')
        sleep(GAP)
    end
    return uid() == cat
end

local function gotoRow(row)
    for _ = 0, 45 do
        if uid() == row then return true end
        nav(DPAD_DOWN, 'row')
        sleep(GAP)
    end
    return uid() == row
end

-- Gizli oturum: aç, kategoriye gir, adımları uygula ({ row, dir }), çık, kapat
local function session(cat, steps)
    local ok = openHidden() and gotoCat(cat) and depth(1)
    if ok then
        for _, s in ipairs(steps) do
            if gotoRow(s.row) then
                sfDo('SET_INPUT_EVENT', { s.dir })
                sleep(150)
            else
                ok = false
            end
        end
        depth(-1)
    end
    if not ok then add('sessionFail', { cat = cat, look = look('fail') }) end
    shut()
    return ok
end

-- Menü kapanınca profil güncellenir: en az 600 ms bekle, iki ölçüm aynı olunca (en çok 2 sn) kabul et
local function settle()
    local t, prev = GetGameTimer(), nil
    while true do
        sleep(300)
        local s = snap()
        if prev and #diff(prev, s) == 0 and GetGameTimer() - t >= 600 then return s end
        if GetGameTimer() - t > 2000 then return s end
        prev = s
    end
end

-- Satır listelerini topla (tek gizli oturum, yalnızca aşağı)
local function collectRows()
    phase('rows')
    local cats = {}
    if not openHidden() then shut() return cats end
    local seen = {}
    for _ = 0, 14 do
        local c = uid()
        if seen[c] then break end
        seen[c] = true
        if MAP_CATS[c] and depth(1) then
            local first = uid()
            local rows = { first }
            for _ = 1, 45 do
                if not nav(DPAD_DOWN, 'collect') then break end
                sleep(GAP)
                local u = uid()
                if u == first then break end
                rows[#rows + 1] = u
            end
            depth(-1)
            cats[#cats + 1] = { cat = c, rows = rows }
            add('rows', { cat = c, rows = rows })
        end
        nav(DPAD_DOWN, 'next-cat')
        sleep(GAP)
    end
    shut()
    return cats
end

local cur = {}          -- profil ayarlarının bilinen güncel durumu
local pending           -- geri alınması gereken son değişiklik: { cat, row, dir, ids = { { id, eski, yeni } } }
local fails = 0

local function restoredOk(p)
    for _, x in ipairs(p.ids) do
        if (cur[x[1]] or 0) ~= x[2] then return false end
    end
    return true
end

local function restoreAlone()
    local p = pending
    pending = nil
    session(p.cat, { { row = p.row, dir = opposite(p.dir) } })
    cur = settle()
    add('restore', { cat = p.cat, row = p.row, ok = restoredOk(p) })
end

-- Satırı `dir` yönünde bir adım değiştir; aynı kategorideki önceki değişikliği aynı oturumda geri al
local function probeRow(it, dir)
    local steps, restoring = {}, nil
    if pending and pending.cat == it.cat then
        restoring, pending = pending, nil
        steps[1] = { row = restoring.row, dir = opposite(restoring.dir) }
    elseif pending then
        restoreAlone()
    end
    steps[#steps + 1] = { row = it.row, dir = dir }
    local before = cur
    local ok = session(it.cat, steps)
    cur = settle()
    local own = {}
    if restoring then for _, x in ipairs(restoring.ids) do own[x[1]] = true end end
    local mine = {}
    for _, x in ipairs(diff(before, cur)) do
        if not own[x[1]] then mine[#mine + 1] = x end
    end
    if restoring then add('restore', { cat = restoring.cat, row = restoring.row, ok = restoredOk(restoring) }) end
    fails = ok and 0 or fails + 1
    return ok, mine
end

local function run()
    begin()
    base = snap()
    cur = base
    pending, fails = nil, 0
    add('profileStart', { list = list(base) })

    local cats = collectRows()
    local items = {}
    for _, c in ipairs(cats) do
        for _, r in ipairs(c.rows) do items[#items + 1] = { cat = c.cat, row = r } end
    end
    add('items', { n = #items })

    phase('map')
    local results, retry, aborted = {}, {}, false
    for _, it in ipairs(items) do
        local ok, mine = probeRow(it, DPAD_RIGHT)
        results[#results + 1] = { cat = it.cat, row = it.row, dir = 'right', ok = ok, ids = mine }
        add('map', results[#results])
        if #mine > 0 then pending = { cat = it.cat, row = it.row, dir = DPAD_RIGHT, ids = mine }
        elseif ok then retry[#retry + 1] = it end
        if fails >= 3 then aborted = true break end
    end
    if not aborted then
        phase('map-left')
        for _, it in ipairs(retry) do
            local ok, mine = probeRow(it, DPAD_LEFT)
            results[#results + 1] = { cat = it.cat, row = it.row, dir = 'left', ok = ok, ids = mine }
            add('map', results[#results])
            if #mine > 0 then pending = { cat = it.cat, row = it.row, dir = DPAD_LEFT, ids = mine } end
            if fails >= 3 then aborted = true break end
        end
    end
    if pending then restoreAlone() end

    phase('close')
    finish()
    sleep(2500)
    local leftover = diff(base, snap())
    add('profile', { tag = 'final', diff = leftover })
    beep()
    local mapped = 0
    for _, r in ipairs(results) do if #r.ids > 0 then mapped = mapped + 1 end end
    say(('Settings map finished: %d rows, %d mapped, leftover changes: %d%s'):format(#items, mapped, #leftover, aborted and ', ABORTED' or ''))
    send({ cats = cats, results = results, items = #items, mapped = mapped, leftover = #leftover, aborted = aborted })
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
