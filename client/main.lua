local isOpen, uiReady, pendingOpen = false, false, nil
local openedAt, closedAt, lastNuiFocusAt = 0, 0, 0
local radarWasHidden, radarOffAtOpen, blurred = false, false, false
-- Bizim başlattığımız yerleşik GTA menüsü akışı: target = hangi menü, seen = gerçekten açıldı mı, returnAt = LOE menüsüne dönüş zamanı
local native = { target = nil, since = 0, seen = false, closingAt = nil, returnAt = nil }
-- Büyük harita arama paneli durumu (ayrıntı: aşağıdaki BÜYÜK HARİTA ARAMA PANELİ bölümü)
local mapPanel = { shown = false, focused = false, token = 0, byId = {}, escGraceUntil = 0 }
local hideMapPanel, showMapPanel

-- ================================================================ YARDIMCILAR
local function menuItem(id)
    for _, item in ipairs(Config.Menu) do
        if item.id == id and item.enabled ~= false then return item end
    end
end

local function resourceStarted(name)
    return type(name) == 'string' and GetResourceState(name) == 'started'
end

local function callExport(res, fnName, ...)
    local args = { ... }
    local ok, result = pcall(function()
        local ex = exports[res]
        return ex[fnName](ex, table.unpack(args))
    end)
    return ok, result
end

local function dbg(...)
    if Config.Debug then print('[loe_pause]', ...) end
end

local function killPause()
    if not IsPauseMenuActive() then return end
    pcall(SetFrontendActive, false)
    pcall(SetPauseMenuActive, false)
end

local function loggedIn()
    return not Config.Hijack.requireLogin or LocalPlayer.state.isLoggedIn == true
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- ================================================================ NUI VERİSİ
local function keyToken(row)
    local token
    if row.control then
        token = GetControlInstructionalButton(0, row.control, true)
    elseif row.command then
        token = GetControlInstructionalButton(0, GetHashKey(row.command) | 0x80000000, true)
    end
    return token
end

local function buildKeys()
    local out = {}
    for _, c in ipairs(Schema.categories) do
        if c.id == 'keys' then
            for _, g in ipairs(c.groups) do
                for _, r in ipairs(g.rows) do
                    if r.type == 'key' or (r.type == 'action' and r.command) then
                        local k = r.control and ('c:' .. r.control) or ('m:' .. tostring(r.command))
                        local token = keyToken(r)
                        if type(token) == 'string' and token ~= '' then out[k] = token end
                    end
                end
            end
        end
    end
    return out
end

local function buildMenu()
    local out = {}
    for _, item in ipairs(Config.Menu) do
        if item.enabled ~= false then
            out[#out + 1] = {
                id = item.id,
                available = (not item.resource) or resourceStarted(item.resource),
                external = item.resource ~= nil,
                soon = item.soon == true,
            }
        end
    end
    return out
end

--- Sağ üst bağlantılar: yalnızca https:// ile başlayan, boşluk/tırnak içermeyen adresler NUI'ye gider (en çok 4).
local function buildLinks()
    local out = {}
    for _, l in ipairs(Config.Links or {}) do
        if type(l) == 'table' and type(l.id) == 'string' and type(l.url) == 'string'
            and l.url:match("^https://[^%s\"'<>]+$") then
            out[#out + 1] = { id = l.id, label = tostring(l.label or l.id), url = l.url }
            if #out >= 4 then break end
        end
    end
    return out
end

local function buildStats()
    local out = {}
    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    if ok and type(pd) == 'table' then
        local ci = pd.charinfo or {}
        out.id = GetPlayerServerId(PlayerId())
        out.name = trim((ci.firstname or '') .. ' ' .. (ci.lastname or ''))
        out.cid = pd.citizenid
        if type(pd.job) == 'table' then
            out.job = pd.job.label or pd.job.name
            if type(pd.job.grade) == 'table' then out.grade = pd.job.grade.name end
        end
        if type(pd.money) == 'table' then
            out.cash, out.bank = pd.money.cash, pd.money.bank
        end
    end
    return out
end

--- GTA'nın GÜNCEL ayar değerleri (yalnızca OKUNUR; GTA bu ayarların yazılmasına script'ten izin vermez).
--- Anahtarlar schema.lua'daki native satırların `read` alanıyla eşleşir. Okunamayan anahtar hiç gönderilmez → satırda değer görünmez.
local function buildNativeValues()
    local out = {}
    local function read(key, fn)
        local ok, v = pcall(fn)
        if ok and v ~= nil then out[key] = v end
    end
    read('subtitles', function() return IsSubtitlePreferenceSwitchedOn() == true end)
    read('metric', function() return ShouldUseMetricMeasurements() == true end)
    read('safezone', function()
        local z = GetSafeZoneSize()
        if type(z) == 'number' and z > 0 and z <= 1.001 then return math.floor(z * 100 + 0.5) end
    end)
    read('resolution', function()
        local w, h = GetActualScreenResolution()
        if type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0 then
            return ('%dx%d'):format(math.floor(w), math.floor(h))
        end
    end)
    read('language', function()
        local l = GetCurrentLanguage()
        if type(l) == 'number' and l >= 0 and l <= 12 then return math.floor(l) end
    end)
    return out
