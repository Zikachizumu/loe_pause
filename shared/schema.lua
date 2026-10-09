-- Ayarlar ekranının TEK doğruluk kaynağı (yalnızca veri, fonksiyon yok → NUI'ye JSON olarak gider).
--
-- Satır türleri:
--   toggle / select / slider : GERÇEKTEN uygulanan ayarlar (client/apply.lua'da karşılığı var, KVP'de saklanır)
--   key      : tuş atamasının güncel değerini OKUR (salt okunur; değiştirmek için FiveM tuş menüsüne yönlendirir)
--   action   : tek seferlik eylem (kayıt başlat, sıfırla...). 'confirm' varsa arayüz önce onay ister
--   native   : GTA/FiveM'in yerleşik menüsünde yönetilen ayar. Burada DEĞİŞTİRİLEMEZ; satır ilgili ekrana götürür
--   info     : açıklama notu
--
-- NUI'den gelen her değer client/prefs.lua içinde bu şemaya göre yeniden doğrulanır.

Schema = { categories = {}, actions = {} }

local features = (Config and Config.Features) or {}
local hijack = (Config and Config.Hijack) or {}

local function L(tr, en) return { tr = tr, en = en or tr } end

-- read: GTA'nın GÜNCEL değerini okuyabildiğimiz satırlarda bir anahtar (client/main.lua buildNativeValues). Yoksa yalnızca bağlantıdır.
local function native(tr, en, target, read) return { type = 'native', label = L(tr, en), target = target or 'settings', read = read } end
local function info(tr, en) return { type = 'info', text = L(tr, en) } end
local function key(tr, en, control) return { type = 'key', label = L(tr, en), control = control } end
local function group(id, tr, en, rows) return { id = id, label = L(tr, en), rows = rows } end
local function cat(id, icon, tr, en, groups) return { id = id, icon = icon, label = L(tr, en), groups = groups } end
local function toggle(id, tr, en, default, extra)
    local r = { id = id, type = 'toggle', label = L(tr, en), default = default }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end
local function slider(id, tr, en, min, max, step, default, extra)
    local r = { id = id, type = 'slider', label = L(tr, en), min = min, max = max, step = step, default = default }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end
local function opt(value, tr, en, extra)
    local o = { value = value, label = L(tr, en) }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end

local NOTE_NATIVE = info(
    'Bu bölümdeki ayarlar yalnızca GTA/FiveM\'in kendi menüsünden değiştirilebilir. Satırlara tıklayınca ilgili menü açılır.',
    'The settings in this section can only be changed from the built-in GTA/FiveM menu. Click a row to open it.')

-- ------------------------------------------------------------------ paylaşılan satırlar (iki yerde görünür, tek tanım)
local AIM_MODE = {
    id = 'aim.mode', type = 'select', default = 'game',
    label = L('Hedefleme modu', 'Targeting mode'),
    desc = L('Silah nişan davranışı. "Oyun varsayılanı" GTA ayarına dokunmaz.',
             'Weapon aiming behaviour. "Game default" leaves the GTA setting untouched.'),
    options = {
        opt('game',             'Oyun varsayılanı',        'Game default'),
        opt('assisted_full',    'Yardımlı nişan - Tam',    'Assisted aim - Full'),
        opt('assisted_partial', 'Yardımlı nişan - Kısmi',  'Assisted aim - Partial'),
        opt('free_assisted',    'Serbest nişan - Yardımlı', 'Free aim - Assisted'),
        opt('free',             'Serbest nişan',           'Free aim'),
    },
}

local TO_KEYBINDS = { type = 'native', label = L('Tuşları değiştir (FiveM tuş atamaları)', 'Change keys (FiveM key bindings)'), target = 'keybinds' }

local function keyGroup(id, tr, en, rows, note)
    local list = { TO_KEYBINDS }
    if note then list[#list + 1] = note end
    for _, r in ipairs(rows) do list[#list + 1] = r end
    return group(id, tr, en, list)
end

-- ------------------------------------------------------------------ 1. Oyun Kolu
Schema.categories[#Schema.categories + 1] = cat('controller', 'gamepad', 'Oyun Kolu', 'Controller', {
    group('aim', 'Hedefleme', 'Aiming', {
        AIM_MODE,
        native('Nişan hassasiyeti', 'Aiming sensitivity'),
    }),
    group('vibration', 'Titreşim ve Bakış', 'Vibration & Look', {
        NOTE_NATIVE,
        native('Titreşim', 'Vibration'),
        native('Bakışı ters çevir', 'Invert look'),
        native('Bakış hassasiyeti', 'Look sensitivity'),
    }),
    group('types', 'Kontrol Tipi', 'Control Type', {
        NOTE_NATIVE,
        native('Birinci şahıs kontrol tipi', 'First-person control type'),
        native('Üçüncü şahıs kontrol tipi', 'Third-person control type'),
    }),
})

-- ------------------------------------------------------------------ 2. Klavye / Fare
Schema.categories[#Schema.categories + 1] = cat('mouse', 'mouse', 'Klavye / Fare', 'Keyboard / Mouse', {
    group('sens', 'Fare Hassasiyeti', 'Mouse Sensitivity', {
        NOTE_NATIVE,
        native('Fare hassasiyeti', 'Mouse sensitivity'),
        native('Fare yumuşatma', 'Mouse smoothing'),
        native('Hassas nişan kontrolü', 'Precision aim control'),
        native('Ters bakış', 'Invert look'),
    }),
    group('aim', 'Nişan Alma', 'Aiming', {
        AIM_MODE,
        native('Nişan alma davranışı (basılı tut / aç-kapat)', 'Aim behaviour (hold / toggle)'),
    }),
    group('vehicles', 'Araç Kontrolleri', 'Vehicle Controls', {
        NOTE_NATIVE,
        native('Araç için fare kontrolü', 'Mouse control for vehicles'),
        native('Uçak için fare kontrolü', 'Mouse control for aircraft'),
        native('Denizaltı için fare kontrolü', 'Mouse control for submarines'),
    }),
})

-- ------------------------------------------------------------------ 3. Tuş Atamaları (salt okunur + FiveM tuş menüsüne köprü)
local NOTE_KEYS = info(
    'Aşağıdaki tuşlar GTA varsayılan kontrolleridir ve güncel atamayı gösterir. Sunucudaki özel sistemler (envanter, telefon...) kendi tuşlarını kullanabilir; onlar "FiveM" grubunda listelenir.',
    'The keys below are the GTA default controls and show the current binding. Server systems (inventory, phone...) may use their own keys; they are listed in the "FiveM" group.')

local fivemRows = {}
for _, m in ipairs(Config.KeyMappings or {}) do
    fivemRows[#fivemRows + 1] = { type = 'key', label = L(m.tr, m.en), command = m.command }
end

Schema.categories[#Schema.categories + 1] = cat('keys', 'keyboard', 'Tuş Atamaları', 'Key Bindings', {
    keyGroup('general', 'Genel', 'General', {
        key('Etkileşim', 'Interact', 51),
        key('Kamera değiştir', 'Switch camera', 0),
        key('Sohbet (yazı)', 'Chat (text)', 245),
        key('Bas-konuş (GTA)', 'Push to talk (GTA)', 249),
        key('Silah tekerleği', 'Weapon wheel', 37),
        key('Karakter tekerleği', 'Character wheel', 19),
    }, NOTE_KEYS),
    keyGroup('move', 'Hareket', 'Movement', {
        key('İleri', 'Forward', 32),
        key('Geri', 'Backward', 33),
        key('Sol', 'Left', 34),
        key('Sağ', 'Right', 35),
        key('Koş', 'Sprint', 21),
        key('Zıpla', 'Jump', 22),
        key('Çömel', 'Crouch', 36),
        key('Arkaya bak', 'Look behind', 26),
        key('Araca bin', 'Enter vehicle', 23),
    }),
    keyGroup('combat', 'Çatışma', 'Combat', {
        key('Ateş et', 'Fire', 24),
        key('Nişan al', 'Aim', 25),
        key('Siper al', 'Take cover', 44),
        key('Şarjör değiştir', 'Reload', 45),
        key('El bombası fırlat', 'Throw grenade', 58),
        key('Hafif yakın dövüş', 'Light melee', 140),
        key('Ağır yakın dövüş', 'Heavy melee', 141),
        key('Yakın dövüş bloğu', 'Melee block', 143),
    }),
    keyGroup('weapons', 'Silah Seçimi', 'Weapon Selection', {
        key('Sonraki silah', 'Next weapon', 14),
        key('Önceki silah', 'Previous weapon', 15),
        key('Silahsız', 'Unarmed', 157),
        key('Yakın dövüş silahı', 'Melee weapon', 158),
        key('Tabanca', 'Handgun', 159),
        key('Pompalı', 'Shotgun', 160),
        key('SMG', 'SMG', 161),
        key('Otomatik tüfek', 'Assault rifle', 162),
        key('Keskin nişancı', 'Sniper', 163),
        key('Ağır silah', 'Heavy weapon', 164),
        key('Özel silah', 'Special weapon', 165),
    }, info('Sunucuda silah ve eşya kısayolları envanter sistemi üzerinden yönetilir.',
            'On this server weapon and item hotkeys are handled by the inventory system.')),
    keyGroup('vehicles', 'Araçlar', 'Vehicles', {
        key('Gaz', 'Accelerate', 71),
        key('Fren / geri', 'Brake / reverse', 72),
        key('Sola dön', 'Steer left', 63),
        key('Sağa dön', 'Steer right', 64),
        key('El freni', 'Handbrake', 76),
        key('Korna', 'Horn', 86),
        key('Farlar', 'Headlights', 74),
        key('Araçtan in', 'Exit vehicle', 75),
        key('Arkaya bak', 'Look behind', 79),
        key('Sinematik kamera', 'Cinematic camera', 80),
        key('Radyo tekerleği', 'Radio wheel', 85),
        key('Sonraki radyo', 'Next radio station', 81),
        key('Önceki radyo', 'Previous radio station', 82),
    }),
    keyGroup('plane', 'Uçak', 'Aircraft', {
        key('Gaz artır', 'Throttle up', 87),
        key('Gaz azalt', 'Throttle down', 88),
        key('Sola sap', 'Yaw left', 89),
        key('Sağa sap', 'Yaw right', 90),
        key('Sola yatış', 'Roll left', 108),
        key('Sağa yatış', 'Roll right', 109),
        key('Burun yukarı', 'Pitch up', 111),
        key('Burun aşağı', 'Pitch down', 112),
        key('İniş takımı', 'Landing gear', 113),
        key('Silah / saldırı', 'Weapon / attack', 114),
    }),
    keyGroup('sub', 'Denizaltı', 'Submarine', {
        key('Sola dön', 'Turn left', 124),
        key('Sağa dön', 'Turn right', 125),
        key('Burun yukarı', 'Pitch up', 127),
        key('Burun aşağı', 'Pitch down', 128),
        key('Gaz artır', 'Throttle up', 129),
        key('Gaz azalt', 'Throttle down', 130),
        key('Yüksel', 'Ascend', 131),
        key('Dal', 'Descend', 132),
    }),
    keyGroup('parachute', 'Paraşüt', 'Parachute', {
        key('Paraşütü aç', 'Deploy parachute', 144),
        key('Paraşütten ayrıl', 'Detach parachute', 145),
        key('Sola dön', 'Turn left', 147),
        key('Sağa dön', 'Turn right', 148),
        key('Burun yukarı', 'Pitch up', 150),
        key('Burun aşağı', 'Pitch down', 151),
        key('Sol fren', 'Brake left', 152),
        key('Sağ fren', 'Brake right', 153),
    }),
    keyGroup('phone', 'Cep Telefonu', 'Cell Phone', {
        key('Telefonu aç (GTA)', 'Open phone (GTA)', 27),
        key('Yukarı', 'Up', 172),
        key('Aşağı', 'Down', 173),
        key('Sol', 'Left', 174),
        key('Sağ', 'Right', 175),
        key('Seç', 'Select', 176),
        key('İptal', 'Cancel', 177),
    }, info('Sunucudaki telefon (loe_telephone) kendi tuşunu kullanır; o tuş "FiveM" grubunda görünür.',
            'The in-server phone (loe_telephone) uses its own key; look for it in the "FiveM" group.')),
    keyGroup('fivem', 'FiveM', 'FiveM', fivemRows,
        info('Sunucu scriptlerinin kayıtlı tuşları. Atanmamış olanlar listelenmez.',
             'Keys registered by server scripts. Unbound ones are not listed.')),
})

-- ------------------------------------------------------------------ 4. Ses
Schema.categories[#Schema.categories + 1] = cat('audio', 'speaker', 'Ses', 'Audio', {
    group('levels', 'Ses Seviyeleri', 'Volume Levels', {
        NOTE_NATIVE,
        native('Efekt seviyesi', 'Sound effects level'),
        native('Müzik seviyesi', 'Music level'),
        native('Diyalog seviyesi', 'Dialogue level'),
    }),
    group('radio', 'Radyo', 'Radio', {
        toggle('audio.vehradio', 'Araç radyosu', 'Vehicle radio', true, {
            desc = L('Kapalıyken araçlarda radyo çalmaz ve radyo tekerleği devre dışı kalır.',
                     'When off, vehicle radios stay silent and the radio wheel is disabled.'),
        }),
        native('Radyo istasyonlarını düzenle', 'Edit radio stations'),
    }),
    group('output', 'Cihaz ve Odak', 'Device & Focus', {
        NOTE_NATIVE,
        native('Ses çıkış cihazı', 'Audio output device'),
        native('Oyun odağı kaybolunca sesi kapat', 'Mute when game loses focus'),
    }),
})

