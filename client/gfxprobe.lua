-- GEÇİCİ ARAŞTIRMA ARACI — GTA'nın kendi ayarlarını (Grafik, Ses, Fare...) LOE menüsünde gösterebilir miyiz?
--
--   /loe_gfxtest : otomatik test (~20 sn). GTA ayar menüsünü açar; script girdisiyle gezinmeyi, menüyü gizlemeyi,
--                  seçili satırı ve değerleri okumayı dener. Hiçbir ayarın DEĞERİNİ değiştirmez (yalnızca aşağı/yukarı gezinir).
--   /loe_gfxrec  : kayıt (en çok 150 sn, Delete ile biter). Oyuncu GTA ayar menüsünde elle gezinir; menü olayları ve
--                  değişen profil ayarları zaman damgasıyla kaydedilir.
--
-- Yalnızca Config.GfxProbe.ace yetkisi olanlar çalıştırabilir (sunucu doğrular). Sonuç sunucuda resource klasörüne
-- gfxprobe_*.json olarak yazılır. Araştırma bitince bu dosya, server/main.lua'daki karşılığı ve Config.GfxProbe kaldırılır.

LoeProbe = { active = false }   -- client/main.lua: true iken ESC yakalama döngüsü yerleşik menüye dokunmaz

local P = Config.GfxProbe or {}
if P.enabled ~= true then return end

local PROFILE_MAX = 1200
local MAX_LOG = 6000
local SETTINGS_MENU = (Config.Native and Config.Native.settings and Config.Native.settings.menu) or 'FE_MENU_VERSION_LANDING_MENU'

-- Kontrol kimlikleri (INPUT_FRONTEND_*)
local C_DOWN, C_UP, C_DELETE = 187, 188, 214