end

--- Yerleşik GTA menüsüne ESC ile geçiş yalnızca config izin veriyorsa VE oyuncu seçtiyse geçerlidir.
local function nativeMenuWanted()
    return Config.Hijack.allowNativeMenu == true and Prefs.get('menu.native') == true
end

-- ================================================================ HIZLI EYLEMLER (kısayol komutları)
-- Görünürlük izni (yalnızca aces tanımlı satırlar için) sunucudan gelir; oyuncu çıkınca silinir.
local SHORTCUTS = {}                         -- 'cmd.<id>' -> Config.Shortcuts girdisi (beyaz liste)
for _, s in ipairs(Config.Shortcuts or {}) do
    if type(s.id) == 'string' and type(s.command) == 'string' and s.command:sub(1, 1) ~= '+' then
        SHORTCUTS['cmd.' .. s.id] = s
    end
end
local caps, lastCapsAsk = {}, 0

local function capsPayload()
    local out = {}
    for id in pairs(caps) do out[id] = true end
    return out
end

RegisterNetEvent('loe_pause:client:caps', function(list)
    if type(list) ~= 'table' then return end
    local fresh = {}
    for _, id in ipairs(list) do
        local s = type(id) == 'string' and SHORTCUTS['cmd.' .. id]
        if s and s.aces then fresh[id] = true end        -- yalnızca yetki gerektiren tanımlı satırlar
    end
    caps = fresh
    if isOpen then SendNUIMessage({ action = 'caps', caps = capsPayload() }) end
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function() caps = {} end)

local function refreshCaps()
    local now = GetGameTimer()
    if now - lastCapsAsk < 5000 then return end
    for _, s in pairs(SHORTCUTS) do
        if s.aces then
            lastCapsAsk = now
            TriggerServerEvent('loe_pause:server:caps')
            return
        end
    end
end

-- ================================================================ SAĞLIK (hastalıklar)
-- Hastalık sistemi loe_jobcreator'dadır (Sağlık sekmesi). Ona DOKUNMADAN, sunucunun bu oyuncuya zaten gönderdiği
-- 'healthState' olayını dinleyip son durumu saklarız; menü açılınca istatistik sayfasında gösteririz.
local HEALTH = Config.Health or {}
local health = { known = false, conditions = {} }
local lastHealthHello = 0

local function clip(v, n)
    if type(v) ~= 'string' or v == '' then return nil end
    return v:sub(1, n)
end

local function healthPayload()
    return { known = health.known, conditions = health.conditions }
end

RegisterNetEvent(HEALTH.event or 'loe_jobcreator:client:healthState', function(state)
    if type(state) ~= 'table' then return end
    local list = {}
    if state.enabled == true and type(state.conditions) == 'table' then
        for _, c in ipairs(state.conditions) do
            if type(c) == 'table' and clip(c.label, 60) then
                list[#list + 1] = {
                    id         = clip(c.id, 40),
                    label      = clip(c.label, 60),
                    symptom    = clip(c.symptom, 140),
                    bandaged   = c.bandaged == true,
                    suppressed = c.suppressed == true,
                }
                if #list >= 12 then break end
            end
        end
    end
    health.known, health.conditions = true, list
    if isOpen then SendNUIMessage({ action = 'health', health = healthPayload() }) end
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function()
    health.known, health.conditions = false, {}
end)