-- ------------------------------------------------------------------ 5. Kamera
local camOptions = function()
    return {
        opt('game',   'Oyun varsayılanı', 'Game default'),
        opt('near',   'Yakın',            'Near'),
        opt('medium', 'Orta',             'Medium'),
        opt('far',    'Uzak',             'Far'),
        opt('first',  'Birinci şahıs',    'First person'),
    }
end
local cameraRows = {}
if features.cameraOverrides ~= false then
    cameraRows = {
        { id = 'cam.foot', type = 'select', default = 'game', label = L('Yürürken kamera', 'On-foot camera'),
          desc = L('Giriş yaptığında ve ayarı değiştirdiğinde uygulanır; sonra V ile serbestçe değiştirebilirsin.',
                   'Applied on login and when changed; you can still cycle with V afterwards.'),
          options = camOptions() },
        { id = 'cam.vehicle', type = 'select', default = 'game', label = L('Araç kamerası', 'Vehicle camera'),
          desc = L('Araca bindiğinde uygulanır.', 'Applied each time you get into a vehicle.'),
          options = camOptions() },
        toggle('cam.cinematic', 'Sinematik kamera tuşu', 'Cinematic camera button', true, {
            desc = L('Kapalıyken sinematik kamera tuşu çalışmaz.', 'When off, the cinematic camera button does nothing.'),
        }),
    }