local log, t0, busy, watching, hidden = {}, 0, false, false, false
local drain   -- aşağıda tanımlanır (izleme thread'i kullanır)

local function now() return GetGameTimer() - t0 end

local function add(kind, data)
    if #log >= MAX_LOG then return end
    data = data or {}
    data.t, data.k = now(), kind
    log[#log + 1] = data
end

local function say(msg)
    print('[loe_gfxtest] ' .. msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local function beep()
    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

-- ---------------------------------------------------------------- native sarmalayıcıları (isim yoksa hash ile çağır)
local function call(name, hash, ...)
    local f = _G[name]
    if type(f) == 'function' then return f(...) end
    return Citizen.InvokeNative(hash, ...)
end

local function callInt(name, hash)
    local f = _G[name]
    if type(f) == 'function' then return f() end
    return Citizen.InvokeNative(hash, Citizen.ResultAsInteger())
end

local function callBool(name, hash)
    local f = _G[name]
    if type(f) == 'function' then return f() == true end
    return Citizen.InvokeNative(hash, Citizen.ResultAsInteger()) ~= 0
end

local function layoutEvent()
    if not callBool('HasMenuLayoutChangedEventOccurred', 0x2E22FEFA0100275E) then return nil end
    if type(GetMenuLayoutChangedEventDetails) == 'function' then return GetMenuLayoutChangedEventDetails() end
    return Citizen.InvokeNative(0x7E17BE53E1AAABAF, Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt())
end

local function triggerEvent()
    if not callBool('HasMenuTriggerEventOccurred', 0xF284AC67940C6812) then return nil end
    return true
end

-- _GET_PAUSE_MENU_SELECTION (GET_MENU_TRIGGER_EVENT_DETAILS): son menü kimliği + seçili öğenin benzersiz kimliği
local function pauseSel()
    local f = GetPauseMenuSelection or GetMenuTriggerEventDetails
    if type(f) == 'function' then return f() end
    return Citizen.InvokeNative(0x36C1451A88A09630, Citizen.PointerValueInt(), Citizen.PointerValueInt())
end

local function hoverIdx() return callInt('PauseMenuGetMouseHoverIndex', 0x359AF31A4B52F5ED) end
local function menuState() return callInt('GetPauseMenuState', 0x272ACD84970869C5) end
local function feVersion() return callInt('GetCurrentFrontendMenuVersion', 0x2309595AD6145265) end
local function feReady() return callBool('IsFrontendReadyForControl', 0x3BAB9A4E4F2FF5C7) end

local function setControl(group, control, value)
    local f = SetControlValueNextFrame or SetControlNormal
    if type(f) == 'function' then return f(group, control, value) end
    return Citizen.InvokeNative(0xE8A25867FBA3B05E, group, control, value)
end

-- ---------------------------------------------------------------- profil ayarları (GET_PROFILE_SETTING) anlık görüntüsü
local function profileSnap()
    local s = {}
    local ok = pcall(function()
        for id = 0, PROFILE_MAX do
            local v = GetProfileSetting(id)
            if type(v) == 'number' and v ~= 0 then s[id] = v end
        end
    end)
    return s, ok
end

local function profileDiff(a, b)
    local d = {}
    for id = 0, PROFILE_MAX do
        local x, y = a[id] or 0, b[id] or 0
        if x ~= y then d[#d + 1] = { id, x, y } end
    end
    return d
end

local function profileList(s)
    local out = {}
    for id = 0, PROFILE_MAX do
        if s[id] then out[#out + 1] = { id, s[id] } end
    end
    return out
end

-- ---------------------------------------------------------------- olay kaydı (her kare)
local function startWatch()
    watching = true
    CreateThread(function()
        local last = {}
        local prevSnap, lastSnapAt, lastDrainAt = profileSnap(), 0, 0
        local function poll(key, fn)
            local ok, a, b = pcall(fn)
            local v = ok and (b ~= nil and (tostring(a) .. '/' .. tostring(b)) or tostring(a)) or ('ERR ' .. tostring(a))
            if v ~= last[key] then
                last[key] = v
                add('poll', { key = key, v = v })
            end
        end
        while watching do
            local ok, a, b, c = pcall(layoutEvent)
            if not ok then
                if last.layoutErr == nil then last.layoutErr = true; add('err', { what = 'layout', e = tostring(a) }) end
            elseif a ~= nil then
                add('layout', { prev = a, screen = b, uid = c })
            end
            local okT, trig = pcall(triggerEvent)
            if okT and trig then
                local okS, m, u = pcall(pauseSel)
                add('trigger', { menu = okS and m or nil, uid = okS and u or nil })
            end
            poll('sel', pauseSel)
            poll('hover', hoverIdx)
            poll('state', menuState)
            poll('active', IsPauseMenuActive)
            poll('version', feVersion)
            poll('ready', feReady)
            local t = GetGameTimer()
            if t - lastSnapAt >= 250 then
                lastSnapAt = t
                local snap = profileSnap()
                local d = profileDiff(prevSnap, snap)
                if #d > 0 then add('profile', { diff = d }) end
                prevSnap = snap
            end
            if t - lastDrainAt >= 150 then
                lastDrainAt = t
                drain('w')
            end
            Wait(0)
        end
    end)
end

-- ---------------------------------------------------------------- zamanlama yardımcıları (gizleme her karede sürer)
local function tick()
    if hidden then SuppressFrontendRenderingThisFrame() end
end

local function sleep(ms)
    local s = GetGameTimer()
    repeat tick(); Wait(0) until GetGameTimer() - s >= ms
end

-- Tuşa basmayı taklit eder: değer 2 kare boyunca 1.0, sonra bırakılır
local function press(group, control)
    add('press', { group = group, control = control })
    for _ = 1, 2 do
        tick()
        local ok, e = pcall(setControl, group, control, 1.0)
        if not ok then add('err', { what = 'press', e = tostring(e) }) end
        Wait(0)
    end
end

local function navEventsSince(t)
    local n = 0
    for i = #log, 1, -1 do
        local e = log[i]
        if e.t < t then break end
        if e.k == 'layout' or e.k == 'trigger' or (e.k == 'poll' and (e.key == 'sel' or e.key == 'hover')) then n = n + 1 end
    end
    return n
end

local function phase(name)
    add('phase', { name = name })
    print('[loe_gfxtest] phase: ' .. name)
end

local function info(tag)
    local d = { tag = tag }
    local function put(k, fn)
        local ok, a, b = pcall(fn)
        if not ok then d[k] = 'ERR ' .. tostring(a)
        elseif b ~= nil then d[k] = { a, b }
        else d[k] = a end
    end
    put('build', GetGameBuildNumber)
    put('active', IsPauseMenuActive)
    put('state', menuState)
    put('version', feVersion)
    put('ready', feReady)
    put('sel', pauseSel)
    put('hover', hoverIdx)
    put('res', GetActualScreenResolution)
    put('lang', GetCurrentLanguage)
    put('subtitles', IsSubtitlePreferenceSwitchedOn)
    put('metric', ShouldUseMetricMeasurements)
    put('safezone', GetSafeZoneSize)
    add('info', d)
end

-- ---------------------------------------------------------------- scaleform dönüş değeri denemeleri
local function sfCall(header, name, params)
    local begin = header and BeginScaleformMovieMethodOnFrontendHeader or BeginScaleformMovieMethodOnFrontend
    local res = { name = name, header = header, params = params }
    local okB, started = pcall(begin, name)
    if not okB or not started then
        res.started = false
        if not okB then res.e = tostring(started) end
        add('sf', res)
        return
    end
    for _, p in ipairs(params or {}) do ScaleformMovieMethodAddParamInt(p) end
    local okE, h = pcall(EndScaleformMovieMethodReturnValue)
    if not okE or type(h) ~= 'number' then
        res.e = 'end: ' .. tostring(h)
        add('sf', res)
        return
    end
    res.handle = h
    local s = GetGameTimer()
    while GetGameTimer() - s < 400 do
        local okR, r = pcall(IsScaleformMovieMethodReturnValueReady, h)
        if okR and r then res.ready = true break end
        tick(); Wait(0)
    end
    if res.ready then
        local o1, vi = pcall(GetScaleformMovieMethodReturnValueInt, h); if o1 then res.int = vi end
        local o2, vs = pcall(GetScaleformMovieMethodReturnValueString, h); if o2 then res.str = vs end
        local o3, vb = pcall(GetScaleformMovieMethodReturnValueBool, h); if o3 then res.bool = vb end
    end
    add('sf', res)
end

local SF_CANDIDATES = {
    { false, 'GET_COLUMN_SELECTION', { 0 } },
    { false, 'GET_COLUMN_SELECTION', { 1 } },
    { false, 'GET_COLUMN_SELECTION', { 2 } },
    { false, 'GET_COLUMN_SELECTION', { 3 } },
    { false, 'GET_CURRENT_SELECTION' },
}

-- ---------------------------------------------------------------- LOE scaleform kancası (stream/pause_menu_sp_content.gfx)
-- Yamalı içerik filmi, oyunun ayar sayfasına gönderdiği çağrıları (SET_DATA_SLOT, SET_VIDEO_MEMORY_BAR...) kaydeder.
-- LOE_PING → "LOE_OK" (yama yüklü mü), LOE_DUMP(n) → kaydın ilk n karakteri (okunan kısım silinir).
local patched = false

local function sfStr(name, params)
    local okB, started = pcall(BeginScaleformMovieMethodOnFrontend, name)
    if not okB or not started then return nil end
    for _, p in ipairs(params or {}) do ScaleformMovieMethodAddParamInt(p) end
    local okE, h = pcall(EndScaleformMovieMethodReturnValue)
    if not okE or type(h) ~= 'number' then return nil end
    local s = GetGameTimer()
    while GetGameTimer() - s < 400 do
        local okR, r = pcall(IsScaleformMovieMethodReturnValueReady, h)
        if okR and r then
            local okS, v = pcall(GetScaleformMovieMethodReturnValueString, h)
            return okS and v or nil
        end
        tick(); Wait(0)
    end
    return nil
end

-- Yama yüklü mü? Film henüz hazır olmayabilir → birkaç kez dene; kontrol olarak oyunun kendi metodunu da çağır
-- (kontrol dönerse kanal çalışıyor, yalnızca LOE_PING yoksa yamalı dosya yüklenmemiştir)
local function detectPatch()
    local ping
    for _ = 1, 4 do
        ping = sfStr('LOE_PING')
        if ping == 'LOE_OK' then break end
        sleep(400)
    end
    patched = ping == 'LOE_OK'
    local ctrl = sfStr('GET_COLUMN_SELECTION', { 0 })
    add('patch', { ping = ping, active = patched, control = ctrl })
end

-- Kaydı boşaltır (yalnızca izleme thread'i ve kapanışta çağrılır → parçalar sırayla gelir)
drain = function(tag)
    if not patched then return 0 end
    local total = 0
    for _ = 1, 60 do
        local chunk = sfStr('LOE_DUMP', { 2000 })
        if type(chunk) ~= 'string' or chunk == '' then break end
        add('sflog', { s = chunk, tag = tag })
        total = total + #chunk
    end
    return total
end

local function sfSince(t, words)
    for i = #log, 1, -1 do
        local e = log[i]
        if e.t < t then break end
        if e.k == 'sflog' then
            for _, w in ipairs(words) do
                if e.s:find(w, 1, true) then return true end
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------- menü aç / kapat
local function openSettings()
    ActivateFrontendMenu(GetHashKey(SETTINGS_MENU), true, -1)
    local deadline = GetGameTimer() + 3000
    while not IsPauseMenuActive() and GetGameTimer() < deadline do Wait(0) end
    return IsPauseMenuActive()
end

local function closeMenu()
    hidden = false
    for _ = 1, 40 do
        if not IsPauseMenuActive() then break end
        pcall(SetFrontendActive, false)
        Wait(50)
    end
end

local function send(kind, extra)
    local payload = { kind = kind, log = log }
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
    log, t0, patched = {}, GetGameTimer(), false
    LoeProbe.active = true
    -- Güvenlik: test ne olursa olsun 200 sn sonra ESC yakalama geri gelir
    local token = {}
    LoeProbe.token = token
    SetTimeout(200000, function()
        if LoeProbe.token == token and LoeProbe.active then
            watching, hidden, busy = false, false, false
            LoeProbe.active = false
        end
    end)
end

local function finish()
    watching = false
    Wait(300)          -- izleme thread'i dursun; kalan kaydı sırayla buradan oku
    drain('final')
    closeMenu()
    SetTimeout(1000, function() LoeProbe.active = false; busy = false end)
end

-- ---------------------------------------------------------------- /loe_gfxtest: otomatik test
local function runAuto()
    begin()
    info('start')
    local snap0 = profileSnap()
    add('profileStart', { list = profileList(snap0) })

    phase('open')
    if not openSettings() then
        say('Could not open the GTA settings menu.')
        finish()
        send('auto', { failed = 'open' })
        return
    end
    sleep(1200)
    phase('patch')
    detectPatch()
    startWatch()
    info('opened')

    phase('deeper0')
    pcall(call, 'PauseMenuceptionGoDeeper', 0x77F16B447824DA6C, 0)
    sleep(900)
    info('afterDeeper')

    -- Hangi girdi grubu menüyü hareket ettiriyor? (yamalı film her hareketi kaydeder; yama yoksa eski olay okuyucu)
    local NAV_WORDS = { 'SET_COLUMN_HIGHLIGHT', 'LAYOUT_CHANGED', 'SET_INPUT_EVENT', 'SET_HIGHLIGHT', 'SET_DESCRIPTION' }
    local group
    for _, g in ipairs({ 2, 0 }) do
        phase('nav-g' .. g)
        local t = now()
        press(g, C_DOWN); sleep(700)
        press(g, C_UP); sleep(700)
        local moved = sfSince(t, NAV_WORDS) or navEventsSince(t) > 0
        add('navResult', { group = g, moved = moved })
        if moved and not group then group = g end
    end
    info('afterNav')

    -- Kategori listesinde aşağı doğru gez: her kategori seçildiğinde oyun sağ sütuna o kategorinin satırlarını ve
    -- güncel değerlerini gönderir (yalnızca gezinme, hiçbir değer değişmez)
    phase('walk')
    for _ = 1, 15 do
        press(group or 2, C_DOWN)
        sleep(650)
    end
    info('afterWalk')

    -- Menü görünmezken (SuppressFrontendRenderingThisFrame) açık kalıp girdi almaya devam ediyor mu?
    phase('hidden')
    beep()
    hidden = true
    local t = now()
    sleep(800)
    press(group or 2, C_DOWN); sleep(700)
    press(group or 2, C_UP); sleep(700)
    info('whileHidden')
    hidden = false
    add('hiddenResult', { events = navEventsSince(t), moved = sfSince(t, NAV_WORDS), stillActive = IsPauseMenuActive() })
    beep()
    sleep(800)

    phase('scaleform')
    for _, c in ipairs(SF_CANDIDATES) do sfCall(c[1], c[2], c[3]) end

    phase('end')
    info('end')
    local snap1 = profileSnap()
    add('profileEndDiff', { diff = profileDiff(snap0, snap1) })
    finish()
    say(('Auto test finished. Patch: %s, script input: %s'):format(patched and 'active' or 'NOT loaded',
        group and ('group ' .. group) or 'not detected'))
    send('auto', { navGroup = group, patched = patched })
end

-- ---------------------------------------------------------------- /loe_gfxrec: elle gezinme kaydı
local function runRecord()
    begin()
    info('start')
    local snap0 = profileSnap()
    add('profileStart', { list = profileList(snap0) })

    phase('open')
    if not openSettings() then
        say('Could not open the GTA settings menu.')
        finish()
        send('record', { failed = 'open' })
        return
    end
    sleep(800)
    detectPatch()
    startWatch()
    beep()
    phase('record')

    local started, offSince, reason = GetGameTimer(), nil, 'timeout'
    while GetGameTimer() - started < 150000 do
        if IsControlJustPressed(2, C_DELETE) or IsDisabledControlJustPressed(2, C_DELETE)
            or IsControlJustPressed(0, C_DELETE) or IsDisabledControlJustPressed(0, C_DELETE) then
            reason = 'delete' break
        end
        if not IsPauseMenuActive() then
            offSince = offSince or GetGameTimer()
            if GetGameTimer() - offSince > 1500 then reason = 'closed' break end
        else
            offSince = nil
        end
        Wait(0)
    end
    add('recordEnd', { reason = reason })
    phase('end')
    info('end')
    local snap1 = profileSnap()
    add('profileEndDiff', { diff = profileDiff(snap0, snap1) })
    finish()
    beep()
    say('Recording finished (' .. reason .. '). Patch: ' .. (patched and 'active' or 'NOT loaded'))
    send('record', { reason = reason, patched = patched })
end

-- ---------------------------------------------------------------- /loe_gfxpath: yamasız okuma (AS2 yolu)
-- Oyun scaleform metodlarını "TIMELINE.<ad>" yolundan çağırır. Yola oyunun kendi AS2 nesnelerini (veri modeli) yazıp
-- sonu bir dize/dizi metoduyla (join, toString) bitirirsek metod DEĞERİ döner → oyunun tuttuğu ayar satırlarını okuruz.
-- Satır verisi: [0 index, 1 menuID, 2 uniqueID, 3 type, 4 initialIndex, 5 isSelectable, 6.. etiket ve seçenek metinleri]
local function sfRead(path, sep, ints)
    local okB, started = pcall(BeginScaleformMovieMethodOnFrontend, path)
    if not okB then return nil, nil, 'ERR ' .. tostring(started) end
    if not started then return nil, nil, 'begin-false' end
    if sep then pcall(ScaleformMovieMethodAddParamTextureNameString, sep) end
    for _, v in ipairs(ints or {}) do pcall(ScaleformMovieMethodAddParamInt, v) end
    local okE, h = pcall(EndScaleformMovieMethodReturnValue)
    if not okE or type(h) ~= 'number' then return nil, nil, 'end' end
    local t = GetGameTimer()
    while GetGameTimer() - t < 250 do
        local okR, r = pcall(IsScaleformMovieMethodReturnValueReady, h)
        if okR and r then
            local o1, str = pcall(GetScaleformMovieMethodReturnValueString, h)
            local o2, int = pcall(GetScaleformMovieMethodReturnValueInt, h)
            return o1 and str or nil, o2 and int or nil, 'ok'
        end
        tick(); Wait(0)
    end
    return nil, nil, 'timeout'
end

-- Bulgular (önceki turlar): yol çözümü adlı özelliklerde ve film kliplerinde çalışıyor, DİZİ elemanlarında (viewList.0)
-- ve "length"te çalışmıyor; dönen metin en çok 63 karakter. Bu yüzden satırlara adlı kliplerden ulaşılır:
--   currentPage.columnList.1.menuContainer.dataViewMC<d>.settingsListItem<i>MC
-- Satır alanları (PauseMenuSettingsTextItem): itemTextLeft (ad), itemTextRight (değer metni), _uniqueID, initialIndex,
-- type, menuID, isSelectable, multiListItems (seçenekler). Oyuna yazma: <satır>.setPref(değer).
local SETCOL = 'currentPage.columnList.1'
local PATH_DISCOVER = {
    -- denetim (önceki turda çalışanlar)
    { SETCOL .. '.state.toString' },
    { SETCOL .. '.menuContainer.toString' },
    -- alt klibe ADIYLA inilebiliyor mu? (menuMC adı biliniyor)
    { SETCOL .. '.CONTENT.toString' },
    { SETCOL .. '.CONTENT.menuMC.toString' },
    { SETCOL .. '.menuContainer._name.toString' },
    -- menuMC içinde hangi derinlikler dolu?
    { SETCOL .. '.menuContainer.getNextHighestDepth' },
    { SETCOL .. '.menuContainer.getInstanceAtDepth', nil, { 0 } },
    { SETCOL .. '.menuContainer.getInstanceAtDepth', nil, { 1 } },
    { SETCOL .. '.menuContainer.dataViewMC0._name.toString' },
    { SETCOL .. '.menuContainer.dataViewMC1._name.toString' },
    { SETCOL .. '.menuContainer.dataViewMC2._name.toString' },
    -- dizi elemanı biçimleri
    { SETCOL .. '.model.viewList.toString' },
    { SETCOL .. '.model.viewList.0.viewIndex.toString' },
    { SETCOL .. '.model.viewList.0.viewContainer.toString' },
    { SETCOL .. '.model.viewList.0.viewContainer._name.toString' },
    { SETCOL .. '.model.viewList.slice', nil, { 0, 1 } },
    { SETCOL .. '.model.dataList.join', '|' },
    { 'currentPage.columnList.0.model.viewList.join' },
    { 'currentPage.column2.toString' },
    { 'currentPage.column2.menuContainer.toString' },
    -- sınıf örneği metodu (undefined dönerse zaman aşımı gibi görünür)
    { SETCOL .. '.model.getCurrentSelection', nil, { 0 } },
    { SETCOL .. '.model.getCurrentView', nil, { 0 } },
    { SETCOL .. '.dbgID.substr', nil, { 0, 5 } },
}

-- Uzun metni 63 karakterlik parçalarla oku (String.substr(start, len))
local function readText(path)
    local out = ''
    for i = 0, 5 do
        local s = sfRead(path .. '.substr', nil, { i * 63, 63 })
        if type(s) ~= 'string' then return i == 0 and nil or out end
        out = out .. s
        if #s < 63 then break end
    end
    return out
end

local function viewPath(d) return SETCOL .. '.menuContainer.dataViewMC' .. d end

local function findView(prefer)
    local order = { prefer or 0 }
    for d = 0, 4 do if d ~= prefer then order[#order + 1] = d end end
    for _, d in ipairs(order) do
        local s = sfRead(viewPath(d) .. '.settingsListItem0MC._uniqueID.toString')
        if type(s) == 'string' and s ~= '' then return d end
    end
end

local function readItems(d)
    local rows = {}
    for i = 0, 24 do
        local it = viewPath(d) .. '.settingsListItem' .. i .. 'MC'
        local uid = sfRead(it .. '._uniqueID.toString')
        if type(uid) ~= 'string' then break end
        rows[#rows + 1] = {
            i = i, uid = uid,
            mid = sfRead(it .. '.menuID.toString'),
            type = sfRead(it .. '.type.toString'),
            init = sfRead(it .. '.initialIndex.toString'),
            sel = sfRead(it .. '.isSelectable.toString'),
            label = readText(it .. '.itemTextLeft.text'),
            value = readText(it .. '.itemTextRight.text'),
            opts = sfRead(it .. '.multiListItems.join', '|'),
        }
    end
    return rows
end

local function runPath()
    begin()
    info('start')
    phase('open')
    if not openSettings() then
        say('Could not open the GTA settings menu.')
        finish()
        send('path', { failed = 'open' })
        return
    end
    sleep(2500)          -- LANDING_MENU doğrudan Ayarlar sayfasını açar (sol sütun kategoriler, sağ sütun ayar satırları)
    info('opened')

    phase('discover')
    for _, d in ipairs(PATH_DISCOVER) do
        local str, int, st = sfRead(d[1], d[2], d[3])
        add('path', { p = d[1], args = d[3], s = str, i = int, st = st })
    end

    -- Kategori listesinde aşağı in (yalnızca vurgu; sağ sütun o kategorinin satırlarını gösterir). Değer değişmez.
    phase('walk')
    local okSteps, view = 0, nil
    for step = 0, 2 do
        if not IsPauseMenuActive() then add('walkStop', { step = step, reason = 'menu closed' }) break end
        if step > 0 then press(2, C_DOWN); sleep(800) end
        view = findView(view)
        local rows = view and readItems(view) or {}
        if #rows > 0 then okSteps = okSteps + 1 end
        add('rows', { step = step, view = view, n = #rows, rows = rows, state = sfRead(SETCOL .. '.state.toString') })
    end
    info('end')
    phase('end')
    finish()
    say(('Path test finished. Steps with data: %d / 3'):format(okSteps))
    send('path', { stepsWithData = okSteps })
end

-- ---------------------------------------------------------------- komutlar (sunucu yetkiyi onaylayınca başlar)
local function request(mode)
    if busy then say('A test is already running.') return end
    if (Apply and Apply.menuOpen and Apply.menuOpen()) or IsPauseMenuActive() then
        say('Close the menu first, then run the command again.')
        return
    end
    busy = true
    TriggerServerEvent('loe_pause:server:gfxprobeAsk', mode)
    SetTimeout(5000, function()
        if busy and not LoeProbe.active then busy = false end   -- sunucu yanıt vermedi / yetki yok
    end)
end

RegisterNetEvent('loe_pause:client:gfxprobeGo', function(mode, allowed)
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
        local ok, err = pcall(mode == 'record' and runRecord or (mode == 'path' and runPath or runAuto))
        if not ok then
            add('err', { what = 'run', e = tostring(err) })
            finish()
            say('Test error: ' .. tostring(err))
            send(mode, { error = tostring(err) })
        end
    end)
end)

RegisterNetEvent('loe_pause:client:gfxprobeSaved', function(name)
    if name then say('Saved on the server: ' .. tostring(name)) else say('The server could not save the result.') end
end)

RegisterCommand('loe_gfxtest', function() request('auto') end, false)
RegisterCommand('loe_gfxrec', function() request('record') end, false)
RegisterCommand('loe_gfxpath', function() request('path') end, false)
