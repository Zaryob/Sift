# Sift — Acımasız Kod ve Ürün İncelemesi

> Tarih: 2026-10-07 · Kapsam: `main` @ `daa4921` · ~16.6k satır Swift (app + widget + tests)
>
> Yöntem: dört paralel inceleme (mimari, doğruluk/eşzamanlılık, güvenlik/hijyen, ürün/UX/test),
> macOS ve iOS derlemeleri, test koşusu ve uygulamanın **gerçekten çalıştırılıp** macOS + iPhone
> simülatöründe kullanılması. Aşağıdaki her kritik iddia kodda veya çalışan uygulamada doğrulandı.

---

## Hüküm

Sift'in çekirdeği iyi: actor tabanlı refresh servisi, enjekte edilebilir HTTP istemcisi,
in-memory SwiftData ile yazılmış testler, güzel bir okuyucu tipografisi ve gerçekten çalışan
on-device Apple Intelligence brifingi. **Ama ürün, çekirdeğin etrafına eklenmiş sekiz yarım
entegre "akıllı" özelliğin ağırlığı altında çöküyor.** Bazıları kullanıcı verisini sessizce
siliyor, biri bu silmeyi kutlayan bir popup gösteriyor, test paketi hiç derlenmemiş ve README
uygulamanın neredeyse her teknik gerçeği hakkında yanlış bilgi veriyor.

Bugünkü haliyle **yayına hazır değil.** İyi haber: en kritik sorunların çoğu küçük, lokal
düzeltmeler. Kötü haber: güvenlik ağı (testler) olmadan bunları düzeltmek kör uçuş.

| Alan | Not | Tek cümle |
|---|---|---|
| Çekirdek RSS doğruluğu | **D** | Parser `content:encoded`, `dc:date`, `dc:creator`, `media:*` öğelerinin hiçbirini okuyamıyor. |
| Veri güvenliği | **F** | Promosyon filtresi, "Keep All" ve pruning birlikte kullanıcı verisini siliyor/diriltiyor. |
| Test | **F** | Test binary'si sembolsüz; `TEST SUCCEEDED` = 0 test koştu. |
| Eşzamanlılık | **D** | `ModelContext` aktörler arasında geziyor; Swift 5 modu bunu gizliyor. |
| Performans | **C−** | Liste her render'da tüm kütüphaneyi yeniden sıralıyor. |
| Mimari | **C** | God object'ler, 4 ayrı tam-metin yolu, 3 ayrı içe aktarma yolu, ürüne sızmış "spike". |
| macOS HIG | **D** | File menüsü yok, komutlar yok, kısayollar görünmez butonlar. |
| UX / ürün odağı | **C** | Güzel görsel dil; dağınık kimlik, yanıltıcı etiketler, dırdır eden popup. |
| Yerelleştirme | **D** | tr %15, de/fr %19 — README "fully localized" diyor. |
| Güvenlik | **C+** | RCE yok; ama feed'den gelen her URL şeması açılıyor, widget dosyası `0666`. |
| Dokümantasyon / hijyen | **D** | README macOS 14 diyor, gerçek hedef 26.6; entitlements git'te yok. |

---

## Uygulamayı kullanırken gözle görülenler

Bunlar kod okumadan, sadece uygulamayı açarak görülen sorunlar — yani ilk kullanıcının da göreceği şeyler.

1. **HTML entity'leri başlıkta ham görünüyor.** iOS'ta The Verge başlığı:
   `ChatGPT&#8217;s &#8216;Intelligent…`. Parser'da hiçbir entity çözümü yok (`FeedParser.swift`).
2. **Okuyucu sadece özet gösteriyor.** Nature makalesi tek paragraf; çünkü parser `content:encoded`'ı
   hiç yakalayamıyor (aşağıda P0-2). "1 min read" etiketi de bu yüzden.
3. **"Apple Intelligence" etiketli kart, aslında offline özet** ve metin makale gövdesinin
   **birebir kopyası**. Kullanıcıya AI çalıştı izlenimi veriyor — yanıltıcı.
   (bkz. [ai-summary.png](screenshots/ai-summary.png))