end
Schema.categories[#Schema.categories + 1] = cat('camera', 'camera', 'Kamera', 'Camera', {
    group('view', 'Görüş Modu', 'View Mode', cameraRows),
    group('fine', 'Kamera Ayarları', 'Camera Settings', {
        NOTE_NATIVE,
        native('Araç kamera yüksekliği', 'Vehicle camera height'),
        native('Birinci şahıs görüş açısı (FOV)', 'First-person field of view'),
        native('Birinci şahıs araç kamerası', 'First-person vehicle camera'),
        native('Kamera sarsıntısı', 'Camera shake'),
    }),
})

-- ------------------------------------------------------------------ 6. Görüntü
Schema.categories[#Schema.categories + 1] = cat('display', 'monitor', 'Görüntü', 'Display', {
    group('hud', 'HUD ve Radar', 'HUD & Radar', {
        toggle('disp.radar', 'Radar ve HUD', 'Radar & HUD', true, {
            desc = L('Kapalıyken minimap ve minimap\'e bağlı tüm HUD panelleri gizlenir.',
                     'When off, the minimap and every HUD panel tied to it are hidden.'),
        }),
        toggle('disp.reticle', 'Nişangâh', 'Crosshair', true),
        toggle('disp.gps', 'GPS rotası', 'GPS route', true, {
            desc = L('Kapalıyken harita işaretinin yol çizgisi gösterilmez.', 'When off, the waypoint route line is hidden.'),
        }),
        native('Nişangâh boyutu', 'Crosshair size'),
        native('Silah hedefi göstergesi', 'Weapon target indicator'),
    }),
    group('screen', 'Ekran', 'Screen', {
        NOTE_NATIVE,
        native('Parlaklık', 'Brightness'),
        native('Güvenli alan', 'Safe zone', nil, 'safezone'),
        native('Altyazılar', 'Subtitles', nil, 'subtitles'),
        native('Ölçü birimi', 'Measurement units', nil, 'metric'),
        native('Oyun dili', 'Game language', nil, 'language'),
    }),
})