--- loe_pause sonradan başladıysa (restart) önbellek boştur: sistemin kendi "merhaba" olayıyla güncel durumu iste.
--- Bu olay loe_jobcreator tarafında tekrar çağrılabilir (ilk karşılamadan sonra yalnızca durumu yeniden gönderir).
local function refreshHealth()
    local res = HEALTH.resource or 'loe_jobcreator'
    if health.known or not resourceStarted(res) then return end
    local now = GetGameTimer()
    if now - lastHealthHello < 10000 then return end
    lastHealthHello = now
    TriggerServerEvent(HEALTH.helloEvent or 'loe_jobcreator:server:healthHello')
end

-- ================================================================ AÇ / KAPAT
local function restoreRadar()
    -- Oyuncu radarı kapattıysa kapalı kalsın; başka bir script açılıştan ÖNCE gizlemişse onun durumuna dön.
    if Prefs.get('disp.radar') == false then
        DisplayRadar(false)
    elseif radarWasHidden and not radarOffAtOpen then
        DisplayRadar(false)
    else
        DisplayRadar(true)
    end
end

local function close()
    if not isOpen then return end
    isOpen = false
    closedAt = GetGameTimer()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    if blurred then TriggerScreenblurFadeOut(200.0); blurred = false end
    restoreRadar()
    Prefs.flush()
    killPause()
end

local function open(anim)
    if isOpen then return end
    if not uiReady then pendingOpen = anim or 'open'; return end
    isOpen = true
    openedAt = GetGameTimer()

    radarWasHidden = IsRadarHidden()
    radarOffAtOpen = Prefs.get('disp.radar') == false
    DisplayRadar(false)

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    if Config.Hijack.blurGame then TriggerScreenblurFadeIn(250.0); blurred = true end

    SendNUIMessage({
        action = 'open',
        anim   = anim or 'open',
        values = Prefs.snapshot(),
        keys   = buildKeys(),
        menu   = buildMenu(),
        stats  = buildStats(),
        health = healthPayload(),
        native = buildNativeValues(),
        caps   = capsPayload(),
    })
    refreshHealth()
    refreshCaps()
end

Apply.menuOpen = function() return isOpen end

local function canOpenManually()
    return not isOpen and not native.target and loggedIn() and not IsNuiFocused() and not IsPauseMenuActive()
        and not IsPlayerSwitchInProgress() and not IsCutsceneActive()
end

-- ================================================================ YERLEŞİK GTA MENÜSÜ / HARİTA
local function activateNative(target, noReturn)
    local n = Config.Native[target]
    if not n then return false end
    -- Akış başladı: ana döngü menü AÇILANA kadar (en çok 4 sn) ve açık kaldığı sürece ona dokunmaz.
    -- noReturn: harita tuşuyla (menüden değil) açıldı → kapanınca LOE menüsüne dönülmez.
    native.target, native.since, native.seen, native.closingAt, native.returnAt = target, GetGameTimer(), false, nil, nil
    native.noReturn = noReturn == true
    dbg('native start', target)
    ActivateFrontendMenu(GetHashKey(n.menu), n.pause == true, n.component or -1)
    if n.deeper ~= nil then
        -- ActivateFrontendMenu tek başına tüm duraklatma menüsünü açar; doğrudan sayfaya (ör. büyük harita)
        -- girmek için menü açılana kadar bekleyip bir seviye derine iniyoruz. (Çağıran bir thread içinde olmalı.)
        local deadline = GetGameTimer() + 1500
        while not IsPauseMenuActive() and GetGameTimer() < deadline do Wait(0) end
        Wait(n.deeperDelayMs or 100)
        PauseMenuceptionGoDeeper(n.deeper)
    end
    return true
end

--- Yerleşik menü akışı bitti. wasOpen = menü gerçekten açılmıştı → (tercih açıksa) LOE menüsüne dön.
local function finishNative(wasOpen)
    dbg('native finished, wasOpen =', wasOpen)
    if hideMapPanel then hideMapPanel() end
    local noReturn = native.noReturn
    native.target, native.seen, native.closingAt, native.noReturn = nil, false, nil, false
    closedAt = GetGameTimer()
    if wasOpen and not noReturn and Prefs.get('pref.mapReturn') then
        native.returnAt = closedAt + Config.Hijack.reopenCooldownMs + 60
    end
end

