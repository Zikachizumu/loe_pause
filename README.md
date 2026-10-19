# loe_pause

Legends of Empire (LOE) için **Pause Menü + Ayarlar ekranı**. ESC / P ile açılan yerleşik GTA duraklatma menüsünün yerine geçen FiveM NUI menüsü (Qbox, `[loe]` kategorisi).

- Ana menü (konsept: `_work/design/loe_pause_concept`, renk ve tarz `loe_illegalmarket`'ten: koyu mor paneller, pembe vurgu): solda panel menü **CONTINUE · MAP · CHARACTER · INVENTORY · BATTLEPASS · SHOP · SETTINGS · SUPPORT · DISCONNECT**; üstte LOE logosu + `PAUSE MENU` + sağda oyuncu kimliği / sunucu / saat; sağda karşılama kartı, Cash · Bank · Home · Vehicles kartları ve Battlepass / Shop kartları; arka plan bulanık, karartılmış oyun görüntüsü
- Ayarlar: 3 bölümlü ekran (kategoriler · alt kategoriler · arama + ayar satırları), klavye + fare, **İngilizce (varsayılan)** / Türkçe (Arayüz Ayarları → Language). Yeni metinler önce İngilizce yazılır (`Config.Defaults['pref.lang']`)
- Zorunlu bağımlılık yok: `qbx_core`, `pma-voice`, `loe_jobcore`, `ox_inventory`, `loe_hud` ve `loe_3dmap` yalnızca **varsa** (pcall) kullanılır; `ox_lib` gerekmez. `oxmysql` yalnızca Home / Vehicles sayıları için kullanılır (sorgu başarısızsa kartlar "—" gösterir).

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
| `shared/gtaset_data.lua` | GTA ayar menüsünün satır tablosu: satır kimliği, profil kimliği (`pid`), tür, kaydırıcı üst sınırı, seçenek etiketleri (`_dev/gtaset/` ölçümlerinden) |
| `client/gtaset.lua` | GTA'nın kendi ayarlarını okur/yazar (gizli GTA menüsü ile; aşağıya bak) |
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
7. Kaçınılmaz istisna: grafik ayarları (doku, gölge...) ve tuş atamaları yalnızca GTA'nın ekranında değiştirilebilir (aşağıya bak). Game Settings → Grafik sayfasındaki **GTA grafik ekranı** ve OPTIONS'ın sonundaki **GTA Settings** o ekranı açar; ESC ile kapanınca (Menü Davranışı tercihine göre) menüye ya da oyuna dönülür.

## Kapsam: GTA'nın kendi ayarları menüde

Game Settings sayfalarında (Controls, Keyboard / Mouse, Audio, Camera, Display) GTA'nın **gerçek** ayarları kendi satırlarıyla, gerçek değerleriyle ve GTA'nın kendi (oyuncunun GTA dilindeki) metinleriyle görünür: ses seviyeleri, fare/oyun kolu hassasiyeti, FOV, kamera seçenekleri, parlaklık, güvenli bölge, altyazı, ölçü birimi... (~64 ayar; tablo `shared/gtaset_data.lua`). Değişiklik yapınca satır kırmızıya döner ve altta **APPLY CHANGES (n)** görünür (kısayol: `A`); uygulayınca değerler GTA'ya yazılır. Ayarlardan uygulanmamış değişiklikle çıkarken "Şimdi uygula / Vazgeç / Düzenlemeye devam" sorulur.

**Nasıl çalışır** (`client/gtaset.lua`): FiveM bu ayarlar için native sunmaz.
- **Okuma:** her satırın değeri bir *profil ayarı*dır → `GetProfileSetting(pid)`; menü kapalıyken anlıktır.
- **Yazma:** GTA'nın kendi ayar menüsü **gizli** açılır (`SuppressFrontendRenderingThisFrame`) ve menünün iç scaleform çağrılarıyla (`SET_INPUT_EVENT`, `MENU_SHIFT_DEPTH`) satırlar oyuncu sağ/sol tuşa basmış gibi adım adım değiştirilir; menü kapanınca GTA değeri kaydeder, sonra profil okunup doğrulanır, tutmayan satırlar yavaş aralıkla en çok 3 kez denenir. Uygulama birkaç saniye sürer (oyun sesi kısılıp açılabilir); bu sırada menü kilitlenir. Bu sürede GTA'nın kendi menü tıkları duyulur (menü açılışı, kategori girişi/çıkışı ve her değer adımı için bir tık); gezinirken tık yoktur. Susturulamıyor: ses sahneleri ve SFX = 0 denendi, tıklar GTA'nın C++ tarafından SFX seviyesinden bağımsız çalınıyor; uygulama zaten en az adım/oturumla çalışır.
- **Zamanlama** (ölçüldü): GTA menüsü her işlemden sonra kısa süre meşgul kalır ve o sırada gelen çağrıyı yutar → gezinme ≥ 60 ms, değer adımı 50 ms (ilk deneme), giriş/çıkış ve adım öncesi ≥ 250 ms, seviye değişiminden sonra 400 ms.
- **Kaydırıcılar** 0..`max` tam sayı adımlarıdır (çoğu 0–10, hassasiyetler 0–14, parlaklık 0–30, fare hassasiyeti 0–200). **Güvenli bölge** ters çalışır (sağ = küçük profil değeri; tabloda `inv = true`).
- Bizim satırlarımızla aynı işi yapan GTA ayarları listelenmez (hedefleme modu, radar/HUD/GPS/nişangâh modu): bizimkiler kalır.
- `Config.Features.gtaSettings = false` bu satırları tamamen kaldırır.

**Grafik ayarları (doku, gölge, MSAA, çözünürlük...)** hâlâ GTA'nın kendi ekranındadır: değerleri okunamıyor (ayar satırlarına scaleform yoluyla erişilemedi). Grafik sayfasındaki **GTA grafik ekranı** GTA ayar ekranını doğrudan Graphics kategorisinde açar (`Config.Native.graphics`, `category = 6`). Neden videodaki gibi yapılamadı (2026-10-19, FiveM for GTAV Enhanced): videodaki script Legacy FiveM'de pause menü scaleform dosyasını değiştiriyor; Enhanced istemcisi aynı isimli oyun dosyası geçersiz kılmalarını yok sayıyor (citizenfx/rfc#92, #378). Araçlar `_dev/gfx/` içinde; FiveM bu hatayı düzeltirse yeniden denenebilir. Ölçüm sonuçları ve tablo üreticileri `_dev/gtaset/` içinde.

- **Uygulanan ayarlar** (anahtar/seçici/kaydırıcı; KVP'de saklanır, giriş yapınca yeniden uygulanır):

| Ayar | Karşılığı |
|---|---|
| Hedefleme modu (`aim.mode`) | `SetPlayerTargetingMode` |
| Yürürken / araç kamerası, sinematik kamera tuşu | `SetFollowPedCamViewMode`, `SetFollowVehicleCamViewMode`, `SetCinematicButtonActive` |
| Radar ve HUD, Nişangâh, GPS rotası | `DisplayRadar`, `HideHudComponentThisFrame(14)`, `SetBlipRoute` |
| Araç radyosu | `SetUserRadioControlEnabled`, `SetVehicleRadioEnabled` |
| Mesafe ayrıntısı ölçeği (Grafik) | `OverrideLodscaleThisFrame` |
| Telsiz / arama ses seviyesi, mikrofon tıkı | `pma-voice` export'ları (`setRadioVolume`, `setCallVolume`, `setMicClick*Volume`, `setVoiceProperty`) |
| Rockstar Editor kaydı (başlat / kaydet / iptal) | `StartRecording`, `StopRecordingAndSaveClip`, `StopRecordingAndDiscardClip` |
| Tercihler: vurgu rengi, koyu mod, portre modu, dil, harita dönüş animasyonu, görünümü sıfırla | Yalnızca bu menünün kendi arayüzü |
| Normal Menü: ESC'de yerleşik menü | Yalnızca `allowNativeMenu = true` iken görünür; ana döngü bu tercihe bakar |

- **Büyük harita tuşu (M):** `Config.MapKey` / `Config.MapCommand` (`loe_bigmap`). M'ye basınca LOE menüsü açılmadan doğrudan yerleşik büyük harita açılır (menüdeki "Harita" ile aynı akış); harita açıkken M (ya da ESC) kapatır. Tuştan açılan harita kapanınca `pref.mapReturn` açık olsa bile LOE menüsüne dönülmez. Oyuncu tuşu FiveM tuş atamalarından değiştirebilir; `Config.MapKey = ''` tuş kaydını kapatır. Haritada M'nin kapatması, yerleşik menü açıkken FiveM'in tuş komutlarını işleyip işlemediğine bağlıdır (ESC her zaman kapatır).
- **Hızlı Eylemler** (Tuş Atamaları'nın ilk grubu): sunucuya eklenen tek seferlik kısayollar (fare imleci, fotoğraf modu, minimap, araç tuş ayarları, acil çıkış, konuşma mesafesi, yönetici paneli / geliştirici modu) menüden **Çalıştır** ile çalışır; atanmış tuş yanında gösterilir. Menü kapanır, 300 ms sonra komut `ExecuteCommand` ile çalıştırılır. Liste `Config.Shortcuts`'tır; NUI'den komut metni alınmaz, yalnızca şemadaki `cmd.<id>` kimliği gelir ve yalnızca bu beyaz listedeki komutlar çalışır. `+` ile başlayan (bas-bırak) komutlar eklenemez. `aces` tanımlı satır (yönetici paneli) yalnızca o ACE'e sahip oyunculara görünür (`loe_pause:server:caps` ile sunucu doğrular); asıl yetki kontrolü komutun kendi resource'undadır (`/admin` → `loe_adminmenu`). Geliştirici modunun 1–0 tuşları panelden açılınca çalışır.
- **Tuş Atamaları** salt okunurdur: güncel tuş `GetControlInstructionalButton` ile okunur. Değiştirmek için OPTIONS → GTA Settings → Key Bindings (FiveM sekmesi). "FiveM" grubu `Config.KeyMappings` listesinden beslenir; atanmamış olanlar gizlenir.

### Ana menü

Ana ekranın ölçüleri 1672x941'lik konsepttendir (CSS'te `--u` = 1 konsept pikseli; 1672 px = 120 rem, yani 1920x1080'de 1 rem = 16 px). Ayarlar ekranı `PSettings.mp4` yerleşimini korur, renkleri `loe_illegalmarket` paletine çevrilmiştir (vurgu varsayılanı **Pink**).

| Madde | Davranış |
|---|---|
| CONTINUE | Menüyü kapatır (ESC ile aynı) |
| MAP | GTA'nın büyük haritasını açar (menü kapanır; kapanınca `pref.mapReturn` açıksa menüye döner). **M tuşu** bu menüden bağımsızdır: `loe_hud/client/bigmap.lua` (komut `loe_bigmap`) açar; harita açıkken ESC yakalama ona dokunmaz (`exports.loe_hud:IsBigMapOpen`) |
| CHARACTER | Yerleşik sayfa: **Character** (ad, vatandaş no, meslek / rütbe), **Finance** (nakit, banka), **Health**. Zamanla doldurulacak: yeni kart `renderPage` içindeki `stats` dalına (`app.js`), veri `buildStats` (`client/main.lua`) ile eklenir. Sağlık kartı `loe_jobcreator`'ın `healthState` olayından beslenir (`Config.Health`) |
| INVENTORY | Menü kapanır, `ox_inventory` çalışıyorsa `exports.ox_inventory:openInventory()` (oyuncunun kendi çantası) çağrılır; çalışmıyorsa "SOON" |
| BATTLEPASS / SHOP | `loe_battlepass` / `loe_shop` resource'u çalışıyorsa menüyü kapatıp `Open` export'unu çağırır; çalışmıyorsa **SOON** etiketli görünür ve tıklayınca "Coming soon" sayfası açılır (resource başlarsa etiket kendiliğinden **NEW**'e döner). Sağdaki kartlar aynı maddeleri açar; Battlepass kartı `Config.Cards.battlepass` export'u (`{ season, level, maxLevel }`) varsa seviye çubuğunu gösterir, yoksa "Coming soon" yazar — uydurma veri gösterilmez |
| SETTINGS | Ayar ekranı: ana menü solda kalır, yanında **OPTIONS** sütunu (GTA ayar kategorileri + Appearance / Menu behaviour arayüz tercihleri), sağda ayar paneli (`SETTINGS // GRAPHICS`). Satır türleri: `‹ değer ›` seçici, `OFF \| ON` anahtar, `‹ ▬▬ ›` kaydırıcı, tuş etiketi. OPTIONS'ın son maddesi **GTA SETTINGS**: Enter doğrudan GTA'nın ayar ekranını açar. **RESTORE DEFAULTS** yalnızca o sayfayı varsayılana döndürür; **APPLY CHANGES** GTA ayarlarını uygular (aşağıya bak). Arama kutusu `/`. **ESC = bir adım geri** (satırlar → OPTIONS → ana liste → menüyü kapatır) |
| SUPPORT | `Config.Links` içindeki `discord` adresi doluysa onu açar; boşsa "SOON" sayfası |
| DISCONNECT | Listenin son satırı. Onay penceresi → "Leave server" (sunucuya `loe_pause:server:leave` gönderir → `DropPlayer` ile oyuncu FiveM ana menüsüne düşer; 3 sn içinde düşürülmezse yedek olarak `RestartGame()` oyunu kapatıp FiveM'i yeniden açar) / "Cancel". Oyunu tamamen kapatan seçenek yoktur |
| Üst şerit | Oyuncu kimliği (`#<sunucu id>`), sunucu adı (`Config.ServerName`, yeşil nokta) ve gerçek saat / tarih (`GG.AA.YYYY`) |
| Karşılama kartı | Los Santos silüeti + karşılama metni. **SEVİYE / XP çubuğu yalnızca `Config.Cards.level` export'u varsa görünür** (`{ level, xp, xpMax }`); şu an sunucuda böyle bir sistem yoktur, çubuk gösterilmez |
| Cash · Bank | `qbx_core` GetPlayerData |
| Home · Vehicles | Menü açılınca sunucu (`loe_pause:server:summary`, 2 sn sınırlı, yalnızca isteyen oyuncunun kendi kayıtları) sayar: araçlar = `player_vehicles`, ev = `loe_properties` (sahip ya da süresi dolmamış kiracı) + `loe_hotel_rooms` (süresi dolmamış). Tablo yoksa / yanıt gelmediyse "—" görünür. `oxmysql` gerekir |
| Meslek / rütbe | CHARACTER sayfasında ve oyuncu verisinde: **`loe_jobcore`'dan** (`GetPlayerState`: mesaideki meslek, yoksa birincil meslek; rütbe = `gradeLabel`), çünkü qbx_core'daki job alanı güncel tutulmaz (hep "Freelancer"). Mesleği olmayan oyuncuda jobcore'un "Unemployed" etiketi; jobcore çalışmıyorsa qbx_core'a düşer (`Config.JobSystem`) |
| YOUTUBE / STORE / DISCORD | Sağ altta; `Config.Links` içinde `https://` adresi **doldurulan** bağlantılar görünür (varsayılan: boş → hiçbiri görünmez). Yalnızca config'teki adresler açılır |

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
5. Game Settings → OPTIONS → GTA Settings → Enter: GTA'nın ayar ekranı açılmalı, ESC ile çıkınca (tercihe göre) menüye/oyuna dönmeli. **Çalışmazsa** `config.lua > Config.Native` hash'lerini düzelt. Grafik → "GTA grafik ekranı": ayar ekranı doğrudan Graphics sayfasında açılmalı.
5b. Audio → SFX/Music seviyesini değiştir → **Apply Changes**: birkaç saniye "Applying…" görünür, GTA menüsü **hiç görünmemeli**, bitince menü açık kalmalı ve değer korunmalı (GTA Settings → Audio'dan doğrula). Güvenli bölge (Display) sağ okla küçülmeli/büyümeli. Uygulanmamış değişiklikle çıkarken soru çıkmalı.
6. Ayarlar → Kamera/Görüntü/Ses vb.: değiştir, çık, tekrar gir: değerler korunmalı; yeniden bağlanınca da korunmalı (KVP).
7. Tercihler → Görünümü Sıfırla: onay çıkmalı; sonra tema/renk/dil varsayılana dönmeli.
8. Ayarlar'da "Normal Menü" kategorisi **görünmemeli**; ESC/P her zaman LOE menüsünü açmalı.
9. Karakter seçimi/ilk giriş ekranında ESC: yerleşik davranış bozulmamalı.

> Doğrulanması gerekenler (oyun içi test yapılmadan kesinleştirilemez): `Config.Native` hash'lerinin ESC'deki gerçek menüye karşılığı, `GetControlInstructionalButton`'ın fare düğmeleri için döndürdüğü jeton adları (`html/js/app.js > MOUSE`), `SetBlipRoute`'un waypoint çizgisini kapatması.

## Geliştirme

```bash
pip install lupa
python _dev/check.py                      # Lua sözdizimi + şema + doğrulama testleri, _dev/schema.json üretir
python -m http.server 8123                # sonra http://localhost:8123/_dev/mock.html  (?lang=en &dark=0 &portrait=1 &accent=blue)
```

Geliştirme arka planı: `_dev/mock_bg.jpg` (git'e girmez). Gerçek oyunda arka plan oyun görüntüsüdür.
