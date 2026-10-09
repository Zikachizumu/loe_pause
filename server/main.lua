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

AddEventHandler('playerDropped', function()
    lastLeave[source] = nil
end)