local function openNative(target)
    if not Config.Native[target] then return false end
    close()
    CreateThread(function()
        Wait(200)
        activateNative(target)
    end)
    return true
end

local function mapIsOpen(m)
    local ok, res = callExport(m.resource, m.isOpen)
    return ok and res == true
end

-- Harita kapanınca (ve tercih açıksa) menüyü animasyonla geri getir.
local function watchMapReturn(m)
    if not (m.isOpen and Prefs.get('pref.mapReturn')) then return end
    CreateThread(function()
        local deadline, opened = GetGameTimer() + 3000, false
        while GetGameTimer() < deadline do
            if mapIsOpen(m) then opened = true break end
            Wait(100)
        end
        if not opened then return end                       -- harita açılamadı (örn. uçuşta) → oyuna dön
        while mapIsOpen(m) do Wait(150) end
        Wait(450)                                           -- harita kapanış solması
        if canOpenManually() then open('return') end
    end)
end

local function openMap(fromKey)
    local m = Config.MapResource
    local wasOpen = isOpen
    close()
    if wasOpen then Wait(200) end
    if m and resourceStarted(m.resource) then
        local ok = callExport(m.resource, m.open)
        if ok then
            if not fromKey then watchMapReturn(m) end
            return
        end
    end
    activateNative('map', fromKey)
end

-- ================================================================ BÜYÜK HARİTA ARAMA PANELİ
-- M ile açılan yerleşik büyük haritanın sağında kendi panelimiz: üstte arama kutusu, altta haritadaki işaretlerin (blip) listesi.
-- GTA'nın kendi sağ listesi (Legend) script'ten değiştirilemez; panel onu örter. Blip'lere DOKUNULMAZ (yalnızca okunur).
-- Yazmak ve listeye tıklamak için NUI odağı gerekir; odak varken oyun fare girişini almaz (harita sürüklenemez). Bu yüzden
-- panel yalnızca "arama modunda" odak alır: tuşla (Config.MapSearch.key) ya da panele tıklayınca girilir; ESC / panel dışına
-- tıklama ile çıkılır. Arama modundaki ESC haritayı KAPATMAZ (yalnızca modu bitirir).
local MS = Config.MapSearch or {}

--- Oyundaki blip'leri sprite sprite tarar (thread içinden çağrılmalı: Wait kullanır). Ad: GXT 'BLIP_<sprite>' etiketi.
local function scanBlips()
    local out, seen, dedupe = {}, {}, {}
    local pc = GetEntityCoords(PlayerPedId()) or { x = 0.0, y = 0.0, z = 0.0 }
    local ignore, names = MS.ignoreSprites or {}, MS.spriteNames or {}
    for sprite = 1, MS.maxSprite or 900 do
        if not ignore[sprite] then
            local blip = GetFirstBlipInfoId(sprite)
            local guard = 0
            while DoesBlipExist(blip) and guard < 300 do
                guard = guard + 1
                if not seen[blip] then
                    seen[blip] = true
                    if GetBlipInfoIdDisplay(blip) ~= 0 and GetBlipAlpha(blip) > 0 and not DoesEntityExist(GetBlipInfoIdEntityIndex(blip)) then
                        local c = GetBlipInfoIdCoord(blip)
                        if c and (c.x ~= 0.0 or c.y ~= 0.0) then
                            local key = ('%d:%d:%d'):format(sprite, math.floor(c.x), math.floor(c.y))
                            if not dedupe[key] then
                                dedupe[key] = true
                                local name = names[sprite]
                                if not name then
                                    local t = GetLabelText('BLIP_' .. sprite)
                                    name = (t and t ~= 'NULL' and t ~= '') and t or (MS.fallbackName or 'Point of interest')
                                end
                                local dx, dy = c.x - pc.x, c.y - pc.y
                                out[#out + 1] = { n = tostring(name):sub(1, 60), x = c.x + 0.0, y = c.y + 0.0, d = math.floor(math.sqrt(dx * dx + dy * dy)) }
                            end
                        end
                    end
                end
                blip = GetNextBlipInfoId(sprite)
            end
        end
        if sprite % 150 == 0 then Wait(0) end
    end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n < b.n end return a.d < b.d end)
    while #out > (MS.maxItems or 600) do out[#out] = nil end
    for i, e in ipairs(out) do e.id = i end
    return out
end