4. **Kaynak çeşitliliği çalışmıyor.** `7e1a135 "Kaynak-bazlı eşit dağıtım sorunu … çözüldü"` commit'ine
   rağmen SIFT Feed'in ilk 7–10 öğesi hem macOS'ta hem temiz iOS kurulumunda **tamamen Nature**.
5. **Mükerrer abonelikler.** macOS kenar çubuğunda 9to5Mac ×2, Swift.org ×2, Sidebar ×2,
   UX Collective ×2, Swift by Sundell ×2, Smashing ×2. "Add Feed" sayfası mükerreri yakalıyor
   ("You're already subscribed") ama `Feed.url`'de unique kısıt olmadığı için diğer yollar (OPML,
   onboarding, yönlendirme sonrası URL yeniden yazımı) mükerrer üretiyor.
6. **Sayaçlar tutarsız.** Aynı anda: "All Articles 1.821", "All (1.837)", "80 curated · 1.757 filtered".
   Kenar çubuğu yalnız okunmamışları sıralıyor, liste hepsini (`SidebarView.swift:33` vs `ArticleListView.swift:194`).
7. **Okunan makale listeden anında kayboluyor.** Seçili satır seçimin ortasında listeden düşüyor;
   kullanıcı nerede kaldığını kaybediyor.
8. **File menüsü yok.** Menü çubuğu: Apple, Sift, Edit, View, Window, Help. View menüsünde yalnızca
   "Enter Full Screen". Feed ekleme, yenileme, OPML, okundu işaretleme — hiçbiri menüde değil.
9. **Brifingde ham Markdown.** `*Ply*` yıldızlarıyla görünüyor.
10. **Bildirim izni bağlamsız soruluyor** — onboarding'de 13 feed'e abone olunduğu anda, açıklama yok.
    Varsayılan olarak açık ve feed başına 5 bildirim → ilk senkronda ~65 bildirim riski.
11. **Liste satırları erişilebilirlik ile açılamıyor.** AXPress satırı seçmiyor; okunmamış noktası
    `accessibilityHidden` ve yerine bir değer yok — VoiceOver kullanıcısı okunmuş/okunmamış ayırt edemiyor.

---

## P0 — Bu hafta düzeltilmeli (veri kaybı, sahte güvence, kırık çekirdek)

### P0-1 · Test paketi hiç derlenmiyor — "yeşil" sahte
- `SiftTests` hedefinin `fileSystemSynchronizedGroups`'u yok, Sources fazı boş
  (`Sift.xcodeproj/project.pbxproj:169-186`).
- Doğrulama: `nm SiftTests.xctest/Contents/MacOS/SiftTests` → **no symbols**. `xcodebuild test` →
  `TEST SUCCEEDED`, çünkü koşacak test yok.
- Kanıt ki hiç derlenmemiş: `SiftTests/FeedDiscoveryServiceTests.swift:19` var olmayan
  `MockHTTPClient(result:)` tipini kullanıyor.
