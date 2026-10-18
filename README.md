# loe_pause

Legends of Empire (LOE) için **Pause Menü + Ayarlar ekranı**. ESC / P ile açılan yerleşik GTA duraklatma menüsünün yerine geçen FiveM NUI menüsü (Qbox, `[loe]` kategorisi).

- Ana menü (tasarım: `PMenü.mp4` referans videosu): **RESUME · MAP · GAME SETTINGS · UI SETTINGS · POSITION MODE** ve altta **DISCONNECT**; başlıkta seçili maddenin adı "karıştırma" efektiyle yazılır, sol altta oyuncu kartı (ad [id], meslek, nakit / banka), sağ üstte bağlantılar, sağ altta "ALL GTA SETTINGS"
- Ayarlar: 3 bölümlü ekran (kategoriler · alt kategoriler · arama + ayar satırları), klavye + fare, **İngilizce (varsayılan)** / Türkçe (Arayüz Ayarları → Language). Yeni metinler önce İngilizce yazılır (`Config.Defaults['pref.lang']`)
- Bağımlılık yok: `qbx_core`, `pma-voice`, `loe_3dmap` yalnızca **varsa** (pcall) kullanılır; `ox_lib` gerekmez.

## Kurulum

```
resources/[loe]/loe_pause      →  server.cfg'de zaten `ensure [loe]` var; ayrıca satır eklemek gerekmez.
```