showMapPanel = function()
    if mapPanel.shown or MS.enabled == false then return end
    mapPanel.shown = true
    mapPanel.token = mapPanel.token + 1
    local token = mapPanel.token
    CreateThread(function()
        local items = scanBlips()
        if not mapPanel.shown or mapPanel.token ~= token then return end      -- tarama sırasında harita kapandı
        mapPanel.byId = {}
        local payload = {}
        for _, e in ipairs(items) do
            mapPanel.byId[e.id] = { x = e.x, y = e.y, n = e.n }
            payload[#payload + 1] = { id = e.id, n = e.n, d = e.d }
        end
        SendNUIMessage({ action = 'mapPanel', show = true, items = payload, key = keyToken({ command = 'loe_mapsearch' }), geo = MS.panel })
        dbg('map panel shown,', #payload, 'places')
    end)
end

hideMapPanel = function()
    if not mapPanel.shown then return end
    mapPanel.shown = false
    mapPanel.token = mapPanel.token + 1
    mapPanel.byId = {}
    if mapPanel.focused then
        mapPanel.focused = false
        SetNuiFocus(false, false)
    end
    SendNUIMessage({ action = 'mapPanel', show = false })
end

local function enterSearch()
    if not mapPanel.shown or mapPanel.focused or native.target ~= 'map' or native.closingAt then return end
    mapPanel.focused = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'mapFocus', on = true })
    dbg('map search on')
end

local function leaveSearch()
    if not mapPanel.focused then return end
    mapPanel.focused = false
    SetNuiFocus(false, false)
    mapPanel.escGraceUntil = GetGameTimer() + 500          -- arayüzde basılan ESC haritayı kapatmasın
    SendNUIMessage({ action = 'mapFocus', on = false })
    dbg('map search off')
end

--- Fare sol tuşu bırakıldığında imleç panel bölgesindeyse true (arama moduna girmek için).
local function cursorClickInPanel()
    if not (IsDisabledControlJustReleased(0, 237) or IsControlJustReleased(2, 237)) then return false end
    local x, y = GetDisabledControlNormal(0, 239), GetDisabledControlNormal(0, 240)
    if x == 0.0 and y == 0.0 then x, y = GetControlNormal(2, 239), GetControlNormal(2, 240) end
    local g = MS.panel or {}
    dbg('map click', x, y)
    return x >= (g.left or 0.76) and x <= (g.right or 0.98) and y >= (g.top or 0.06) and y <= (g.bottom or 0.94)
end

-- ================================================================ ANA DÖNGÜ: ESC / P YAKALAMA
local function canHijack()
    return Config.Hijack.enabled and loggedIn() and not IsPlayerSwitchInProgress()
        and not IsCutsceneActive() and not IsScreenFadedOut()
end

CreateThread(function()
    while true do
        Wait(0)
        local now = GetGameTimer()
        local paused = IsPauseMenuActive()

        if isOpen then
            DisableAllControlActions(0)
            HideHudAndRadarThisFrame()
            local sinceOpen = now - openedAt

            if paused then
                -- Açılışı tetikleyen ESC'nin yerleşik menüsü hâlâ sönüyor olabilir; sonrasında gelen = ESC ile kapat
                if sinceOpen > 350 then close() else killPause() end
            elseif sinceOpen > 300 and (IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 199)) then
                close()
            elseif sinceOpen > 400 and not IsNuiFocused() then
                close()     -- ESC odağı bıraktırdı ya da başka bir resource odağı aldı
            end
        else
            if IsNuiFocused() then lastNuiFocusAt = now end

            if native.target then
                -- Bizim başlattığımız yerleşik menü (harita / oyun / ayarlar).
                if paused then
                    if not native.seen then dbg('native menu active') end
                    native.seen = true
                    -- Script ile açılan (ActivateFrontendMenu) menü ESC'de kendiliğinden KAPANMAZ; yalnızca bir seviye geri gider
                    -- ve harita açık kalır. Bu yüzden ESC / P / Geri'yi biz yakalayıp menüyü kapatırız.
                    if not native.closingAt and now - native.since > 500 and not mapPanel.focused and now >= mapPanel.escGraceUntil
                        and (IsControlJustPressed(0, 200) or IsControlJustPressed(0, 199) or IsControlJustPressed(2, 202)) then
                        native.closingAt = now
                        dbg('ESC in native menu -> closing')
                    end
                    if native.target == 'map' and not native.closingAt then
                        if not mapPanel.shown then showMapPanel() end
                        if mapPanel.shown and not mapPanel.focused and cursorClickInPanel() then enterSearch() end
                    end
                    if native.closingAt then hideMapPanel(); killPause() end
                end
                if native.closingAt then
                    -- Kapanışta sızan ESC yerleşik menüyü yeniden açabilir: pencere boyunca her karede söndür.
                    if now - native.closingAt > 600 and not paused then finishNative(true) end
                elseif not paused and (native.seen or now - native.since > 4000) then
                    finishNative(native.seen)         -- menü kendi kapandı (ya da hiç açılmadı)
                end
            elseif paused then
                if nativeMenuWanted() or not canHijack() then
                    -- yerleşik menü serbest (oyuncu tercihi / giriş yapılmamış / ara sahne)
                else
                    killPause()
                    local h = Config.Hijack
                    if not native.returnAt and now - closedAt >= h.reopenCooldownMs and now - lastNuiFocusAt >= h.nuiGraceMs then
                        open('open')
                    end
                end
            end

            if native.returnAt and now >= native.returnAt then
                if canOpenManually() then
                    native.returnAt = nil
                    open('return')
                elseif now - native.returnAt > 1500 then
                    native.returnAt = nil               -- dönüş mümkün olmadı (başka bir arayüz açık): oyunda kal
                end
            end
        end
    end