-- ------------------------------------------------------------------ 7. Grafikler
Schema.categories[#Schema.categories + 1] = cat('graphics', 'chip', 'Grafikler', 'Graphics', {
    group('screen', 'Ekran', 'Screen', {
        NOTE_NATIVE,
        native('Çözünürlük', 'Resolution', nil, 'resolution'),
        native('Ekran seçimi', 'Display selection'),
        native('FXAA', 'FXAA'),
        native('MSAA', 'MSAA'),
        native('VSync', 'VSync'),
        native('Odak kaybında oyunu duraklat', 'Pause game on focus loss'),
    }),
    group('quality', 'Kalite', 'Quality', {
        NOTE_NATIVE,
        native('Doku kalitesi', 'Texture quality'),
        native('Gölge kalitesi', 'Shadow quality'),
        native('Yansıma kalitesi', 'Reflection quality'),
        native('Su kalitesi', 'Water quality'),
        native('Parçacık kalitesi', 'Particle quality'),
        native('Çimen kalitesi', 'Grass quality'),
    }),
    group('distance', 'Mesafe Ayrıntıları', 'Distance Detail', {
        NOTE_NATIVE,
        native('Nüfus yoğunluğu', 'Population density'),
        native('Nüfus çeşitliliği', 'Population variety'),
        native('Uzak nesne mesafesi', 'Distance scaling'),
    }),
})