Resource ilk kez eklendiği için **sunucu restart** (ya da txAdmin'den `ensure loe_pause`) gerekir.
`loe_hud` aktifken menü açıkken radar gizlenir, loe_hud'ın minimap eşitlemesi sayesinde HUD de gizlenir.

### Güncelleme (git)

```bash
runuser -u fivem -- git -C "/opt/fivem/txData/LegendsofEmpire_AC516C.base/resources/[loe]/loe_pause" pull
```

Sonra txAdmin konsolunda `restart loe_pause`. **`fxmanifest.lua` değiştiyse** (yeni script/dosya eklendiyse) önce `refresh` çalıştır:
FXServer manifesti yalnızca `refresh`/sunucu açılışında okur; tek başına `restart` yeni eklenen script'i YÜKLEMEZ.

## Dosyalar

| Dosya | Görev |
|---|---|
| `fxmanifest.lua` | Manifest (`ui_page`, paylaşımlı/client/server scriptler) |
| `config.lua` | Marka, arka plan, ESC yakalama, ana menü, harita/native menü bağlantıları, özellik anahtarları, varsayılanlar, FiveM tuş listesi |
| `shared/schema.lua` | **Ayarlar ekranının tek doğruluk kaynağı** (kategoriler, gruplar, satırlar, tr/en metinler) |
| `client/prefs.lua` | Şemaya göre doğrulama + oyuncu bazında KVP kalıcılığı |
| `client/apply.lua` | Ayarları oyuna uygulayan native çağrıları + eylemler (kayıt, sıfırlama) |
| `server/main.lua` | "Sunucudan ayrıl": olayı gönderen oyuncuyu `DropPlayer` ile düşürür (3 sn sınırı); Hızlı Eylemler için yetki (ACE) görünürlüğü |
| `client/main.lua` | ESC/P yakalama, aç/kapat, NUI odağı, NUI callback'leri, harita/yerleşik menü geçişleri |
| `html/` | NUI (vanilla HTML/CSS/JS), `html/fonts/` yerel Montserrat (OFL, bkz. NOTICE.txt) |
| `_dev/` | Yalnızca geliştirme: `check.py` (Lua/şema/doğrulama testleri), `mock.html` (tarayıcıda önizleme) |

## ESC nasıl yönetiliyor

1. Yerleşik menü açıldığı kare tespit edilir (`IsPauseMenuActive`) ve hemen kapatılır; bu menü açılır. (Başka resource'lar — `loe_apt` gibi — kontrol seviyesinde ESC'nin engellenemediğini zaten belgelemişti.)
2. Menü açıkken oyun kontrolleri kapatılır, radar gizlenir; kapanınca radar önceki durumuna döner, NUI odağı bırakılır.
3. Başka bir NUI (envanter, `loe_apt`, `loe_dealership`, `loe_cursor`...) ESC ile **kapanırken** aynı basış bu menüyü **açmaz** (`Config.Hijack.nuiGraceMs`). Menü kapanırken sızan ESC de yutulur (`reopenCooldownMs`).
4. Giriş yapılmamışken (`LocalPlayer.state.isLoggedIn ~= true`), ara sahnede ve ekran kararmışken yerleşik menüye dokunulmaz → karakter seçimi/yaratma bozulmaz.
5. Script ile açılan yerleşik menü/harita (`ActivateFrontendMenu`) ESC'de kendiliğinden kapanmaz — yalnızca bir seviye geri gider ve açık kalır. Bu yüzden akış sırasında ESC / P / Geri yakalanır, menü kapatılır, sızan yeniden açılış söndürülür ve (tercih açıksa) LOE menüsüne dönülür. Sorun giderme: `Config.Debug = true` yapınca F8 konsolunda `[loe_pause] native ...` satırları görünür.
6. Yerleşik GTA duraklatma menüsü **tamamen gizlidir** (`Config.Hijack.allowNativeMenu = false`, varsayılan): ESC/P her zaman bu menüyü açar, "Normal Menü" kategorisi arayüzde görünmez ve eski bir KVP tercihi (`menu.native`) etkisizdir. Arıza durumunda bir kaçış kapısı istenirse `allowNativeMenu = true` yapılır (kategori geri gelir). `Config.Hijack.enabled = false` hepsini kapatır; `/loepause` her durumda bu menüyü açar.
7. Kaçınılmaz istisna: grafik/ses/kontrol ayarlarının değiştirilmesi yalnızca GTA'nın kendi ekranlarında mümkündür (aşağıya bak). `GTA Ayarları` satırına tıklayınca o ekran açılır; ESC ile kapanıp doğrudan oyuna dönülür.

## Kapsam: ne GERÇEKTEN çalışır, ne yerleşik menüye yönlenir

GTA'nın grafik/ses/kontrol ayarlarının çoğu **FiveM'den yazılamaz** (CFX native dokümanında `SET_PROFILE_SETTING` yoktur; `STAT_SET_PROFILE_SETTING_VALUE` yalnızca 936–938'i kabul eder ve anında uygulanmaz). Bu yüzden ekrandaki her satır dürüstçe etiketlidir. Okunabilen birkaç ayarın **güncel değeri** (salt okunur) satırda gösterilir:

| Satır | Okunan değer |
|---|---|
| Altyazılar | `IS_SUBTITLE_PREFERENCE_SWITCHED_ON` |
| Ölçü birimi | `SHOULD_USE_METRIC_MEASUREMENTS` |
| Güvenli alan | `GET_SAFE_ZONE_SIZE` (yüzde) |
| Çözünürlük | `GET_ACTUAL_SCREEN_RESOLUTION` |
| Oyun dili | `GET_CURRENT_LANGUAGE` |

Okuma başarısız olursa satırda değer görünmez (menü bozulmaz). Diğer `GTA Ayarları` satırlarının güncel değeri okunamaz.

- **Uygulanan ayarlar** (anahtar/seçici/kaydırıcı; KVP'de saklanır, giriş yapınca yeniden uygulanır):

| Ayar | Karşılığı |
|---|---|
| Hedefleme modu (`aim.mode`) | `SetPlayerTargetingMode` |
| Yürürken / araç kamerası, sinematik kamera tuşu | `SetFollowPedCamViewMode`, `SetFollowVehicleCamViewMode`, `SetCinematicButtonActive` |
| Radar ve HUD, Nişangâh, GPS rotası | `DisplayRadar`, `HideHudComponentThisFrame(14)`, `SetBlipRoute` |
| Araç radyosu | `SetUserRadioControlEnabled`, `SetVehicleRadioEnabled` |
| Mesafe ayrıntısı ölçeği (Gelişmiş Grafikler) | `OverrideLodscaleThisFrame` |
| Telsiz / arama ses seviyesi, mikrofon tıkı | `pma-voice` export'ları (`setRadioVolume`, `setCallVolume`, `setMicClick*Volume`, `setVoiceProperty`) |
| Rockstar Editor kaydı (başlat / kaydet / iptal) | `StartRecording`, `StopRecordingAndSaveClip`, `StopRecordingAndDiscardClip` |
| Tercihler: vurgu rengi, koyu mod, portre modu, dil, harita dönüş animasyonu, görünümü sıfırla | Yalnızca bu menünün kendi arayüzü |
| Normal Menü: ESC'de yerleşik menü | Yalnızca `allowNativeMenu = true` iken görünür; ana döngü bu tercihe bakar |

- **`GTA Ayarları` etiketli satırlar** (çözünürlük, MSAA, VSync, doku/gölge kalitesi, ses seviyeleri, çıkış cihazı, fare/gamepad hassasiyeti, titreşim, altyazı, parlaklık, güvenli alan...): burada **değiştirilemez**. Satıra tıklamak yerleşik GTA/FiveM menüsünü açar (`Config.Native`).
- **Büyük harita tuşu (M):** `Config.MapKey` / `Config.MapCommand` (`loe_bigmap`). M'ye basınca LOE menüsü açılmadan doğrudan yerleşik büyük harita açılır (menüdeki "Harita" ile aynı akış); harita açıkken M (ya da ESC) kapatır. Tuştan açılan harita kapanınca `pref.mapReturn` açık olsa bile LOE menüsüne dönülmez. Oyuncu tuşu FiveM tuş atamalarından değiştirebilir; `Config.MapKey = ''` tuş kaydını kapatır. Haritada M'nin kapatması, yerleşik menü açıkken FiveM'in tuş komutlarını işleyip işlemediğine bağlıdır (ESC her zaman kapatır).
- **Hızlı Eylemler** (Tuş Atamaları'nın ilk grubu): sunucuya eklenen tek seferlik kısayollar (fare imleci, fotoğraf modu, minimap, araç tuş ayarları, acil çıkış, konuşma mesafesi, yönetici paneli / geliştirici modu) menüden **Çalıştır** ile çalışır; atanmış tuş yanında gösterilir. Menü kapanır, 300 ms sonra komut `ExecuteCommand` ile çalıştırılır. Liste `Config.Shortcuts`'tır; NUI'den komut metni alınmaz, yalnızca şemadaki `cmd.<id>` kimliği gelir ve yalnızca bu beyaz listedeki komutlar çalışır. `+` ile başlayan (bas-bırak) komutlar eklenemez. `aces` tanımlı satır (yönetici paneli) yalnızca o ACE'e sahip oyunculara görünür (`loe_pause:server:caps` ile sunucu doğrular); asıl yetki kontrolü komutun kendi resource'undadır (`/admin` → `loe_adminmenu`). Geliştirici modunun 1–0 tuşları panelden açılınca çalışır.
- **Tuş Atamaları** salt okunurdur: güncel tuş `GetControlInstructionalButton` ile okunur. Değiştirmek için "Tuşları değiştir" satırı FiveM tuş atamaları menüsünü açar (`FE_MENU_VERSION_LANDING_KEYMAPPING_MENU`). "FiveM" grubu `Config.KeyMappings` listesinden beslenir; atanmamış olanlar gizlenir.
- **Kayıt ve Başlangıç**: GTA'nın kayıt yükleme / başlangıç akışı FiveM'de uygulanmaz; bölüm bunu açıklar.

### Ana menü

Referans videodaki yerleşim 1280x720 ölçülerinden birebir alınmıştır (soldan 10 rem, başlık / madde / kart konumları, 48 px seçili çizgi, iki ağırlıklı Montserrat). İngilizce etiketler videodaki gibi bitişik yazılır (`GAMESETTINGS`); Türkçede iki sözcük arasında küçük bir boşluk vardır. Videodaki üçüncü taraf tanıtım yazısı/logosu menünün parçası değildir ve kullanılmamıştır.

| Madde | Davranış |
|---|---|
| RESUME (DEVAM ET) | Menüyü kapatır (ESC ile aynı) |
| MAP (HARİTA) | **Menüde yok** (`Config.Menu` → `map`, `enabled = false`): büyük harita yalnızca **M** tuşuyla açılır (`Config.MapKey`). `enabled = true` yapılırsa menüde de görünür; o durumda `pref.mapReturn` açıkken kapanınca menüye dönülür |
| GAME SETTINGS (OYUN AYARLARI) | Ayar ekranı (tasarım: `PSettings.mp4`): ana menü solda kalır, yanında **OPTIONS** sütunu (kategoriler), sağda ayar paneli (`GAMESETTINGS // GRAPHICS`). Satır türleri: `‹ değer ›` seçici, `OFF \| ON` anahtar, `‹ ▬▬ ›` kaydırıcı, tuş etiketi, "GTA SETTINGS" bağlantısı. Seçili satırın açıklaması panelin altındaki not satırında görünür. **RESTORE DEFAULTS**: yalnızca o sayfadaki ayarları varsayılana döndürür (onay sorar; Lua yalnızca şemadaki id'leri kabul eder). Videodaki *APPLY CHANGES* ve *VIDEO MEMORY* **yoktur**: ayarlarımız anında uygulanır, GPU belleği okunamaz. Arama kutusu başlık satırının sağındadır (`/`). **ESC = bir adım geri** (satırlar → OPTIONS → ana liste → menüyü kapatır); arayüz alt ekranda iken Lua'ya `sub` bildirir ve ESC menüyü kapatmaz |
| UI SETTINGS (ARAYÜZ AYARLARI) | Aynı ekran; OPTIONS sütununda "Tercihler" grupları (Appearance, Menu behaviour): vurgu rengi (varsayılan **Crimson**), koyu mod, portre modu, dil, GTA ekranlarından menüye dönüş, görünümü sıfırla |
| POSITION MODE (KONUM MODU) | **Henüz işlevi yok**: "Yakında" etiketli; tıklayınca bilgi verir. Bir HUD konumlandırma özelliği bağlanınca `Config.Menu`'den `soon = true` kaldırılır |
| DISCONNECT (AYRIL) | Onay penceresi → "Sunucudan ayrıl" (sunucuya `loe_pause:server:leave` gönderir → `DropPlayer` ile oyuncu FiveM ana menüsüne düşer; 3 sn içinde düşürülmezse yedek olarak `RestartGame()` oyunu kapatıp FiveM'i yeniden açar. `ExecuteCommand('disconnect')` script'ten çalışmadığı için kullanılmaz) / "Vazgeç". Oyunu tamamen kapatan seçenek yoktur |
| ALL GTA SETTINGS | Sağ alt düğme: yerleşik GTA ayar ekranını açar (`Config.Native.settings`); `Config.Features.allGtaSettings = false` ile gizlenir |
| Oyuncu kartı | Sol altta ad [sunucu kimliği], meslek + rütbe, nakit ve banka (`qbx_core` GetPlayerData). Veri yoksa kart gizlenir |
| YOUTUBE / STORE / DISCORD | Sağ üstte; `Config.Links` içinde `https://` adresi **doldurulan** bağlantılar görünür (varsayılan: boş → hiçbiri görünmez). Yalnızca config'teki adresler açılır |
| İstatistikler / Battlepass / Shop | Varsayılan **kapalı** (`Config.Menu` → `enabled = false`). Açılırsa aynı listede görünür; `resource`/`export` başlamışsa onu açar, yoksa yerleşik özet / "Yakında" sayfası gösterir. İstatistik sayfasındaki Sağlık kartı `loe_jobcreator`'ın `healthState` olayından beslenir (`Config.Health`) |

Arka plan: oyun görüntüsü + koyu katman; `Config.Hijack.blurGame = true` iken oyun ekranı `TriggerScreenblurFadeIn` ile bulanıklaşır (videodaki derinlik). Bulanıklık fazla gelirse `false` yap.

## Güvenlik

- NUI'den gelen **her** değer Lua'da yeniden doğrulanır: id şemada olmalı; toggle yalnızca boolean, select yalnızca tanımlı seçenek, slider yalnızca sonlu sayı (aralığa kırpılır, adıma yuvarlanır). Bozuk/oynanmış KVP yüklenirken süzülür.
- Eylem ve native hedefleri beyaz listededir (`Schema.actions`, `Config.Native`); `quit` callback'i yalnızca `disconnect` kabul eder.
- Menü kapalıyken gelen NUI callback'leri reddedilir. Sağlık verisi yalnızca sunucudan gelen olaydan okunur ve uzunluk/tür süzgecinden geçer.

## Test (oyunda)

1. Giriş yap → ESC: LOE menüsü açılmalı, yerleşik GTA menüsü **görünmemeli**; HUD/minimap gizlenmeli.
2. ESC tekrar: menü kapanmalı, oyun kontrolü ve minimap/HUD geri gelmeli, yerleşik menü açılmamalı.
3. Envanteri aç, ESC ile kapat: pause menü **açılmamalı**.
4. Harita: `loe_3dmap` açılmalı; kapanınca (tercih açıksa) menü geri gelmeli.
5. Ayarlar'da bir `GTA Ayarları` satırı: yerleşik GTA menüsü açılmalı, ESC ile çıkınca oyuna dönmeli. **Çalışmazsa** `config.lua > Config.Native` hash'lerini düzelt.
6. Ayarlar → Kamera/Görüntü/Ses vb.: değiştir, çık, tekrar gir: değerler korunmalı; yeniden bağlanınca da korunmalı (KVP).
7. Tercihler → Görünümü Sıfırla: onay çıkmalı; sonra tema/renk/dil varsayılana dönmeli.
8. Ayarlar'da "Normal Menü" kategorisi **görünmemeli**; ESC/P her zaman LOE menüsünü açmalı. Görüntü → Ekran'da Altyazılar / Ölçü birimi / Güvenli alan / Oyun dili, Grafikler → Ekran'da Çözünürlük satırlarında güncel değer görünmeli.
9. Karakter seçimi/ilk giriş ekranında ESC: yerleşik davranış bozulmamalı.

> Doğrulanması gerekenler (oyun içi test yapılmadan kesinleştirilemez): `Config.Native` hash'lerinin ESC'deki gerçek menüye karşılığı, `GetControlInstructionalButton`'ın fare düğmeleri için döndürdüğü jeton adları (`html/js/app.js > MOUSE`), `SetBlipRoute`'un waypoint çizgisini kapatması.

## Geliştirme

```bash
pip install lupa
python _dev/check.py                      # Lua sözdizimi + şema + doğrulama testleri, _dev/schema.json üretir
python -m http.server 8123                # sonra http://localhost:8123/_dev/mock.html  (?lang=en &dark=0 &portrait=1 &accent=blue)
```

Geliştirme arka planı: `_dev/mock_bg.jpg` (git'e girmez). Gerçek oyunda arka plan oyun görüntüsüdür.

## GEÇİCİ: GTA ayarları araştırması (`/loe_gfxtest`, `/loe_gfxrec`)

Amaç: GTA'nın kendi ayarlarını (Grafik, Ses, Fare...) LOE menüsünde gerçek kontrol olarak gösterebilmek için GTA ayar menüsünün script'ten yönetilip yönetilemeyeceğini ölçmek. Yalnızca `Config.GfxProbe.ace` (varsayılan `admin`) yetkisi olanlar çalıştırabilir.

- `/loe_gfxtest`: ~15 sn otomatik test. GTA ayar menüsünü açar; script girdisiyle aşağı/yukarı gezinmeyi, menüyü gizlemeyi (`SuppressFrontendRenderingThisFrame`) ve scaleform dönüş değerlerini dener. Hiçbir ayarın değerini değiştirmez.
- `/loe_gfxrec`: elle gezinme kaydı (en çok 150 sn, **Delete** ile biter). Menü olayları, seçim kimlikleri ve değişen profil ayarları (`GetProfileSetting` 0–1200) zaman damgasıyla kaydedilir.
- Sonuç sunucuda resource klasörüne `gfxprobe_<tarih>_<oyuncu>.json` olarak yazılır (git yok sayar).
- Test sırasında ESC yakalama durur (`LoeProbe.active`); test bitince ya da en geç 200 sn sonra geri gelir.

- `stream_enhanced/pause_menu_sp_content.gfx`: GTA'nın pause menü içerik filminin **yamalı** kopyası (Legacy ve Enhanced'ta aynı dosya). Kök kareye eklenen küçük bir AS2 kancası, oyunun içerik filmine gönderdiği çağrıları (`SET_DATA_SLOT`, `SET_VIDEO_MEMORY_BAR`...) `_global.LOE_LOG`'a yazar; `TIMELINE.LOE_PING()` / `LOE_DUMP(n)` / `LOE_CLEAR()` ile okunur. Asıl metodlar aynen çağrılır. Yeniden üretmek için: `_dev/gfx/cw_extract.ps1` (CodeWalker ile çıkarma) → `python _dev/gfx/patch_gfx.py girdi.gfx stream_enhanced/pause_menu_sp_content.gfx`. Klasör adı `stream_enhanced` (sunucu GTA V Enhanced; FiveM `stream/` klasörü için "deprecated" uyarısı veriyor). Sorun çıkarsa dosyayı silip resource'u yeniden başlatmak yeterli.

Araştırma bitince `client/gfxprobe.lua`, fxmanifest satırı, `server/main.lua`'daki gfxprobe bölümü ve `Config.GfxProbe` kaldırılır.