end)

-- ================================================================ NUI CALLBACK'LERİ
RegisterNUICallback('ready', function(_, cb)
    uiReady = true
    SendNUIMessage({
        action = 'init',
        schema = Schema.categories,
        bg     = Config.Background,
        links  = buildLinks(),
        gta    = (Config.Features or {}).allGtaSettings ~= false,
    })
    cb({ ok = true })
    if pendingOpen then
        local anim = pendingOpen
        pendingOpen = nil
        open(anim)
    end
end)

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    close()
end)

RegisterNUICallback('setting', function(d, cb)
    if not isOpen or type(d) ~= 'table' then return cb({ ok = false }) end
    if d.id == 'menu.native' and Config.Hijack.allowNativeMenu ~= true then return cb({ ok = false, value = false }) end
    local ok, value = Prefs.set(d.id, d.value)
    if not ok then return cb({ ok = false, value = type(d.id) == 'string' and Prefs.display(d.id) or nil }) end
    Apply.run(d.id)
    cb({ ok = true, value = value })
end)

RegisterNUICallback('action', function(d, cb)
    local id = type(d) == 'table' and d.id
    if not isOpen or type(id) ~= 'string' or not Schema.actions[id] then return cb({ ok = false }) end
    local handler = Apply.actions[id]
    if not handler then return cb({ ok = false }) end
    local res = handler() or { ok = false }
    cb(res)
    if res.close then close() end
end)

RegisterNUICallback('native', function(d, cb)
    local target = type(d) == 'table' and d.target
    if not isOpen or type(target) ~= 'string' or not Config.Native[target] then return cb({ ok = false }) end
    cb({ ok = true })
    openNative(target)
end)

RegisterNUICallback('menu', function(d, cb)
    local id = type(d) == 'table' and d.id
    local item = type(id) == 'string' and menuItem(id)
    if not isOpen or not item then return cb({ ok = false }) end

    if id == 'map' then
        cb({ ok = true })
        CreateThread(openMap)
    elseif id == 'stats' or id == 'battlepass' or id == 'shop' then
        if item.resource and resourceStarted(item.resource) and item.export then
            cb({ ok = true })
            close()
            CreateThread(function()
                Wait(150)
                callExport(item.resource, item.export)
            end)
        else
            -- harici sistem yok: istatistik için yerleşik karakter özeti, diğerleri için "Yakında" sayfası
            cb({ ok = true, page = (id == 'stats') and 'stats' or 'soon' })
        end
    else
        cb({ ok = false })
    end
end)

-- Haritadaki listeden seçilen yere GPS kurar. Yalnızca arama modunda ve yalnızca taramadan çıkan kimliklerle çalışır (koordinat arayüzden ALINMAZ).
RegisterNUICallback('mapPick', function(d, cb)
    local id = type(d) == 'table' and d.id
    local e = mapPanel.focused and type(id) == 'number' and mapPanel.byId[id]
    if not e then return cb({ ok = false }) end
    SetNewWaypoint(e.x, e.y)
    cb({ ok = true, name = e.n })
    leaveSearch()
end)

