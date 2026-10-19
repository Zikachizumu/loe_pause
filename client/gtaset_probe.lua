-- GEÇİCİ ARAŞTIRMA ARACI — GTA'nın kendi ayarlarını LOE menüsünden yönetme (v9: kaydırıcı aralıkları)
--
-- Bulgular: GTA ayar menüsü gizliyken (SuppressFrontendRenderingThisFrame) tuş işlemiyor ama kök scaleform metodları
-- çalışıyor: SET_INPUT_EVENT (9 gezinme, 10/11 değer) ve MENU_SHIFT_DEPTH(±1) (satırlara gir/çık). Değer menü kapanınca
-- profile yazılıyor (GetProfileSetting). Satır tablosu: shared/gtaset_data.lua (v8 eşleştirmesinden).
--
--   /loe_gtaset : (~7-10 dk, GTA menüsü hiç görünmez) 24 kaydırıcının en büyük değerini ölçer ve eski değerine döndürür.
--
-- Yalnızca Config.GfxProbe.ace yetkisi olanlar çalıştırabilir (sunucu doğrular). Sonuç sunucuda resource klasörüne
-- gfxprobe_*.json olarak yazılır. Araştırma bitince bu dosya, server/main.lua'daki karşılığı ve Config.GfxProbe kaldırılır.

LoeProbe = { active = false }   -- client/main.lua: true iken ESC yakalama döngüsü yerleşik menüye dokunmaz

local P = Config.GfxProbe or {}
if P.enabled ~= true then return end

