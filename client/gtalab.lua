-- GEÇİCİ DENEY ARACI — GTA ayar menüsünü gizli açıp gezinirken hangi işlemin "tık" sesi çıkardığını bulur.
--
--   /loe_gtalab : (~1 dk) GTA ayar menüsü gizli açılır; ekranın üstündeki başlık hangi aşamada olduğunu söyler:
--     P1 boşta · P2 kategori gezinme (SET_INPUT_EVENT) · P3 kategori atlama (SET_COLUMN_HIGHLIGHT) · P5 satır gezinme ·
--     P6 satır atlama · P7 değer adımı (Display → Subtitles 6 kez; çift sayıda → eski değere döner) ·
--     M1..M4 gezinme sırasında denenen ses susturma yöntemleri.
--   Oyuncu hangi aşamalarda tık sesi duyduğunu söyler. Hiçbir ayar kalıcı değişmez.
--
-- Yalnızca Config.GfxProbe.ace yetkisi olanlar çalıştırabilir (sunucu doğrular). Sonuç sunucuda resource klasörüne
-- gfxprobe_*.json olarak yazılır. Deney bitince bu dosya, server/main.lua'daki karşılığı ve Config.GfxProbe kaldırılır.

local P = Config.GfxProbe or {}
if P.enabled ~= true then return end