RegisterNUICallback('mapSearchExit', function(_, cb)
    cb({ ok = true })
    leaveSearch()
end)

RegisterCommand('loe_mapsearch', function()
    if mapPanel.focused then leaveSearch() else enterSearch() end
end, false)
if MS.enabled ~= false and (MS.key or '') ~= '' then
    RegisterKeyMapping('loe_mapsearch', 'Big map: search places', 'keyboard', MS.key)
end

RegisterNUICallback('quit', function(d, cb)
    cb({ ok = true })
    local mode = type(d) == 'table' and d.mode
    -- Yalnızca "sunucudan ayrıl": bağlantıyı keser ve FiveM ana menüsüne döner. Oyunu tamamen kapatan 'quit' bilerek yok.
    if not isOpen or mode ~= 'disconnect' then return end
    close()
    CreateThread(function()
        Wait(150)
        -- 1) Sunucu bu oyuncuyu düşürür (server/main.lua, DropPlayer) → FiveM ana menüsüne "Sunucudan ayrıldın" mesajıyla düşer.
        --    (ExecuteCommand('disconnect') script'ten çalışmıyor; bu yüzden kullanılmaz.)
        dbg('leave requested')
        TriggerServerEvent('loe_pause:server:leave')
        -- 2) Yedek: birkaç saniye sonra hâlâ sunucudaysak (sunucu betiği yüklenmemiş vb.) oyunu kapatıp FiveM'i yeniden açar.
        --    Düşürme başarılı olursa resource durur ve bu satıra hiç gelinmez.
        Wait(3000)
        dbg('leave fallback: RestartGame')
        RestartGame()
    end)
end)

-- Hızlı Eylemler: menüyü kapatır, kısa bir beklemeden sonra kısayolun komutunu çalıştırır. Yalnızca Config.Shortcuts'taki
-- komutlar çalışır (NUI'den komut metni ALINMAZ; yalnızca şemadaki eylem kimliği gelir).
for actionId, s in pairs(SHORTCUTS) do
    Apply.actions[actionId] = function()
        if s.aces and not caps[s.id] then return { ok = false } end
        CreateThread(function()
            Wait(300)      -- menü kapanışı + kısayolun kendi debounce süresi (örn. imlec 250 ms)
            dbg('shortcut', s.command)
            ExecuteCommand(s.command)
        end)
        return { ok = true, close = true }
    end
end

Apply.actions['menu.opennative'] = function()
    if Config.Hijack.allowNativeMenu ~= true then return { ok = false } end
    openNative('game')
    return { ok = true }
end

-- ================================================================ KOMUT / EXPORT
RegisterCommand(Config.Command, function()
    if isOpen then
        close()
    elseif canOpenManually() then
        open('open')
    end
end, false)
RegisterKeyMapping(Config.Command, 'LOE pause menu', 'keyboard', Config.OpenKey or '')

-- Büyük harita tuşu (varsayılan M): menü açılmadan doğrudan büyük harita. Harita açıkken aynı tuş (ESC gibi) kapatır.
-- Harita menüden değil tuştan açıldığı için kapanınca LOE menüsüne dönülmez.
RegisterCommand(Config.MapCommand or 'loe_bigmap', function()
    if mapPanel.focused then return end
    if native.target == 'map' then
        if not native.closingAt and GetGameTimer() - native.since > 500 then
            native.closingAt = GetGameTimer()
            dbg('map key -> closing')
        end
        return
    end
    if canOpenManually() and not IsScreenFadedOut() then
        CreateThread(function() openMap(true) end)
    end
end, false)
if (Config.MapKey or '') ~= '' then
    RegisterKeyMapping(Config.MapCommand or 'loe_bigmap', 'Big map', 'keyboard', Config.MapKey)
end

exports('Open',   function() if canOpenManually() then open('open') end end)
exports('Close',  function() close() end)
exports('IsOpen', function() return isOpen end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if mapPanel.focused then SetNuiFocus(false, false) end      -- harita arama modunda kapanırsa fare/klavye oyuna dönsün
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    if blurred then TriggerScreenblurFadeOut(0.0) end
    restoreRadar()
    Prefs.flush()
end)
