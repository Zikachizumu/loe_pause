Config = {}

-- ================================================================ GENEL
Config.Command = 'loepause'   -- /loepause : menüyü elle açar/kapatır (yerleşik menü tercih edilse bile çalışır)
Config.OpenKey = ''           -- RegisterKeyMapping varsayılanı. Boş = atanmamış; oyuncu FiveM tuş ayarlarından verebilir.
Config.Debug   = false

Config.Brand = {
    name   = 'LEGENDS OF',
    accent = 'EMPIRE',                        -- vurgu renginde yazılan kısım
    footer = 'LEGENDS OF EMPIRE ROLEPLAY',
}

-- Arka plan. mode = 'image' → html/img/bg.jpg (tasarım referansı), 'game' → canlı oyun + bulanıklık.
-- Kendi görselini kullanmak için html/img/bg.jpg dosyasını değiştirmen yeterli (16:9, tercihen 1920x1080+).
Config.Background = {
    mode = 'image',
    image = 'img/bg.jpg',
}

-- ================================================================ ESC / P YAKALAMA
-- Yerleşik duraklatma menüsü açıldığı anda kapatılır ve bu menü açılır.
-- Diğer NUI'ler (envanter, loe_apt, loe_dealership...) ESC ile kapanırken aynı basış bu menüyü AÇMAZ.
Config.Hijack = {
    enabled          = true,
    requireLogin     = true,   -- LocalPlayer.state.isLoggedIn == true olmadan devralma (karakter seçimi/yaratma bozulmasın)
    nuiGraceMs       = 450,    -- başka bir NUI'nin odağı bu kadar yeni bıraktıysa ESC'yi yut
    reopenCooldownMs = 450,    -- kapanıştan hemen sonra gelen (sızan) ESC'yi yut
    blurGame         = false,  -- true: menü açıkken oyun ekranına bulanıklık (Background.mode = 'game' için anlamlı)
    allowNativeMenu  = false,  -- false: yerleşik GTA duraklatma menüsü ESC/P ile ASLA açılmaz ve "Normal Menü" kategorisi gizlenir.
                               -- true: oyuncular ayarlardan yerleşik menüye geçebilir (arıza durumunda kaçış kapısı).
}

-- ================================================================ ANA MENÜ
-- Sıra sabittir (Harita, İstatistikler, Battlepass, Shop, Ayarlar, Oyundan Çık).
-- enabled = false → satır gizlenir.
-- resource/export: bu resource 'started' ise export çağrılır; değilse satır "Yakında" sayfası gösterir.
Config.Menu = {
    { id = 'map',        enabled = true },
    { id = 'stats',      enabled = true },   -- resource verirsen harici istatistik sistemi açılır; yoksa yerleşik karakter özeti (+ hastalık durumu)
    { id = 'battlepass', enabled = true, resource = 'loe_battlepass', export = 'Open' },
    { id = 'shop',       enabled = true, resource = 'loe_shop',       export = 'Open' },
    { id = 'settings',   enabled = true },
    { id = 'quit',       enabled = true },
}

-- Harita: loe_3dmap varsa onu açar, yoksa yerleşik GTA haritasına düşer.
Config.MapResource = { resource = 'loe_3dmap', open = 'Open', isOpen = 'IsOpen' }

-- İstatistik sayfasındaki "Sağlık" kartı: hastalık sistemi loe_jobcreator'dadır. Menü o resource'a dokunmaz; yalnızca sunucunun
-- bu oyuncuya zaten gönderdiği durum olayını dinler (resource/olay adları değişirse buradan güncelle).
Config.Health = {
    resource   = 'loe_jobcreator',
    event      = 'loe_jobcreator:client:healthState',   -- sunucu → istemci: { enabled, conditions = { { label, symptom, bandaged, suppressed } } }
    helloEvent = 'loe_jobcreator:server:healthHello',   -- loe_pause sonradan başlarsa güncel durumu yeniden ister (tekrar çağrılabilir)
}

-- Yerleşik GTA menüsüne geçişler. DOĞRULAMA GEREKİR: menü hash'leri sürümden sürüme farklı davranabilir;
-- çalışmayan olursa buradan değiştir (kod değişikliği gerekmez). Hash listesi: ActivateFrontendMenu dokümanı.
-- deeper: menü açıldıktan sonra PauseMenuceptionGoDeeper(deeper) ile o sayfaya girer (0 = büyük harita).
Config.Native = {
    map      = { menu = 'FE_MENU_VERSION_MP_PAUSE',               pause = false, component = -1, deeper = 0, deeperDelayMs = 100 },
    game     = { menu = 'FE_MENU_VERSION_LANDING_MENU',           pause = true,  component = -1 },
    settings = { menu = 'FE_MENU_VERSION_LANDING_MENU',           pause = true,  component = -1 },
    keybinds = { menu = 'FE_MENU_VERSION_LANDING_KEYMAPPING_MENU', pause = true,  component = -1 },
}