-- ------------------------------------------------------------------ 8. Gelişmiş Grafikler
local advDistRows = { NOTE_NATIVE }
if features.lodScale ~= false then
    advDistRows[#advDistRows + 1] = slider('gfx.lod', 'Mesafe ayrıntısı ölçeği', 'Distance detail scale', 1.0, 2.0, 0.1, 1.0, {
        unit = 'x', decimals = 1,
        desc = L('Uzaktaki nesnelerin ayrıntı mesafesini artırır. 1.0 = oyun varsayılanı. Performansı düşürebilir.',
                 'Increases how far objects keep their detail. 1.0 = game default. May reduce performance.'),
    })
end
advDistRows[#advDistRows + 1] = native('Uzun gölge mesafesi', 'Long shadows')
advDistRows[#advDistRows + 1] = native('Yüksek çözünürlüklü gölgeler', 'High-resolution shadows')
advDistRows[#advDistRows + 1] = native('Yüksek detaylı akış', 'High detail streaming while flying')
Schema.categories[#Schema.categories + 1] = cat('advgfx', 'sliders', 'Gelişmiş Grafikler', 'Advanced Graphics', {
    group('distance', 'Mesafe', 'Distance', advDistRows),
    group('effects', 'Efektler', 'Effects', {
        NOTE_NATIVE,
        native('Gölge yumuşatma', 'Soft shadows'),
        native('Yansıma MSAA', 'Reflection MSAA'),
        native('Anizotropik filtreleme', 'Anisotropic filtering'),
        native('Ortam kapanması (SSAO)', 'Ambient occlusion'),
        native('Tessellation', 'Tessellation'),
        native('Sonradan işleme (Post FX)', 'Post FX'),
    }),
})

-- ------------------------------------------------------------------ 9. Sesli Sohbet
local voiceLevels, voiceMic = {}, {}
if features.voice ~= false then
    local pct = { unit = '%', decimals = 0 }
    voiceLevels = {
        slider('voice.radio', 'Telsiz ses seviyesi', 'Radio volume', 0, 100, 5, 60, pct),
        slider('voice.call', 'Arama ses seviyesi', 'Call volume', 0, 100, 5, 60, pct),
    }
    voiceMic = {
        toggle('voice.clicks', 'Mikrofon tık sesi', 'Microphone click sound', true),
        slider('voice.click_on', 'Tık sesi (açılış)', 'Click volume (on)', 0, 100, 1, 10, pct),
        slider('voice.click_off', 'Tık sesi (kapanış)', 'Click volume (off)', 0, 100, 1, 3, pct),
    }
end
Schema.categories[#Schema.categories + 1] = cat('voice', 'mic', 'Sesli Sohbet', 'Voice Chat', {
    group('levels', 'Seviyeler', 'Levels', voiceLevels),
    group('mic', 'Mikrofon Tıkı', 'Mic Click', voiceMic),
    group('devices', 'Cihazlar', 'Devices', {
        NOTE_NATIVE,
        native('Sesli sohbeti aç / kapat', 'Enable / disable voice chat'),
        native('Mikrofon aygıtı', 'Microphone device'),
        native('Ses çıkış aygıtı', 'Voice output device'),
        native('Mikrofon seviyesi', 'Microphone level'),
        native('Sohbet seviyesi', 'Chat volume'),
    }),
})

-- ------------------------------------------------------------------ 10. Rockstar Editor
local editorRows = {}
if features.recording ~= false then
    editorRows = {
        { id = 'rec.start', type = 'action', label = L('Kaydı başlat', 'Start recording'), button = L('Başlat', 'Start'),
          desc = L('Rockstar Editor klibi kaydını başlatır.', 'Starts recording a Rockstar Editor clip.') },
        { id = 'rec.save', type = 'action', label = L('Kaydet ve bitir', 'Save and stop'), button = L('Kaydet', 'Save'),
          desc = L('Kaydı durdurur ve klibi kaydeder.', 'Stops recording and saves the clip.') },
        { id = 'rec.discard', type = 'action', label = L('Kaydı iptal et', 'Discard recording'), button = L('İptal', 'Discard'),
          desc = L('Kaydı durdurur ve klibi siler.', 'Stops recording and deletes the clip.') },
    }
end
editorRows[#editorRows + 1] = info(
    'Klipleri düzenlemek için oyun dışındaki ana menüden Rockstar Editor\'ü aç. Sunucu kurallarına uygun kayıt yap.',
    'To edit clips, open Rockstar Editor from the game\'s main menu. Record in line with server rules.')
Schema.categories[#Schema.categories + 1] = cat('editor', 'film', 'Rockstar Editor', 'Rockstar Editor', {
    group('record', 'Kayıt', 'Recording', editorRows),
})