local log, t0, busy = {}, 0, false
local wantProf = false
local function now() return GetGameTimer() - t0 end
local function add(kind, data)
    if #log >= 3000 then return end
    data = data or {}
    data.t, data.k = now(), kind
    log[#log + 1] = data
end

local function banner(text)
    SendNUIMessage({ action = 'lab', text = text })
    add('phase', { text = text })
    print('[loe_gtalab] ' .. tostring(text))
end

local function say(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local function send(extra)
    local payload = { kind = 'lab', log = log }
    for k, v in pairs(extra or {}) do payload[k] = v end
    local ok, data = pcall(json.encode, payload)
    if ok and type(data) == 'string' then
        TriggerLatentServerEvent('loe_pause:server:gfxprobe', 200000, data)
    end
end

local function run()
    local T = GtaSet._t
    log, t0 = {}, GetGameTimer()
    GtaSet.busy = true
    local before = GetProfileSetting(203)
    banner('LAB: starting')
    T.sleep(1500)
    if not T.openHidden() then
        banner('')
        GtaSet.busy = false
        say('Could not open the GTA settings menu.')
        return
    end

    banner('P1: idle (no actions) 4s')
    T.sleep(4000)

    banner('P2: category nav - SET_INPUT_EVENT x8')
    for _ = 1, 8 do T.nav(); T.sleep(350) end

    banner('P3: category jump - SET_COLUMN_HIGHLIGHT x8')
    for i = 0, 7 do
        T.call('SET_COLUMN_HIGHLIGHT', 0, i, true, false)
        T.sleep(350)
        add('jump', { col = 0, idx = i, uid = T.uid(), level = T.level() })
    end

    banner('P4: setup (ignore sounds)')
    local okCat = T.gotoCat('5')
    local okDepth = okCat and T.depth(1)
    add('setup', { cat = okCat, depth = okDepth })
    T.sleep(800)

    if okDepth then
        banner('P5: row nav - SET_INPUT_EVENT x8')
        for _ = 1, 8 do T.nav(); T.sleep(350) end

        banner('P6: row jump - SET_COLUMN_HIGHLIGHT x8')
        for i = 0, 7 do
            T.call('SET_COLUMN_HIGHLIGHT', 1, i, true, false)
            T.sleep(350)
            add('jump', { col = 1, idx = i, uid = T.uid(), level = T.level() })
        end

        banner('P6b: setup (ignore sounds)')
        local okRow = T.gotoRow('28')
        add('setup', { row28 = okRow, uid = T.uid() })
        T.sleep(800)

        if okRow then
            banner('P7: value steps - Subtitles x6')
            for _ = 1, 6 do
                T.pace(250)
                T.call('SET_INPUT_EVENT', 11)
                T.sleep(450)
            end
        end

        -- susturma denemeleri: aynı gezinme (P5) her yöntemle
        local function trial(name, on, off)
            banner(name .. ' - row nav x8')
            local okOn = on()
            add('mute', { name = name, result = tostring(okOn) })
            for _ = 1, 8 do T.nav(); T.sleep(350) end
            off()
        end
        trial('M1: stop PAUSE_MENU_SCENE', function() StopAudioScene('PAUSE_MENU_SCENE') return true end, function() end)
        trial('M2: frontend radio off', function() SetFrontendRadioActive(false) return true end, function() SetFrontendRadioActive(true) end)
        trial('M3: audio scene MP_LEADERBOARD_SCENE', function() return StartAudioScene('MP_LEADERBOARD_SCENE') end, function() StopAudioScene('MP_LEADERBOARD_SCENE') end)
        trial('M4: audio scene DEATH_SCENE', function() return StartAudioScene('DEATH_SCENE') end, function() StopAudioScene('DEATH_SCENE') end)

        -- G: Grafik sayfasında "bekleyen değişiklik" (GFX_Dirty) bağlam bayrağı okunabiliyor mu? Hiçbir şey UYGULANMAZ:
        -- değişiklikler geri alınır ve menü kapanınca bekleyen değer zaten atılır.
        banner('G: graphics dirty flag test')
        T.depth(-1)
        local DIRTY, ONGFX = GetHashKey('GFX_Dirty'), GetHashKey('ON_VID_GFX_MENU')
        local function ctx(h) local ok, v = pcall(PauseMenuIsContextActive, h) return ok and v or false end
        local okG = T.gotoCat('6') and T.depth(1)
        add('gsetup', { ok = okG, uid = T.uid(), level = T.level() })
        if okG then
            T.sleep(500)
            add('ctx', { tag = 'base', dirty = ctx(DIRTY), onGfx = ctx(ONGFX) })
            -- ilk satır (kimlik 103): iki seçenekli açık/kapalı
            T.pace(250); T.call('SET_INPUT_EVENT', 11); T.sleep(500)
            add('ctx', { tag = 'row103 right', dirty = ctx(DIRTY), uid = T.uid() })
            T.pace(250); T.call('SET_INPUT_EVENT', 10); T.sleep(500)
            add('ctx', { tag = 'row103 left', dirty = ctx(DIRTY) })
            -- kaydırıcı satırları: sona (en küçüğe) git, sonra sağa adım at, bayrak temizlenince adım sayısı = asıl değer
            for _, row in ipairs({ '80', '100' }) do
                if T.gotoRow(row) then
                    T.pace(250)
                    for _ = 1, 45 do T.call('SET_INPUT_EVENT', 10); T.sleep(70) end
                    T.sleep(300)
                    local d0 = ctx(DIRTY)
                    local steps = 0
                    while ctx(DIRTY) and steps < 120 do
                        T.call('SET_INPUT_EVENT', 11); T.sleep(120)
                        steps = steps + 1
                    end
                    add('slider', { row = row, dirtyAtZero = d0, stepsToClean = steps, cleanNow = not ctx(DIRTY) })
                else
                    add('slider', { row = row, missing = true })
                end
            end
            add('ctx', { tag = 'end', dirty = ctx(DIRTY) })
        end
    end

    if T.level() == '2' then
        banner('P8: leave and close')
        T.depth(-1)
    end
    T.shut()
    T.sleep(2500)
    local after = GetProfileSetting(203)
    add('subtitles', { before = before, after = after })
    banner('')
    GtaSet.busy = false
    say(('Lab finished. Subtitles %s -> %s'):format(tostring(before), tostring(after)))
    send({ before = before, after = after })
end

-- ---------------------------------------------------------------- /loe_gtaprof: StatSetProfileSettingValue ile doğrudan yazma
-- Belge: "Does not take effect immediately, unfortunately. profileSetting seems to only be 936, 937 and 938 in scripts".
-- GTA menüsü hiç açılmaz (ses de çıkmaz). Her yazmadan sonra GetProfileSetting ve ilgili native'ler zaman içinde okunur;
-- değerler sonda eski haline döner. Son aşamalarda SFX seviyesi 10 ve 0 yapılıp her biri 4 sn tık sesiyle dinlenir.
local function sample(tag, pid, extra)
    local d = { tag = tag, pid = pid, profile = GetProfileSetting(pid) }
    if extra then for k, fn in pairs(extra) do local ok, v = pcall(fn); d[k] = ok and v or ('ERR ' .. tostring(v)) end end
    add('sample', d)
end

local function writeTest(pid, value, extra)
    local before = GetProfileSetting(pid)
    add('write', { pid = pid, before = before, want = value })
    local ok, err = pcall(StatSetProfileSettingValue, pid, value)
    add('writeCall', { pid = pid, ok = ok, err = (not ok) and tostring(err) or nil })
    local waited = 0
    for _, ms in ipairs({ 50, 250, 1000, 3000 }) do      -- toplam bekleme bu noktalarda ölçülür
        Wait(ms - waited)
        waited = ms
        sample('after ' .. ms .. 'ms', pid, extra)
    end
    pcall(StatSetProfileSettingValue, pid, before)
    Wait(1500)
    sample('restored', pid, extra)
    return before
end

local function runProf()
    log, t0 = {}, GetGameTimer()
    GtaSet.busy = true
    banner('PROF: starting')
    Wait(1500)
    local ids = { 203, 212, 300, 301, 754, 13, 231, 227 }
    for _, pid in ipairs(ids) do sample('start', pid) end
    add('natives', {
        subtitles = IsSubtitlePreferenceSwitchedOn(), safezone = GetSafeZoneSize(), metric = ShouldUseMetricMeasurements(),
    })

    banner('W1: subtitles (203) toggle')
    local sub0 = GetProfileSetting(203)
    writeTest(203, sub0 == 1 and 0 or 1, { subtitlesOn = IsSubtitlePreferenceSwitchedOn })

    banner('W2: safe zone (212) -> 0 (100%)')
    writeTest(212, 0, { safezone = GetSafeZoneSize })

    banner('W3: measurement (227) toggle')
    local m0 = GetProfileSetting(227)
    writeTest(227, m0 == 1 and 0 or 1, { metric = ShouldUseMetricMeasurements })

    banner('W4: mouse look sens (754) +10')
    writeTest(754, GetProfileSetting(754) + 10)

    -- sesli deneme: SFX seviyesi (300) 10 ve 0; her aşamada 4 sn boyunca 500 ms'de bir ön yüz sesi çalınır
    local sfx0 = GetProfileSetting(300)
    local function clicks(ms)
        local e = GetGameTimer() + ms
        while GetGameTimer() < e do
            PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            Wait(500)
        end
    end
    banner('S0: clicks at your current SFX volume (4s)')
    clicks(4000)
    pcall(StatSetProfileSettingValue, 300, 10)
    Wait(300)
    banner('S1: SFX volume written = 10 - clicks (4s)')
    add('sfx', { step = 'to10', profile = GetProfileSetting(300) })
    clicks(4000)
    pcall(StatSetProfileSettingValue, 300, 0)
    Wait(300)
    banner('S2: SFX volume written = 0 - clicks (4s)')
    add('sfx', { step = 'to0', profile = GetProfileSetting(300) })
    clicks(4000)
    pcall(StatSetProfileSettingValue, 300, sfx0)
    Wait(300)
    banner('S3: SFX restored - clicks (4s)')
    add('sfx', { step = 'restored', profile = GetProfileSetting(300), want = sfx0 })
    clicks(4000)

    banner('')
    local final = {}
    for _, pid in ipairs(ids) do final[#final + 1] = { pid, GetProfileSetting(pid) } end
    GtaSet.busy = false
    say('Profile write test finished.')
    send({ final = final })
end

local function request()
    if busy or GtaSet.busy then say('Already running.') return end
    if IsPauseMenuActive() then say('Close the menu first.') return end
    busy = true
    TriggerServerEvent('loe_pause:server:gfxprobeAsk', 'lab')
    SetTimeout(5000, function() if busy and not GtaSet.busy then busy = false end end)
end

RegisterNetEvent('loe_pause:client:gfxprobeGo', function(_, allowed)
    if not allowed then
        busy = false
        say('You are not allowed to run this test.')
        return
    end
    CreateThread(function()
        Wait(1200)
        local ok, err = pcall(wantProf and runProf or run)
        wantProf = false
        if not ok then
            GtaSet.busy = false
            banner('')
            say('Lab error: ' .. tostring(err))
            send({ error = tostring(err) })
        end
        busy = false
    end)
end)

RegisterNetEvent('loe_pause:client:gfxprobeSaved', function(name)
    say(name and ('Saved: ' .. tostring(name)) or 'The server could not save the result.')
end)

RegisterCommand('loe_gtalab', request, false)

-- /loe_gtaprof: aynı yetki akışı, farklı deney
RegisterCommand('loe_gtaprof', function()
    if busy or GtaSet.busy then say('Already running.') return end
    if IsPauseMenuActive() then say('Close the menu first.') return end
    busy, wantProf = true, true
    TriggerServerEvent('loe_pause:server:gfxprobeAsk', 'prof')
    SetTimeout(5000, function() if busy and not GtaSet.busy then busy, wantProf = false, false end end)
end, false)