-- ================================================================ ÖZELLİKLER
-- false yapılan özellik arayüzden tamamen kalkar ve uygulanmaz.
Config.Features = {
    recording = true,    -- Rockstar Editor: kayıt başlat / kaydet / iptal
    lodScale  = true,    -- Gelişmiş Grafikler: mesafe ayrıntısı ölçeği (OverrideLodscaleThisFrame, performansı etkiler)
    voice     = true,    -- Sesli Sohbet: pma-voice seviyeleri (pma-voice yoksa satırlar çalışmaz)
    cameraOverrides = true, -- Kamera: varsayılan görüş modu / sinematik kamera
}

-- ================================================================ VARSAYILANLAR
-- Oyuncu bir şeyi değiştirmediyse geçerli olan değerler. Verilmeyen id'ler schema.lua'daki varsayılanı kullanır.
-- Görünüm tercihleri oyuncu bazında KVP'de saklanır; buradaki değerler yalnızca başlangıç değeridir.
Config.Defaults = {
    ['pref.lang']      = 'tr',        -- 'tr' | 'en'
    ['pref.accent']    = 'magenta',   -- magenta | purple | blue | green | orange | red
    ['pref.dark']      = true,
    ['pref.portrait']  = false,
    ['pref.mapReturn'] = false,       -- true: harita / yerleşik menü kapanınca LOE menüsüne animasyonla dön (false: doğrudan oyuna)
    ['menu.native']    = false,       -- true: ESC yerleşik GTA menüsünü açar
}

-- ================================================================ HIZLI EYLEMLER
-- Sunucuya eklenen kısayolların (RegisterKeyMapping komutları) menüden çalıştırılması: Ayarlar → Tuş Atamaları → Hızlı Eylemler.
-- Böylece oyuncunun FiveM'in "Key Bindings → FiveM" ekranına gitmesi gerekmez. Yalnızca '+' ile BAŞLAMAYAN (bas-bırak olmayan,
-- tek seferlik) komutlar eklenebilir. Menü kapanır, kısa bir bekleme sonrası komut çalıştırılır.
-- aces verilirse satır yalnızca o ACE'lerden birine sahip oyunculara görünür (sunucu doğrular). Asıl yetki kontrolü yine komutun
-- kendi resource'unda yapılır; bu liste yalnızca görünürlüğü belirler.
Config.Shortcuts = {
    { id = 'cursor',    command = 'imlec',               tr = 'Fare imlecini aç/kapat',    en = 'Toggle mouse cursor' },
    { id = 'photo',     command = 'loe_hud_photomode',   tr = 'Fotoğraf modu (HUD gizle)', en = 'Photo mode (hide HUD)' },
    { id = 'minimap',   command = 'loe_hud_minimapzoom', tr = 'Minimap uzaklaştır (5 sn)', en = 'Minimap zoom out (5 s)' },
    { id = 'vehkeys',   command = 'aractuslari',         tr = 'Araç tuş ayarları',         en = 'Vehicle key settings' },
    { id = 'propexit',  command = 'loecik',              tr = 'Acil çıkış (mülk)',         en = 'Emergency exit (property)' },
    { id = 'proximity', command = 'cycleproximity',      tr = 'Konuşma mesafesi',          en = 'Cycle voice proximity' },
    { id = 'admin',     command = 'admin',               tr = 'Yönetici paneli / Geliştirici modu', en = 'Admin panel / Developer mode',
      aces = { 'admin' },
      desc = { tr = 'Yalnızca yetkililere görünür. Geliştirici modu panelin içinden açılır.', en = 'Visible to staff only. Developer mode is switched on inside the panel.' } },
}

-- ================================================================ TUŞ ATAMALARI → "FiveM" grubu
-- RegisterKeyMapping ile kayıtlı komutların GÜNCEL tuşu okunur (salt okunur). Okunamayan/atanmamış olanlar listelenmez.
-- command: RegisterKeyMapping'e verilen tam ad ('+inv' gibi ox_lib keybind'leri '+' ile başlar).
Config.KeyMappings = {
    { tr = '3D Harita',             en = '3D map',               command = '3dmap' },
    { tr = 'Fare imleci',           en = 'Mouse cursor',         command = 'imlec' },
    { tr = 'Minimap uzaklaştır',    en = 'Minimap zoom out',     command = 'loe_hud_minimapzoom' },
    { tr = 'Fotoğraf modu',         en = 'Photo mode',           command = 'loe_hud_photomode' },
    { tr = 'Envanter',              en = 'Inventory',            command = '+inv' },
    { tr = 'İkincil envanter',      en = 'Secondary inventory',  command = '+inv2' },
    { tr = 'Hızlı erişim çubuğu',   en = 'Hotbar',               command = '+hotbar' },
    { tr = 'Silahı doldur',         en = 'Reload weapon',        command = '+reloadweapon' },
    { tr = 'Araç kilidi',           en = 'Toggle vehicle lock',  command = '+togglelocks' },
    { tr = 'Motoru aç/kapat',       en = 'Toggle engine',        command = '+toggleengine' },
    { tr = 'Araç tuş ayarları',     en = 'Vehicle key settings', command = 'aractuslari' },
    { tr = 'Telsiz konuşma',        en = 'Radio talk',           command = '+radiotalk' },
    { tr = 'Konuşma mesafesi',      en = 'Cycle proximity',      command = 'cycleproximity' },
    { tr = 'Acil çıkış (mülk)',     en = 'Emergency exit',       command = 'loecik' },
}