-- ------------------------------------------------------------------ 11. Kayıt ve Başlangıç
Schema.categories[#Schema.categories + 1] = cat('startup', 'save', 'Kayıt ve Başlangıç', 'Save & Startup', {
    group('startup', 'Başlangıç', 'Startup', {
        info('GTA\'nın kayıt yükleme ve başlangıç akışı seçenekleri FiveM\'de uygulanmaz: oyuna giriş FiveM istemcisi ve sunucu tarafından yönetilir, karakter verisi sunucuda saklanır.',
             'GTA\'s save-loading and startup-flow options do not apply in FiveM: joining is handled by the FiveM client and the server, and character data is stored server-side.'),
        info('Bu bölümde değiştirilebilir bir ayar yoktur.', 'There are no adjustable settings in this section.'),
    }),
})

-- ------------------------------------------------------------------ 12. Tercihler (LOE arayüzü; oyuncu bazında KVP)
Schema.categories[#Schema.categories + 1] = cat('prefs', 'palette', 'Tercihler', 'Preferences', {
    group('look', 'Görünüm', 'Appearance', {
        { id = 'pref.accent', type = 'select', default = 'magenta', label = L('Vurgu rengi', 'Accent colour'),
          options = {
              opt('magenta', 'Magenta', 'Magenta', { color = '#ff2e93' }),
              opt('purple',  'Mor',     'Purple',  { color = '#a855f7' }),
              opt('blue',    'Mavi',    'Blue',    { color = '#38bdf8' }),
              opt('green',   'Yeşil',   'Green',   { color = '#34d399' }),
              opt('orange',  'Turuncu', 'Orange',  { color = '#fb923c' }),
              opt('red',     'Kırmızı', 'Red',     { color = '#ef4444' }),
          } },
        toggle('pref.dark', 'Koyu mod', 'Dark mode', true),
        toggle('pref.portrait', 'Portre modu', 'Portrait mode', false, {
            desc = L('Menüyü dar/dikey ekranlar için alt alta dizer. Dar ekranlarda otomatik açılır.',
                     'Stacks the menu for narrow/tall screens. Turns on automatically on narrow displays.'),
        }),
        { id = 'pref.lang', type = 'select', default = 'tr', label = L('Dil', 'Language'),
          desc = L('Bu menünün dilini değiştirir; oyunun kendi dili GTA ayarlarındadır.',
                   'Changes the language of this menu; the game\'s own language is in the GTA settings.'),
          options = { opt('tr', 'Türkçe', 'Türkçe'), opt('en', 'English', 'English') } },
        { id = 'pref.reset', type = 'action', label = L('Görünümü Sıfırla', 'Reset Appearance'), button = L('Sıfırla', 'Reset'),
          desc = L('Vurgu rengi, koyu mod, portre modu, dil ve harita dönüşü varsayılana döner.',
                   'Accent colour, dark mode, portrait mode, language and map return go back to defaults.'),
          confirm = {
              title = L('Görünümü sıfırla?', 'Reset appearance?'),
              text = L('Görünüm tercihlerin varsayılana döner. Oyun ayarların etkilenmez.',
                       'Your appearance preferences return to defaults. Your game settings are not affected.'),
              yes = L('Evet, sıfırla', 'Yes, reset'), no = L('Vazgeç', 'Cancel'),
          } },
    }),
    group('behavior', 'Menü Davranışı', 'Menu Behaviour', {
        toggle('pref.mapReturn', 'Haritadan dönüş animasyonu', 'Map return animation', false, {
            desc = L('Açıkken harita ve yerleşik GTA menüleri ESC ile kapanınca bu menü animasyonla geri gelir; kapalıyken doğrudan oyuna dönersin.',
                     'When on, closing the map or a built-in GTA menu with ESC brings this menu back with an animation; when off you return straight to the game.'),
        }),
    }),
})

