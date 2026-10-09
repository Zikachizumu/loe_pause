-- "Oyundan Çık → Sunucudan ayrıl": oyuncuyu sunucudan ayırır (FiveM ana menüsüne düşer).
-- İstemcideki ExecuteCommand('disconnect') her sürümde güvenilir çalışmadığı için kesin yol sunucudan DropPlayer'dır.
-- Yalnızca olayı gönderen oyuncunun KENDİSİ düşürülür; başka oyuncu hedeflenemez.

local REASON = 'Sunucudan ayrıldın. Tekrar görüşmek üzere!'
local lastLeave = {}

RegisterNetEvent('loe_pause:server:leave', function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end

    local now = GetGameTimer()
    if lastLeave[src] and now - lastLeave[src] < 3000 then return end   -- art arda istek
    lastLeave[src] = now

    DropPlayer(src, REASON)
end)

-- Hızlı Eylemler görünürlüğü: yalnızca Config.Shortcuts'ta `aces` tanımlı satırlar için, oyuncunun o ACE'lerden birine
-- sahip olup olmadığını söyler. Bu yalnızca arayüzde satırı gösterir; asıl yetki kontrolü komutun kendi resource'undadır.
local lastCaps = {}

RegisterNetEvent('loe_pause:server:caps', function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end

    local now = GetGameTimer()
    if lastCaps[src] and now - lastCaps[src] < 2000 then return end
    lastCaps[src] = now

    local allowed = {}
    for _, s in ipairs(Config.Shortcuts or {}) do
        if type(s.id) == 'string' and type(s.aces) == 'table' then
            for _, ace in ipairs(s.aces) do
                if IsPlayerAceAllowed(src, ace) then allowed[#allowed + 1] = s.id break end
            end
        end
    end
    TriggerClientEvent('loe_pause:client:caps', src, allowed)
end)

AddEventHandler('playerDropped', function()
    lastLeave[source] = nil
    lastCaps[source] = nil
end)