- **Etki:** 10 dosya / ~1.000 satır test yetim. Aşağıdaki parser ve veri kaybı hataları bu yüzden yakalanmadı.
- **Düzeltme:** `SiftTests` klasörünü test hedefine synchronized group olarak ekle, `MockHTTPClient`'ı
  tanımla (veya `MockFeedHTTPClient`'ı kullan), CI'da `xcodebuild test` koş ve test sayısının > 0 olduğunu assert et.

### P0-2 · Parser namespace'li öğelerin hiçbirini okuyamıyor
- `FeedParser.swift:107` → `shouldProcessNamespaces = true`. Bu durumda `XMLParser` `elementName`
  olarak **yerel adı** verir (`encoded`, `creator`, `date`, `thumbnail`).
- Kod ise `"content:encoded"`, `"dc:creator"`, `"dc:date"`, `"media:thumbnail"`, `"media:content"`
  ile karşılaştırıyor (`:172, :214, :250-256`). **Hiçbiri asla eşleşmez.**
- **Etki:** feed'den tam metin yok, thumbnail yok, yazar yok; yalnız `dc:date` taşıyan feed'lerde
  (RSS 1.0/RDF ve pek çok WordPress) her makale tarihi "şimdi" → SIFT sıralaması hepsini "breaking" sanıyor.
- **Düzeltme:** `qName`'i (küçük harfle) kullan veya namespace işlemeyi kapat. Bu dört öğe için regresyon testi ekle.

### P0-3 · Başlıklarda HTML entity çözümü yok
- Çift kaçışlı başlıklar (`&amp;#8217;`) ham `&#8217;` olarak gösteriliyor. Ayrıca bir başlıktaki
  tek bir `&nbsp;` (XML'de tanımsız entity) **tüm feed'i** `invalidXML` ile düşürüyor (`FeedParser.swift:111-116`).
- **Düzeltme:** başlık/özet için HTML entity decode adımı; parse öncesi named entity → numeric dönüşümü ve retry.

### P0-4 · Promosyon filtresi kullanıcı verisini kalıcı olarak siliyor
- `FeedRefreshService.swift:224-233`: VIP olmayan her öğe `SmartFeedFilter.isHighConfidenceNoise`
  true ise **hiç kaydedilmiyor**. Eşleşme düz `contains` (`SmartFeedFilter.swift:401-495`):
  `"black friday"`, `"giveaway"`, `"job opening"`, `"çekiliş"`, `"gewinnspiel"`…
- "Black Friday sales slump hits retailers" veya "Government giveaway to banks" gibi gerçek haberler kayboluyor.
- `DataPruningService.swift:79-101` tek seferlik bir taramayla mevcut **okunmamış** makaleleri de aynı kuralla siliyor.
- UI yalan söylüyor: `ArticleListView.swift:1368` — "Promotional and repeated posts stay available in All Articles."
- Haftalık "kutlama" popup'ı bu silmeyi kutluyor; ve sayı şişik çünkü atlanan öğeler kaydedilmediği için
  her refresh'te yeniden sayılıyor.
- **Düzeltme:** öğeleri `isPromotional` bayrağıyla sakla, yalnız SIFT Feed'de gizle; kelime sınırlı eşleşme;
  okunmamışı asla silme; ayara bağla; popup'ı kaldır veya Ayarlar'da pasif istatistiğe çevir.

### P0-5 · "0 = kapalı" ayarları sessizce eziliyor
- **"Keep All" = 30 gün:** `SettingsView.swift:550` `tag(0)` kaydediyor;
  `FeedRefreshService.swift:177-178` `retentionDays > 0 ? retentionDays : 30`. Kullanıcı "hepsini tut"
  dedikçe okunmuş makaleleri 30 günde siliniyor. `DataPruningService.swift:28` "0 = süresiz" diyor — kendi kontratını bozuyor.
- **"Manually" = 15 dk:** `SettingsView.swift:444,457` `tag(0)`, `BackgroundFeedScheduler.swift:33-34`
  `stored > 0 ? stored : 15`. Arka plan yenilemeyi kapatmak yeniden açılışta geri alınıyor.
- **Kök neden:** dağınık, string anahtarlı `UserDefaults` ve `integer(forKey:)`'in "yok = 0" dönüşünün sentinel olarak kullanılması.
- **Düzeltme:** tek bir tipli `AppSettings` (enum/optional değerler, tek yerde varsayılanlar).

### P0-6 · Okunmuş makaleler silinip okunmamış olarak geri geliyor
- Pruning `publicationDate`'e göre siliyor, tombstone tutmuyor (`DataPruningService.swift:41-49`);
  `merge` yalnız hâlâ var olan öğelere karşı dedup yapıyor (`FeedRefreshService.swift:196-225`).
- Son 20 yazıyı 6 aya yayan bir blog → her döngüde okunmuşlar silinir, sonraki refresh'te **okunmamış ve
  yeni** olarak geri gelir, bildirim tetikler.
- **Düzeltme:** feed başına görülen guid/link hash tablosu (veya gövdeyi silip stub satırı tut).

### P0-7 · `ModelContext` aktörler arasında paylaşılıyor (data race)
- `WidgetSnapshotManager` bir `actor` (`WidgetSnapshotManager.swift:10`); `updateSnapshot(context:)`
  **ana** context'i alıp kendi executor'ünde fetch ediyor (çağrılar: `ContentView.swift:122`,
  `AppViewModel.swift:220,236,609,647`). `FeedRefreshService.swift:120,170` aynısını yapıyor.
- Yalnızca `SWIFT_VERSION = 5.0` sayesinde derleniyor. Build'de zaten 10+ "Swift 6'da hata olacak" uyarısı var
  (`DataPruningService.swift:83,91,98`, `FeedRefreshService.swift:100,206,230,254`, `NotificationManager.swift:104,136`).
- **Düzeltme:** `ModelContainer` geçir (Sendable), aktör içinde context oluştur veya `@ModelActor` kullan;
  ardından Swift 6 dil moduna geç.

### P0-8 · Beş ayrı `FeedRefreshService` → mükerrer kayıtlar
- Örnekler: `SiftApp.swift:66`, `BackgroundFeedScheduler.swift:23`, `AppViewModel.swift:172`,
  `SettingsView.swift:656`, `MenuBarExtraView.swift:8`. `refreshingFeedIDs` koruması örnek başına.
- Modelde `guid`, `link` veya `Feed.url` üzerinde benzersizlik yok (`FeedItem.swift:6-7`, `Feed.swift:8`).
  Manuel refresh + zamanlayıcı yarışı → aynı makale iki kez. Gözlemlenen mükerrer feed'ler bu ailenin parçası.
- Ek: macOS'ta in-process timer **ve** `NSBackgroundActivityScheduler` aynı aralıkta ikisi birden
  `refreshAllFeeds` çağırıyor (`BackgroundFeedScheduler.swift:60-90`).
- **Düzeltme:** kökte tek bir enjekte edilmiş refresh koordinatörü; `#Unique<FeedItem>([\.feed, \.guid])`,
  `#Unique<Feed>([\.url])`; tek zamanlama mekanizması.

### P0-9 · Temiz klondan derlenmiyor + sandbox kaçışı
- `.gitignore:46` → `*.entitlements`. App Group ve ağ entitlement'ları repoda yok; `project.pbxproj`
  onlara referans veriyor. **Taze bir klon derlenemez.**
- Widget veri yolu `getpwuid` ile gerçek home'u bulup `temporary-exception.files.home-relative-path`
  ile sandbox dışına yazıyor, dosyaları `0o666` (herkes yazabilir) yapıyor
  (`WidgetSnapshotManager.swift:16-35, 87-117`); widget dört farklı yolu deniyor (`SiftWidget.swift:130-170`).
  App Store reddi için neredeyse garanti, ve kullanıcı olarak çalışan her süreç widget'ı kurcalayabilir.
- **Düzeltme:** entitlements'ı commit et; yalnız App Group container kullan, tek bir paylaşılan `WidgetStore`.

### P0-10 · Feed'den gelen her URL şeması açılıyor
- `AppViewModel.swift:689-692`, `PlatformHelper.swift:11`, `ArticleDetailView.swift:1304,1517,1680`
  link'i şema kontrolü olmadan `open`'a veriyor. Kötü niyetli bir feed `x-apple.systempreferences:`,
  `facetime:`, herhangi bir uygulamanın URL handler'ını tetikleyebilir. Favicon URL'leri de herhangi bir şemayı kabul ediyor.
- **Düzeltme:** yalnız `http`/`https` allowlist'i.

---

## P1 — Yayın öncesi (performans, güvenilirlik, macOS ürünü)

**Performans**
- `ArticleListView.swift` (2.342 satır) limitsiz `@Query` ile tüm `FeedItem`'ları yüklüyor (`:132`), sonra
  `body` içinde computed property'lerle `SmartFeedFilter.filteredArticles`'ı (O(N log N) + token kümeleme)
  **render başına birkaç kez** çağırıyor (`:188-205, :298, :348-351`, kısayollar `:1436-1438`);
  `Dictionary(uniqueKeysWithValues:)` her render'da (`:359`). Okundu işaretlemek tüm kütüphaneyi yeniden sıralıyor.
- `ArticleDetailView`: `irrelevantBlockIDs` `ForEach` içinde blok başına okunuyor; her okuma
  `extractedArticle` JSON'unu yeniden decode edip tam metni SHA-256'lıyor (`:1266-1278, :793-803`).
  `scrollProgress` her scroll tick'inde değiştiği için 60 bloklu bir makalede **kare başına 60 decode + 60 hash**.
- `ArticleExtractor.extract(html:)` (MB'larca HTML'de regex + JSON-LD) `NonisolatedNonsendingByDefault`
  yüzünden **ana aktörde** çalışıyor (`ArticleExtractor.swift:110-146`). `@concurrent` ile işaretle.
- `FeedItem.extractedArticle` her erişimde JSON decode ediyor (`FeedItem.swift:89-92`) ve sıcak yollarda tekrar tekrar çağrılıyor.
- Ayarlar sadece `.count` için tüm makaleleri yüklüyor (`SettingsView.swift:67`) → `fetchCount`.
- `#Index` yok: `publicationDate`, `isRead`, `isStarred` her sorguda filtre/sıralama.
- Yanıt boyutu sınırsız (`FeedHTTPClient.swift:50`) — 500 MB dönen bir sunucu belleği bitirir.

**Güvenilirlik**
- **Açılışta otomatik yenileme hiç çalışmıyor:** `lastRefreshedAt: Date? = Date()` (`AppViewModel.swift:152`) +
  `> 300 s` kontrolü (`ContentView.swift:126-134`). UI bu arada "Updated just now" diyor.
- **Link'e göre dedup yeni makaleleri yutuyor:** guid yeni ama link aynıysa (durum sayfaları, iş ilanları, çizgi romanlar)
  öğe atılıyor (`FeedRefreshService.swift:217-223`). guid varsa yalnız guid'e bak.
- **Geçici yönlendirme feed URL'sini kalıcı yeniden yazıyor** — 302/307 dahil (`FeedRefreshService.swift:79-81`). Yalnız 301/308.
- Göreli URL'ler (`xml:base`, `/p/1`) hiç çözülmüyor (`FeedParser.swift:199-204, 247`).
- Atom `type="xhtml"` içerik kırpılıyor — `accumulatedText` her start tag'de sıfırlanıyor (`:146`).
- Parse edilemeyen tarih → `Date()`; guid ve link yoksa dedup anahtarı `title:timestamp` her fetch'te değişiyor → 15 dakikada bir mükerrer.
- Tek fetch içinde dedup yok (set'ler insert sonrası güncellenmiyor, `:198-202`).
- Şema versiyonlama yok (`PersistenceController.swift:12-29`); migration başarısız olursa sessizce in-memory store'a
  düşüyor ve kullanıcıya "Your subscriptions are safe" deniyor (`ContentView.swift:145`) — o oturumda eklenen her şey kayboluyor.
- Enrichment kuyruğu en yeni 25'i alıyor ama zaten işlenenleri dışlamıyor → 25'ten sonrası hiç zenginleşmiyor (`ArticleEnrichmentQueue.swift:58-66`).
- Başlık ve gövde çevirisi tek bir dil alanını paylaşıyor → dil değişince yanlış dilde gövde gösterilebilir.

**macOS ürünü**
- Sıfır `CommandMenu`/`CommandGroup`. Kısayollar `opacity(0)` boş `Button("")`'lar (`ArticleListView.swift:1434-1475`):
  menüde görünmüyor, keşfedilemez, kompakt düzende liste ekrandan çıkınca çalışmıyor, VoiceOver'a 7 etiketsiz buton olarak sızabilir.
- Tooltip "⌘N" vaat ediyor (`:771`), bağlı değil. README "⌘P" diyor, bağlı değil.
- `moreOptionsMenu` yalnız iOS toolbar'ında (`:748-763`) → **macOS'ta Stories, Sort, Hide Read erişilemez**;
  ama Ayarlar "On-Device Story Analysis (Preview)" bölümünü reklam ediyor.
- Okuyucudaki "Settings…" menü öğesi macOS'ta hiçbir şey yapmıyor (`ArticleDetailView.swift:396-397`) → `@Environment(\.openSettings)`.
- `@SceneStorage` yok — seçili kaynak ve makale her açılışta sıfırlanıyor.
- Feed hatası yalnız turuncu üçgen + tooltip; Retry yok, VoiceOver etiketi yok. Feed yeniden adlandırma yok
  (başlık her refresh'te eziliyor). "Delete Feed" onaysız ve **yıldızlı makaleler dahil** cascade siliyor.
- Tam metin indirme başarısız olunca her makale açılışında **modal alert** (`ArticleDetailView.swift:118-134`). Inline banner olmalı.
- Hardened Runtime kapalı → notarize edilemez.

**Ürün dürüstlüğü**
- "Apple Intelligence" başlıklı kart offline extractive özet gösterirken de aynı markayı taşıyor.
- Widget, snapshot yokken **uydurma manşetleri gerçek yayıncılara atfederek** gösteriyor
  ("Appeals Court Reverses…" — "Business Insider") (`SiftWidget.swift:48-75, 117-129`).
- Bildirimler varsayılan açık, feed başına 5, "ilk senkron" koruması yok; Ayarlar altbilgisi
  ("yalnız SIFT Feed'e giren yüksek sinyalli haberler") yanlış (`SettingsView.swift:478`).
- Haftalık "Cleanup Celebration" sheet: kullanıcı eylemi sonrası açılan modal, kapatma ayarı yok, iki ayrı "Done"/"Nice" butonu, şişik sayı.
- Liste başlıkları ve gövdeler kullanıcıya sorulmadan otomatik çevriliyor; arka planda her refresh'te 25 yayıncı sayfası taranıyor
  (README'deki "privacy-focused" iddiasıyla gerilimde). İkisi de ayara bağlanmalı, varsayılan kapalı.

---

## P2 — Mimari borç

- **God object:** `AppViewModel` (762 satır) navigasyon, 5 sheet bayrağı, toast/undo, story clustering,
  tam metin çıkarımı, feed keşfi, OPML, deep link ve widget reload'ı yönetiyor; dosya seviyesinde 12 public tip.
  → `NavigationState`, `SubscriptionService`, `StoryPreviewModel`, `ArticleActions`.
- **Dört ayrı tam-metin yolu**, dört farklı eşik (120 / 300 / 400 / 400 kelime) ve farklı yan etkiler:
  `AppViewModel.swift:451-517`, `:657-687`, `ArticleEnrichmentQueue.swift:98-152`, `ArticleIntelligenceService.swift:438-467`.
  Bir makalenin "excerpt" mi "full" mü sayıldığı hangi yolun önce çalıştığına bağlı. → tek `ArticleBodyService`.
- **Üç ayrı feed oluşturma / OPML yolu** (`AppViewModel.subscribe`, `AppViewModel.importOPMLFile`, `SettingsView.handleImportResult`);
  `subscribe` merge'deki dedup ve noise filtresini atlıyor.
- **Ürüne sızmış spike:** `StoryClusteringSpike.swift` (1.059 satır) kendi doc-comment'inde "ürün deneyimini değiştirmez"
  diyor; `pipelineVersion = "m0-spike-17"`, ama `AppViewModel` üzerinden kullanıcıya açık "Show Stories" menüsünü besliyor.
- **2.000+ satırlık view dosyaları** iş mantığı, persistence ve çeviri yapıyor. `ArticleListView.swift` içinde filtre config'i,
  iki filtre sheet'i, satır view'ı, çeviri view'ı ve özel UIKit API'lerini (`UIDictationController*` bildirimleri,
  0.25 s polling, global first-responder hack'i) kullanan `DictationObserver` var — App Store riski.
- **Karışık gözlem modeli:** `AppViewModel` `@Observable`; 8 servis `ObservableObject` singleton. `SettingsView.swift:63-65`
  `.shared` singleton'ları `@StateObject` ile sarıyor (sahip olmadığı nesneyi sahipleniyor).
- **Singleton bağımlılıklar:** `PersistenceController.shared` ×15, `NotificationManager.shared` ×9,
  `ArticleIntelligenceService.shared` ×9. `FeedRefreshService` container'ı enjekte ediyor ama bildirim, widget,
  enrichment, `UserDefaults.standard`'ı hard-wire ediyor → testler gerçek bildirim gönderir, gerçek widget dosyası yazar.
- **String anahtarlı UserDefaults** dağınık (`"vipFeedIDs"`, `"articleRetentionDays"`, `"feedRefreshIntervalMinutes"` ×3…);
  VIP ID'leri virgülle birleştirilmiş string. P0-5'in kök nedeni.
- **SwiftData model tasarımı:** her modelde `@Attribute(.unique) id: UUID` (persistentModelID ile gereksiz, CloudKit'i engeller),
  ama gereken yerde benzersizlik yok; `FeedItem` üzerinde 5 düz çeviri kolonu (ilişkili model olmalı).
- **Ölü kod derleniyor:** `Sift/Agent.swift`, `Sift/FeedRefreshEngine.swift` (yalnız `print` yapan şablon stub'lar),
  kullanılmayan `LaunchAgentManager`, `Feed.unreadCount`, `FeedItem.deduplicationKey`, `TimelineSection.init(for:)`,
  `SiftApp.swift:63-71`'deki `--background-refresh` CLI yolu. `ArticleSnapshot.swift` iki hedefte byte-byte kopya.
- **`Shared/` çöplük:** 19 dosya; servisler, view'lar, platform yapıştırıcısı, intent'ler ve tema bir arada.
  `FeedEngine/` ve `Clustering/` birer dosya. → `Services/`, `Domain/`, `UI/Components/`, `Platform/`.
- **Sihirli sayılar** (`86_400`, `172_800`, `>= 85`, concurrency 4 üç yerde) ve **26 ham `print`** — bildirim başlıklarını ve makale URL'lerini logluyor. → `os.Logger` + privacy annotation.
- Meşgul bekleme: `while viewModel.isBuildingStoryPreview { sleep 100ms }` (`ArticleListView.swift:363-366`).

---

## Yerelleştirme ve erişilebilirlik

- `Localizable.xcstrings`: 372 anahtar. **tr 57 (%15.3), de 71 (%19.1), fr 71 (%19.1).** Widget'ın string catalog'u yok.
- Çevrilemeyen yollar: `Text(String)` ile gelen kenar çubuğu satırları (`SidebarView.swift:91-95`), enum `rawValue` başlıkları
  (`ArticleListView.swift:404, 1192, 1200`), `"\(n) articles marked as read"` (`AppViewModel.swift:216`),
  modelde saklanan İngilizce hata metni (`FeedRefreshService.swift:39`), birleştirme ile kurulan `"\(n) " + "unread"`. Hiç plural yok.
- Okunmamış noktası `accessibilityHidden`, yerine `accessibilityValue` yok; yıldız/VIP ikonları etiketsiz; satırlar birleştirilmemiş.
- 120+ sabit `.font(.system(size:))` — iOS'ta Dynamic Type'ı öldürüyor.
- Onboarding paketleri yalnız ABD/İngilizce teknoloji kaynakları; paket adları yerelleştirilmemiş — Türkçe hedefleyen bir ürün için tuhaf.
- Terminoloji dağınık: "Sift", "SIFT Feed", "curated", "high-signal", "Stories"; brifingin tek sheet içinde üç adı var
  ("Daily Briefing", "Spoken Briefing", "Sift Daily Briefing"); URL şeması hâlâ eski `rssreader://`.
  macOS'a sızan iOS dili: "Pull to refresh", "Double-tap to reveal".

---

## Repo hijyeni ve dokümantasyon

| Konu | Durum |
|---|---|
| README dağıtım hedefi | "macOS 14 / Xcode 15 / Swift 5.9" — gerçek: **macOS 26.6 / iOS 26.6**, Swift 5 dil modu, Xcode 26 |
| README özellikleri | "Fully localized" yanlış; "This Week" filtresi yok; ⌘P bağlı değil; widget'lar etkileşimli değil ve okunmamış sayısı göstermiyor. AI, brifing, TTS, çeviri, menü çubuğu, Siri, iOS — hiçbiri anılmıyor. |
| Entitlements | `.gitignore` ile dışlanmış → taze klon derlenmez |
| `xcuserdata` | `.gitignore`'a rağmen commit'lenmiş (`xcschememanagement.plist`) |
| Team ID | `project.pbxproj` içinde kişisel team ID |
| CI | Yok (`.github/` yok). CHANGELOG, CONTRIBUTING, Privacy Manifest yok |
| `docs/` | Ürün dokümanları (ARCHITECTURE, DATA_FLOW) ile M0 araştırma protokolü/etiketleme rehberleri karışık |
| `tools/` | Araştırma script'leri; kazınmış makale metni yalnız makineye özel bir dosyayla dışlanıyor |
| Platform listesi | App visionOS (`xros`) içeriyor, widget içermiyor; tutarsız |
| Commit dili | Türkçe ve İngilizce karışık; son commit'ler ne değiştiğini anlatmıyor ("Feed temizliği") |
| ATS | Düz `http` feed'ler engelleniyor, kullanıcıya açıklanmıyor |

---

## Önerilen iyileştirme sırası

**Sprint 1 — Güvenlik ağı ve veri bütünlüğü**
1. Test hedefini bağla, `MockHTTPClient`'ı tanımla, GitHub Actions'ta `xcodebuild test` (test sayısı > 0 assert'i ile).
2. Entitlements'ı commit et; README'deki gereksinimleri düzelt.
3. Parser: `qName` eşleşmesi + HTML entity decode + `&nbsp;` toleransı + göreli URL çözümü. Her biri için regresyon testi.
4. Tipli `AppSettings` → "Keep All" ve "Manually" hatalarını kökten kapat.
5. Promosyon filtresini yıkıcı olmaktan çıkar (`isPromotional` bayrağı), kutlama popup'ını kaldır.
6. Tombstone tablosu + `#Unique` kısıtları + tek refresh koordinatörü. Şema V1/V2 + migration planı.

**Sprint 2 — Eşzamanlılık ve performans**
7. `@ModelActor` ile veritabanı işini ana aktörden çıkar; `ModelContext` yerine `ModelContainer` geçir; Swift 6 dil modu, sıfır uyarı.
8. Liste sıralamasını `@Observable ArticleListModel`'e taşı; `#Predicate` + `fetchLimit` + `#Index`; detail view'da blok seti `.task(id:)` ile bir kez.
9. HTML çıkarımını `@concurrent` yap; yanıt boyutu limiti.

**Sprint 3 — macOS ürünü ve cila**
10. `.commands {}` + `@FocusedValue`: File (New Feed ⌘N, Import/Export OPML), View (Sort, Hide Read, Stories), Article (Next/Prev, Read, Star, Open, Print ⌘P).
11. Feed inspector (rename, URL, retry, hata metni); silme onayı; `@SceneStorage`.
12. Bildirimleri varsayılan kapalı + ilk senkron koruması + toplu bildirim; otomatik çeviri ve arka plan taramasına ayar.
13. "Apple Intelligence" etiketini yalnız gerçek model çıktısında göster; brifingde Markdown render; widget'ta sahte manşet yok.
14. Yerelleştirme: `LocalizedStringResource`'a geçiş, plural'lar, widget catalog'u, eksik tr/de/fr çevirileri.
15. Erişilebilirlik: satırlara `accessibilityValue("Unread, Starred")`, semantic font stilleri.
16. Ölü kodu sil, `Shared/`'ı yeniden düzenle, `AppViewModel`'i böl, spike'ı feature flag arkasına al.

---

## Kanıt: ekran görüntüleri

| | |
|---|---|
| ![macOS reader](screenshots/reader.png) | Mükerrer feed'ler (kenar çubuğu), tek kaynaklı SIFT Feed, tek paragraflık "1 min read" okuyucu |
| ![AI summary](screenshots/ai-summary.png) | "Apple Intelligence" başlığı altında gövdenin kopyası olan "Offline summary" |
| ![Daily briefing](screenshots/daily-briefing.png) | Gerçek on-device brifing — ama ham `*Markdown*` |
| ![iOS feed](screenshots/ios-feed.png) | Temiz kurulumda bile SIFT Feed'in ilk 7 öğesi tek kaynaktan |

---

## Adil olmak gerekirse — iyi olanlar

- `FeedRefreshService` bir `actor`; HTTP istemcisi ve container enjekte edilebilir; testler (derlendiğinde) ağa çıkmıyor, in-memory SwiftData kullanıyor.
- Feed parse'ında harici XML entity'leri kapalı (XXE yok); okuyucu feed HTML'ini çalıştırmıyor, düz metin render ediyor.
- Analitik yok, üçüncü taraf SDK yok, sırlar yok.
- Okuyucu tipografisi, Add Feed önizlemesi ve iOS onboarding gerçekten şık.
- On-device Foundation Models brifingi çalışıyor ve gerçekten faydalı; Private Cloud Compute'a düşmüyor.
- `FUTURE_WORK.md` kendi zayıf noktalarının bir kısmını dürüstçe listeliyor.

Kısacası: bu bir "yeniden yaz" vakası değil, bir **"önce durdur, sonra konsolide et"** vakası.
Yeni özellik eklemeyi Sprint 1 bitene kadar dondurun.