-- ------------------------------------------------------------------ 13. Normal Menü
-- Config.Hijack.allowNativeMenu = false (varsayılan) → bu kategori arayüzde GÖRÜNMEZ ve ESC her zaman bu menüyü açar
-- (satırlar şemada kalır; böylece eski KVP değerleri doğrulanır ama hiçbir etkisi olmaz).
Schema.categories[#Schema.categories + 1] = cat('menu', 'menu', 'Normal Menü', 'Standard Menu', {
    group('menu', 'Duraklatma Menüsü', 'Pause Menu', {
        toggle('menu.native', 'ESC ile yerleşik GTA menüsünü kullan', 'Use the built-in GTA menu on ESC', false, {
            desc = L('Açıkken ESC/P yerleşik menüyü açar. Bu menüye /loepause komutuyla ulaşabilirsin.',
                     'When on, ESC/P opens the built-in menu. You can reach this menu with /loepause.'),
        }),
        { id = 'menu.opennative', type = 'action', label = L('Yerleşik GTA menüsünü şimdi aç', 'Open the built-in GTA menu now'),
          button = L('Aç', 'Open') },
        info('Bu menü bir sorun çıkarırsa yerleşik menüye geçmek için yukarıdaki seçeneği aç.',
             'If this menu ever misbehaves, switch to the built-in menu with the option above.'),
    }),
})
Schema.categories[#Schema.categories].hidden = hijack.allowNativeMenu ~= true

-- ------------------------------------------------------------------ yardımcı indeksler
-- Boş grupları at (özellik kapatılınca boş kalan gruplar arayüzde görünmesin).
for _, c in ipairs(Schema.categories) do
    local kept = {}
    for _, g in ipairs(c.groups) do
        if #g.rows > 0 then kept[#kept + 1] = g end
    end
    c.groups = kept
end

Schema.rows = {}   -- id -> satır (yalnızca ayarlanabilir satırlar: toggle/select/slider)
for _, c in ipairs(Schema.categories) do
    for _, g in ipairs(c.groups) do
        for _, r in ipairs(g.rows) do
            if r.id then
                if r.type == 'action' then
                    Schema.actions[r.id] = r
                elseif r.type == 'toggle' or r.type == 'select' or r.type == 'slider' then
                    Schema.rows[r.id] = r
                end
            end
        end
    end
end