local PROFILE_MAX = 1200
local MAX_LOG = 3000
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
    local payload = { kind = 'ranges9', log = log }
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
    -- Güvenlik: test ne olursa olsun 30 dk sonra ESC yakalama geri gelir
    local token = {}
    LoeProbe.token = token
    SetTimeout(1800000, function()
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

-- Zamanlama (v7 çalıştı, v8 ilk iki deneme çalışmadı): menü her işlemden sonra kısa süre meşgul; o sırada gelen çağrı
-- YUTULUR. Art arda gezinme 60 ms aralıkla yeterli; giriş/çıkış ve değer adımı önceki işlemden en az 250 ms sonra;
-- giriş/çıkıştan sonra 400 ms beklenir.
local NAV_GAP, ACT_GAP, DEPTH_SETTLE = 60, 250, 400
local lastAct = 0
local function pace(ms)
    local w = lastAct + ms - GetGameTimer()
    if w > 0 then sleep(w) end
end

local function uid() return val('menuUniqueID.toString') end
local function level() return tostring(val('menuLevel.toString')) end

-- Kök gezinme: çağır, menuUniqueID değişene kadar bekle; yutulursa en çok 3 deneme. Yalnızca sorunlar kaydedilir.
local function nav(dir, tag)
    local before = uid()
    for try = 1, 3 do
        pace(try == 1 and NAV_GAP or ACT_GAP)
        local t = GetGameTimer()
        pcall(BeginScaleformMovieMethodOnFrontend, 'SET_INPUT_EVENT')
        pcall(ScaleformMovieMethodAddParamInt, dir)
        pcall(EndScaleformMovieMethod)
        lastAct = GetGameTimer()
        local u
        repeat
            Wait(0)
            u = uid()
        until u ~= before or GetGameTimer() - t > 400
        if u ~= before then
            if try > 1 then add('navRetry', { tag = tag, tries = try }) end
            return true
        end
    end
    add('navFail', { tag = tag, dir = dir, at = before })
    return false
end

-- Satırlara gir (+1) / çık (-1); seviye değişmezse en çok 3 deneme
local function depth(dir)
    local want = dir > 0 and '2' or '1'
    for try = 1, 3 do
        pace(ACT_GAP)
        sfDo('MENU_SHIFT_DEPTH', { dir, false, false })
        lastAct = GetGameTimer()
        local t = GetGameTimer()
        repeat Wait(0) until level() == want or GetGameTimer() - t > 600
        if level() == want then
            if try > 1 then add('depthRetry', { dir = dir, tries = try }) end
            sleep(DEPTH_SETTLE)
            lastAct = GetGameTimer()
            return true
        end
    end
    add('depthFail', { dir = dir, uid = uid(), level = level() })
    return false
end

-- Değer adımı (sol/sağ): önceki işlemden en az 250 ms sonra
local function step(dir)
    pace(ACT_GAP)
    sfDo('SET_INPUT_EVENT', { dir })
    lastAct = GetGameTimer()
end

-- Toplu değer adımı: n kez, aralık gap ms (günlüğe yazılmaz)
local function stepN(dir, n, gap)
    pace(ACT_GAP)
    for _ = 1, n do
        pcall(BeginScaleformMovieMethodOnFrontend, 'SET_INPUT_EVENT')
        pcall(ScaleformMovieMethodAddParamInt, dir)
        pcall(EndScaleformMovieMethod)
        sleep(gap)
    end
    lastAct = GetGameTimer()
end

local function openHidden()
    hide(true)
    ActivateFrontendMenu(GetHashKey(SETTINGS_MENU), true, -1)
    local deadline = GetGameTimer() + 6000
    while GetGameTimer() < deadline do
        if IsPauseMenuActive() and select(3, sfRead('menuUniqueID.toString')) == 'ok' then
            sleep(300)
            lastAct = GetGameTimer()
            return true
        end
        Wait(0)
    end
    return false
end

-- Önce kapat, SONRA gizlemeyi bırak (menü bir kare bile görünmesin)
local function shut()
    pace(ACT_GAP)
    closeMenu()
    hide(false)
end

-- Açılışta Controls seçili; kategori listesinde (seviye 1) aşağı inerek `cat`'e git.
-- Kategori ve satır kimlikleri çakışabiliyor (Camera = 4, Controls'taki bir satır da 4) → seviye de denetlenir.
local function gotoCat(cat)
    if level() ~= '1' then return false end
    for _ = 0, 14 do
        if uid() == cat then return true end
        if not nav(DPAD_DOWN, 'cat') then return false end
    end
    return uid() == cat
end

local function gotoRow(row)
    if level() ~= '2' then return false end
    for _ = 0, 45 do
        if uid() == row then return true end
        if not nav(DPAD_DOWN, 'row') then return false end
    end
    return uid() == row
end

-- Gizli oturum: aç, kategoriye gir, adımları uygula ({ row, dir }), çık, kapat
local function session(cat, steps)
    local ok = openHidden() and gotoCat(cat) and depth(1)
    if ok then
        for _, s in ipairs(steps) do
            if gotoRow(s.row) then
                if s.n then stepN(s.dir, s.n, s.gap) else step(s.dir) end
            else
                ok = false
            end
        end
        if not depth(-1) then ok = false end
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

-- ---------------------------------------------------------------- v9: kaydırıcı aralıkları
-- v8 eşleştirmesi tamamlandı (shared/gtaset_data.lua). Kaydırıcılar uçta durur (stepVal sınırlar). Her kaydırıcıyı sağa
-- uca kadar iterek en büyük değeri bulur (kaydırıcı en küçük değeri 0), sonra eski değerine döndürür.
-- Önce adım aralığı ölçülür: çok hızlı basış yutulabiliyor (v7/v8: gezinme 60 ms yetti, değer adımı için doğrulanmadı).
local cats = {}
for _, c in ipairs(GtaSetData.cats) do
    local sliders = {}
    for _, r in ipairs(c.rows) do if r.kind == 'slider' then sliders[#sliders + 1] = r end end
    if #sliders > 0 then cats[#cats + 1] = { id = c.id, uid = tostring(c.uid), sliders = sliders } end
end

local R_DIR, L_DIR = DPAD_RIGHT, DPAD_LEFT
local cur = {}          -- profil ayarlarının bilinen güncel durumu

local function orig(base_, pid) return base_[pid] or 0 end

-- Bir kaydırıcıyı kesin eski değerine döndür ve doğrula: ilk deneme verilen aralıkla, sonrakiler yavaş (250 ms); en çok 3 deneme
local function putBack(c, r, want, gap)
    for try = 1, 3 do
        local now_ = cur[r.pid] or 0
        if now_ == want then return true end
        local dir, n = (now_ > want) and L_DIR or R_DIR, math.abs(now_ - want)
        session(c.uid, { { row = tostring(r.uid), dir = dir, n = n, gap = try == 1 and gap or 250 } })
        cur = settle()
    end
    return (cur[r.pid] or 0) == want
end

-- Adım aralığı: liste satırı (MO_CTY, 12 seçenek, uçlarda dönüyor → kırpma yok) 10 basışta tam 10 adım ilerlemeli.
-- Kaydırıcı olmaz: uçta durup ölçümü yanıltır. Geri alma: kalan adımlar (12 - 10) yavaş basılır, doğrulanır.
local function calibrate()
    local cat, row
    for _, c in ipairs(GtaSetData.cats) do
        for _, r in ipairs(c.rows) do
            if r.text == 'MO_CTY' then cat, row = c, r end
        end
    end
    if not row then return 250 end
    local count = #row.labels
    for _, gap in ipairs({ 50, 70, 100, 150, 250 }) do
        local before = cur[row.pid] or 0
        session(tostring(cat.uid), { { row = tostring(row.uid), dir = R_DIR, n = 10, gap = gap } })
        cur = settle()
        local after = cur[row.pid] or 0
        local ok = after == (before + 10) % count
        add('calibrate', { gap = gap, pid = row.pid, before = before, after = after, ok = ok })
        for _ = 1, 3 do   -- eski değere dön (liste dönüyor: yalnızca sağa basılır)
            local back = ((before - (cur[row.pid] or 0)) % count)
            if back == 0 then break end
            session(tostring(cat.uid), { { row = tostring(row.uid), dir = R_DIR, n = back, gap = 250 } })
            cur = settle()
        end
        if ok then return gap end
    end
    return 250
end

local function run()
    begin()
    base = snap()
    cur = base
    add('profileStart', { list = list(base) })

    phase('calibrate')
    local gap = calibrate()
    add('gap', { gap = gap })

    phase('ranges')
    local ranges, failed = {}, {}
    for _, c in ipairs(cats) do
        local plan = {}
        for _, r in ipairs(c.sliders) do plan[#plan + 1] = { row = tostring(r.uid), dir = R_DIR, n = 25, gap = gap } end
        session(c.uid, plan)
        cur = settle()
        -- 25 adımda uca varmayanlar (ör. 0..100 fare hassasiyeti) için ikinci tur
        local more = {}
        for _, r in ipairs(c.sliders) do
            if (cur[r.pid] or 0) - orig(base, r.pid) >= 25 then more[#more + 1] = { row = tostring(r.uid), dir = R_DIR, n = 110, gap = gap } end
        end
        if #more > 0 then
            session(c.uid, more)
            cur = settle()
        end
        for _, r in ipairs(c.sliders) do
            ranges[tostring(r.pid)] = { cat = c.id, uid = r.uid, text = r.text, from = orig(base, r.pid), max = cur[r.pid] or 0 }
            add('range', ranges[tostring(r.pid)])
        end
        for _, r in ipairs(c.sliders) do
            if not putBack(c, r, orig(base, r.pid), gap) then failed[#failed + 1] = r.pid end
        end
    end

    phase('close')
    finish()
    sleep(2500)
    local leftover = diff(base, snap())
    add('profile', { tag = 'final', diff = leftover })
    beep()
    local n = 0
    for _ in pairs(ranges) do n = n + 1 end
    say(('Slider ranges finished: %d sliders, gap %d ms, leftover changes: %d'):format(n, gap, #leftover))
    send({ gap = gap, ranges = ranges, failed = failed, leftover = #leftover })
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
