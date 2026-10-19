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
        local ok, err = pcall(run)
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
