// The Turkish pack's text (LanguagePacks.buildTranslation): every one of the game's texts
// translated anew from English, by hand (3918 texts, tools/lang/turkish.json of th0mk's
// nfsu2-web at e75e10d: by the label the game's code and menus look it up by, here its
// bStringHash, or its hash where no label is known), and the 14 memory-card texts.  The
// translation's own pack (muntazam's, moddb.com) gives only its fonts, whose textures draw
// accented letters of the game's fonts as the Turkish ones; trBytes writes the text in those.
// Ported from th0mk's nfsu2-web tools/lang/turkish.json (MIT).
import Foundation

enum TurkishTexts {
    /// the letters as the translation's fonts draw them, and the game's fonts' own U+2019, U+2122, U+2014 and U+2026; the rest is Latin-1
    static let letters: [Character: UInt8] = ["ş": 0xff, "ı": 0xed, "ğ": 0xfd, "İ": 0xcd, "Ş": 0xfe, "Ğ": 0xdd,
                                              "\u{2019}": 0x81, "\u{2122}": 0x82, "\u{2014}": 0x83, "\u{2026}": 0x86]
    static let latin: Set<Character> = Set((0x20..<0x7f).map { Character(UnicodeScalar(UInt8($0))) })
        .union(["Ç", "Ö", "Ü", "ç", "ö", "ü", "©", "®", "Ñ", "\u{a0}"])

    /// a text in the letters of the translation's fonts; refused if it has a letter the fonts lack
    static func trBytes(_ s: String) throws -> [UInt8] {
        var out: [UInt8] = []
        for ch in s {
            if let b = letters[ch] { out.append(b); continue }
            guard latin.contains(ch), let v = ch.unicodeScalars.first?.value, v < 0x100 else {
                throw LanguagePacks.Failure(message: "a Turkish text with a letter the fonts lack (\(ch))")
            }
            out.append(UInt8(v))
        }
        return out
    }
    /// {hash: the text in the fonts' letters}
    static func bytes() throws -> [UInt32: [UInt8]] {
        var out: [UInt32: [UInt8]] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tab = line.firstIndex(of: "\t"), let h = UInt32(line[..<tab], radix: 16) else {
                throw LanguagePacks.Failure(message: "a Turkish text line of another layout")
            }
            out[h] = try trBytes(String(line[line.index(after: tab)...]))
        }
        return out
    }
    /// the memory-card texts (memcard/LOCALE_ENGLISH.loc's, in its order), in the fonts' letters
    static func memcard() throws -> [[UInt8]] { try memcardTexts.map(trBytes) }

    static let memcardTexts: [String] = [
        "2.03.09",
        "2.08.04",
        "Evet",
        "Hayır",
        "Devam",
        "PC sabit diski",
        "Daha önce kaydedilmiş oyunun üzerine yazılsın mı?",
        "Kayıt tamamlandı.",
        "%1 kaydedilemedi.",
        "Yükleme tamamlandı.",
        "%1 yüklenemedi.",
        "%1 kaydını silmek istediğine emin misin?",
        "Kayıtlı oyun silindi.",
        "%1 silinemedi.",
    ]

    // hash (hex), a tab, the text
    static let raw = #"""
00000535	BAŞLA!
0000061c	Hayır
00000639	TAMAM
0000063c	Açık
0000bcea	km
0000c3e5	Maks
0000c4e3	Min
0000ccfa	Kapalı
0000d99a	KIRMIZI
0000f770	Evet
00075ff1	Performans Atölyelerinden biri, sanayi bölgesindeki Doğu Coal Harbor'da. Atölyenin girişini mavi bir ışık gösteriyor.
000c5436	TİP 3 FUŞYA & MAVİ
000f3aa9	AutoMaxx Magazine
001335f0	Geri
00136707	MAVİ
001578c3	Fit
00163c76	GRİ
00169268	Yardım
0016e856	ESPAÑOL
0018b36f	Tur
0018d506	ÇAĞLA
0018ecff	Yükle
00193f3e	Erkek
001a076f	Yok
001b01cc	Phil
001c0cc9	Arka
001c8ace	Kaydet
001d380e	Süre:
0020747c	Ebeveyn veya Vasi E-posta Adresi:
0023e142	Lobiye bağlanıyor...
00269446	Need for Speed™ Underground 2 demo sunucusu bu ayın sonunda kapatılacak.
0037776c	BILSTEIN
0066568a	Xbox Live Ana Menüsüne Dön
007f80b4	^3 Drag Yarışı
0097e000	City Core:
0097e001	Beacon Hill:
0097e002	Jackson Heights:
0097e003	Doğu Coal Harbor:
0097e004	Batı Coal Harbor:
00d5f627	Araba Seç
00d87a00	%s için geçiş kodunu gir
00f50bb0	^3. Aşamada 6. yarışını kazandığın için dergi kapağına çıktın!
015c767c	Arka Tamponlar
017b2522	Küfür / Müstehcenlik
018127bd	Değişiklikleri İptal Et
018a7ed8	KICKER SUB - 10 İNÇ
018a7eda	KICKER SUB - 12 İNÇ
018a7edd	KICKER SUB - 15 İNÇ
018b0b39	MTX SUB - 10 İNÇ
018b0b3b	MTX SUB - 12 İNÇ
018b0b3e	MTX SUB - 15 İNÇ
018b979a	JL AUDIO SUB - 10 İNÇ
018b979c	JL AUDIO SUB - 12 İNÇ
018b979f	JL AUDIO SUB - 15 İNÇ
018c23fb	CLARION SUB - 10 İNÇ
018c23fd	CLARION SUB - 12 İNÇ
018c2400	CLARION SUB - 15 İNÇ
018cb05c	NFSU SUB - 10 İNÇ
018cb05e	NFSU SUB - 12 İNÇ
018cb061	NFSU SUB - 15 İNÇ
019a5232	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
01a11990	 $JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Araba Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Bu Arabayla Takas Et^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
01ba754e	Mustang GT
01e66364	Motor Yaktı
01f1a2d4	Özel Göstergeler
01fb58d9	Harita filtresi
0217453f	Bu pakette, arabanda takılı olandan daha kötü bir^parça var. Yine de bu performans paketini^takmak istiyor musun?
021f3324	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Pisti Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
02300668	206
023c271e	Ocak
025c8892	Performans Atölyelerinden biri, sanayi bölgesindeki Batı Coal Harbor'da. Atölyenin girişini mavi bir ışık gösteriyor.
0266ba2c	Sesli sohbet sona erdi!
026eea5e	Motor
027eba65	COPPERHEAD KARBON FİBER
028f7092	Kaputlar
02902eed	Chuck
0294d2a3	Jantlar
02956667	KREM
0299d1b4	Havalimanı Drag yarışları
02aadac5	BAGAJ SES SİSTEMİ
02ad727f	Bu oyuncuya zaten davet gönderdin!
02b00aa1	Seçilen ağ yapılandırması yüklenirken bir hata oluştu.
02b641c0	Yeni profil oluşturmak istiyor musun?
02cbdc28	Ön
02d32a79	çevrimiçi
02d48035	Need for Speed™ Underground 2 logosunu görebiliyorsan^ televizyonunun parlaklığını düşürmen gerekiyor.
02ddc8f0	YEŞİL
02fa33b5	SMS mesajı
030353cd	%$.1f yıldız puanına ulaş
03312f33	Bu dergiyi kaydetmek ister misin?
033ce3d4	İnternet servis sağlayıcına bağlanırken zaman aşımı oluştu.
03458a59	Mil
034a3451	^4. Aşamada 27. yarışını kazandığın için dergi kapağına çıktın!
035c9376	Süre (sn)
036652c5	OKYANUS
036e79b9	Mevcut EA Hesabını Kullan
0371711c	Senin
037304ec	Motor freni
03812413	BROOKE: Merhaba, ben Brooke Burke. Need for Speed: Underground 2'de Rachel Teller'i canlandırıyorum.
03812414	BROOKE: Oyunda yarışçı rolü oynamak çok eğlenceliydi ama gerçek sokaklarda her zaman güvenli ve sorumlu araba kullanıyorum.
03812415	BROOKE: Konu yarış olunca, bunu yalnızca Underground 2'nin sokaklarında yap.
03812416	BROOKE: O yüzden her zaman emniyet kemerini tak ve trafik kurallarına uy.
038a6e08	Arkaya Bak (Aşağı)
03932cdc	GT
039df715	Tekrar Dene
03aee1cc	Scott
03b4c3de	%s adlı oyuncuyu arkadaş listenden çıkarmak için bu sesli sohbeti bitirmelisin.
03b83203	ORİJİNAL
03cb927e	Tork
03cd7c4c	EA Hesap Adımı Unuttum
03d43f19	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
03ec7395	Kaydet
03f07d3a	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$  Çevrimiçi Oyundan Çıkış Yap^
03f6f2bf	LAN Menüsü
03f9e820	BEYAZ
040a7027	XENON 4000K
046e7d84	Ana Menüye Dön
047277ae	 - Pek çok sürüş disiplininde yeteneklerini geliştir
047c8718	Ebeveyn İzni
048c2116	KENWOOD AMFİ - 1000 WATT
04984589	Geri bildirim gönderilemedi.
04a28571	Ana Menüye Dön
04a99922	Daha zor tekniklerden biri olan frenle girişte (trail braking) frene ancak viraja girerken basar ve tepe noktasına kadar bırakmazsın. Arabayı drifte sokmamaya dikkat et.
04b28917	Görsel Puan
04d88d82	Kurucu Ayarları
04dc6db5	Kontroller
04fbc4b0	Blok Hassas İşleme
050185f4	%s engellendi.  Artık %s adlı oyuncudan mesaj, davet veya sesli sohbet daveti almayacaksın.
05054a89	KIRMIZI
050b14e9	MÜKEMMEL VİTES %:
05111984	KENWOOD AMFİ - 250 WATT
053d8734	Oyuncu İstatistikleri
05416105	Hızlı Yarış Mod Seçimi
054b17dc	Atölyeye Gir
055ad46b	YOKOHAMA
057873b9	Performans Yayları ve Amortisörleri
059710bd	Arabayı Modifiye Et
0598b065	Mükemmel Vites!
05997667	Sesli Sohbet Kesilsin mi?
05b2b70f	E-posta Adresi
05fc33f5	ECU
0606418e	Havalı bir arabaya son dokunuşu stoplar yapar. Yeni modeller şimdi tüm Bayview Kaporta Atölyelerinde.
061ef24f	Pist Haritası:
0627094e	En Hızlı Drag Derecesi
06285e80	Güç ( %s )
063d57a0	Oyun Oturumuna Katıl
0642806b	Mesafe:
069b71e3	Lobi sunucusuna bilinmeyen bir nedenle bağlanılamadı.
06a63c01	MÜZİK AYARLARI
06cc3750	Kalabalık
06d7902c	Bu vinili değiştirmek ya da kaldırmak istiyor musun?
06f8e5bf	Özel Etkinlikler
07190cab	Bu hesap yasaklandı.
0720fc4e	E-posta Adresini Onayla:
07216a68	Sponsorlu Sprint
078290ed	STILLEN
07901f16	Oluşturulan Oda
07a41042	ITALIANO
07cd17b0	Keşif Moduna dönülsün mü?^Kaydedilmemiş yarış ilerlemen kaybolacak.
07e0de53	Hafif Camlar
07f10319	Yenile
07f24787	Arabana bu grafik tasarımını satın almak istiyor musun?
080f7425	Kontrol Çubuğu
0836f968	Mesajı Sil
08405fb0	LAVANTA
084bc378	Ara Zaman
085b6a2f	Piyasadaki en yeni şanzımana geç, beygirlerini asfalta daha hızlı aktar. Yalnızca Bayview Performans Atölyelerinde taktırabilirsin.
08778f27	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Geri^
0877cb04	Street X, hızlı reflekslerin ve çelik gibi sinirlerin kazanmakla^kaybetmek arasındaki farkı belirlediği kısa pistlerde sıkı bir yarıştır.^Bu meydan okumayı kabul et ve iç çizgiyi kapmak için kıyasıya^mücadele edeceğin, 3 rakibe karşı 3 turluk bir yarışa gir.
087fea07	Çevrimiçi Araba Seçimi
089c4d6c	Dergi %d
08a6b11c	ÜÇ RENK D
08a6b11d	ÜÇ RENK E
08a6b11e	ÜÇ RENK F
08e27392	Performans Ayarı
08fbd504	Bu, bölge 4 yorumu
0903e809	Hesap Şifresi
0905101f	Emeği Geçenler
091bb4ea	Bu çıkartma yuvası zaten boş!
0928b181	Hafıza Kartı Yuvası A
092be141	Sentra
094a635e	Spinner
0972a44b	Yarış yeniden başlatılsın mı?
0988aa9e	Tur Rekoru
0995ced0	ORİJİNAL
099669b1	TEMPEST OFSET
09d1ce77	Kazanılan Şehir Yarışları:
09e275bf	Şifreyi Onayla
0a06c516	Neon
0a10fbc6	Ağırlık
0a16b73d	Şimşek Seti
0a23978b	Bu oyunda gösterilen arabaların görünümü ve^performansı gerçek arabalardan farklı olabilir; oyundaki^sürücüler de trafik güvenliği kurallarına uymuyor olabilir.^Gerçek hayatta araba kullanırken güvenli bir^sürücü olmayı unutma: emniyet kemerini tak, sinyal^ver ve sağduyulu davran.
0a276384	Uygunsuz Ad
0a5f792c	Yarış Tekrarı
0a83064c	Sunucunun Hile Suçlaması
0a96b270	Aşama %d
0a96dc2b	Tur Eleme yarışlarında turlarını iyi yönet. Yarışta kalmak için hiçbir turu sonuncu bitirmemelisin. Son tura kadar rakiplerine yakın dur, sonra galibiyet için hamleni yap.
0aab553e	Galeriye girmek istiyor musun?
0aac6601	Gamertag Bul
0ab092d0	Stilin son noktası: yeni motor neonu renklerimiz şimdi tüm Bayview Aksesuar Atölyelerinde.
0b161ec3	Ön Alçaltma
0b191d2d	Soğuk Hava Emiş Sistemi
0b1b1fc4	Arkadaş İstekleri
0b214c53	Mevcut Aşamada Yarış Başına Ortalama İtibar Puanı
0b24883a	Street X Lideri
0b4f08df	KAZAYI ATLATTIN
0b660729	Oyuncu Adlarını Göster
0b70e285	TAVAN KEPÇESİ YOK
0b8066fd	%s arkadaş listesinden çıkarılıyor ...
0b83ad1b	Çevrimiçi Rekabet
0b9253e9	Kaporta Atölyesi
0b9479a4	Gelen SMS'in türünü anlamanın hızlı bir yolu, mesaj geldiğinde görünen simgeye bakmaktır. Her mesaj türünün kendine özgü bir zarf simgesi vardır.
0bcb8df8	Muhteşem Drift!
0c2925dc	^3 Street X Yarışı
0c36c7ca	%s kapak fırsatı
0c5b144c	Gergi Demiri
0c5cbb42	Özel %s
0c649166	Sponsorluklar, Underground Racing League'e giriş biletin. URL yalnızca davetle girilebilen bir lig ve davet almak için büyük bir itibar gerekiyor. Sponsorlar itibarı yüksek sürücüleri arar; yani rakiplerini pistte yenmekle yetinme, onları yerle bir et.
0c71b0f0	SÖZLEŞME HÜKÜMLERİ:^Sürücü 9 URL yarışı, sponsorun seçeceği 3 yarış ve kendi seçeceği 34 ek yarış kazanmalı.^^EK ŞARTLAR:^4 DVD kapağında yer alacak bir araba yap.^^BONUS:^Bayview galerisinden hediye araba.
0caa2974	Araba
0caa2dbc	Gün
0caa7f8c	Galibiyet
0cb1fe97	Haberler
0cea9ed9	Yakıt Rampası
0cf90ef1	5Zigen
0d05bb71	Daha fazla güç için motorunu yenisiyle değiştir. Yeni motorlar yalnızca Bayview Performans Atölyelerinde.
0d0ae497	Ana menüye dönülsün mü?
0d3f5f29	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Devam^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
0d482b72	Şehrin sanayi bölgesindeki Doğu Coal Harbor'da bulunan Galeriyi ara. Turkuaz ışığı gözden kaçırma.
0d7de8ab	Profilini kaydetmek istediğine emin misin?
0d817a4a	Galibiyet Oranı:
0da7aa1b	Alt Yarı
0dad5a6d	^3 Pist Yarışı
0db1a145	En İyi Drift:
0dc884cb	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
0dd35467	Yan Aynalar
0e00af3f	GERİ
0e013d55	BÜYÜK
0e0204f4	TAMAM
0e115637	Karbon Bagaj
0e1f1271	Derecesiz
0e27cb54	Dinle dostum, bu Sprint yarışını kazanırsan bu sözleşmeyi bitirmeye bir adım daha yaklaşırız. Hem çizgiyi birinci geçtiğinde paramızı alıyoruz.
0e27cb55	Dostum, Sprint yarışları yükselişte ve sponsorun buna bayılan gençlerin gözüne girmek istiyor. Bu yarışı mutlaka kazan, iyi bir izlenim bırakır.
0e27cb56	Kimse bir kaybedeni desteklemek istemez, hiçbir sponsor da batan gemiye para yatırmaz. Para gelmeye devam etsin istiyorsan kazanmaya devam etmelisin. Çık oraya ve iz bırak.
0e27cb57	Ocakta kaynayan birkaç anlaşmam var. Kazanan birini bulurlarsa ciddi para dökmeye hazır başka sponsorlarla da görüşüyorum. Ne dersin, bir galibiyetle onları etkilesene?
0e27cb58	Mesele şu dostum: Kazanmak para demek, büyük para da sponsorlardan gelir. Bu dümdüz gaz şovu sözleşmende büyük ağırlık taşıyacak. O yüzden orada herkesi ağzı açık bırak.
0e27cb59	İkinci olmak, kaybedenlerin birincisi olmak demek ve sponsorlar kaybedenlerle takılmaz. Bu Sprint yarışı şimdiki sözleşmen için birkaç artı puandan çok daha değerli. Bu yarış ileriki anlaşmaların tohumunu atacak, o yüzden büyük gelmen lazım.
0e27cb5a	Hava atmayı bırak da ciddileş. Bu Sprint sözleşmene işleniyor ve sponsorlar galibiyetten başka hiçbir şeye razı olmaz. Sonuna kadar yüklen, ortalığı yak, çünkü iş paraya dayanıyor.
0e27cb5b	Duydun mu! Nasılsın? Doğru ya, kimin umurunda. Tek istedikleri kazanan görmek, bu gece de tam sırası. Bitiş çizgisinden roket gibi birinci geçsen iyi olur, yoksa dünyan başına yıkılır.
0e27cb5c	Hey oğlum, umarım o teneke bu gece sağlam çekiyordur, çünkü bu kapışmada sonuna kadar zorlanacaksın. Sponsor işi ayarladı, bu yarış sözleşmene sayılıyor. Kazanırsan cebine birkaç yüzlük düşer, bir gece daha yaşarsın. Kaybedersen... ne olacağını biliyorsun...
0e3b7e70	URL İkincisi
0e44a6be	Xbox Live'dan önemli bir mesajın var. Giriş yapabilmek için önce bu mesajı okuman gerekiyor.
0e9bc521	Mini Harita, ekranının sol alt köşesinde yer alır. O an ulaşabileceğin yerler ve etkinlikler burada görünür. Dış halkadaki simgeler, bulundukları yerin kabaca yönünü gösterir. Menzile girdiğinde bu simgeler haritada tam konumlarında belirir. Harita dönüşünü Ayarlar menüsünden değiştirebilirsin.
0ef34382	AZAMİ HIZ
0f030942	Jantlar
0f037a7b	Sponsorlu Pist
0f0b824e	Yarış Tipi Eksantrik ve Dişliler
0f0f62a5	Yarış Gecesi
0f19e56d	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Marka Değiştir^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ İlerle^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
0f1bb84d	Liderlik Süresi:
0f4889bd	Artık altında bir araba olduğuna göre garajıma gel. Yerini haritana yükledim ve GPS'ini de açtım. Ha, bir de yarış aramaya hiç uğraşma, ortalıkta bir şey dönmüyor. Beni bekletme. Orada görüşürüz.
0f5ae412	Biraz ekstra itiş mi lazım? Piyasanın en güçlü N2O'su şimdi yalnızca Bayview Performans Atölyelerinde.
0f636a00	BOŞ YER
0f87545d	Azami Tork:
0f9109b2	RACHEL: Sana işin özünü anlatayım. Bayview'daki yarış dünyasında her şey benden geçer.
0f9109b3	RACHEL: Fark etmediysen söyleyeyim, asıl olay burada; buranın yarış dünyası DEV gibi.
0f9109b4	RACHEL: Ne seviyorsan burada bulursun--tabii nereye bakacağını biliyorsan.
0f9109b5	RACHEL: Drag, drift, pist yarışları ve çok daha fazlası. Olay o kadar büyük ki, aklının almayacağı yerlerde yarışıyoruz!
0f9109b6	RACHEL: Tabii bu da ciddi para kazanma fırsatı demek. En güzeli de, elit sürücüler için yalnızca davetle girilen Underground Racing League diye bir seri var; orada dönen para da itibar da uçuk!
0f9109b7	RACHEL: Tek ihtiyacın yeterli itibar ve doğru bağlantılar.
0f9109b8	RACHEL: Unutma, burası benim şehrim; sen misafirsin, saygıda kusur etme. Arkada Tommy var; kaputun altında sihirbazdır. İşini o görür.
0f9109b9	TOMMY: Selam dostum, Rachel her işini garajdan halledebilesin diye ayarladı--sana biraz yer ayırdı. Gel, arabalarını nerede saklayacağını göstereyim.
0fce0dbb	Atölyelerin stokları zamanla değişir; yeni parçalar geldiğinde SMS alırsın. Hangi yeni parçaların açıldığını görmek için mesajlarına bak. Keşfedilen ya da kilidi açılan parçalar, o türdeki tüm atölyelerde satışa sunulur.
0fda6758	Street X
1003ea2b	Titreşim:
10073c4f	Bu ürün için bir yama yayınlandı.  'Tamam' dediğinde oyun kapanacak; çevrimiçi oynamak için yamayı indirip kurman gerekecek.
10199579	Bu arkadaşını engellemek için bu sesli sohbeti bitirmelisin
101a3187	Doğu Beacon Hill
1024215d	Batı Beacon Hill
1036e38e	Bagajı Orijinale Döndür
1038f284	Araba ve Parça Deposu
105149cb	Test Sürüşüne Devam Et
10600aa4	%s adlı oyuncu engellendi. Artık %s adlı oyuncudan mesaj ya da meydan okuma almayacaksın
106ae8c8	Lobi sunucusuna giriş yapılamadı. Sunucu kapalı olabilir ya da şu an bağlantıyı engelleyen ağ sorunları olabilir. Ağ ayarlarını kontrol edip daha sonra tekrar dene.
10811591	Başka bir oyuncu, istenmeyen ilgisiyle doğrudan seni hedef alıyor. O oyuncuyu engellemene rağmen seninle iletişim kurmakta ısrar ediyor.
10965456	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
10a27a02	Bu personayı silmek istediğine gerçekten emin misin?
10adeaf7	SVENSKA
10b5e8d1	Karbon Fiber Yan Aynalar
10b83327	Yeni bir düzen seçersen önceki düzendeki çıkartmalar kaldırılacak. Devam etmek istiyor musun?
10cd6bbc	Araba Aydınlatması
10e39e90	Kabin Neonu
10e836c8	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Araba Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$  Arabaları Yükle^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$  Araba Filtresini Değiştir^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Arabayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
11159f62	GPS'i Kapat
113eab80	Bu bagaj düzenini şimdi yüklemek istiyor musun?
11504d0e	Renk Tonu
11b00cb3	Piyasanın en iyi turbosunu tak, fazladan beygirlerin tekmesini hisset. Seninkini bugün al; yalnızca Bayview Performans Atölyelerinde.
11b1ef7c	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Boya Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Boya Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Rengi Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
11ddb88a	GPS sistemi, haritadaki yerleri bulmana yardım eder. GPS seçeneğine Şehir Haritası tuşuna basarak ulaşabilirsin. Haritada gidebileceğin yerler arasında gezin, sonra GPS'i Etkinleştir düğmesine tıkla. Keşif Moduna döndüğünde mavi ok, seçtiğin yerin yönünü gösterir.
11e168c1	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Vinil Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Vinili Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
11e290e1	Kimden: %s
11f1c307	Sesli sohbet daveti reddedildi.
11f7ac44	Ödüller
12107ffe	Mesaj Gönder
12192771	Harita tercihi
121f05d4	%s için engel kaldırılsın mı?
1231c38f	%s arabanı, %s yerine sürmek istiyor musun?
1283f74e	Müzik Sesi:
1288e414	Kontrol Ayarları
12b0ea08	Arabayı harika toparlamışsın. Kapak çekimi için haritadaki noktaya git.
12c23b2c	GPS kapatılıyor
12c86a0a	Arabayı Sür
12df9f4f	Sıralama tablosu verileri sunucudan alınıyor.
12ebb406	Bu arabayı seçmek istiyor musun?
130d90d1	Yenile
13121940	Arkaya Bak
13138f54	EA Messenger'a bağlanılamadı.
135bdd07	ECU
135c04da	Nitro
13640de9	Puanın:
1365aede	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
1398f642	Ana Menü
13b49408	Para:
13b655c5	Konuşma ve Video Sesi:
13f0edeb	Varsayılan Ayarlar
1404a5ef	PARLAK YEŞİL
14053554	Yeni özel göstergelerle arabanın içini kişiselleştir. Stoklar tükenene kadar tüm Bayview Aksesuar Atölyelerinde.
14216d0d	GELİŞMİŞ DÜZEN
1422bac1	TİP 3 SOL ÜST VE SAĞ ALT NOZULLAR
1435ead4	Bayview Grafik Atölyesi Doğu Beacon Hill şubesine hoş geldin. ^Jant Boyası ve Yırtık Vinillerin kilidini açtın. ^Diğer Grafik Atölyelerinde açılan tüm parçaları burada da bulabilirsin.
144849c1	EA sunucusuna bağlanıyor...
1448c75e	Görsel Hata Ayıklama
145472a7	Seçtiğin Gamertag uygun değil.^Farklı bir Gamertag girip tekrar dene.
145890ee	Oyun Türü:
1492d7be	Doğum Tarihi
14c2eaea	Four on the Floor
14d4bd3b	Direksiyon Tuş Ayarları
14ee2fb1	Jantlar
15051f3d	V1 SOL KAPUT HARİÇ TÜMÜ
150612a9	Sponsor bu arabaya bayılacak. Arabanın fotoğraflarını çektirmek için haritadaki noktaya git.
150dfd4c	Bu persona geçersiz ya da şu an oluşturulamıyor.
151921d1	Gamertag'ler yüklenemedi.
151c443f	Pist:
1520c51f	PARLAK BEYAZ
15314d26	XENON 8000k
153e7337	Direksiyon (Sol)
155409e8	Uyduya ulaşılamıyor
1582adff	Araba Hasarı
158fab75	Jackson Heights
159c3dbf	EA Online Kullanım Şartları - Metni Sue Garfield sağlayacak
15aa8262	Denge Kontrolü:
15d1543a	Sözleşmeni tamamlamak için sponsorunun bizzat seçtiği bazı yarışlara katılman gerekecek. Bu yarışlar haritanda X ile işaretli.
15d6b438	Atölyeye girmek istiyor musun?
15f2a153	Ses Sistemi İpucu
15fe0769	Kulaklık
1605b575	ORİJİNAL AYNA
1606a1bb	Elaborare
16549076	Konu: Dergi Kapağına Bak
165a5df5	Bugün uğra, karbon bagajını kap. Şu sıralar en gözde yükseltme bu. Seninkini Bayview bölgesindeki herhangi bir Kaporta Atölyesinden al.
167bcf0b	Bu persona geçersiz ya da şu an silinemiyor.
16d46194	EA Online Kullanım Şartlarını kabul ediyor musun?
16e1caa9	Açılan Araba:
17137ad4	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
172d67bc	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Boya Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Boya Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Rengi Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
174cc8dc	TUR SÜRESİ
175b3b4a	Araba bomba olmuş kanka. Şimdi onu haritadaki noktaya götür de DVD kapağı çekimini yapalım.
17828bea	Persona oluşturuluyor: '%s'...
17aaef8b	Diğer oyuncularla bağlantı koptu.  Mevcut oyun oturumu sonlandırılacak.
17b4243f	106
17ea64f8	Konu: %s
17fafc32	En İyi Tur
181419e5	© 2004 Electronic Arts Inc. Tüm hakları saklıdır.^Türkçe çeviri: Samet Samyeli
182154db	Bu sesli sohbete girersen mevcut sohbet sona erer. Devam etmek istiyor musun?
18267cdb	Hey, seni önceden uyarayım dedim. Artık sponsorla sözleşmeli olduğuna göre, anlaşmanı tamamlamak için belirli yarışları bitirmen gerekiyor. Haritada X ile işaretliler.
182fad46	Neredeyse
18486dd1	KOŞULLAR:^9 URL galibiyeti, sponsorun belirleyeceği 3 yarışta galibiyet ve sürücünün seçeceği 34 ek galibiyetle sözleşme tamamlanır.^^TANITIM ŞARTLARI:^4 DVD kapağında yer alacak bir araba oluştur.^^BONUS:^Bayview'daki herhangi bir galeriden bedava araba.
184ab1a3	Direksiyon oranı, tekerleklerin direksiyon hareketine ne kadar hızlı tepki vereceğini belirler. Direksiyonun hassasiyetini sürgüyle ayarla. Arabayı kontrol edebildiğin sürece hızlı direksiyon iyidir.
186cf32b	Rakipten SMS mesajı
18af8696	Bugün geldi! Bayview'un gördüğü en gözde yükseltme! Karbon kit uygulaması artık tüm Bayview Kaporta Atölyelerinde. Body kitini ekibinde ilk karbonlayan sen ol.
18b97380	Outrun Kabul Edildi^Onu Yakala!
18cdd1fc	 $JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
18d5a136	Dyno'ya Dön
18daea6d	Kurucuyla bağlantı koptu.
18f8c0d2	Motor neonu
191ce8c3	ORİJİNAL
191e862c	Yüksek Akışlı Emme Manifoldu
19498922	+Kontrol Pedi
194efa7a	Keşif Moduna Dön
1952ea17	Outrun Yarışı
1973da3a	CD anahtarın doğrulanamadı. Anahtarın doğru girildiğinden^ve daha önce başka bir hesabı doğrulamak için^kullanılmadığından emin ol.
19889765	LAN Ayarları
19a1665b	Straight From the Streets IV
1a00ef9b	Bu fotoğrafçı bütün gece bekleyecek değil. O çekip gitmeden yanına varmak için %s süren var.
1a09bef9	0-60 MPH:
1a2153d9	TİP 2 MAVİ
1a2214fc	TİP 2 CAMGÖBEĞİ
1a23d5e6	Dereceli Arabalar
1a241d57	TİP 2 ALTIN
1a311489	Boyadaki değişiklikleri iptal etmek istiyor musun?
1a5eb97d	Bu tipler ciddi; bu Drift yarışını kazanmak sözleşmende yazıyor, yoksa sponsorlar fena bozulur. Çizgiyi yan yan geçip birinci olduğundan emin ol.
1a5eb97e	Şimdiden havalara girme. Bu Drift yarışının ucunda sandığından çok daha fazlası var. Sponsor bunu sözleşmene eklemiş, yani kazanman şart. Kazananları severler, kaybedenleri değil.
1a6a162d	PIAA
1a6c645d	TOYO
1a84d5e7	Kolay
1a9a01d9	Bayview Aksesuar Atölyesi Batı Coal Harbor şubesine hoş geldin. ^Kapılar, Hidrolik ve Ses Sistemi Düzeni 3'ün kilidini açtın. ^Diğer Aksesuar Atölyelerinde açılan tüm parçaları burada da bulabilirsin.
1aca23b9	Doğu Beacon Hill'deki Grafik Atölyesi, Beacon Hill'e çıkan köprünün hemen kuzeyinde. Kırmızı ışığı ara.
1b04af37	Bugün geldi! Piyasadaki en gözde geniş kasa kitleri. Şimdi tüm Bayview Kaporta Atölyelerinde. Ekibinde arabasına ilk takan sen ol.
1b15f53c	Birincil
1b2794c7	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ Gösterge Türünü Değiştir^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Göstergeyi Seç^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
1b3a2485	Manuel
1b4a2070	V1 SAĞ KAPUT HARİÇ TÜMÜ
1b4a3984	Kristian
1b59940c	Elendin!
1b7abf8e	Otomatik
1b7abf8f	Sor
1b7abf90	Kapalı
1b99ca46	Xbox konsolun Xbox Live'a bağlanamıyor.  Sorun gidericiyi başlatmak istiyor musun?
1bc6a610	STİL PUANLARI
1bc6be57	O arabayla beni yendiğine inanamıyorum, bayağı yeteneklisin demek. Sana birkaç özel performans parçası ayarlayıp seni sokakların kralı yapacağım. Haritadaki yıldıza git, seni arayıp ayrıntıları veririm.
1bc7f9a8	Sponsor Simgeleri
1be259f7	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Sayıyı Artır / Azalt^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Devam^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
1be4b223	Kayıtlı oyunlar kontrol ediliyor.
1bf733bd	Bölünmüş Ekran Pist Seçimi
1c0787e6	Geri
1c098ddf	Bu oyun zaten başladı.
1c101778	Oyundan Çık
1c56183c	Arabanı bu derginin kapağına taşımak istiyorsan önümüzdeki %s içinde çekim yerine varsan iyi olur.
1c6f2a82	400m Süresi:
1c767c7a	TİP 3 MAVİ
1c773d9d	TİP 3 CAMGÖBEĞİ
1c775494	Tehdit / Taciz
1c7945f8	TİP 3 ALTIN
1c8994dc	ALTIN NABIZ
1cad29f9	Yarış:
1cb0c3fc	Persona kullanılıyor: '%s'...
1cbfa047	Aksesuar Atölyesi
1cc4b396	Yol Hissi
1cd69245	MERCAN NABIZ
1cd9fe88	Önemsiz
1ce129e0	Süre Doldu
1cedc132	Arabayı Sıfırla
1cef2a7a	Bayview Aksesuar Atölyesi Doğu Coal Harbor şubesine hoş geldin. ^Spinner, Ses Sistemi Bileşenleri ve Ses Sistemi Düzeni 2'nin kilidini açtın. ^Diğer Aksesuar Atölyelerinde açılan tüm parçaları burada da bulabilirsin.
1cfc4d86	Lobi sunucusuna giriş yapılırken bir sorun oluştu.
1d01ec37	Mil ya da Kilometre
1d0351f3	Turbo
1d035425	Ses
1d1073f0	İyi Drift!
1d5494d0	CYCLONE OFSET
1d6bcad0	ANLAŞMA ŞARTLARI:^Sürücü şunları kazanmayı kabul eder: 3 URL yarışı, sponsorun seçeceği 3 yarış, sürücünün seçeceği 9 yarış.^^SOKAK İTİBARI MADDESİ:^1 DVD kapağında yer alacak bir araba yap.^^BONUS:^Sponsor 1 araba hediye eder.
1d7bb6c9	AYARLAR
1da45883	Performans Ayarı
1da8562f	Araba Atölyesi
1db81db6	İnternete bağlanıyor
1dd3420b	Ayarları Yükle
1defb577	Artık arabanın fotoğrafını çektirip bir DVD'nin kapağına çıkabilirsin.
1e101a86	TİP 2 İKİ TEKERLEK NOZULU
1e13c054	Çevrimdışı Görün
1e1be6f8	Güzel yarıştı birader. Bak, madem beni ezip geçtin, sana yardım etmek boynumun borcu. Arabana özel performans yükseltmeleri bulabilecek bir kankam var. Hemen haritandaki yıldıza git, seni arayıp sonra nereye gideceğini anlatırım.
1e1c73aa	Kulaklık
1e4cbc67	Konu: Dergi Kapağı Çekimi
1e6178fe	Satın Alındı
1e7e3391	Şehir Haritası
1e8d8068	Yeterli
1ea459f8	Son Tur
1ea4cec2	Uzak
1eab40dd	Kanka, adamın yetişmesi gereken bir uçak var. Onu oyalıyorum ama önümüzdeki %s içinde çekim yerine gelmezsen adam gider.
1eb104c8	Özel Göstergeler
1eb7bf0e	Ağ bağlantın koptuğu ya da diğer oyuncular oturumuna bağlanamadığı için yarış başlatılamıyor.  Mevcut oyun oturumu sonlandırılacak.
1ebf3a2b	NORTHEAST ÇİFT
1f178b4b	Yeni kabin neonu renkleri şimdi tüm Bayview Aksesuar Atölyelerinde.
1f181f57	START'a bas
1f182080	Enter tuşuna bas
1f26fdd1	BONUS BÖLGESİ
1f2f3afb	Sponsor Yarışı Ödülü:
1f533291	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
2002f302	Bu, bölge 2 yorumu
201e4aa2	Galeriye girmek istiyor musun?
2035b0d7	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Metni Kaydır^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
2038a10d	^3 Drift Yarışı
205b2bf8	Alıcının EA Messenger gelen kutusu dolu.  Bu mesaj gönderilemiyor.
20710f99	Kanka, o arabanı gerçekten uçurabilirim. Bana iyilik borcu olan bir dostum var. Sana çok iyi performans yükseltmeleri ayarlayabilir ama önce işi benim bağlamam lazım. Haritandaki yıldıza git, seni arayıp ayrıntıları veririm.
20870d48	Sonra Oku
20a05d53	Straight From the Streets IV DVD Kapağı
20b30cd8	Dostum, sistemi tahliye edebilmen için önce arabana^nitro takman lazım! Önce git bir nitro al!
20d0d219	Özel bir parça seçmezsen onu bir daha^asla seçemeyeceksin. Özel parça istemediğine^emin misin?
20d93324	Car Audio and Electronics
20e7f018	Kabin Neonu
20f02695	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Bagaj Düzenini Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Bagaj Düzenini Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
2100697e	Dostum, adam birazdan çıkıp gidecek. Vakit dar ama önümüzdeki %s içinde yanına varman lazım, yoksa şansını kaçırırsın.
2106e2fe	Arkadaş isteği geri çekildi
2109ad09	HIZLANMA
210de314	Cam filmleri
211462cc	JETSTREAM ÇİFT
2148f38b	ALPINE 2 ÇİFT LCD - 7 İNÇ
216cb3ec	En yeni tavan kepçesi tasarımlarıyla arabanın görünümünü değiştir. Bu son teknoloji tasarımlar şimdi herhangi bir Bayview Kaporta Atölyesinde.
21707032	Bir viraja yüksek hızla yaklaşırken virajın giriş noktasından önce fren yap. Virajın tepe noktasında gaza yüklen ve virajdan hızla çık.
218693e4	Çıkartma Renkleri
219dd875	En Uzun Atlayış
21cdebf9	ALPINE 2 LCD - 5.5 İNÇ
21d83e05	Arka Yere Basma Kuvveti
21dfd7a9	OptiMatch
221e85b4	çevrimdışı
2225348f	Bagaj Neonu
2237eacb	Profilin kaydedilemedi.^Otomatik Kayıt kapatılacak.
2244b5bd	Xbox Live Bilgi
22465e3c	Rakip Araba
224936f4	Çık
22729437	Adını gir:
227eba64	Drag yarışı - Rüzgar arkası
22a144ec	Sprint:
22a566de	Dereceli Oyunlara Katıl
22b1c2e6	Çevrimiçi Ayarlar
22b841e3	G35
22b8463e	GTO
22b863ed	NSX
22b874f1	RSX
22b87575	RX-7
22b87576	RX-8
22bc94af	Kayıt uyarılarını kapatmak istiyor musun? Artık oyununu kaydetmen istenmeyecek; kaydı elle yapman gerekecek.
22c71a87	Genel performansın ve arabanın görsel puanıyla ilgili bilgiler için Kariyer Durumu tuşuna bas. Kariyer Durumu ekranındayken sağa basarak, kariyerinde ilerlemek için tamamlaman gereken Aşama şartlarıyla ilgili daha ayrıntılı bilgilere de ulaşabilirsin.
22f254af	Ters
22fcca3c	EA GAMES™ TRAX
2303d76c	Erken Vites!
2308f06c	Fren Dengesi
2340fccc	Garaja Git
234f34d1	RACHEL: Nihayet! Arabamla nerelerdeydin sen, ha?
234f34d2	RACHEL: Üstünde tek bir çizik bile olmasa iyi olur!
234f34d3	RACHEL: Sam iyi sürdüğünü söylüyor; olabilir, ama benim arabamı sürmüyorsun.
234f34d4	RACHEL: Paranla kendine bir araba beğen--seni sonra ararım.
2352f304	Arabanı yenilmez bir makineye dönüştürecek lisanslı^performans parçalarının tamamı burada.
2355921f	Dostum, adamın sabrı tükeniyor. Bu gece beğendiği hiçbir şey görmedi, toparlanıp gitmek üzere. Onu oyalıyorum ama %s içinde burada olman lazım.
2363d940	Özel %s
23698b6d	HEADWIND ÇİFT
23c1dc8d	Arabanın sürüş hissini kendine göre ayarla, yarışta fark yarat. Yeni süspansiyonlar herhangi bir Performans Atölyesinde ya da Megalow Parts'ta.
23cf49aa	Bu işleve atamak için bir tuşa bas
23e795c8	Tebrikler!
23f359b8	Sonraki Yarış
240616e2	Uzatma^Outrun Kabul Edildi^Onu Yakala!
2408ad3d	HAFIZA KARTI yuvası 1
2415be66	Biraz daha yarış kazanman gerek!
241b0b3f	Denge Kontrolünü kapatarak arabanın yol tutuşunu değiştir. Kapattığında araban virajlarda kayarak dönebilir. Denge Kontrolü ayarını değiştirmek için Duraklatma menüsünde önce Ayarlar'ı, sonra Oyuncu'yu seç.
241be921	Toplam Galibiyet:
24295bcb	Galeriye Git…Hemen!
2430e6be	Direksiyon Oranı
243f8e1e	Bu oyuna bağlantı kaliten belirlenemedi.^Bu oyuna katılırsan kötü bir oyun deneyimi yaşayabilirsin.^Bu oyuna katılmak istediğine emin misin?
24435413	ORİJİNAL FREN
2451ea7c	TİP 2 KIRMIZI & YEŞİL
245448db	Yarış Modu Ayarları
246536ef	Dergiye Bak
24909fd7	Hızlı Yarış
24911e04	Karbon Fiber
24aae6ff	CALEB: Gördüğümüz hoşumuza gitti. Ekibimde sana yer var, hayır cevabı da kabul etmem. Ne diyorsun?
24ac4b22	İnternet servis sağlayıcınla bağlantın koptu.  Ağ adaptörünün ve ağ kablonun takılı olduğundan emin ol.  Ana menüye döneceksin.
24fe24ff	Kariyerinde ilerledikçe galerilere yeni arabalar gelir. Neler geldiğini görmek için sık sık uğra.
25187435	Turbo
2522a4e9	Parçacık Sistemi
25770b4f	Hafif Kapılar
2580f6e3	KENWOOD LCD - 7 İNÇ
25aac9bf	Yine de oyna
25b9eb23	ORİJİNAL JANT
25beb40e	ANNEX ÇİFT
25c9afe9	EA Online Kullanım Şartları
25cb7f0c	EA sunucuları şu an teknik sorunlar yaşıyor.  Daha sonra tekrar dene.  Sorun devam ederse EA Müşteri Desteği ile iletişime geç.
25ed0381	TİP 2 KIRMIZI & FISTIK YEŞİLİ
25f0c994	Kaporta Parça Deposu
25f16f40	Arkadaş isteği gönderiliyor: %s
26011f5a	1. SÖZLEŞME ŞARTLARI
26033125	Düşük
2617052e	Sen basıp giderken arkada kalanlara bakacak bir şey bırak: egzoz uçların için yeni özel boya renkleri geldi. En yeni renklere herhangi bir Bayview Grafik Atölyesinde göz at.
264a5f10	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Geri^
266131ce	Bu düzeni kaldırırsan daha önce takılan tüm ses^bileşenleri de sökülecek. Bu bagaj ses sistemi^düzenini şimdi kaldırmak istiyor musun?
26782c3e	Genel Ses Seviyesi
2680c3c8	Hafif Koltuklar
268d063c	Pist
2699cf8e	Diğer Arabalarıma Bak
26ddf58a	V3 SOL TEKERLEK HARİÇ TÜMÜ
26e0b3cc	Azami Güç
26e857be	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$  Arabayı Döndür
26fecee7	SPONSOR ARABALARI
2719025a	1. DVD
271918d2	2. DVD
272ebeba	Rachel arabasını geri istiyor. Çıkmadan önce kendine yeni bir araba seçmelisin.
27329d35	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
2756fb2f	Giriş yapılıyor: '%s'...
2765d827	SAMANTHA: Eddie'yi devirdin, kızı da kaptın. Peki sırada ne var, hiç düşündün mü?
27670dc1	YAPAY ZEKA HATA AYIKLAMA
27891593	Kapılar
279643ad	Bu Drift sponsorlar için. Yatırım yaptıkları şeyden onlara bir tadımlık verelim. Bu yarışı kazanırsan kapında kuyruk olurlar.
279643ae	Sokaklarda senin hakkında konuşulmaya başlandı. Kazanmaya devam edersen kısa sürede yarış efsanesi olma yoluna girersin.
279643af	Sponsorlar kazananlarla anlaşır, çünkü ürünü kazananlar sattırır. Bu gençler arabalarına kazananların kullandığı parçaların aynısını takmak istiyor. Bunu da kazanmaya ne dersin?
279643b0	Sponsorunun beklentileri yüksek, onları hayal kırıklığına uğratmasan iyi olur. Sokaktaki itibar satışlar için çok önemli ve sadece kazananı desteklemek istiyorlar. Birinci olursan güzel şeyler olur.
279643b1	Sözleşmeye baktım; bu yarışa sadece katılmayı kabul etmemişsin, kazanmanı da bekliyorlar. Bu adamlar galibiyetler için güzel para bayılıyor, o yüzden onları hayal kırıklığına uğratmayalım... tamam mı?
279643b2	Bu iş resmi oğlum. Bu kayma şovu sponsor sözleşmene işleniyor. Galibiyet bekliyorlar, temiz bir iş çıkarsan iyi olur. Bitişte görüşürüz.
279643b3	Bu yarışta sonuna kadar zorlanacaksın oğlum. Bu Drift, büyük abilerle imzaladığın sözleşmede yazılı. Önemli olan tek şey galibiyet. Çık oraya ve asfaltta şovunu yap, bu sefer şakası yok.
279643b4	Bu gece Drift'te olay var. Mesele şu: Buradaki galibiyet sözleşmene yazılacak. İkinci olursan kapı dışarı edilirsin. O adamların fark edeceği tek şey, müthiş bir kayma şovuyla birinciliğe uçman olacak.
279643b5	Bak şimdi: Bu geceki Drift, büyük abilerle yaptığın sözleşmeye yazılıyor. Galibiyet görmek istiyorlar ve onlara bunu vermekten başka seçeneğin yok. Gerekirse kirli oyna ama işi bitir.
27b8f0dd	Alt Katman
27b8f0de	Orta Katman 1
27b8f0df	Orta Katman 2
27b8f0e0	Üst Katman
27c499ee	Turnuva
27d2dd45	İyi Vites!
27d75cd8	Aşırı Devir!
27eabc8e	Şerit Vinil
27fafa1c	TİP 3 İKİ KAPUT NOZULU
2800e645	1 Drift Yarışı^1 Drag Yarışı^1 Sprint Yarışı
2813dcaf	RIPTIDE ÇİFT
2824ac08	^4. Aşamada 7. yarışını kazandığın için dergi kapağına çıktın!
2850c61d	Xbox Live hizmeti için zorunlu bir güncelleme var. Güncelleme yüklenene kadar Xbox Live'a bağlanamazsın.
286c2dcf	Motorunu şık yeni bir kaputla taçlandır. Bugün herhangi bir Bayview Kaporta Atölyesine uğra, yeni gelen geniş kaput çeşitlerimize göz at.
2881ab87	Ses Modu
288c79b7	%d kayıtlı mesaj
28a690a2	Titreşim
28b6eabc	TİP 2 İKİ SOL NOZUL
28bf66f6	Ses Bileşenleri
28cf7c1b	 — Arabanın performansının her ayrıntısına ince ayar yap
28f42ae8	Genel Kuvvet Şiddeti
2909a9d3	Bayrak Seti
29230556	Karbon Kaputlar
296692a0	Doğrusal
29742f2d	Aylık Puan Liderleri
2981cd3e	Nitro Tahliyesi
2994d892	Yarış sırasında ekranda gördüğün bilgileri kendine göre ayarla. Duraklatma menüsünden Oyuncu ayarlarına girerek Göstergeleri, Tur Bilgisini ya da anlık Yarış Sırasını kapatabilirsin.
29f25a81	PENÇE
29f4bf03	Sn.
29f66022	Racing Hart
2a004e10	^2. Aşamada 8. yarışını kazandığın için dergi kapağına çıktın!
2a1dc425	%s yeniden çevrimiçi ve Need for Speed™ Underground 2 oynuyor.  Davetin yeniden gönderildi.
2a2a4ab3	Yol Yansıma Detayı
2a2c6aef	Vinil rengi bu olsun mu?
2a5b5f42	Devam etmek için kumandanı %d numaralı kumanda girişine yeniden tak.
2a5f78f6	Kumandayı %d numaralı kumanda girişine yeniden tak.
2a690550	XIMIAN ÇİFT
2a795cd8	GPS'i Kapat
2a90c4d7	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ İmleci Sola / Sağa Taşı^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$ Sil^$JOY_EVENT_FENG_RTRIGGER$ $ICON_SPACER$ BÜYÜK HARF^$JOY_EVENT_FENG_LTRIGGER$ $ICON_SPACER$ Özel Karakterler^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön
2a9ba6f9	%s adlı profili^kaydetmek istediğinden emin misin?
2ab10d61	DVD Para Ödülü
2ac15670	Kaputu açtığında ekibin ağzı açık kalsın: herhangi bir Bayview Aksesuar Atölyesinde stoklara giren yeni motor neonu renklerinden birini taktır.
2ac7d02d	Vinil Katmanı Seç
2aced725	Egzoz Uçları
2acffcf9	Para
2b3041cb	Mayıs
2b360c2b	Dostum, benim adamın atölyesinde araban için özel bir parça var. Adamım onu başka bir enayiye kaptırmadan hemen oraya git kanka. Elden çıkmadan önce %s süren var.
2b5abcf4	Çıkartma Yok
2b7c9d3d	TİP 1 TÜM NOZULLAR
2b950c36	Bagaj kapağını karbon fibere dönüştürmek istiyor musun?
2bab7212	Şehir haritasında gizle
2bba4b21	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  İstatistik Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$  Oyun Modu Sıralama Tablosunu Değiştir^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
2bbcca6b	Ayarlar sıfırlansın mı?
2bdb07de	NITROUS EXPRESS - 10 LB TÜP
2bf01869	İmza Parası:
2bf54daf	Farlar
2c119933	Reddet
2c20c5de	Sesli Sohbete Davet Et
2c248265	Grup mesajlarını oku
2c30c3d7	Bayview Grafik Atölyesinin Jackson Heights şubesine hoş geldin. ^Ek Boya kategorilerinin, çıkartma yerleşimlerinin ve yeni Vinillerin kilidi açıldı. ^Diğer Grafik Atölyelerinde açılan tüm parçalar burada da var.
2c710c4d	Sol Arka Çamurluk
2c8ec31d	%s adlı profili^silmek istediğinden emin misin?
2ca301e7	Orijinal kalmak enayilerin işi. Performans Atölyesinde kaputun altına birkaç beygir daha ekleyebilirsin. 9 kategoride parça al ve arabanın performansını baştan sona modifiye et.
2ca40d1f	Ödül:
2cbe2df1	AEROSTYLE ÇİFT
2ccba545	%d okunmamış mesaj
2cd70470	Kariyer Yükle
2ce7c43e	TİP 3 BORDO
2d167f11	Makinene en yeni cam filmlerini taktır, kimin geldiğini tahmin etmeye çalışsınlar. Yeni renkler şimdi tüm Aksesuar Atölyelerinde.
2d647339	Yeni sorunlar, sunucu kesintileri vb. hakkında^ÇEVRİMİÇİ haberler burada...
2d71d011	Sürüş Kontrolleri
2d8b34cc	Vay be, sürmeyi biliyorsun. %s içinde Jimmy'nin atölyesine yetişirsen, arabanla sokakları yakıp geçirecek bir parça seni bekliyor.
2d9a9333	Dergi Kapağı Çekimi
2dab24e4	Azami G Kuvveti:
2dc3a547	Çaylak
2dc3a548	Acemi
2dc3a549	Orta Seviye
2dc3a54a	Yetenekli
2dc3a54b	Deneyimli
2dc3a54c	Kıdemli
2dc3a54d	Uzman
2dc3a54e	Profesyonel
2dc3a54f	Efsanevi
2dc3a550	Elit
2dfcde7c	Maxi Tuning
2e01a0ba	Modifiyeli Araba 1
2e01a0bb	Modifiyeli Araba 2
2e10703a	^3 Drag Yarışı
2e2ba736	Outrun düellosunda amaç rakibinin önüne geçmek... ve sonra onu ekmek! Öndeyken istediğin rotayı seçmekte serbestsin. Gerideysen yarışın kontrolünü ele almak için lidere yetişip onu geçmen gerekir.
2e37e28b	Özel Etkinlik
2e3a9cf9	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Devam^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
2e782407	ŞARTLAR:^7 URL galibiyeti, sponsorun belirleyeceği 3 yarışta galibiyet ve sürücünün seçeceği 29 ek galibiyetle sözleşme tamamlanır.^^TANITIM ŞARTLARI:^3 DVD kapağında yer alacak bir araba oluştur.^^BONUS:^Bayview'daki herhangi bir galeriden bedava araba.
2e8d7e4b	Bulunan Gizli Atölyeler
2ea43025	Son dişli oranı tüm vitesleri birlikte etkiler: vitesleri kısaltarak daha iyi hızlanma, uzatarak daha yüksek azami hız elde edersin. Hızlanma ile azami hız arasında seçim yapmak için sürgüyü ayarla.
2eb0b024	SIÇRAMA 1
2eb0b025	SIÇRAMA 2
2eb0b026	SIÇRAMA 3
2eb94b88	Bu hesap oluşturulurken bir hata oluştu.
2ee4f90f	Outrun'a Giriş
2eeeaa14	Galeriye Git
2ef02ddc	Gösterişli sürüş puan kazandırır, bu puanlar da N2O'ya dönüşür. Göstergenin taşma bölümünü dolduracak kadar puan topla, arabanın N2O gücünü ikiye katla.
2efadf61	Bu parçaları takabilmek için önce geniş kasa kitini sökmelisin.
2f0cfb04	Aranıyor...
2f135692	BLINDSIDE ÇİFT
2f22f860	Mitsubishi
2f562143	Hey kasaba çocuğu, artık büyük şehirdesin. Umarım sende o iş vardır, çünkü burada kimse sana acımaz. Hala büyük abilerle oynamak istiyor musun?
2f562144	Pekala, kimler gelmiş bakalım? Ciddi bir Drag yarışında mangırını teslim etmeye hazır bir enayi daha. Aferin oğlum, buyur gel, sıraya geç.
2f562145	D-R-A-G! Tüm hızıyla geliyor! Dayak yemeye hazır bütün tırsaklar çizgiye buyursun. Bütün gece bekleyecek değiliz!
2f6ba7b2	Yeni özel göstergelerimizden birini taktırarak arabana en iddialı modifiyeyi yap. Yeni modeller kapış kapış gidiyor, seninkini bu gece herhangi bir Bayview Aksesuar Atölyesinden al.
2f735833	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
2f8344ea	Sınırsız
2fcbcaa8	NITROUS EXPRESS - 20 LB TÜP
2fe05d6d	Hızlıydın! Önümüzdeki %s içinde arabanı benim adam Kaiser'in atölyesine getir, sana çılgın bir parça ayarlasın.
2fffded0	Egzoz Ucu Boyası
30003d27	Şanzıman:
300b420b	Enkei
301bc2e3	SAMANTHA: Hey, parti coştu, herkes partinin yıldızını bekliyor! Çabuk gelsen iyi olur! ... Alo? Alo?!
30372bbf	Şehir Merkezi
303bb325	Serbest Dolaşım
3050c316	NITROUS EXPRESS - 5 LB TÜP
305ca8b3	Performans Atölyesi İpucu
306024ac	GPS Kullanımı
306c1ccd	WRX STi
30786eb7	Konig
308db484	Engelle
309b91ba	Şu an bir LAN sunucusu çalıştırıyorsun.  LAN modundan çıkarsan^sunucundaki tüm kullanıcıların bağlantısı kesilecek.^Devam edilsin mi?
30afbcb0	SÖZLEŞME ŞARTLARI:^Sürücü şu yarışları kazanmalı: 5 URL yarışı, sürücünün seçeceği 19 yarış, sponsorun seçeceği 3 yarış.^^EK ŞARTLAR:^2 DVD kapağında yer alacak bir araba hazırla.^^BONUS:^Bayview'daki herhangi bir galeriden ücretsiz araba.
30b938be	Oasis
30c2b7f4	ABD
30c3e6ac	ELİT SEVİYEYE ULAŞTIN
30cbdcb6	Sunucudan sonuçlar bekleniyor
30da61e1	Street X
30eb8f53	Demodan çıkılsın mı?
30ed2368	Ana menüye çıkılsın mı?
30f7037f	Bu düzendeki tüm çıkartmaları kaldırmak istiyor musun?
310bf423	Orijinal
3112bfef	BACKDRAFT OFSET
31139b65	Rota bulunamadı
313f8cc5	Başlangıç geri sayımı bilinmeyen bir nedenle başlatılamadı.
31687f33	WINDTUNNEL ÇİFT
3175f2b0	Bagaj kapağını karbon fibere dönüştürme seçeneğini satın almak istiyor musun?
3192f5d1	%s arabanı ^bu orijinal %s ile takas etmek istiyor musun?^Yoksa diğer arabalarından birini mi seçmek istersin?
3194b26f	Bayview Aksesuar Atölyesi
31963938	BİRLEŞİK KRALLIK A
31963939	BİRLEŞİK KRALLIK B
319a6272	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
31ab5422	Stadyum
31c0d053	Yeni stop tasarımlarımızdan biriyle modifiyeli görünümünü tamamla. En yeni modeller Bayview Kaporta Atölyelerinde. Seninkini hemen al.
31d451c9	İnternet servis sağlayıcınla (İSS) bağlantı kurulamıyor.  Ağ adaptörünü, bağlantını ve/veya Ağ Yapılandırması dosyanı kontrol edip tekrar dene.
31e50d09	Drag yarışlarında şerit değiştirmek için gitmek istediğin yönün tuşuna kısaca basman yeterli; araban yan şeride geçer. Önündeki trafiği ve engelleri gözleyerek şerit değişimlerini önceden planla, çarpışmalardan kaçın.
31e52c85	Arabanın performansını Performans Ayarı / Dyno bölümünde ayarla. Her yarış modu için özel ayarlar kaydet; bunlar her yarışa girdiğinde otomatik olarak yüklenir. Farklı ayar kombinasyonları dene, yarışta üstünlüğü ele geçir.
31edaecb	Şehrin dört bir yanında bilgi simgeleri var. Birini etkinleştirdiğinde oyunla ilgili faydalı ipuçları içeren bir SMS alırsın, üstüne yükseltmelere harcaman için biraz da cep harçlığı kazanırsın.
31fbc167	Bu vinili tasarımına eklemek istiyor musun?
31fff078	^3 Drift Yarışı
320964f9	Demo Zorluğu
321149a0	Doğu Beacon Hill'deki Galeriyi ara. Suyun hemen kuzeyinde, yolun biraz dışında. Turkuaz ışığı gözden kaçırma.
32222962	TİP 3 KIRMIZI & FISTIK YEŞİLİ
32675d4f	$JOY_EVENT_FENG_PAD_LEFT$
3291a14c	$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
3298ccdb	Para:
3298de8d	En İyi:
32a2cd8e	Süre:
32bb1206	Escalade
32cd4820	Xbox Live'a giriş yaparsan kaydedilmemiş değişiklikler kaybolabilir.  Devam etmek istediğine emin misin?
331f4f58	Bu oyuna artık katılınamaz.
332c0b6f	Şifreyi Gir
332e1d34	Bu parça %d karşılığında satılsın mı?
333f7902	Arkadaş İsteği Gönder
336b7fae	ANLAŞMA ŞARTLARI:^Sürücü şunları kazanmayı kabul eder: 7 URL yarışı, sponsorun seçeceği 3 yarış, sürücünün seçeceği 29 yarış.^^SOKAK İTİBARI MADDESİ:^3 DVD kapağında yer alacak bir araba yap.^^BONUS:^Sponsor 1 araba hediye eder.
3384a679	Rakipler
3389f685	d/dk (x1000)
33ac30ff	^3. Aşamada 11. yarışını kazandığın için dergi kapağına çıktın!
33c11663	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Boya Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Boya Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Rengi Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
33c42e03	Şehir haritasına dönülsün mü?
33ec155c	Selam dostum, güzel yarıştı. Bu işi biliyorsun. Arabanı bambaşka gösterecek özel görsel parçalar ayarlayabilecek bir arkadaşım var. İlgileniyorsan haritandaki yıldıza git, seni arayıp yerini söylerim.
340a6ff1	Şanzıman
3415f8f4	Tüm Bayview Kaporta Atölyelerine yeni gelen spoilerlardan biriyle arabana hem yere basma kuvveti hem de stil kat. Stoklar tükenmeden seninkini kap.
3438b351	Davet Gönder
3454a3b0	Sesli Sohbet Bağlantısı Kesildi
346ca432	Sunucu bu personayı reddetti. Başka bir ad seçip tekrar dene.
34a89700	Rachel
34c1d90f	Kaputun altına gir, arabalarının 20'yi aşkın performans ayarını tek tek elden geçir. Drift pistlerinde rahat kaymak için süspansiyonu yumuşat ya da Drag yarışlarında kalkışta ekstra hızlanma için vites oranlarını kısalt. Her araba için ayarlarını yapıp kaydet, her yarış türünde en yüksek performansı yakala.
34d83742	Girdiğin ebeveyn e-posta adresi geçersiz.
34e6adba	Sponsor
34e8c5b8	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Yuva Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Parçayı Tak^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
3503ba7a	Sesli Sohbet Daveti
35102edf	Drag
35457863	Render Hata Ayıklama
356457be	ESRB UYARISI: ÇEVRİMİÇİ OYUN SIRASINDA OYUN DENEYİMİ DEĞİŞEBİLİR
358cdbd4	Titreşim:
358cdcfd	Geri Bildirim:
359a9188	Bu atölyede her şey görünüşle ilgili. Makas kapılar, hidrolik,^ses sistemi bileşenleri ve spinner gibi arabanı gerçekten^öne çıkaracak parçaların bulunduğu yepyeni^kategoriler seni bekliyor.
35aaa91c	Oyuncuyu At
35b4e6b3	Performans Atölyesi
35b9f571	Arkaya Bak
35ccc129	DVD Kapağı %d  %$.1f Yıldızlı Araba
35e23bf3	HİDROLİK YOK
35ec190e	%s oyundan atılamadı.
362f9974	Ön ve Arka Viraj Demirleri
36422263	İstemci Ayarları
365dc8e2	0-100 KM/SA:
367161f5	Bu modifiyeli arabayı silmek istiyor musun?
36a462c7	Gamertag'ini değiştirmen gerekiyor!
36bec45f	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
36c30e70	Güçlü
36c5fae4	Drift Lideri
36d56bf1	Arabanı test pistine çıkar ve performans ayarlarını yolda, gerçek zamanlı olarak değiştir.
36da152d	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
36e577c2	Bu kaputu takarsan kaputtaki tüm çıkartmalar^kaldırılacak. Parçayı şimdi takmak istiyor musun?
370269e8	Bu adla sonuç bulunamadı!
3706f93d	Maalesef bu viniller karbon fiber kaputlarla kullanılamıyor.
3708c383	Ayarla
3712cc32	Azami Hız
371b340f	Kayıt formunda^13 ile 17 yaş arasında olduğunu belirttin.^^EA, bir EA üyeliği oluşturduğunu ebeveynine veya vasine bildirir.^^Aşağıya ebeveyninin veya vasinin geçerli e-posta adresini gir.
373dad1a	Grafik Atölyesi
375b62f1	Ekran Y
37a77b51	Burning Wheels DVD Kapağı
37b7246a	Dyno Sonuçları
37b975dc	En Uzun Powerslide
37bccab3	Sana 14 saniyelik adam diyorlarmış, çünkü o hurdanın 1. vitesten çıkması o kadar sürüyormuş. Burada işler öyle yürümez; sen ne olduğunu anlayana kadar biz bitiş çizgisinde partiye başlamış oluruz.
37bccab4	Hey köylü. Büyük şehre hoş geldin. Bizimle oynamak istiyorsan hakkını vereceksin. Burada Drag işini büyük oynarız. Gözünü kırparsan bizi kaçırırsın. Memlekette yarıştığın o kağnılardan biriyle kapışmıyorsun artık.
37bccab5	Bizimle Drag yapmak istiyorsan yanında biraz beygir getirsen iyi olur. Bitiş çizgisine varınca bir güneş saati kurarım ki araba dediğin o hurdanın süresini doğru ölçebilelim.
37bccab6	Kanka, bu yarışa girmek için biraz yürek bir de biraz mangır yeter. Mangırın var, görüyorum; gerisi için sözüne güveniyorum.
37bccab7	Ne haber köylü? Traktörünü başlangıç çizgisine çek, cebinden biraz yeşillik çıkar da şu yarışı başlatalım. Hadi dostum, vakit geçiyor.
37bccab8	Yuhuuu, Ali Baba çiftliğinden kalkmış gelmiş! Bu yarışa girecek kadar parayı arka bahçeden kazıp çıkarabildin mi bari?
37bccab9	Ne haber oğlum? Gel bakalım, bizimle Drag yapabileceğini sanan enayilere her zaman yer var. Ben paramı gıcır gıcır, büyük banknotlarla severim. Hazır tut onları.
37bccaba	O arabayla bizi yenebileceğini sanıyorsan kafayı yemişsin. Ama enayinin parası para değil diyen mi var? Hadi oğlum, gel sıraya gir de sopanı ye.
37bccabb	Hey kanka! Ortalık KIZIŞACAK! O arabayla iyi bir kalkış yapabileceğine inanıyorsan başlangıç çizgisine gel.
37d13ae5	Kaydet
37d15f43	SAMANTHA: Bence sokaklarda seni yenebilecek kimse yok.
37d34f78	Serbestçe Gezilen Şehir
37e740e0	İkincil
37fd17ee	ANLAŞMA KOŞULLARI:^7 URL yarışı, sponsorun seçeceği 3 yarış ve sürücünün seçeceği 29 ek yarış kazanılınca sözleşme tamamlanır.^^MEDYA ŞARTLARI:^3 DVD kapağında yer alacak bir araba yap.^^BONUS:^Bayview galerisinden bedava araba.
38150112	Süspansiyon
381b2a32	Yarış Bitti. Süre Doldu
381fe1e9	Görüntü Ayarlarını Özelleştir
382a9e49	^^3 yıldızlı bir araba yaptığın için DVD kapağına çıktın!
38763b90	ŞERİT 1
38763b91	ŞERİT 2
38763b92	ŞERİT 3
38794102	Bayview Grafik Atölyesinin South Market şubesine hoş geldin.
3888a7ef	Ara
3895d8e7	Dereceli Oyun
38d548d2	Tork ( %s )
38f21dd9	Swiss Tuner Magazine
39052317	Önceki Süre:
390e7e99	TEK RENK
391ef6ae	Hesap bilgilerin kısa süre içinde e-postayla gönderilecek.
392cdcb0	$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
393f2202	CLARION LCD - 7 İNÇ
3949abee	Bu parça, sahip olduğundan daha kötü.^Yine de bu parçayı satın alıp takmak istiyor musun?
395a51be	Performans Atölyelerinden biri El Norte bölgesinde. Otopark girişinin önündeki mavi ışığı ara.
395ab9e2	SMS Kullanımı
39751bdf	Yenile
3988faef	Ön Lastik Tutuşu
3991dd49	Sabit Disk
39b57034	Bu persona oluşturulurken bir hata oluştu.
39c79aa2	Grup Bayrağı
39df9562	%s ile anlaşmak ister misin?
39e4e946	Eğitim İpucu
39e6725e	Katalizör Sonrası Egzoz Sistemi
39ef3a6c	Ekran Boyutu
3a10a7c2	Drift
3a341ce8	Aksesuar Atölyesi
3a36f0a8	Filtrele
3a3c63fc	Yarış Tipi Fren Balataları
3a5b7b29	Dyno / Performans Ayarından Çıkılsın mı?
3a608bf3	Selam dostum. Az önce haber geldi, Jackson Heights bölgesi sonunda açılmış. Hemen o tarafa çık. Tepelerdeki yarışlar tam olay!
3a64a189	Kariyer Durumu ve İlerleme
3a6eeeec	Ekstrem Performans Lastikleri
3a89a38b	ALPINE
3a9ad81e	Burnout® 3: Takedown™ demosunu başlatmayı seçtin. Mevcut oyunundaki kaydedilmemiş tüm değişiklikler kaybolacak. Demoyu başlatmak istediğine emin misin?
3a9ccf4e	Zemin Rengini Seç
3ac39906	Sağ
3af66b96	Turbo
3b10cb47	Arabaya Harcanan:
3b33c4fc	Bu EA Online hesabı kilitli ve kullanılamaz.  EA Müşteri Desteği ile iletişime geç.
3b3bfaf0	Motor Detayları
3b4a1ecb	En İyi Tur:
3b550c71	Mesajı Oku
3b67b393	Delikli ve Kanallı Diskler
3b7b9567	En İyi Tur
3b7e6ad9	PARLAK KIRMIZI
3b959dba	Harika sürüş! Fark ettiysen rakibini yendiğin için para kazandın. Outrun düellolarını kazanmaya devam et, yoksa o para da uçar gider.
3bc6066d	Çevrimiçi Pist Seç
3bfe592c	Kişisel İstatistikler
3bff6152	Otoyoldan büyük Stadyumu bul; Aksesuar Atölyelerinden birine yaklaşmış olacaksın. Stadyum, City Core'un batı kesiminde.
3c149013	EA Girişi
3c1f9233	Motor
3c4cf1c0	Devre
3c4d1148	Mesaj Kutusuna Git
3c51d18b	Arabanı değiştirmek mi istiyorsun?
3c78fc5b	Sadece aynı seviyedeki oyunlar
3cf13157	Yarış bilgisi
3d0447aa	Kullan: %s
3d263938	ORİJİNAL CAM FİLMİ
3d358519	Grafik Atölyesi
3d456689	BREMBO
3d5e37b9	13-17 yaş arasında olduğunu belirttiğin için, EA GAMES™ Online Hizmeti'ne kaydolduğunu ebeveynine veya vasine bildirmek politikamız gereğidir.  Kaydına devam etmek için 18 yaşından büyük ebeveyninin veya vasinin güncel bir e-posta adresini gir.  Girdiğin adrese, ebeveynine veya vasine EA GAMES™ Online Hizmeti'ne kaydolduğunu bildiren bir e-posta göndereceğiz.
3d698353	Skyline
3d6a70e6	Sponsorlu Drag
3db3758c	Yeni bir araba lazımsa adres belli: galeri
3dc6a111	Farlar
3de28f60	3. ZORUNLU YARIŞLAR
3de4eff0	Kullanıcı Adı Oluştur
3de94db2	$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
3e0de37b	6 AY ÖNCE...
3e10eab2	Yalnızca EA GAMES™ Kullanım Şartları ile ilgili bildirimleri kabul ediyoruz.  Bu özelliği sadece gerçek şikayetler için kullan.  Kötüye kullanım, hesabına yaptırım uygulanmasına yol açabilir.
3e56ded3	Oyuna Katıl
3e7d4ca8	Stuff Magazine
3e867905	Kaizer
3e9431dc	Kapıları Aç/Kapat
3eb318ce	Vites Yükselt
3ec118dd	Underground Speed Zone
3ef1da8c	Cam filmi
3efe5317	Haberler indirilemedi
3f0bbdff	MOR
3f0dce03	Sponsor Seç
3f1409cc	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$  Personayı Sil^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
3f1524d6	ANLAŞMA KOŞULLARI:^9 URL yarışı, sponsorun seçeceği 3 yarış ve sürücünün seçeceği 34 ek yarış kazanılınca sözleşme tamamlanır.^^TANITIM ŞARTLARI:^4 DVD kapağında yer alacak bir araba yap.^^BONUS:^Bayview galerisinden bedava araba.
3f4b9e43	Bagaj Yuvası %d
3f6da129	Vahşi Seti
3f7c1b01	Aynı adlı profillerin üzerine yazılacak.^Devam etmek istiyor musun?
3f920248	EA sunucusuyla bağlantın koptu.  Ana menüye döneceksin.
3f9932fd	NOS - 10 LB TÜP
3fadd34c	Impreza
3fcd641c	Need for Speed™ Underground 2 ile modifiye kültürünün^yaşayan, nefes alan dünyasını keşfet.^Birbirine bağlı beş farklı^semtten oluşan devasa,^serbestçe gezilebilen bir şehirde^geçen Need for Speed^Underground 2, sokakların menü olduğu^sürükleyici bir oyun dünyası sunuyor.
3fe6fab9	Bu demo yalnızca tanıtım amaçlıdır ve^hiç kimse tarafından satılamaz, kiralanamaz veya çoğaltılamaz.^^Bu demonun izinsiz her türlü kullanımı^yürürlükteki yasalarca yasaktır.
40152751	Kazanılan İtibar Puanı:
402a2354	Karbon Aynalar, Spoilerlar, Tavan Kepçeleri
403eccc7	TİP 2 FISTIK YEŞİLİ
40813f63	Ayardan çıkmak istediğine emin misin?
40889e10	Müziği kendine göre ayarlamak için Ayarlar menüsündeki EA GAMES™ TRAX bölümüne gir. Her şarkının nerede ve ne zaman çalacağını sen seçersin. Şarkıları dinle, sıralarını değiştir ve kusursuz çalma listeni oluştur.
409607e2	Gaz
40a5ef5d	TİP 2 BORDO
40c7f697	Kaporta Atölyesi
40c91ba7	Drag
40d7a271	Düz hatta frenleme
40faf14b	Bu Ayın Sıralama Tablosu
4100ada8	Sil
410258c3	Profili Kaydet
412bd420	Lexani
414b91db	V1 SAĞ TEKERLEK HARİÇ TÜMÜ
414f19d7	Kaput
418e681d	Menü Müziği Sesi
419ca63a	Kamera
41afaf4a	Yeni bir Xbox Live mesajın var. Şimdi okumak ister misin?
41baf149	Bağlantıyı Kes
41ccbe09	Bayview Kaporta Atölyesinin Hotel Plaza şubesine hoş geldin.
41e233f4	BLARG YARDIM
41effb1b	Kapak Çekimi
4204d527	Görüntü
4205bc22	Kasım
420aa71a	Toplam Tutar:
4244447e	Integra
424d7a17	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
42501aa0	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
42501ff8	$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
427ba061	Ebeveyn E-posta Adresi:
4287206f	Takılı Değil
42a81c57	Yüksek Performanslı Debriyaj
42e57a0d	Mevcut Değil
42fc6bad	Işıklar
43003b5b	LAN sunucuları aranıyor ...
430c6cdd	Ağ koşulları bu oyunu etkileyebilir.
4339d9f2	Yorumlar:
4342d430	Beşinci oldun!
43512519	GPS'i Aç
436c91d4	Dyno Testi
437c6a36	Downhill Drift
437e4111	Motor Neonu
438aeaf1	Yaş Doğrulama
438da7c0	.
43a05263	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Parçayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
43aeef78	%$3.1f %s^@%$d d/dk
43d1d33f	$JOY_EVENT_FENG_SELECT$ İptal
43eeb333	Görsel Yükseltme Ödülü:
4402f357	Çelik Örgülü Fren Hortumları
44167cbc	HAVADA KALMA
4421e6aa	Bayview Kaporta Atölyesinin Fort Union şubesine hoş geldin.
442b3936	Dereceli bir oyuna girdiğinde, bu oyun modu için uygun çevrimiçi dereceli arabaya otomatik olarak geçilir.  Bu oyuna girmek istediğine emin misin?
44345f7f	Yeni hesap oluşturuluyor...
443fab5a	Üçüncü oldun!
4477baf7	Her galerinin stoku farklıdır; istediğin modeli bulmak için biraz keşfe çıkman gerekebilir. Nissan, Mazda, Toyota, Subaru, Mitsubishi, Ford ve daha nicesi dahil, modifiye dünyasının en tanınmış üreticilerinden 30'dan fazla model seni bekliyor.
4477baf8	İşte Underground 2'nin tam sürümünde yaratabileceğin^modifiyeli canavarlardan 2 örnek.
4477baf9	Her galerinin stoku farklıdır; istediğin modeli bulmak için biraz keşfe çıkman gerekebilir. Nissan, Mazda, Toyota, Subaru, Mitsubishi, Ford ve daha nicesi dahil, modifiye dünyasının en tanınmış üreticilerinden 30'dan fazla model seni bekliyor.^^İşte Underground 2'nin tam sürümünde yaratabileceğin modifiyeli canavarlardan birkaç örnek.
447cac44	YOL TUTUŞ
4492955d	Lobi sunucusuna bağlanmayı iptal edersen Xbox Live oturumun kapanacak ve ana menüye döneceksin.  Bunu yapmak istediğine emin misin?
449a9dd9	Çıkartmalardaki değişiklikleri iptal etmek istiyor musun?
44a217cd	Megalow Parts
44abac78	Bağlantı koptu: %s
44b7167f	Bu parçayı satın almak istiyor musun?
44d0eb0e	ZEPHYR OFSET
451879e2	Araba Seç
452383e7	Engeli Kaldır
452606ca	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Araba Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçili Arabayla Takas Et^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
453890e1	Garaja gidilsin mi?
45532746	EA ürünleri, haberleri ve etkinlikleri hakkında bilgi almak ister misin?
455c3f80	Dyno'ya dönülsün mü?
456409ad	BİLEŞEN YOK
459ea230	Piste Bak
459ee68b	Yüksek Isı
45a6a9ce	Başlamak için START'a bas
46214c34	WINDTUNNEL OFSET
462a24de	MAVİ NABIZ
462d17b7	Bu kişiyi EA Messenger'dan çıkarmak istediğine emin misin?  Bu kişiden gelen okunmamış tüm mesajlar kaybolacak.
46527fd0	Bir personayı silmek üzeresin. Bu oyuncuya ait tüm istatistikleri ve başarıları kaybedeceksin.  Bu işlem geri alınamaz. Bu personayı silmek istediğine emin misin?
46573b3f	.
468770af	YARIŞ TÜRÜ:  %s
46905b81	Yağmur yağarken arabanın çekişi biraz azalır, bu da yol tutuşunu etkiler. Virajlara yüksek hızla girerken dikkatli ol, araban normalden fazla kayabilir.
46b41bb8	Nitro, arabana kısa süreli bir güç patlaması sağlar. Nitronu daha güçlü ya da daha uzun süreli yapmak için sürgüyü ayarla. Kısa yarışlarda güçlü, uzun yarışlarda uzun süreli nitroyu dene.
46c41a7c	Grafik Atölyesi
46e61779	Garaja Gir
4706fcce	Tavan Kepçeleri
4754130e	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ İptal^
47597606	Hızlı Yarış Oyun Ayarları
47abe874	ANLAŞMA KOŞULLARI:^5 URL yarışı, sponsorun seçeceği 3 yarış ve sürücünün seçeceği 19 ek yarış kazanılınca sözleşme tamamlanır.^^TANITIM ŞARTLARI:^2 DVD kapağında yer alacak bir araba yap.^^BONUS:^Bayview galerisinden bedava araba.
47b276ef	Yarış Modu Seç
47c515d5	Araba bilgilerin gönderilirken bir sorun oluştu.  Tekrar denemek ister misin?
47cfbedd	Kanka! Belediye ekipleri paydos etti; Batı Coal Harbor yolları açık ve yarışa hazır. Duyduğuma göre sürücüler şimdiden toplanmaya başlamış. Hemen git, bir bak.
47d572a3	Oyunun müziklerini ayarlamak için önce Ayarlar'ı, sonra EA GAMES™ TRAX bölümünü seç. Şarkıları önizleyebilir, kapatabilir ya da sıralarını değiştirebilirsin.
47d7108b	Performans Ayarı
480e0f39	Araba Performans Kısıtlaması:
48157d57	Konu: Özel Parçalar
4815fdbd	Haberler
48494e83	Tur
485d94a3	Grafik Atölyelerinden biri South Market'teki kumarhanelerin hemen kuzeyinde. Seni girişe götürecek kırmızı ışığı takip et.
48665617	Megalow Parts Mağazası
48b8729b	Denge Kontrolünü kapatarak arabanın yol tutuşunu değiştir. Kapattığında araban virajlarda kayarak dönebilir. Denge Kontrolü ayarını değiştirmek için Duraklatma menüsünde önce Ayarlar'ı, sonra Oyuncu'yu seç.
48c05672	Çıkartmalar
48d82996	Gamertag'ler yükleniyor
48e220da	TİP 3 SAĞ KAPUT NOZULU
48ef0bb1	GREDDY
48facf43	Galibiyet Ödülü:
4904cdde	Yeni personan %d ile %d karakter arasında olmalı.^Farklı bir ad dene.
490a722d	Diskalifiye
490c1cb0	TİP 3 İKİ SAĞ NOZUL
4922b6a0	Garaj
4940a0e3	Kazanılan Sponsor Yarışları:
49652aff	TİP 1 SOL ÜST VE SAĞ ALT NOZULLAR
496817d5	3B
49d0555b	Özel Performans Yükseltmesi
49e33645	Mangırın ve yüreğin varsa bizimle yarışabilirsin herhalde. Yalnız sana bir şey sorayım: O arabayı yürüttüğün sirk palyaçosu kayıp olduğunu fark etti mi?
49e33646	Bakınmayı bırak da öne çık. Sprint yapıyoruz. Mangırın varsa rotayı alırsın. Kararını ver.
49e33647	Hey oğlum, ya gir ya çık! Sürücüler Sprint için hazırlanıyor ve etrafta aylak aylak dolaşan meraklı istemiyorlar. Mangırın varsa sıradaki seride yerin hazır. Ciddi olduğunu anladığımız an parkur haritası SMS'le gelir.
49e33648	Bak şimdi, bir Sprint başlamak üzere. Paran varsa katılmaya hala vaktin var. Her zamanki gibi, parayı koyduğun an rota SMS'le gelir.
49e33649	Hey havalı! Büyük abilerle Sprint atmak istiyor musun, istemiyor musun? Tek ihtiyacın biraz para. Eee, ne yapıyoruz?
49e3364a	Duyduk duymadık demeyin! Bunu okuyan herkese duyurulur: SPRINT! Usulü bilirsiniz. Parayı yatıran rotayı SMS'le alır; oyalanmayın, katılın!
49fd5dcb	ÇEYREK MİL SÜRESİ:
4a0c932d	Yarışma
4a1341b3	Yarışa/Atölyeye Gir
4a32e382	Race Breaker
4a3b8a4e	Bağlantı
4a4d7dfb	Direksiyon Yardımı:
4a5ea160	Performans Atölyesi
4a69f7aa	Girilen EA hesap adı geçersiz.
4a6cd391	V2 SAĞ KAPUT HARİÇ TÜMÜ
4a8764a8	Bağlantı koptu
4a8a8a69	PLASMAGLOW
4aa403de	Alev Seti
4ab6a4f8	Lobi
4ac28a7a	Silindir Kapağı Port ve Polisaj
4ac50bcf	Araba Model Ayrıntısı
4ad41e75	Seçili araban bu oyunda kullanılamaz.
4ad62ee1	Ulaşılan Azami Hız
4af2e79e	Profil
4b118def	Egzoz Uçları
4b14af4e	Arkadaş isteği iptal ediliyor: %s ...
4b27846f	Düz giderken en sert frenlemeyi viraja girmeden önce yap. Virajın tepe noktasını geçince gaza bas ve virajdan hızlanarak çık.
4b42fbed	Hızlı Eşleşme
4b5c9721	Bu oyun oturumu artık mevcut değil.
4b5de3e9	Konu: %s
4ba0d22f	Pert oldun!
4be31125	SÜRE BONUSU
4c22cee8	Buraya sadece sokakların en iyi yarışçıları davet edilir, yani itiraf edeyim, etkilendim. Trafik yok, dikkat dağıtan bir şey yok; sadece sen ve sana toz yutturmak isteyen beş adam. Burada her kazandığında camiada adın biraz daha duyulur.
4c22cee9	Sokaktaki söylentiye göre buradaki son galibiyetin şans eseriymiş. Henüz kimse seni ciddiye almıyor. Gel şu soytarılara kimin patron olduğunu gösterelim, sonra aynasızlar uyanmadan buradan toz olalım.
4c22ceea	Bu gece kazanırsan sponsorlar seni gerçekten fark etmeye başlar. Şimdiye kadar pek de zorlu rakiplerle karşılaşmadın ama bunu kazanırsan yeniden davet edilme şansın artar. Sakın batırma.
4c22ceeb	Burada rekabet çetin. Sokakta kazanmak başka, gerçek bir pistte kazanmak bambaşka. URL yarışları, işini bilenle atıp tutanı birbirinden ayırır.
4c22ceec	URL yarışları bomba gibi. Bu pistlerde sadece en iyiler yarışmaya davet edilir, yetenek her şeydir. Biri yanlışlıkla bir ninenin aile arabasına takıldı diye gelen şans eseri galibiyetler yok burada.
4c22ceed	Dostum, bu yarışta gözünü dört açman lazım. URL, en iyilerin en iyisi ve bu adamlar resmen döktürüyor. Şehrin en iyi yarışçılarından bazılarıyla kapışacaksın, o yüzden sakın gevşeme.
4c22ceee	Kanka, bu gece pistte zorlu rakiplerle karşılaşacaksın. Bu adamların bazıları pek temiz oynamaz; etrafından dolaşmaktansa üstünden geçmeyi tercih ederler. İyi bir yarış çizgisi seç, tetikte ol, bitişi görürsün.
4c22ceef	Bu adamlar işi ciddiye alıyor. Düşünmeye vakit yok, sadece yap. Bu adamların virajlarda ve düzlüklerde çıkardığı işler inanılmaz, o yüzden hep önde kal. Kimse hala senden etkilenmiş değil, sonuna kadar bastırsan iyi olur.
4c22cef0	Kendini toparlasan iyi olur, yoksa bu tipler seni darmadağın eder. Bunlar en tepedekilerle yarışıyor, bu da senin aralarına sızma şansın. Caka satacak vakit yok; gazı kökle ve ne gerekiyorsa yap.
4c713b1e	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
4c8770be	Race Breaker
4c9186f4	ORİJİNAL KASA
4c938dc7	Elit Ol
4c94d290	ORİJİNAL
4c967cdc	Yarış Türü:
4ca36b89	Sıralı
4cd52237	%s davetini reddetti ve seni engelledi!
4cd775ac	Tam Ekran Kenar Yumuşatma
4cddbebb	Yağmur Damlaları
4cfd4d21	ALPINE 2 LCD - 7 İNÇ
4d156786	Zorluk
4d38dbda	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Neonu Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
4d451881	South Market
4d64646c	Drift yarışı
4d8e1223	Pist adı
4d90f415	Aynalar
4da10f66	EA hesap adının uzunluğu geçersiz.^Hesap adı %lu ile %lu karakter arasında olmalı.
4da8fb93	Arabanı yenisiyle takas etmek için galeriye gel. Sürekli yeni modeller geldiği için stok hep değişiyor, sık sık uğra.
4dbbc129	İkinciyle Aradaki Fark:
4dc0a646	Galeri
4dd097a7	%s engellendi.
4dd68286	ÜÇ RENK A
4dd68287	ÜÇ RENK B
4dd68288	ÜÇ RENK C
4de319cc	LAN Sunucu Seçimi
4deab931	Direksiyon Ayarları
4df1d794	Yükseltme atölyeleri Bayview'un dört bir yanına gizlenmiş. Seni gizli yerlere götürebilecek renkli sokak lambalarına dikkat et. Bayview'un her yeni bölgesinde yeni atölyelerin ve ürünlerin kilidi açılır. Bulduğun atölyeler haritanda görünür.
4e0a36a0	En İyi Puan:
4e1c849e	Stage 2 Turbo Kiti
4e20c880	Kaydın Üzerine Yazılsın mı?
4e35a42a	Drag Yarışı Sonuçları:
4e4485fe	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ Renk Değiştir (Yukarı / Aşağı)^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Renk Değiştir (Sol / Sağ)^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Rengi Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
4e57d355	Ufuk Sisi
4e6ae825	Yırtık Seti
4e6c2af9	Marşpiyeller
4e706980	Yarış Sonrası İstatistikler
4e7212d8	Kurucuyla bağlantı koptuğu için yarış başlatılamıyor.
4e802849	Xbox Live Ana Menüsüne dönmek istediğine emin misin?  Bu oyun, istatistiklerine yenilgi ve bağlantı kopması olarak işlenecek.
4e84829f	Davet reddediliyor: %s ...
4e933e83	Çıkartmalar
4e98a8a8	KAMU SPOTU
4eae994f	Speed Demons 3 DVD Kapağı
4ec27bcd	Yeni Profil Oluştur
4f1c1f10	Tavan Kepçeleri
4f37b101	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Çıkartma Markasını Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Çıkartmayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
4f3e2298	Oyuncu Adlarını Göster
4f75e0ce	Eleme Tipi
4f8406c2	Persona bulunamadı.
4f876b6f	Kabul Et
4fafb114	Bu düzeni kurarsan daha önce takılan tüm ses^bileşenleri sökülecek. Bu bagaj ses sistemi düzenini^şimdi satın alıp kurmak istiyor musun?
4fc2c80e	Drag Yarışı
4ff12b33	%s markasını zaten Aşama %d sponsorun olarak seçtin.
501cdf6f	Mevcut işlem iptal edildi.
508380cf	Amortisörler — Amortisörler tümseklerin ilk darbesini emer ve lastiklerinin yerle temasını korur. Araban ciddi şekilde patinaj yapıyorsa, arka lastiklere daha fazla ağırlık aktarmak için arka amortisörleri yumuşatmayı dene.
50931fce	Kuru Sistem Nitro
509db271	Bu işlemi iptal ettin. Tekrar denemek ister misin?
50a003a3	İtfaiye
50cf1107	bağlanıyor...
50cfeae8	Araba verisi yükleniyor...
50eac1e3	Personayı Sil
50fef720	Gösterişli sürüş puan kazandırır, bu puanlar da N2O'ya dönüşür. Göstergenin taşma bölümünü dolduracak kadar puan topla, arabanın N2O gücünü ikiye katla.
51024a73	Sol
511cca10	Arabanın grafik tasarımı değişti.^Yeni grafik tasarımını yüklemek istiyor musun?
51493c59	Puan:
51735c50	Hız Birimi:
51865dd7	ALPINE AMFİ - 1000 WATT
518e7265	Xbox Live oturumun kapatıldı,^çünkü başka biri senin hesabınla^oturum açtı
51ba7190	3. DVD
51c3dc07	Tur Süresi
51c4207a	Yarış Türü
51df7921	Yarışlar
51e3f647	Satın almadan önce yüklemek için bir seçim yap!
51e8ec25	TİP 1 İKİ TEKERLEK NOZULU
520b5645	ALPINE AMFİ - 250 WATT
52260bdc	Arkadaş isteği iptal ediliyor...
5247a7b4	HUD'u Özelleştir
5278c50b	Menü
528ad4e3	Her araba on yıldız üzerinden görsel puan alır. Parçalar ne kadar havalıysa puanın o kadar yükselir.
528e03bf	Bozuk
5298ba46	Otoyol Drag yarışları
52a5398e	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$  Kategoriyi Varsayılana Sıfırla^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Geri^
52bceecc	Sesli Sohbet
52c8426b	Bayview Kaporta Atölyesi Doğu Beacon Hill şubesine hoş geldin. ^Spoiler ve Kaput seçeneklerinin kilidini açtın. ^Önceki Kaporta Atölyelerinde açılan tüm parçaları burada da bulabilirsin.
52d837f5	Azami Güç:
52ded91d	Ön Cam
53007e4f	En yeni özel göstergeler geldi. Tükenmeden tüm Bayview Aksesuar Atölyelerinde.
5326b031	Şanzıman
534e99e4	Arka Alçaltma
5352cd36	Kullanıcı Adı Gir
535a2751	Kapak Çekimi
53679b54	Temel frenleme
53691b86	Direksiyon Ayarlarına girmek için bir direksiyon seti takılı olmalı.
5369bbcf	Gösteriş Yap
536c452d	Geçersiz EA hesap adı.^Hesap adı rakamla başlayamaz.
5375e902	Filtre
53966afa	Kariyerinde kazandığın ödülleri görmek için garaja uğra. Mevcut sponsoruna, dergi kapaklarına ya da DVD kapaklarına göz at.
53b157fc	Yok
53c1fd2c	DRAG
53c6c89a	KARIŞIK
53ebbf48	TOMMY: İşte bu be! Burası yokuş aşağı drift, şakaya gelmez!
53f785ff	Oyunun Görüntü ayarlarını yapmayı unutma. Görüntü ayarlarına Ayarlar menüsünden ulaşabilirsin. Ekran kartından en iyi performansı alman için pek çok ayar seni bekliyor.
53f9fd5c	Sohbet
53fc5958	Tut
53fcafe5	Yardım
541389e5	İptal
542110c3	Dakika
543ca317	Grafik Atölyesi
545c5292	Çıkış Yap
54634577	4000
54634578	Dış Halka
54634579	Batı Otoyolu
5463457a	Doğu Otoyolu
5463457b	Jackpot
5463457c	Garibaldi Run
5463457d	Broad Street
54634599	Freemont
5463459a	Providencia
5463459b	Manzaralı Yol
5463459c	Tatil Köyü Turu
5463459d	Lower Eastside
546345ba	Belediye Binası
546345bb	Serpantin
546345bc	Sahil Boyu
546345bd	Park Drive
546345fc	Rıhtım
546345fd	Yük Vagonu
546345fe	Fabrika Bacası
546345ff	Bayview Concrete
54634600	Phoenix Steel
5463463e	Gözlemevi
5463463f	Bellavista
54634640	Bayview Summit
54634680	Palm Highway
54634681	Ambassador Ridge
54634682	University Hill
54634683	Marine & 25th
54634684	Grandview Station
54634685	Woodbine Park
54634686	12th & Arbutus
54634687	Bayview International
546346a0	Outrun
546346a1	Outrun
546346a2	Outrun
546346a3	Outrun
546346a4	Outrun
546346a5	Outrun
546346a6	Outrun
546346a7	Outrun
546346a8	Outrun
546346a9	Outrun
546349b9	Bayview Plaza
546349ba	Palomino & 16th
546349bb	Güney Kavşağı
546349bc	Üst Tribün
546349bd	Blackcomb Way
546349be	Cypress Bowl
546349bf	Maraton
546349fb	Rockridge Cross
546349fc	Palm Hill
546349fd	Wall Center
546349fe	Tampon Tampona
546349ff	Sentinel Hill
54634a00	Black Tusk
54634a01	2nd & Bellevue
54634a3d	Terminal & 2nd
54634a3e	Liman İdaresi
54634a3f	Atık Tesisi
54634a40	İç Hatlar Geliş
54634a41	Broadway & Granville
54634a7f	Hız Treni
54634a80	Eagleridge Estates
54634a81	The Chief
54634a82	Grouse Grind
54634aa3	Capilano Heights
54634aa4	Hillside Manor
54634aa5	Yüksek Gerilim
54634aa6	Hollyburn Ridge
54634aa7	Deniz Feneri
54634aa8	Şehir Işıkları
54634dfa	Bayview Bridge
54634dfb	4202
54634dfc	4203
54634e1b	Merkez Garı
54634e1c	Sahil Ekspresi
54634e1d	Manevra Sahası
54634e3c	Güney Pisti
54634e3d	Pist 15
54634e3e	Pist 9
5463523b	Otopark Drift 1
5463523c	Otopark Drift 2
5463523d	Otopark Drift 3
5463523e	Otopark Drift 4
5463523f	Otopark Drift 5
54635240	Otopark Drift 6
5463525c	Stadyum Drift 1
5463525d	Stadyum Drift 2
5463525e	Stadyum Drift 3
5463525f	Stadyum Drift 4
54635260	Stadyum Drift 5
5463567c	Tünel İnşaatı
5463567d	Kuzey Otoyolu
5463567e	Sanayi Otoyolu
5463567f	Havalimanı Otoyolu
54635efe	Sanayi Bölgesi Pisti 1
54635eff	Sanayi Bölgesi Pisti 2
54635f00	Sanayi Bölgesi Pisti 3
54635f01	Sanayi Bölgesi Pisti 4
54635f02	Otopark Pisti 1
54635f03	Otopark Pisti 2
54635f04	Otopark Pisti 3
54635f05	Otopark Pisti 4
5463633f	Bayview Speedway Pisti 1
54636340	Bayview Speedway Pisti 2
54636341	Bayview Speedway Pisti 3
54636342	Bayview Speedway Pisti 4
54636343	Bayview Speedway Pisti 5
54636360	Havalimanı Pisti 1
54636361	Havalimanı Pisti 2
54636362	Havalimanı Pisti 3
54636363	Havalimanı Pisti 4
54636364	Havalimanı Pisti 5
54636365	Havalimanı Pisti 6
548b4385	Değiştir
54974e6e	TİP 2 FUŞYA
5498e449	Bu persona zaten alınmış.^Farklı bir ad dene.
54a4d5be	TURKUAZ NABIZ
54b649f1	Performans Ayarı / Dyno pistine girmek istiyor musun?
54c4a91c	V2 SAĞ TEKERLEK HARİÇ TÜMÜ
54f93964	Batı Beacon Hill'deki Aksesuar Atölyesi, bulması en zor atölyelerden biri. Giriş yolunun ağzındaki sarı ışığı gözden kaçırma.
551be4da	Özel Etkinlik SMS mesajı
552094e0	Oyuncuya Bak
553eda6b	Genel Sıralama
55423473	Oluştur
5555a6f0	Arabana biraz stil kat. Yeni karbon aynalar, spoilerlar ve tavan kepçeleri Bayview bölgesindeki tüm Kaporta Atölyelerinde.
555bd5b6	Yarıştan şimdi ayrılırsan bu oturum sona erer.  Ayrılmak istediğine emin misin?
556149af	KICKER SUB - 8 İNÇ
55614df0	MTX SUB - 8 İNÇ
55615231	JL AUDIO SUB - 8 İNÇ
55615672	CLARION SUB - 8 İNÇ
55615ab3	NFSU SUB - 8 İNÇ
5562cbd2	Frenler
5566d903	Geri bildirim gönderiliyor: %s
55c60293	Tükenme Hızı
55da8bf8	Stereo
55f6c1ea	En Uzun Kayma
5632d96d	Daveti İptal Et
56575496	Oyuncu listendeki kişilere çevrimdışıyken davet gönderilemez.
56720dc1	Diğer oyuncu oyundan çıktı
56756942	Drag yarışlarında önündeki arabaların rüzgar arkasına girerek fazladan hız kazan. Öndeki arabaya yakın durursan onun yardığı havadan faydalanırsın; sollamaya çıktığında da sapan gibi ileri fırlarsın.
56a3658e	Klasik
56afe190	Vites Düşür
56b00632	Sil
56bba6dd	Kaporta Atölyesi
56caa9bf	Hey oğlum! Tam zamanında geldin! Tur Eleme yarışları birazdan başlıyor, istersen sen de katılabilirsin. Yüreğin yetiyor mu, yetmiyor mu?
56caa9c0	Hey, şov canavarı! Sana diyorum, sana! Herkese sadece gösterişten ibaret olmadığını kanıtla! Tur Eleme yarışı başlıyor, sahneye çıkma şansın bu. Var mısın?
56d63b1e	Sesli sohbet isteğini reddettin
56da42e0	Tak
56e8e74c	Xbox Live OptiMatch Arama Ayarları
56f9ef27	Performans
56feb0d2	Direksiyon Açısı
571f6c00	Gelişmiş Kontrast
5722f2da	Yüksek Isı
57314152	Karbon Aynalar, Spoilerlar, Tavan Kepçeleri
5735483a	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
574e6205	Doğu Coal Harbor'da bir Aksesuar Atölyesi var. Binanın girişi arka tarafta. Giriş yolunu bulmak için sarı ışığı ara.
5755251f	Jackson Heights
576f6980	SMS'e (Kısa Mesaj Sistemi) hoş geldin. Oyun boyunca bilgileri bu sistemle alacaksın.^^Mesaj geldiğinde ekranda bir zarf yanıp söner; okumak için SMS sistemini aç.^^Posta simgelerinin rengi, mesajın içerdiği bilginin türüne göre değişir.^^Yarış etkinlikleri, mesaj göstergesinin üst kısmında simge olarak görünür.^^Yarışa / Atölyeye Gir tuşunu kullanarak etkinlik hakkında daha fazla bilgi alabilirsin.^^Her yarış türünün kendine ait bir simgesi vardır.^^Keşif modunda sürerken Şehir Haritasını da açabilirsin. Tüm şehri, keşfettiğin bütün yarışları ve atölyeleri görmenin en kolay yolu budur. Burada etkinlikleri filtreleyebilir, GPS sistemini de etkinleştirebilirsin.^^Kariyerinde ne kadar ilerlediğini görmek istiyorsan Kariyer Durumu tuşunu kullan. Burada arabanın görsel puanını ve oyundaki genel ilerlemeni öğrenebilirsin.
57aacf91	Karbonda seçenekler çoğaldı! Yeni karbon aynalara, spoilerlara ve tavan kepçelerine herhangi bir Bayview Kaporta Atölyesinde göz at.
57f833ad	Street X
5813e1a5	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
586ca736	Trafikli Drift yarışı
5882fa01	Görüntü Ayarları
588a0a91	Şimşek
588f162d	AIRSTREAM OFSET
58b8df93	En Uzun Drift:
58babcfc	Her URL Galibiyeti:
58baebba	SMS Oku
58dc5ffa	^Tebrikler, araban Blacktop Bandits DVD kapağına seçildi! Fotoğrafçıyla buluşmak için mini haritandaki yıldıza git.
58f09252	TİP 3 SOL TEKERLEK NOZULU
58f71919	Race Breaker
594620f8	Şehirde dolaşırken diğer modifiyecilere Outrun yarışı teklif et. Yarış başlayınca öne geç ve rakibini ekmeye çalış. Onu peşinden atmak için istediğin yere git, ne gerekiyorsa yap ve kazananın parasını cebine koy.
596a8287	Grafik Atölyesi
597893d7	Etkinlikleri ve atölyeleri haritada filtrelemek için Şehir Haritası tuşuna basarak haritayı aç. Filtrelemek istediğin etkinlik ve atölyeler arasında gezin, sonra onları haritalarda gizlemeyi ya da yeniden göstermeyi seç.
59867de5	Haberler
59ab7fdd	ORİJİNAL
59b6dc45	Outrun SMS mesajı
59bfb401	Anlık G Kuvveti:
59c4937b	Harita Açıklaması
59df7753	BLINDSIDE OFSET
59ecb2c2	Drift
59ecd886	İç Donanım/Aksesuar
59fff832	Olay karbonda! Yepyeni karbon aynalar, spoilerlar ve tavan kepçeleri tüm Bayview Kaporta Atölyelerine geldi.
5a014c34	35ueueu
5a3bb868	^3 Drag Yarışı
5a5d44a3	El Norte
5a6ed61c	Blacktop Bandits DVD Kapağı
5a6f817f	EA sunucusuyla bağlantın koptu. Ağ adaptörünün ve ağ kablonun takılı olduğundan emin ol. Yeniden bağlanmak ister misin?
5a890bda	1. Oyuncu, START düğmesine bas
5ab21d17	Arkadaş Çıkarılıyor...
5ac1fb59	Hızlı Yarış Araba Seçimi
5ac221fd	MERCAN
5ac2319f	YEŞİL
5ae08536	Turbo
5ae1d9e5	Pist Ayarı
5ae3441f	Yakın
5aece53f	SÖZLEŞME HÜKÜMLERİ:^Sürücü 7 URL yarışı, sponsorun seçeceği 3 yarış ve kendi seçeceği 29 ek yarış kazanmalı.^^EK ŞARTLAR:^3 DVD kapağında yer alacak bir araba yap.^^BONUS:^Bayview galerisinden hediye araba.
5af77283	Kaporta
5b4967f0	Drag Ayarı
5b4aa6e4	Dikey Senk.
5b5ad1c9	Kadın
5b81d5ba	kW
5b81d613	Nm
5bc4bc1e	2. Oyuncu, START'a bas
5bdbbb19	Otomatik Kayıt
5bde50cf	BEYAZ
5be4a3ba	Dergi kapağı çekimi
5be5e40a	Süre Farkı:
5c17ec47	EN UZUN DRIFT:
5c1b351c	Yarış
5c262253	KOYU SEDEF KIRMIZI
5c5520d3	Karbon bir kaputla arabana biraz stil kat. Şimdi herhangi bir Bayview Kaporta Atölyesinde.
5c8b6c4a	Oyunlar Arası Davet
5c912475	GÜVENLİK GÖREVLİSİ: Evet? İş tamam; her şey ayarlandı. Sen de anlaşmada üstüne düşeni yap, duydun mu?
5c9c6823	^3. Aşamada 18. yarışını kazandığın için dergi kapağına çıktın!
5ca73434	Bir oyun odasına girersen etkin sesli sohbetler iptal edilir.  Ayrıca okunmamış mesajlarını ve oyun davetlerini kaybedebilirsin.
5cf08eb7	Klavye Tuş Ayarları
5cf5f8bd	Kazanılan Puan:
5d10f6af	Para Ödülü:
5d1621b2	Outrun'ı Kaybettin!
5d2b0b43	Çevrimiçi Yarış Modu Ayarları
5d304669	AZAMİ HIZ:
5d336f96	Orijinal parçalar takılsın mı?
5d4ed35d	Sponsor Bilgileri
5d645acd	En İyi Tur
5d7d51a5	%s adlı profildeki arabaları^yüklemek istediğinden emin misin?
5d82dba2	Elendi
5da6131b	Modifiyeli Arabayı Düzenle
5dafd047	Unuttuğun şifreyi istemeden önce^EA hesap adını girmelisin.
5dc20c71	Gamertag Bul
5dc29751	Çevrimiçi Persona Seç
5def84fe	MODERN 1
5def84ff	MODERN 2
5def8500	MODERN 3
5e0ab884	Çıkartmayı Yükle
5e1f61ee	cm
5e30942b	Street X Yarışı
5e51cab9	Göstergeler:
5e58bb90	Direksiyon Doğrusallığı
5e5c5f2e	Nitro
5e623733	Kasım 2004'te Çıkıyor
5e670a9e	Şehir Haritasına Dön
5e7309d1	Mevcut Araba
5e7e1192	Kariyer
5e7e7075	GPS Kullanımı
5ea95002	TİP 2 YEŞİL
5eaa4974	Gel, yeni gelen karbon kaput çeşitlerine bir göz at. Herhangi bir Bayview Kaporta Atölyesinde.
5eb035d1	$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
5eb0abe1	sn
5ed1c215	Harita tercihi
5ee1c847	Boyayı Yükle
5f38e63e	ORTALAMA HIZ:
5f42ed07	Rachel'dan SMS mesajı
5f4445f5	Drag yarışı - Mükemmel vites
5f5116c0	TİP 2 SAĞ ÜST VE SOL ALT NOZULLAR
5f52d4fd	Vinili Yükle
5f77bb60	İmzalanan Sponsorluk:
5fb0f3d1	KIRMIZI NABIZ
5ff40d68	GATO KARBON FİBER
600de6fa	Kaporta Atölyesinde arabanın görünümünü modifiye etmek için^jantlardan spoiler ve kaputlara, geniş kasa kitlerine kadar^çok çeşitli parçalar bulunur. Underground 2'de sadeden çılgına^yüzlerce yepyeni tasarım seni bekliyor!^^İşte Underground 2'nin tam sürümünde yaratabileceğin^modifiyeli canavarlardan 2 örnek.
60129941	Bağlanıyor...
601410dc	MAGAZINE_SETUP_AMT
601417c3	MAGAZINE_SETUP_CAE
601417c4	MAGAZINE_SETUP_CAF
6014211a	MAGAZINE_SETUP_EGT
60142b3b	MAGAZINE_SETUP_GTF
601459f4	MAGAZINE_SETUP_RSU
60145be1	MAGAZINE_SETUP_SAS
60145c24	MAGAZINE_SETUP_SD3
60145e23	MAGAZINE_SETUP_SSC
60145e47	MAGAZINE_SETUP_STF
60145eb8	MAGAZINE_SETUP_SWT
601462b5	MAGAZINE_SETUP_TUR
601466bc	MAGAZINE_SETUP_USZ
6026c91f	Şehir Haritası
60689615	Racing Street Unleashed
609e0bf8	Otomatik Kaydı açmak için mevcut^profiline bir ad vermen gerek.
60b42afb	Keşif Moduna dönülsün mü?
60bb7840	ALPINE 1 LCD - 7 İNÇ
60c1a872	Dostum, kankam çıkmak üzere, bütün gece seni bekleyecek değil. %s içinde dükkanına varmazsan parçayı kaçırırsın. Hadi bas gaza.
60ca01ac	Bu yarıştan çıkıp Xbox Live Ana Menüsüne dönmek istediğine emin misin?
60d088cd	Şehir Haritasının özelliklerine ulaşmak için Şehir Haritası tuşuna bas. Şehir Haritası; şehri, ortaya çıkan yerleri ve etkinlikleri bir bakışta gösterir. Haritanın sol tarafındaki listeden etkinlikleri seçip seçimlerini kaldırarak haritayı filtreleyebilirsin. Ayrıca burada farklı harita görünümleri arasında geçiş yapabilirsin.
60d24d65	Etkin bir profil olmadan Performans Ayarı / Dyno ekranına giremezsin.
60d77359	Özel Performans Yükseltmesi
60e532c2	OZ WHEELS
60f699c2	Yakıt Enjektörleri
60ff7215	Yepyeni tasarımlar az önce geldi! Mahallede en müthiş yeni karbon kaputa ilk sahip olan sen ol! Bayview bölgesindeki tüm Kaporta Atölyelerinde.
61032ce5	Modifiye Araba Seçimi
6109e4b5	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Kategoriyi Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
611751fd	Coal Harbor
612af8a6	Yüksek
613d3106	Outrun
614b6fc9	Yasaklı Gamertag
614dbd61	DAVET GÖNDERİLDİ
61789791	"I Do"^Seslendiren: Chingy^Söz-Müzik: Howard Bailey, Alonzo Lee ve Shamar Daugherty^© 2004 BMG Songs, Inc. (ASCAP) o/b/o Chingy Music / Trak Starz Music / ^Almo/Irving Music (ASCAP)^Kayıt izni: Capitol Records^Lisans: EMI Film & Television Music^^"Nothing But You" (Cirrus Remix)^Seslendiren: Paul Van Dyk^Söz-Müzik: Leslie Hemstock, Christopher Jennings ve Paul Van Dyk^© 2004 Notting Hill Music / BMG Songs, Inc. (ASCAP) o/b/o Arabella Musikverlag GMBH,^ Sights and Sounds Publishing^Kayıt izni: Mute^Lisans: EMI Film & Television Music^^"In My Head"^Seslendiren: Queens of the Stone Age^Söz-Müzik: Josh Homme, Josh Freese ve Troy Van Leeuwen^© 2004 Copyright Control^Kayıt izni: Interscope Records^Lisans: Universal Music Enterprises
619b23b0	Gaz
61a50b8f	Doku Filtreleme
61c9b7a2	--:--.--
61cb0720	Otomatik
61f022c0	EA Messenger sistemiyle arkadaşlarınla yarış ayarla, yalnızca davetle girilebilen özel oyunlar kur
621cc718	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Ayarı Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
622866bc	Bayview Performans Atölyesi Batı Coal Harbor şubesine hoş geldin. ^Ekstrem seviyesindeki Ağırlık Azaltma, Lastik ve Fren yükseltmelerinin kilidini açtın. ^Diğer Performans Atölyelerinde ve Megalow Parts'ta açılan tüm parçaları burada da bulabilirsin.
624f037f	Hibrit
626e210c	Aranacak Adı Gir
62925361	Işık Parlaması
629477de	Bayview Kaporta Atölyesi Batı Coal Harbor şubesine hoş geldin. ^Yeni Ön Tampon, Arka Tampon ve Marşpiyel seçeneklerinin kilidini açtın. ^Önceki Kaporta Atölyelerinde açılan tüm parçaları burada da bulabilirsin.
6298f309	MAGAZINE_SETUP_FOTF
629b0d0f	GPS'i Aç
629cdefc	MAGAZINE_SETUP_MTTM
629fedba	MAGAZINE_SETUP_SFTS
62ae717d	Grafik Atölyesinde yüzlerce özel boya rengi, benzersiz vinil ve çıkartma arasından seçimini yap.
62ef5d9d	Xbox Live Ayarları
63078970	Burnout
6316d113	Kanka, bu sağlam iş ama son kullanma tarihi var. %s içinde dükkanına yetişemezsen ahbabım gitmiş olur. Bu fırsat bir daha ele geçmeyebilir.
6322f230	StreetSpin
632b8da7	Orta
632d35e2	Parlak
633d70f3	GPS sistemi, haritada listelenen yerleri bulmana yardımcı olur. GPS seçeneğine ulaşmak için SMS'te Şehir Haritasını seç. Olası hedefler arasında gezinmek için GPS'i Etkinleştir düğmesine bas. Keşif Moduna döndüğünde mavi ok, seçtiğin hedefin yönünü gösterir.
63477036	GPS'i etkinleştirmek istediğine emin misin?
6353f07e	Geri Bildirim
635cb250	%s giriş yaptı.  Davetin yeniden gönderildi.
6369f4b8	Duraklat
6380768e	ÖZEL DÜZEN
6382ece0	inç
638380f5	Sadece denk performanslı arabalara izin ver
63909762	JAPONYA
63aa639d	Direksiyon
63aa662a	KORE
63c53643	Arabanda değişiklik yaptın. Bunları^profiline kaydetmek istiyor musun?
63eb6a03	.
63ec22c2	STREETGLOW
640db893	Son Tur
643bde3c	Karbon Fiber Tavan Kepçeleri
6452d482	Outrun taktiği
64730aac	Hidrolik Zıplatma
647bc574	GALLER
647d8f5d	Bayview Performans Atölyesi Doğu Coal Harbor şubesine hoş geldin. ^Pro seviyesindeki Ağırlık Azaltma, Lastik ve Fren yükseltmelerinin kilidini açtın. ^Diğer Performans Atölyelerinde ve Megalow Parts'ta açılan tüm parçaları burada da bulabilirsin.
64953698	Başka biri senin hesabınla giriş yaptığı için Xbox Live oturumun kapatıldı.
649da17f	$JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$
64c6cc1a	SPARCO
64cf99a3	Yan Sanayi
64e7e6aa	Otomatik Kayıt özelliği, bir şeyi değiştirdiğinde ya da kariyerinde ilerlediğinde oyunu kendiliğinden kaydeder. Otomatik Kayıt ayarını Duraklatma menüsündeki Oynanış bölümünde bulabilirsin.
64e9a07f	Bayview Kaporta Atölyesi Doğu Coal Harbor şubesine hoş geldin.
6502b778	İstediğin bu mu?
651edb93	ZİNCİRLEME DRIFT
653b26c4	DVD kapakları
654fd8c3	Sadece aynı seviyedeki oyunculara izin ver
6563a4d7	Hızlı Yarış Araba Seçimi
656bf9b4	Tamam, ayarladım. %s içinde bizim Nesto'nun dükkanına yetiş, o hızlı arabana harika bir parça ayarlasın.
6584c378	Otomatik Kaydı açmak için mevcut^profiline bir ad vermen gerek.
65929d97	EA Hesap Adı
65b5b74d	Four on the Floor DVD Kapağı
65fda335	Güncel oyun listesi^sunucudan alınıyor...
660bdf52	Karbon fiber body kitini orijinal haline döndürmek istiyor musun?
663437a9	Stoplar
66516470	Sil
665439b2	Bu katmana yeni bir vinil uygularsan arabandaki mevcut^Özel vinil kaldırılacak. Devam etmek istiyor musun?
66559034	%%20 İndirim:
666128e0	Dolby Surround
667d0409	KOYU SEDEF MOR
66886589	Çevrimdışı görünmeyi seçersen oyun davetleri ve sesli sohbet davetleri gönderemez, alamazsın.
668b0666	- Hararetli çevrimiçi yarışlarda dünyanın en iyi yarışçılarıyla kapışma
668c7453	Yarış Bitti. Süre Doldu.
66abd1f1	Beacon Hill
66b47619	MARKA:  %s
66b496d8	BRIDE
66cf56ae	Dereceli
66e8b77e	ENKEI
66e8e275	Sunucuyla iletişim kurulurken bir sorun oluştu. ^Daha sonra tekrar dene.
66fe473b	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Devam^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
670b90d0	Drift Kralı!
6729a51e	Davet Et
6741bf48	Lastik ve Fren
6755e42a	KONIG
678144ae	DVD Kapakları:
679ce5e6	Hızlı Yarış Mod Seçimi
679fd4e9	%s oynuyor
67ba44b4	Girdiğin geçiş kodu yanlış.
67bb5481	^^9 yıldızlı bir araba yaptığın için DVD kapağına çıktın!
67c12255	Dostum, %s içinde Jimmy'nin dükkanına yetişecek kadar hızlıysan, müthiş bir görsel modifiyeyle o arabanın görüntüsünü de sürüşü kadar iddialı hale getirebiliriz.
67e53439	Süre
67eea09e	%s seni bir Need for Speed™ Underground 2 oyununa davet etti
67f1d911	Bu EA hesap adı zaten kullanılıyor.^Başka bir ad seçip tekrar dene.
67f34517	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$  Sohbeti Kaydır^$JOY_EVENT_FENG_BUTTON2$ $ICON_SPACER$  Sohbet^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
67f55a89	Garaja Gir
67f59054	Sponsorluklar:
67f70c7b	GÜNÜMÜZ
6808e865	Para Bulmak
680ac597	MÜKEMMEL VİTES:
683dc05d	V3 SAĞ TEKERLEK HARİÇ TÜMÜ
68445ad3	Pist yarışları Underground 2'nin olmazsa olmazıdır. Bu etkinliğe katıl ve şehir sokaklarından geçen, avuçlarını terletecek bir pistte 3 rakibe karşı 2 turluk bir yarışta yeteneklerini sına. Üstünlüğü ele geçirmek için nitronu ve bulabildiğin tüm kestirmeleri kullan.
6864bfed	E-posta adresin en az 7 karakter uzunluğunda olmalı.
686d16f2	Megalow Parts İndirimleri
687767f1	Seni engellemiş birine ya da kendi kurduğun bir oyun odasındayken sesli sohbet isteği gönderemezsin.
687f411e	Modern Seti
6887e3b4	Azami Tork
68df0cfa	Harika Drift!
68e97f75	KOYU MOR
68f7c286	ŞİMŞEK 1
68f7c287	ŞİMŞEK 2
68f7c288	ŞİMŞEK 3
690348ea	NİNJA
6912b5af	NITROUS EXPRESS
6945bb41	Meydan Oku
6950ec05	TEST SÜRÜŞÜ
695d0495	%s sesli sohbete davet ediliyor
695ea632	KAYKAYCI
695efa45	KURUKAFA 1
69644e4b	BLASTBACK ÇİFT
6967656c	Sesli Sohbet
69a45fd1	Tren Deposu Drag yarışları
69a8bc54	Kullanıcı kimliği ve şifre doğrulanıyor ...
69ac1acd	%s kapak fırsatı
69b14e86	Kapak Çekimi
69b36b15	Özel Mesaj Gönder
69b6213d	EA giriş bilgilerini %s profiline kaydetmek ister misin?
69b745c6	Lastik Sesi
6a0b254c	İbre Rengini Seç
6a164af6	Birader, Hector birazdan kaçacak ama %s daha beklemeye razı. Zamanında yetişirsen o roket gibi arabana şahane bir görsel modifiye yapıştırır. Kapatıyorum.
6a2b93eb	2 Oyunculu Bölünmüş Ekran
6a347e9b	Hey uyan oğlum! X'te üstüne çok sert gelecekler. Düşünmeye vakit yok, sadece yap. Bir galibiyet seni sponsorun radarına sokar, bunun iyi bir şey olduğunu da biliyorsun.
6a4c46a6	Boya
6a4ec4ab	Bu persona silinirken bir hata oluştu.
6a71e798	Son Dişli Oranı
6a88b9a0	Yavaş gir, hızlı çık
6a8d9f01	Super Street
6a9b74bd	Profil Yükle
6aa4c280	EA Messenger'da en fazla 100 arkadaşın olabilir.
6aa654c5	Megalow Parts
6ab6d7c7	Güzel yarıştı dostum. Sokakta konuşulana göre bir dergi fotoğrafçısı havalı arabalar arıyormuş. İlgileniyorsan mini haritadaki yıldıza git. Daha fazla bilgi alınca seni ararım.
6ab80afa	Fren/Geri Vites
6ac31b6e	Bayview Kaporta Atölyesinin Jackson Heights şubesine hoş geldin. ^Yeni Ön Tampon, Arka Tampon ve Marşpiyellerin kilidi açıldı. ^Önceki Kaporta Atölyelerinde açılan tüm parçalar burada da var.
6ad0772f	Amortisörler, arabanın ne kadar yumuşak ya da sert olacağına ince ayar yapmanı sağlar. Ön ve arka amortisör sertliğini sürgülerle ayarla; bu ayar, viraja girerken arabanın ne kadar önden ya da arkadan kaydığını ve tümsekleri nasıl sönümlediğini etkiler.
6ad9a7c7	MOR NABIZ
6ae40a28	^5. Aşamada 16. yarışını kazandığın için dergi kapağına çıktın!
6aee5cca	Lider
6af195b3	Performans Atölyelerinin yerini bulmak için haritana bak. Megalow Parts, Bayview'da indirimli performans parçaları satan bir mağaza. Ürün çeşidi az ama en ucuz fiyatlar onda.
6af70496	Hızlı Yarış Pist Seçimi
6afab3cb	Lancer
6b212108	Fizik Hata Ayıklama
6b234b68	Aramıza hoş geldin kanka. Senin için kurallar basit: Yavaş araçlar sağ şeritten. Yoluma çıkmanı istemem, burada pazar gezmesine çıkmadık. Katıldığın an parkur haritası sende. Var mısın?
6b234b69	Ooo, şu çaylağa bakın. Sana işi kolaylaştırayım: Paranı yarışı başlatana ver ve kimsenin yoluna çıkmamaya çalış. Bu saftiriklere atacağım dayağı berbat etmeni istemem.
6b234b6a	Hop kanka, o hurdayı cidden bu yarışa sokmayı düşünmüyorsun, değil mi? Sana tur bindirirken o zavallı arabana çarpmayayım diye galibiyetimi riske atmak istemem. Haritaya dikkat et ve yolumdan uzak dur.
6b234b6b	Bu yarış için atına binmeye hazır mısın kanka? Dur dur, arabandan bahsediyorum ha, gerçek attan değil, anladın değil mi? Köyden geldiğini hep unutuyorum. Kusura bakma kanka.
6b234b6c	Ne haber sokak köpeği? Bütün yeşillerini ben alacağıma göre bana Banka diyebilirsin. Cüzdanıma yeterince yatırırsan belki sana hediye bir tost makinesi veririm. Hesap açmaya hazır mısın?
6b234b6d	Hey dostum, diğer sürücüler sana söylememi istedi: Bu yarışa çöp kamyonu alınmıyor. Belediyenin olsa gerek dedik, çünkü kimse öyle bir hurdayla yarışırken yakalanmak istemez.
6b234b6e	Bu yarışa gireceksen ciddi geleceksin... o tenekenin de raydaymış gibi yol tutsa iyi olur, çünkü burada şaka yapmıyoruz. Paranı da her enayininkini aldığım gibi alırım. Var mısın?
6b234b6f	Bizimle yarışacaksan elindeki en iyi şeyi getirsen iyi olur. Bindiğin o arabanın bitiş çizgisini bırak, başlangıç çizgisine bile varabileceğini sanmıyorum. Bunu bir daha düşün istersen.
6b234b70	Tamam, galiba bir talibimiz var. Paran yeterliyse çizgiye gel. Arada bir hayır işi yaptığımız da olur; görünüşe göre sen de tam biçilmiş kaftansın.
6b3d4f56	BBS
6b42f6f6	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
6b44997a	Ayarlar
6b4cc184	Sports Compact Car
6b5ac462	ÇİZGİLİ
6b6538a1	EA Hesap Adı
6b68362c	Tüm Arabalar
6b77f56e	İTALYA
6b7fe115	JAPONYA
6b87bd29	Zorlu
6b99afdd	KORE
6bb2d6af	Metre
6bb7037e	Bu yarış türü için ayar yapılsın mı?
6bb976ec	AIRSTREAM ÇİFT
6bcbceea	Spinner boyaları normal jantlara uygulanamaz. Boyayabilmek için önce arabana spinner takmalısın.
6bcc7461	Araba Takası
6c02f6e1	%s meşgul!
6c09c82d	Yarış Bitti.  Süre Doldu!
6c11c80c	Arabana en yeni N2O teknolojisini ekle, bir sonraki yarışta fark yarat. Herhangi bir Bayview Performans Atölyesinde ya da Megalow Parts'ta taktır.
6c2ab886	İSPANYA
6c328734	Keşif Moduna dönmek istediğinden emin misin?^Turnuvadaki ilerlemen kaybolacak.
6c340bd2	Devam etmek için Xbox kişisel bilgilerini^EA ile paylaşmayı kabul etmelisin.
6c4bf67c	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Bagaj Düzenini Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Bagaj Düzenini Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
6c4d414c	BLASTBACK OFSET
6c5f7b10	2. SIRAYA ÇIKTIN
6c6b0f27	GALLER
6c6c43fe	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Araba Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Arabayı Seç^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$  Arabayı Modifiye Et / Düzenle^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$  Araba Filtresini Değiştir^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
6c839fbe	Duraklat
6cacf1ec	Bu hesapla sunucuya zaten giriş yapılmış.
6cad61be	Sponsor arabası mı seçmek istiyorsun?
6cdcf27e	BALKABAĞI
6cf6e689	Sıralama verileri sunucudan alınırken bir sorun oluştu.^Daha sonra tekrar dene.
6d0c0068	Tanıdıklarımdan biri az önce aradı: %s dergisinden bir fotoğrafçı şehirdeymiş, gelecek ayın kapağı için havalı arabalar arıyormuş. Haritadaki yıldıza git, oraya varınca seni arayıp ayrıntıları veririm.
6d35c53f	V3 SOL KAPUT HARİÇ TÜMÜ
6d4c5049	Yarış Sonuçları
6d583407	^^8 yıldızlı bir araba yaptığın için DVD kapağına çıktın!
6d8cff3e	ALMANYA
6d9da272	AEROSTYLE OFSET
6da17a25	%%10 İndirim:
6da1e521	Şehir Haritası
6dabc0bd	Profil Seç
6dc2c4db	Kaporta Atölyesi
6dd36fe5	Chrom & Flammen
6de3b2ed	Devam etmek için kumandayı %d numaralı kumanda soketine yeniden tak.
6e0e9f8d	ZEPHYR ÇİFT
6e11e175	Downhill Drift'te büyük puan toplamanın sırrı, yol dışında ve trafikteki arabaların arasında drift atmak. Trafiğe ne kadar yakın drift atarsan o kadar çok puan alırsın.
6e37cdc4	Sıçrama Seti
6e3cda8e	Aksesuar Atölyesi, arabana "şatafat" katacağın yer.  Makinen için çok çeşitli "şov" parçaları arasından seç, sokaklardaki itibarını yükselt.
6e43304c	CLARION ÇİFT LCD - 7 İNÇ
6e500e4b	Nissan
6e58f193	Motor Neonu
6e66f0ad	Araban herkesinki gibi mi ses çıkarıyor? Yeni egzoz uçlarımızla hem havalı bir görünüm hem de kendine has bir kükreme kazan. Bugün herhangi bir Bayview Kaporta Atölyesinde taktır.
6e6a103b	EUROLITE
6e86d064	Drift yarışlarında puan, arabanın hızına ve açısına göre verilir. Hızın ve drift açın ne kadar yüksekse o kadar çok puan alırsın. İşaretli bonus bölgelerinde kayarak drift puanlarını tavan yaptır.
6e8a0b76	^3 Pist Yarışı
6eb0eccb	Kaporta Atölyesinde arabanın görünümünü değiştirecek çok çeşitli parçalar var: jantlar, spoilerlar, kaputlar, geniş kasa kitleri ve daha fazlası. Underground 2'de sadeden çılgına yüzlerce yepyeni tasarım bulacaksın!
6ec828ba	CLARION LCD - 5.5 İNÇ
6ee64972	Vinillerdeki değişiklikleri iptal etmek istiyor musun?
6ef09d0d	SMS'leri Göster
6f188dee	SPRINT
6f2421b7	Serbest Sürüş
6f2c7417	Işık İzleri
6f4796a6	Ana menüye çıkılsın mı?
6f612909	Adını gerçekten duyurmaya başladın. %s dergisinden tanıdığım bir fotoğrafçı arabanı derginin kapağına koymak istiyor. Haritandaki yıldıza git. Beni arayıp ayrıntıları verir vermez onunla nerede buluşacağını sana söylerim.
6f99f62a	Duraklat
6faa6b90	ZİNCİRLER
6fbb3bf0	Hey dostum, arabamı geri istiyorum…HEMEN! Kıçını kaldırıp buraya gelsen iyi edersin, yoksa herkese senden uzak durmalarını söylerim — bu da ben izin verene kadar yarış falan yok demek. Galeriye git, bütün gece seni bekleyemem. Yeri haritanda!
6fc04e6f	Arabayı Sıfırla
6fd3b71c	Üst Katman
6ffe3717	Outrun Kuralları
700e3dcf	Lokomotif deposunun açılıp kapanan kapılarına dikkat et. Yukarı kalkan kapıları gözle ve o şeride geçmeye çalış. Kapanmakta olan bir kapıdan son anda geçmeye çalışmak riskli bir hamledir ve sana yarışı kaybettirebilir.
7019add7	Mesafe:
703970f8	Geçen Ayın Sıralama Tablosu
704f4f94	YARIŞÇI: Ortam ısınsın!
7063c82e	BACKDRAFT ÇİFT
7067ab57	Ayarlı Kamber Plakaları
70802830	Puan
7087ce45	Engellenen
70a30056	Kariyer İstatistikleri
70b11cf1	Vinil Uygula
70bc194e	N2O tahliyesi için yepyeni yerleşim seçenekleriyle tarzını konuştur. Bayview Aksesuar Atölyesi sana müthiş bir kurulum ayarlar. Bu gece ara, randevunu al.
70c738e6	Yeni Oyun Modları
70df6656	Race Breaker
70e72b92	Bölünmüş ekran için arabaları^yüklemek istediğinden emin misin?
7129d5ce	KICKER AMFİ - 500 WATT
712d304b	GENİŞ KASA YOK
71322a28	TİP 3 FISTIK YEŞİLİ
71345941	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
713b9c46	Bu kişiyi arkadaş listenden çıkarmak için bu sesli sohbeti bitirmelisin.
713e201b	TURUNCU
716ad2a9	Oynanan Oyun
71851654	Özel ayarlarından biri değişti. Profilini şimdi kaydetmek istiyor musun?
719afe9e	Pist Lideri
71b651aa	%s dergisinden bir arkadaşım şehre geldi, gelecek ayın kapağı için havalı bir makine arıyor. Yeri bildirmek için beni tekrar arayacak. Haritadaki yıldıza git, ayrıntıları öğrenince seni ararım.
71d5e280	alındı
720f48fe	Bu arada söylemeyi unuttum, bu gece şehirde ortalık çok hareketli. Yarış noktalarını haritana yükledim. Hadi çık dışarı ve adını duyurmaya başla!
722f35a1	PİST
726382b4	Neon
7282b9ec	Son Dişli Oranı — Dar ve virajlı bir pistte Son Dişli Oranını daha fazla hızlanma için ayarlamak isteyebilirsin; uzun bir drag pistindeyse azami hız daha önemli olabilir.
72943cc4	Bu Gamertag ile zaten giriş yapılmış.^Daha sonra tekrar dene.
7294434c	LAN
72988dbe	Garaja girmek istiyor musun?
72b2e513	Peugeot
72b8f0cf	CYCLONE ÇİFT
72bb728e	Persona Adını Gir
72c15fcb	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Geri^
72eca090	MAGAZINE_SETUP_SCNORWAY
72f18963	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Parçayı Tak^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
72f7569a	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
72f7f4c5	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Parçayı Tak^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
731141ef	Piyasaya yeni çıkan şanzımanlardan birini taktır, beygirlerini yola daha hızlı aktar. Montaj için herhangi bir Bayview Performans Atölyesine ya da Megalow Parts'a uğra.
73332e68	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Çıkartma Markasını Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Çıkartmayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
735b2e6c	Kariyer İstatistikleri
737d1b97	SES
7382e1ef	Sınırlı Kaymalı Diferansiyel
739c4a1b	Ön Tamponlar
73ad2f72	Şanzıman
73bc702e	Orijinal parçalar boyanamaz; boyamak istiyorsan modifiye parçalar takmalısın.
73cc4a6b	Şehirde dolaşırken gizli yarışları gözden kaçırma. Gizli yarışlar mini haritanda görünmez ama yüklü para kazandırır. Yerlerini bulmak için SMS'lerini kontrol et ve diğer yarışçıların verdiği ipuçlarına kulak ver.
73d2edd7	MOR
73d67f0a	Yaylar — Sert yaylar düzgün zeminli parkurlar için idealdir; yumuşak yaylar ise bordür ve rampalarla karşılaşabileceğin engebeli parkurlarda işe yarar.
73da4a74	Race Breaker özelliğinden yararlanmak için arabana nitro takman gerekir. Şehirdeki herhangi bir Performans Atölyesinden ya da Megalow Parts'tan bir N2O sistemi al.
73e322fd	Oyundaki ilerlemeni^profiline kaydetmek istiyor musun?
73f33e6b	Sözleşme şartları karşılandı
73f36979	Pist Ayarları
740b7a4b	%s dergisinden bir fotoğrafçının şehre geldiğini az önce duydum. Gelecek ayın kapağını nerede çekeceğini öğrenmeye çalışıyorum. Haritana yüklediğim yıldıza git. Yerini öğrenir öğrenmez seni ararım.
7447c0e3	.
7449d26d	Motor yaktın!
744a80a7	Şifre korumalı mı?
748bc8b9	Mesajı oku
74b2a894	Bir derginin kapağına çıktın. Hemen git, bir bak!
74e34714	Bu çıkartma kaldırılsın mı?
74e499b0	DVD Kapakları
74face4a	Görsel Modifiye
750e1970	TEMPEST ÇİFT
7535bf16	Garaj, arabalarını saklayıp modifiye ettiğin yerdir.
75635a0b	ORİJİNAL
75666a90	Yeni kaputlar geldi! ^En yeni kaput tasarımlarını hemen herhangi bir Bayview Kaporta Atölyesinden al.
758d5e3c	Ağırlık Azaltma
75941dc1	Vites Kaçtı!
7597cbc3	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
75b6ca33	Sıra
75c1d7fe	Yeni profil oluştur
75d2168e	Tek Yarış Sonuçları:
75d23e29	Kazanılan Para:
75e2a098	İsim Gir
75f903f4	URL Yarışı
7608683e	Hey Rachel
761e08ce	Çeyrek Mil Süresi: %s^Çeyrek Mil Hızı: %$3.2f MPH
7647b08c	DVD Kapaklarını Gör
7652f899	Kapak Çekimi
7668e127	TİP 3 SOL KAPUT NOZULU
766a0edf	Pist Seç
766e13d5	Stoplar
769a4775	Sprint kralı olmak istiyorsan hızlı karar verebilmen lazım. Burada bir dönemeci kaçırırsan işin biter. Merak etme, bitiş çizgisinde seni bekleriz.
769a4776	Sprint yarışı hızlı refleks ister dostum. Tek bir yanlış hamlede işin biter. Bol şans, ihtiyacın olacak. Haritayı SMS'le yollarım.
769a4777	Kanka, bu yarışı Sprint olarak yapıyoruz. Sen ve o hurda yığını bitiş çizgisini bir gün geçebilirseniz beni uyandırın da paramı alayım. Katıldığın an parkuru sana yüklerim.
769a4778	Bu yarış Sprint kurallarıyla yapılıyor. Bindiğin şey yaşlı bir teyzenin yürüteci ayarında olduğuna göre paranı şimdiden teslim etsen iyi olur.
769a4779	Ah be dostum, bu yarış Sprint, emekleme yarışı değil. Belki de Rachel'ı arayıp gerçek bir araba ödünç almalısın, ben de biraz rekabet göreyim.
769a477a	Vay, bakın rüzgar kimi getirmiş! Burada atari oynamıyoruz birader, biliyorsun. Bu yarış gerçek para için ve o parayı toplayacak olan benim. Bitiş çizgisinde ayaklarımı uzatmış seni bekliyor olacağım. Ben uyuyakalmadan gelmeye çalış.
769a477b	Ne haber yıldız çocuk? Hakkında iyi şeyler duydum. Biraz para ortaya koyup bunları kanıtlasana? Yeteneğini göstermeden benden saygı falan göremezsin.
769a477c	Dostum, araban fena... ama iyi anlamda değil, resmen fenalık geçiriyor. Biri doktor çağırsın, bu arabanın ciddi bir tedaviye ihtiyacı var. Açıkçası kurtarılabilir mi, bilmiyorum.
769a477d	Bu dandik arabayla sana bir teselli partisi vermemiz lazım. Ne dersin, bu yarışta seni bir güzel benzeteyim, sonra bitiş çizgisinde parti verip araba dediğin o hurda için ağlaşırız.
769d5fe0	Corolla
76a191b3	Ses Modu:
76ae5c10	1. Sponsor
76ae7288	2. Sponsor
76be33ff	%s seni sesli sohbete davet etti.
76e721c7	Fren dengesi, frenlemenin ne kadarını ön lastiklerin, ne kadarını arka lastiklerin yapacağını belirler. Fren dengesini öne ya da arkaya kaydırmak için sürgüyü ayarla. Fren dengesini değiştirmek, arabanın fren yaparken ne kadar dönebileceğini etkiler.
76f2bc60	%$3.1f %s^@%$d d/dk
76fb2b66	VELOCITY KARBON FİBER
7709fd9b	Ödüllerine Bak
770af86e	Rachel
7712e575	Çarpışma Algılama
772093db	TİP 2 İKİ KAPUT NOZULU
774aacaa	Doğrusal Değil
7758f62d	Kaldır
77634211	TYPHOON ÇİFT
77bb9331	Yeni turbolar tüm Bayview Performans Atölyelerinde ve Megalow Parts mağazalarında. Seninkini bugün al.
77d405a2	Devasa Drift!
77dc847b	TİP 1 İKİ SOL NOZUL
77ea7d34	SEVİYE 1 HİDROLİK
77feec35	Şikayet Gönder
780207ca	Kullanım Şartları İndiriliyor ...
78300ebf	%s engelleniyor...
783202b0	Outrun Kabul Edildi^Onu Atlat!
783f8d11	Haberler İndiriliyor ...
7840428a	Tekrar İzle
78671db6	Drift İkincisi
788c05e8	Tur
78cb3307	Drag yarışı - Mükemmel vites
78d5f70f	Önizle
78dad861	Kaporta Atölyesine girmek istiyor musun?
78deea1c	Viniller
78f307e3	Pro Performans Lastikleri
79115f4b	Chevrolet
79165861	Tavan Kepçeleri
791f62a3	Gelen Mesaj
79595c08	FUŞYA NABIZ
796d6858	NEDERLANDS
796dc449	Kaporta Atölyesi
797e7f7b	Hey birader, Coal Harbor yolundaki inşaat çalışması bitti. Duyduğuma göre orada güzel yarışlar dönüyor. Mutlaka bir göz at.
798f86b2	V3 SAĞ KAPUT HARİÇ TÜMÜ
79964833	Hesabın Electronic Arts tarafından kilitlendi.^EA Müşteri Desteği ile iletişime geç.
79a85513	Yarıştan şimdi ayrılırsan bu oturum sona erer ve istatistiklerine bir yenilgi ve bir bağlantı kopması işlenir.  Ayrılmak istediğine emin misin?
79ad657f	Seç
79b0b11d	Serena
79b58ee6	350Z
79b86ab2	TWISTER ÇİFT
79bc1e2a	Toplam Puan: %d
79c0f89c	Golf
79c4a524	Neon
79e5b675	İKİ RENK C
79e5b676	İKİ RENK D
79e9c09d	Büyük Çaplı Downpipe
79f084e9	6 Pistonlu Yarış Kaliperleri
7a04c109	En İyi Tur:
7a10bbd2	Bulunması zor ayna tasarımları artık burada. Dünyanın en nadir ayna tasarımları şimdi tüm Bayview Kaporta Atölyelerinde.
7a255162	Pist Haritası
7a4c4ab2	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Geri^
7a513e2a	^Tebrikler, araban Bayview’s Best DVD kapağına seçildi! Fotoğrafçıyla buluşmak için mini haritandaki yıldıza git.
7a60c857	1 Drift Yarışı^1 Drag Yarışı^1 Pist Yarışı
7a78a4f6	Motor Detayları
7a84021e	Bu body kiti seçmek istiyor musun?
7a91c865	TİP 3 SAĞ TEKERLEK NOZULU
7aa591cc	Katılmaya çalıştığın oyun artık yok
7ab90260	Stefan
7aca0a4e	Bayview Grafik Atölyesi
7ad18f04	Yeni Oyun Oturumu Oluştur
7adba6be	TİP 2 TÜM NOZULLAR
7afaf0ef	Kurucu, yarışın yeniden başlatılmasını istedi.
7b04ecc5	Her arabanın ideal bir vites değiştirme noktası vardır. Arabanın her viteste en doğru değiştirme noktasını öğren; Mükemmel Vites yaptıkça yarışta fazladan hız kazanırsın.
7b0f3b82	Aerodinamik Yere Basma Kuvveti — Toplam yere basma kuvveti çok fazla olursa araban tümseklere ve bordürlere daha sert tepki verir; o yüzden tutuşla sürüş rahatlığı arasında bir denge bul.
7b14f5c7	SÖZLEŞME HÜKÜMLERİ:^Sürücü 5 URL yarışı, sponsorun seçeceği 3 yarış ve kendi seçeceği 19 ek yarış kazanmalı.^^EK ŞARTLAR:^2 DVD kapağında yer alacak bir araba yap.^^BONUS:^Bayview galerisinden hediye araba.
7b5545d3	CROSSOVER ORTA
7b63ff85	Çevrimiçi
7b66942e	Görsel Yıldız Puanı
7b6790ef	Islak Sistem Nitro
7bc467df	profil
7bd87cda	Fizik Hata Ayıklama
7be4fa45	%s arkadaş isteğini engelledi!
7bf4e178	Çevrimdışı Görün
7c15b695	^4. Aşamada 16. yarışını kazandığın için dergi kapağına çıktın!
7c65e473	Hakkında okudun, şimdi arabana tak. En yeni ECU'lar geldi; yalnızca Bayview Performans Atölyelerinde.
7ca327e0	Yarış bilgisi
7ca666cb	^Tebrikler, araban Four on the Floor DVD kapağına seçildi! Fotoğrafçıyla buluşmak için mini haritandaki yıldıza git.
7cc05367	YEŞİL NABIZ
7cccee87	TEMİZ SEKTÖR
7ce21662	Garaj
7ce4ee4f	TİP 2 İKİ SAĞ NOZUL
7cf58af8	Import Tuner
7d0707b6	SAMANTHA: Kafanı toparlamak için ortam değiştirmek isteyebileceğini düşündüm. Seni suçlayamam.
7d0707b7	SAMANTHA: Bak, dinle! Bayview'a varınca kankam Rachel sana her şeyi ayarlar. Arabasını sana ödünç verdi; havalimanında seni bekliyor.
7d0707b8	SAMANTHA: Ama o araba onun gözbebeği, nazik davran. Bol şans, birader! Görüşürüz.
7d13da29	KENWOOD
7d162708	Kurucu seni oyundan çıkardı.
7d1d448d	%s oyundan atılıyor.
7d283d29	Araba
7d29f8f8	Simon
7d347e05	Çevrimiçi Ayarlar
7d3930e7	Araba Yansıma Güncelleme Hızı
7d485221	Buraya yaz
7d784605	Bu, bölge 5 yorumu
7d7a6e0e	Bölünmüş Ekran Oyun Ayarları
7d822b64	1. Vites
7d822b65	2. Vites
7d822b66	3. Vites
7d822b67	4. Vites
7d822b68	5. Vites
7d822b69	6. Vites
7d90c187	EA giriş bilgileri profil olmadan kaydedilemez.  Bir profil oluşturmak ister misin?
7dadee33	Çevrimiçi Pist Ayarları
7db3b4f8	Bilgilerin EA ortaklarıyla paylaşılsın mı?
7ddf4897	Mini Harita Açıklaması
7defb45e	ALEV 1
7defb45f	ALEV 2
7defb460	ALEV 3
7dfa04b4	^4. Aşamada 20. yarışını kazandığın için dergi kapağına çıktın!
7dfdacc0	Girilen ad kabul edilemez, farklı bir ad gir.
7e630fac	Uyarı!^Bu bilgileri ağ üzerinden göndermek üzeresin.^Emin misin?
7e71c8a9	Bu arkadaşını EA Messenger ve Xbox Live arkadaş listenden çıkarmak istediğine emin misin? Bu arkadaşından gelen okunmamış tüm mesajlar kaybolacak.
7e77208c	Geçersiz bir e-posta adresi girdin.
7e833617	Spoilerlar
7e891f93	Turnuva Sıralaması
7e9a9c67	Herkesin sesi kapatılsın mı?
7eadfd76	Sistem Hoparlörü
7ebb0d14	Arabana o küçük ama özel dokunuşu katmak mı istiyorsun? Gel, motor detaylarını boyayalım. Hortumlar, silindir kapakları ve daha fazlası. Tüm Bayview Aksesuar Atölyelerinde.
7ed554d1	Aerodinamik
7edc9715	Galeri
7ee84e4e	Zaten %s arabanı sürüyorsun!
7ef5aacb	Ödüller
7efb8f6c	^Tebrikler, araban Underground Speed Zone DVD kapağına seçildi! Fotoğrafçıyla buluşmak için mini haritandaki yıldıza git.
7eff16c2	Parçayı Tak
7f042bcd	KLAVYE
7f1025e7	Arkadaş isteği engelleniyor: %s ...
7f1c766d	Süre
7f2d0c79	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Devam^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
7f2f7ad6	YOK
7f5c8c06	Direksiyon Dönüşü
7f61feed	Yarış Seti
7f6253ef	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Geri^
7f742d4f	Gidilen Yol:
7f842556	1 Drift Yarışı^1 Street X Yarışı^1 Drag Yarışı
7f8537ef	Adını Gir:
7f904ae8	Yarış Türü:
7fc3cd5c	Arabanı %s DVD'si için çekime hazırla. Kadrajı beğendiğinde fotoğrafı çek!
7fd73849	Tur Eleme
801f34f7	TRİBAL 1
801f34f8	TRİBAL 2
801f34f9	TRİBAL 3
803eb1be	ORTA KIRMIZI
8050ca3f	KOYU KIRMIZI
807f53be	CALEB: Evet, her şey yolunda. Sadece şey... küçük bir sorunu halletmem gerekti.
80833fc2	Yeniden Başlat
808ab037	İşine baksan iyi olur, çünkü bu asfalt yakma seansı sözleşmene işleniyor ve sayılacak tek şey galibiyet. Gözleri hep üstünde, hadi göster kendini.
808ab038	Başlayacağını biliyordun, şaşırmış gibi yapma. Bu viraj şovu sözleşmende yazılı, birinci gelsen iyi olur. Sponsor kaybedenle takılmaz.
8090b36a	Drag:
80af4fc7	LAN Sunucusu Kur
80b338cb	%s kapak fırsatı
80b8267c	URL
80c151d5	Özel viniller dört vinil katmanının^hepsini kaplar. Arabandaki diğer tüm ^viniller kaldırılacak. Bu vinili değiştirmek^ya da kaldırmak istiyor musun?
80d92c43	Özel %s
80e17b11	Yeni Ağ Yapılandırması dosyası oluştur
8106d26a	Sıralama
8109153d	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Performans Paketi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
811035b5	Yeni far renkleri tüm Aksesuar Atölyelerinde. Şu anda tüm marka ve modeller için stoklarda var.
81163a96	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Katman Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Katmanı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
81273f29	Ağ Yapılandırması dosyan başka bir konsolda oluşturulmuş, kullanılamaz.
812b621c	yön tuşları
813251f6	Filtrele
8150b80d	^Tebrikler, araban Speed Demons 3 DVD kapağına seçildi! Fotoğrafçıyla buluşmak için mini haritandaki yıldıza git.
815bcd91	XIMIAN OFSET
8173fc6b	Bu filtre şu an uygulanamıyor.
817a974b	Mevcut performans parçalarının hepsini satmasa da Megalow Parts'a uğramaya değer. Parça ve paketlerde normal Performans Atölyelerine göre ek indirim var. İyi parçaları en ucuza almak istiyorsan Megalow Parts'a git.
817e8de6	Grafik Atölyesi, arabanın görünümünü kişiselleştirmenin adresi. Tamamen sana özel bir araba yaratmak için yüzlerce boya, çok katmanlı vinil ve çıkartma ekleyebilirsin.
818f0385	AD
81ab4717	Arama Sonuçları
81b1d73d	Profil yüklersen mevcut profildeki kaydedilmemiş tüm değişiklikler kaybolur. Profil yüklemek istediğinden emin misin?
81caa8e6	Hedef Puan:
81f6d1b5	TİP 3 GÖK MAVİSİ & ALTIN
8202c364	Seç
820434b1	^^4 yıldızlı bir araba yaptığın için DVD kapağına çıktın!
82159a60	Araba bilgilerin gönderilirken bir sorun oluştu.
8217efab	GERİ GERİ
8218f5fd	Arabanı alanın içinde istediğin yere koyabilirsin. Görüntüden memnun kaldığında fotoğrafı çek!
822e4e9b	Hareket Bulanıklığı
823b1fd8	Burnout Mesafesi:
824bc854	Güç
828dc738	Karbon Kit
829bd8a8	Marka Değiştir
82cd8f92	Yarış Sırası
82cdba8b	Oyuna Katıl
82d1359e	Tamamdır! Başlasın parti! Drift zamanı oğlum, kendini kanıtlama şansın var. Usulü biliyorsun.
82d1359f	DRIFT geliyor, hem de tüm gücüyle! Ya gir ya çekil, çünkü bu iş ciddi. Özentilere yer yok; sen sınırdasın, o yüzden çabuk ol. Evet mi, hayır mı oğlum?
82d135a0	Dalga geçiyorsun herhalde! O hurdayla kazanmayı mı umuyorsun?... Ama paranı sokağa atmak istiyorsan, buyur gel birader.
82d135a1	Dostum, olay başlıyor ve sıradaki Drift yarışında ilk sıra senin. Ufak bir yatırımla ciddi bir şöhret. Ne dersin?
82dfd62a	Uyarı! Bu geniş kasa kitini karbon fiber olarak takarsan bazı viniller kaldırılabilir.
82ebcc98	Fren / Geri
82ec0f03	Ağ donanımında bir sorun oluştu.
82ec12c8	CD anahtarını bu EA hesabına bağlamak istediğine emin misin?
82f20772	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
8326e324	Güncelle
838feef5	Bölge Tamamlanma Durumu:
839ee8be	Spoiler
83a5e0ae	^Tebrikler, araban Modified to the Max DVD kapağına seçildi! Fotoğrafçıyla buluşmak için mini haritandaki yıldıza git.
840d7ab3	CALEB: Ah, işte bundan bahsediyorum! Sana demiştim--sen bir hiçsin. Bir HİÇSİN! (gülüyor)
841e5117	Hyundai
8424d624	Şimdi Oku
843f5d58	Performans Ayarı / Dyno Pistine girersen okunmamış mesajlarını ve oyun davetlerini kaybedersin. Devam etmek istiyor musun?
844feb00	$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
84684ee8	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ Kaydır^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla
846e1e9e	Konumundan memnun kalana kadar arabanı alanın içinde gezdir. İstediğin görüntüyü yakalayınca fotoğrafı çek!
846ee660	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ Neon Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Neonu Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
847121dd	Hazır
8497e678	Bu Gamertag ile ilişkili bir EA hesabı yok.
84c9e2d9	Kaporta Atölyesi
84d8a279	Artık altında bir araba olduğuna göre garajıma gel. Yarış aramaya hiç uğraşma, ortalıkta bir şey dönmüyor. Beni yine bekletme. Orada görüşürüz.
84dbc3e8	Seçtiğin Gamertag geçersiz.^Geçerli bir Gamertag girip tekrar dene.
84e39124	Ayarlar SMS mesajı
84e79dff	Çevrimiçi LAN
84e800ed	ALPINE AMFİ - 500 WATT
8513f2c0	Performans Ayarı / Dyno
851c212a	EA Messenger
85215bc6	%s arabanı ^bu orijinal %s ile takas etmek istiyor musun?
8528bd24	ÖDÜL
85344a3e	EA.COM'a bağlanırken bir sorun oluştu.^Ayarlarını kontrol edip daha sonra tekrar dene.
85600f91	Splash Vinil
8569a25f	KM/SA
8569ab44	MPH
8590f3c5	^5. Aşamada 25. yarışını kazandığın için dergi kapağına çıktın!
859bf6f8	Xbox Live'a Giriş Yap
85a6ce05	Dikiz Aynası
85c044a2	Dereceli Arabalar
85d2ed13	Grafik Atölyesine girmek istiyor musun?
85fb094f	^Tebrikler, araban Burning Wheels DVD kapağına seçildi! Fotoğrafçıyla buluşmak için mini haritandaki yıldıza git.
86203875	Render Hata Ayıklama
862a0519	Çabuk!
86444c9d	Bu persona seçilirken bir sorun oluştu.  Tekrar denemek ister misin?
8645e0d4	Desteklenen ağ donanımı algılanmadı.  Ağ adaptörü olmadan bu oyunun çevrimiçi özelliklerine erişemezsin.
864bd0bd	Yarışları kazanmakta zorlanıyor musun? Arabana performans yükseltmeleri almak için şehrin dört bir yanındaki Megalow Parts ve Performans Atölyelerine uğra. Yeni gelen ürünlerden SMS ile haberin olur.
8655e76d	DANİMARKA
8668dc07	Resmi Yarış Sonuçları
867b06a0	SÖZLEŞME HÜKÜMLERİ:^Sürücü 3 URL yarışı, sponsorun seçeceği 3 yarış ve kendi seçeceği 9 ek yarış kazanmalı.^^EK ŞARTLAR:^1 DVD kapağında yer alacak bir araba yap.^^BONUS:^Bayview galerisinden hediye araba.
8680e646	KUDUZ KÖPEK
86cc69b7	Sistem Hoparlörü
86cd6929	Bu özel ayarı saklamak istediğine emin misin?
86f0a661	Hızlı Yarış Pist Ayarları
86f11927	Lobi sunucusuna yeniden bağlanırken bir sorun oluştu.^Daha sonra tekrar dene.
86ffe723	Toplam
87055515	Harita Açıklaması
8718dd0b	Street X oldukça yeni bir etkinlik, o yüzden sponsorların büyük parasını sadece kazananlar çekecek. Bu işte kendine ilk isim yapan kişi büyük paraya konabilir.
8718dd0c	Kanka, bu yarış sponsorlara karşı yükümlülüklerinden birini kapatmak için. Nasıl sürdüğünü görmek için buraya adam yollamışlar, o yüzden aptalca bir şey yapma. Burada kazanırsak paramızı alırız.
8718dd0d	Şehre yeni gelen çocuğun adı dilden dile dolaşıyor. Kazanmaya devam edersen ileriye dönük birkaç tatlı anlaşma ayarlayabilirim. Sponsorlara heyecanlanacak bir şey verelim.
8718dd0e	Birader, sponsor kazananı destekler. Kazanan ürün sattırır. Kazananın cebi dolar. Bizim de cebimiz dolmalı, o yüzden çık ve kazan.
8718dd0f	Bak şimdi kanka. Kimse Street X'ten ne bekleyeceğini bilmiyor, yani parlama şansın bu. Birinciliği kap, sponsorlar seni fark etsin. Fark edilmek para demek, para da daha iyi bir araba.
8718dd10	Hava atmanın sırası değil. Bu tiplere dağdan inmediğini kanıtlama gecesi bu gece. Yarışı birinci bitir, para akmaya başlasın. Ne yapman gerektiğini biliyorsun, yap.
8718dd11	X'te işi sağlama bağlarsan büyük balıklar seni not etmek zorunda kalır. Öyle bir görünürlük para getirir; senin de buna ihtiyacın var, biliyoruz.
8718dd12	Hey çılgın! Street X'lerin babası geliyor. Zirveye oturursan kravatlılar bayılır. Arkasından da bir anlaşma gelir, hiç şüphen olmasın.
8718dd13	Gözüne pek bir şey gibi görünmez ama iyi anla... X'i hafife alırsan seni darmadağın eder. Sen bildiğini yap, birinci bitir. Gerisi gelir.
87783a6a	Yepyeni cam filmleriyle arabana ekstra bir stil kat. Şimdi tüm Bayview Aksesuar Atölyelerinde.
87962b3f	Spor Yaylar ve Amortisörler
87983521	Üzgünüz, bu kayıt senin yaş grubuna uygun değil.^Hesap oluşturmak için ebeveynine veya vasine danış.
87ac789b	SARI
87c86448	Arka Amortisör
8809cad2	Drag yarışçısı olarak umut vadediyorsun, sakın şimdi batırma. Bu yarış sponsorunun ilgisini çekiyor, o yüzden farkla kazanıp paramızı alalım.
8809cad3	Pekala, bu yarışın hakkından gelirsen yine kolay para. Bunu kazanırsan sözleşmeni tamamlamaya bir adım daha yaklaşırsın. Görelim bakalım neler yapabiliyorsun.
8809cad4	Bu galibiyete ihtiyacın var. Kulağıma çalındı ki sponsor bu yarışı izliyormuş. Şu işi bitir de para kazanmaya devam edelim.
8809cad5	Kimse bir kaybedeni desteklemek istemez, hiçbir sponsor da batan gemiye para yatırmaz. Para gelmeye devam etsin istiyorsan kazanmaya devam etmelisin. Çık oraya ve iz bırak.
8809cad6	Bak dostum. Asfaltı yakıp bu Drag yarışında zirveye çıkman lazım, çünkü bu yarış sözleşmende yazılı. Sponsorlar seçimlerinden şüpheye düşmesin diye kazanmak zorundasın. Ben bitiş çizgisinden izliyor olacağım.
8809cad7	Hey oğlum, bu geceki Drag yarışını birinci bitirirsen kaymağı sen yersin. Galibiyet sözleşmene yazılır, cebine de birkaç yüzlük girer. Sen mutlu, ben mutlu, sponsor mutlu.
8809cad8	Kafana takma ama bu Drag sıradan bir yarış değil. Hem sponsor sözleşmene işleniyor hem de biraz para kazandırıyor. Bunu birinci bitirirsen dert edecek bir şeyin eksilir - para hariç tabii.
8809cad9	Bu gece olay var. Sponsorlar galibiyet istiyor, senin de paraya ihtiyacın var. Birinciliğe uç ve sözleşmenin galibiyet hanesine bir yarış daha yaz. Kazanmak anlaşma getirir, anlaşmalar da seni spot ışıklarının altına sokar. Büyük oyna!
880c43ab	ORTA MAVİ
882c96af	İYİ ÇIKIŞ
8832f372	Ekim
885031f0	^Tebrikler, araban Slammed & Stretched DVD kapağına seçildi! Fotoğrafçıyla buluşmak için mini haritandaki yıldıza git.
8852bf06	TİP 2 SOL KAPUT NOZULU
88576cff	Kapalı
88579775	Evet
885ed413	Ters
88632ee7	Yarışlar her an, her yerde başlayabilir
88632ee8	Arabanın her ayrıntısına ince ayar yap
88632ee9	Pek çok sürüş disiplininde yeteneklerini geliştir
88632eea	Yeni kişiselleştirme seçenekleri ve tonla yeni parça
88632eeb	Dünyaya meydan oku
886da3d8	Outrun'a Giriş
889bacb6	Çıkartma Rengi
88a7cf05	Davetin süresi doldu ya da davet geri çekildi.
88de696b	KESTİRME
88f9acb3	Daha fazla para kaybetmek istemiyor musun? O zaman bundan sonraki Outrun düellolarında kazanan taraf sen ol.
88ff0d21	Keşif Moduna dönmek istiyor musun?
890fa231	Vites Yardımı:
8966d866	Tasarıma Vinil Ekle
896aa0b2	Fren kaliperi boyası
896bcb4d	Yok
8990eadb	Tüm MODİFİYELİ ARABA YUVALARI dolu.^Modifiyeli arabaları araba atölyesinde^ MODİFİYELİ ARABAYI SİL seçeneğiyle silebilirsin.
89946400	AÇIK SİYAH
899ab38d	BİTİŞ HIZI:
89bb9cea	Yuva 1
89bb9ceb	Yuva 2
89bb9cec	Yuva 3
89bb9ced	Yuva 4
89bb9cee	Yuva 5
89bb9cef	Yuva 6
89bb9cf0	Yuva 7
89bb9cf1	Yuva 8
89cd630b	Duydun mu? Yepyeni egzoz uçlarımızla arabanı kalabalıktan ayır. Çeşitlerimize tüm Bayview Kaporta Atölyelerinde göz at.
89d4e03f	Bu performans kategorisi zaten orijinal!
89e3b31f	Davet gönderme sınırına zaten ulaştın!
89f23a14	AÇIK YEŞİL
8a0ab225	Gizle
8a24d87a	Dyno Atölyesi
8a33654c	Tandem Drift yarışı
8a5a61b1	Street Car Magazine
8a60f52c	KOYU TURKUAZ
8a616c4c	KOYU MAVİ
8a6435ca	KOYU ALTIN
8a66da4b	KOYU ÇAĞLA YEŞİLİ
8a690bf6	KOYU FUŞYA
8a9e0f44	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
8aa2aa13	Hesap geçerliyse, belirtilen e-posta adresine bir şifre gönderilecek.
8aa477a8	Batı Beacon Hill'deki Aksesuar Atölyesi, bulması en zor atölyelerden biri. Giriş yolunun ağzındaki sarı ışığı gözden kaçırma.
8aa55a91	^Tebrikler, araban Straight From the Streets IV DVD kapağına seçildi! Fotoğrafçıyla buluşmak için mini haritandaki yıldıza git.
8b026675	Azami Hız:
8b207e1a	Arama ölçütlerine uyan oyuncu bulunamadı.
8b476814	EA kaydını tamamlamak için aşağıdakileri doldur...
8b543f71	Bagaj Ses Sistemi
8b84e940	Aşama %d:
8b8e913a	Rakip Yetişmesi
8bab66ef	Ayarlarını yapılandır
8bc0b80c	Şifre
8bec8f84	Yarış Ödülü
8c00bbdd	GPS
8c066d23	HOLLANDA
8c228bac	Şerit Vinillerle o kaplumbağan bile hızlı görünür. Geniş seçeneklerimize bölgedeki herhangi bir Grafik Atölyesinde göz at.
8c4d03ea	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla
8cac9d6a	Tümü
8cb6e51e	URL Lideri
8cbe2b00	Demodan Çık
8cc45ab2	Toplam Puan:
8cd2171b	Arabana performans parçaları taktıktan sonra ince ayar için onu test pistine çıkar. Her yarış modu için ayrı pistler var. Burada arabanda değişiklikler yaparak onu her tür yarışta avantaj sağlayacak şekilde hazırla.
8cfa8332	^Tebrikler, araban Racing Street Unleashed DVD kapağına seçildi! Fotoğrafçıyla buluşmak için mini haritandaki yıldıza git.
8d0a8371	%s adlı oyuncuyu engellemek istediğine emin misin? Artık bu kullanıcıdan mesaj veya davet alamayacaksın.
8d0dafec	Kariyer Arabaları
8d0fa2d9	Hız Sınırlayıcıyı Kaldır
8d204e91	Dereceli bir oyuna girdiğinde, bu oyun modu için uygun dereceli arabaya otomatik olarak geçilir.  Etkin sesli sohbetler de iptal edilir.  Ayrıca okunmamış mesajlarını ve oyun davetlerini kaybedebilirsin.
8d3ee1af	çevrimiçi: %s
8d5abf58	Modifiye
8d7531d3	Cam filmleri
8d9b9ec7	Yorum: %s
8da6481d	SUV'ler, Need for Speed™ Underground 2'deki yarışlara yepyeni bir boyut katıyor. SUV'lerin ekstra ağırlığı ve büyüklüğü, en deneyimli yarışçıların bile yeteneklerini zorlayacak.
8dad3684	Sohbet Sesi
8dcaccbc	1. SIRAYA ÇIKTIN
8deece42	Çevrimiçi Oyuncu:
8e024964	TRAP KARBON FİBER
8e06920b	Oyuncuyu Yasakla
8e076bec	Sanat Fabrikası
8e4312b0	Bu düzeni kurarsan daha önce takılan tüm ses^bileşenleri sökülecek. Bu bagaj ses sistemi^düzenini şimdi kurmak istiyor musun?
8e4433af	Bu bir Tur Eleme yarışı. Her turun sonuncusu elenir. Zaten ilk elenen sen olacağına göre kenarda oturup bu yarışların nasıl işlediğini izleyebilirsin. Varsan haritayı sana yüklerim.
8e4433b0	Dostum, bu sefer Tur Eleme yapıyoruz. Her turda sonuncu elenir. Ayakta kalan son kişi ödülü alır; ama inan bana, senin öyle bir derdin olmayacak.
8e4433b1	Kanka, Tur Eleme kazanmak için baştan sona gazı köklemen lazım. Arkada bekleyip son anda atak yapmak yok. Herhangi bir turda geride kalırsan kendini bir anda elenmiş bulursun.
8e4433b2	Ne haber kanka? Bu gece Tur Eleme yarışları var; yarışa girmek istiyorsan göster bakalım paranı. Bu arada, ilk turda mı elenmek istersin, ikincide mi, üçüncüde mi?
8e4433b3	Dostum, abinle cidden bir raunt daha mı istiyorsun? Sana hafif vurmak isterdim birader ama bu bir Tur Eleme yarışı ve tahminim şu: Bu gece ilk raundda nakavt oluyorsun.
8e4433b4	Hey ezik! Sokakları ısıtıyoruz! Herkesin dediğinin yarısı kadar iyiysen gelirsin. Cevabın ne, ha? Sabaha kadar seni bekleyemeyiz!
8e4433b5	Vay vay vaaaay! Kafa kurmayı bırak da işine bak! Yumrukları sık, Tur Eleme yarışı var. Ne olduğunu bilmiyorsan uzak dursan iyi olur. Varsan parkur haritası sende. Evet mi, hayır mı?
8e4433b6	TUR ELEME! Aynen öyle! Bu yarışa girersen ilk elenen sen olursun. Var mısın, yoksa tırstın mı?
8e4433b7	Bu gece SERT gidiyoruz! Tur Eleme yarışı başlıyor ve sen de davetlisin. Havlamayı kes de göster kendini!
8e52365c	Kaput
8e566831	Mevcut
8e77b44d	Yeni geldi! Makinenin görünümünü değiştirecek müthiş aynalar burada. Tüm marka ve modeller için, tüm Bayview Kaporta Atölyelerinde.
8eab27c5	Drift:
8ebbeeba	ORİJİNAL
8ef89614	Ağ yapılandırmasını seç
8f1436a4	A Yuvasındaki Hafıza Kartı çıkarıldı^ ya da değiştirildi. Otomatik Kayıt açıkken^ devam etmek istiyor musun?
8f24d3b7	Çevrimiçi modda dereceli oyunlara ayrılmış altı araba yuvası var ve her yuva bir oyun moduna bağlı. Dereceli bir oyuna girdiğinde otomatik olarak o modun dereceli arabasına geçersin
8f287cfa	Yeni Hesap Oluştur
8f4b9dfd	CROSSOVER BÜYÜK
8f56222b	Kabul Etmiyorum
8f6e7874	Aksesuar Atölyesi
8f998fbb	Sponsorluklar
8fd0966b	CROSSOVER KÜÇÜK
8fe9288e	Araba Yansıma Detayı
8ff3f225	Artık arabanın fotoğrafını çektirip bir derginin kapağına çıkabilirsin.
90038d25	Tur
90083e89	^^5 yıldızlı bir araba yaptığın için DVD kapağına çıktın!
9016a670	EA Online Kullanım Şartları indirilemedi
9021f500	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Parça Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Performans Paketlerine Geç^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Parçayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
903854f0	Uyarı! Modifiye bir kaput takarsan kaputtaki tüm çıkartmalar kaldırılacak.
90599828	Sonuçlar için %d saniye bekleniyor
90643bdc	Outrun Zaferi
906b132a	Sunucuyla iletişim kurulurken bir hata oluştu.^Daha sonra tekrar dene.
90732102	GİZLE
90792669	GÖSTER
907c555e	Orta
907d8d60	Street X yarışlarında başarılı olmak için virajları iyi almayı öğren. Bu dar ve teknik parkurlarda en iyi sonucu yol tutuşu iyi arabalar alır.
909cd3e8	EA Online Kullanım Şartları
90c2d8ba	Ayarları Kaydet
90ccdcee	Parlamaya hazır ol! Yeni kabin neonuyla kızların ağzını açık bırak. Seninkini bugün herhangi bir Bayview Aksesuar Atölyesinden al.
90dfd9d2	TRAFİĞE ÇARPTIN
90f3e1cf	Gözünü dört aç, gazı da kökle.
90f8ac46	Sesli Sohbeti Kapat
91070ff2	Davet kabul ediliyor: %s ...
913729c8	Temmuz
913729f6	Haziran
913ac36a	Kaputlar
913df10e	Sedefli
91439e2c	Güç
914508cf	3. SIRAYA ÇIKTIN
9148097e	RÜZGAR ARKASI
916039b4	Çok Uzak
917fc2f4	Aynalar
9182c3f3	Race Breaker
91921a8d	Modifiye edebileceğin yeni araba sınırını aştın.^Mevcut arabalarını düzenle ya da ana menüdeki ARABAYI MODİFİYE ET menüsünden sil.
91bb1bd2	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Xbox Live'dan Çıkış Yap^
91c92a94	EA sunucuları şu an teknik sorunlar yaşıyor.  Daha sonra tekrar dene.  Sorun devam ederse EA Müşteri Desteği ile iletişime geç.
91d22557	Bayview Performans Atölyesinin El Norte şubesine hoş geldin. Megalow Parts'ta kilidi açılan tüm parçaları burada da bulabilirsin.
91d36963	İSKOÇYA
91f0139b	Yarış Süresi
91f7ca09	Mevcut Aşamada Yarış Başına Ortalama İtibar Puanı
92008d45	Leke
9202238e	Kıvılcım
920dbb02	Tasarımı Satın Al
92243754	Trafiğe açık parkurlarda her drifti trafiğin akış yönünü hesaba katarak planla. Dış şeritte drift atmak risklidir, çünkü karşıdan gelen trafikle burun buruna gelebilirsin.
92260f04	Genel Durum
92377943	Performans Ayarı / Dyno Pistine girersen etkin sesli sohbetler iptal edilir.  Ayrıca okunmamış mesajlarını ve oyun davetlerini kaybedebilirsin.  Devam etmek istiyor musun?
923e2728	Performans Paketi İndirimleri
92423b95	Direksiyon Ayarları
924cf95e	%s için gönderdiğin davetin süresi doldu.
9252c11d	Modified to the Max
92ac16eb	Kısa Kurslu Vites Kiti
92e4f7f1	Genel
9322058f	En yeni Splash Vinil koleksiyonu az önce geldi. Tarzını kendin belirle. Seninkini bu gece herhangi bir Grafik Atölyesinden al.
9323df57	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
93243268	SELECT
932538c3	Çarpışma Algılama:
933dd695	Geri
93447ee3	İleri
93475966	Yuva
9354d1c2	Street X yarışı
939209b0	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Parça Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Marka Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
93b7d1a3	Arka Yay
93c075b1	Hızlı Yarış Mod Ayarları
93fdee74	Pist
93fee5ed	Direksiyon:
93ff4a6e	Galeri
94330d15	Hey tatlım
94544527	%10 İndirim
945e9bc5	Geniş Kasa Kitleri
946bf653	Yarış SMS mesajı
946ca212	Atölye SMS mesajı
9471028b	Sürüş Kontrollerini Değiştirme
947f6403	Bu, bölge 3 yorumu
94c5e7bf	Jantlar
94d3715b	Aşama %d - %s Durumu
94ef34d4	Xbox Live Ayarları
94f4c140	Bu performans paketini satın alıp takmak istiyor musun?
950302d7	Hiçbiri Yok
9519f8b0	RIPTIDE OFSET
951b63e8	ORİJİNAL EGZOZ
951cce54	Racing Street Unleashed DVD Kapağı
953e4317	KURUKAFA 2
953e4318	KURUKAFA 3
95684a90	Özel Oda
95772e30	En yeni tavan kepçeleriyle arabana yarışçı havası kat. Seninkini Bayview Kaporta Atölyelerinden al.
958a5415	Farlar
95a7073d	Hızlanma
95b7a7fb	Performans Çipi
95b8f38d	Sis
95e10f41	Geri Sil
95eb6769	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Geri^
9633e6c2	İstatistiklere Bak
96438588	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ Renk Değiştir (Yukarı / Aşağı)^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Renk Değiştir (Sol / Sağ)^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$  Boya Türünü Değiştir^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Rengi Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
969f96a5	Tur Bilgisi
96a1e80f	Araba Performans Kısıtlaması
96b05f47	Sıra
96b89c4c	"the Keys to Life vs. 15 Minutes of Fame"^Seslendiren: Atmosphere^Kayıt, Rhymesayers Entertainment LLC'nin izniyle, Epitaph Records'a^lisanslı olarak kullanılmıştır.^^"Switch/Twitch"^Seslendiren: Fluke^Kayıt, One Little Indian Records'un izniyle kullanılmıştır.^^"Notice of Eviction"^Seslendiren: The Bronx^Kayıt, Ferret Music'in izniyle kullanılmıştır.
96d596bc	Bağlantı^Aranıyor
96d7d398	Oyun Oluştur
96dbe962	HAÇ A
96dbe963	HAÇ B
96dbe964	HAÇ C
96dd344f	GİDİLEN YOL:
96ddb796	Uyduya Bağlan
96e47726	"NISSAN" adı ile NISSAN ürünlerinin adları, logoları, işaretleri ve tasarımları NISSAN MOTOR CO., LTD.'nin ticari markaları ve/veya fikri mülkiyet haklarıdır ve Electronic Arts Inc. tarafından lisansla kullanılır.^^Tüm yan sanayi araba parçası şirketlerinin adları ve logoları, ilgili sahiplerinin ticari markalarıdır ve izinle kullanılır.
9700a5ad	Yeni Persona Oluştur
9701f11d	Denge Kontrolü
972dd7ed	Oyun Oluştur
97422602	Galeri
976bdaaa	%s adlı profili^yüklemek istediğinden emin misin?
9796dfb4	Uyarı! Karbon fiber kaput takarsan arabandaki tüm kaput vinilleri ve çıkartmaları kaldırılacak.
979e6441	Kaporta Atölyesi
97a4e19f	400m Hızı:
97b1dcda	Yeni Kariyere Başla
97b25a02	Arkadaşın aynı oyunu oynuyor olmalı!
97b3c8cf	Xbox sabit diski
97ba56c9	%s kapak fırsatı
97cb518b	Şifreyi onayla
97cba5d2	NIKKI & RACHEL: Ah, bu MUHTEŞEMDİ! Harika yarıştın! İnanamıyorum!
97cba5d3	NIKKI & RACHEL: (sevinç çığlıkları) İşte bu; onun işi bitti! BİTTİ! Başardığımıza inanamıyorum! Gerçekten başardık be!
97cbc6d8	Sesli Sohbeti Aç
97cc56d1	Yepyeni motor neonlarıyla arabanı sokakların en havalısı yap. Seninkini bugün herhangi bir Aksesuar Atölyesinden sipariş et.
97e04a41	Özel %s
97efcb16	Mesaj Yönetimi
97fcbdea	Megalow Parts, indirimli parçaların dev mağazası. 1. ve 2. seviye performans parçalarını burada bulabilirsin. Performans parçaları şehirdeki diğer atölyelerde de satılsa da en büyük indirimler Megalow'da.
9807ba99	TİP 2 SAĞ KAPUT NOZULU
987eecda	Garaja girmek istiyor musun?
988238a9	TİP 2 YEŞİL & MAVİ
98850227	TİP 2 YEŞİL & ALTIN
98a62c0c	KENWOOD AMFİ - 500 WATT
98d34851	Atölyelere ya da yarışlara girmek için animasyonlu alanın içine sür ve Yarışa / Atölyeye Gir tuşuna bas. Posta simgesi belirince gelen mesajlarını okumak için SMS sistemini aç.
98d587f7	Rachel
98e3ce26	Garaj Araba Seçimi
98f11a2f	Sokaklarda harika sürüyorsun! Vaktin olunca galeriye bir uğra; duyduğuma göre bomba gibi yeni bir araba gelmiş.
991414a7	1995 Mazda RX-7
99419a50	SPONSOR PUAN ÖZETİ
9953843b	Şifreyi gir
996463e6	Kayıt
99659496	Hesap Şifresini Onayla
99829679	Konu: DVD Kapağı Çekimi
9986a6e3	Özel Parça Seçimi
9994e536	Göstergeler
99d8bae0	Başka bir oyuncu sohbet odalarında, sesli sohbette ya da EA Messenger üzerinden sürekli müstehcen veya kaba bir dil kullanıyor.
99e91974	Mesaj Kutusuna Dön
9a1d4ac9	Direksiyon Ayarları
9a217f72	Yepyeni bir turboyla arabanı sol şeride taşı. Turbonu Bayview Performans Atölyelerinde ya da en yakın Megalow Parts mağazasında taktır.
9a2e5f7b	Mesaj Yaz
9a3c9ce5	TİP 1 SOL KAPUT NOZULU
9a58e01c	Bu oyuncunun arkadaş listesi dolu.
9a9f1336	Yarışı Başlat
9ab08da6	Bu Ağ Yapılandırması dosyası bozuk ve kullanılamaz.
9abaf068	SIRA
9ad5095f	Dergiler
9ae84a1d	EDELBROCK
9ae9d2f1	Street Car Magazine
9b07307f	0:00.00
9b1307f0	Sonraki Sınıfa Puan:
9b2870f2	Direksiyon kontrollerini değiştirmek için Duraklatma menüsünden önce Ayarlar'ı, sonra Oyuncu'yu seç. Burada farklı direksiyon tercihleri arasında geçiş yapabilirsin.
9b2ab098	Rachel
9b2af3c7	Geride Kaldın!
9b39c122	Pist
9b3a5569	Kapalı
9b6bf47e	Xbox Live Ayarları
9b796534	Odadan şimdi ayrılırsan bu oyun oturumu sona erer. Ayrılmak istediğine emin misin?
9b7e1435	Outrun Yenilgisi
9b8c9d7a	Yarış Geri Sayımı:  %d
9b90975b	Diğer oyuncular bağlanamadı.  Bu oyun oturumu artık mevcut değil.
9b985275	EA ürünleri, haberleri ve etkinlikleri hakkında bilgi almak ister misin?
9ba134fc	Nintendo Lisanslı
9ba4bec8	Önceki özel ayarını yüklemek istediğine emin misin?
9bcb71cc	4. SIRAYA ÇIKTIN
9c07ca52	Şehir Haritası
9c302c85	Tur Sayısı:
9c34c75f	Süspansiyon
9c672d8f	Yan aynalar
9c6e60a4	Oyun Oturumu Başlıyor...
9c74baa2	Orijinal parça satılamaz.
9ca10d4b	BİRLEŞİK KRALLIK
9ca77701	ABD
9cce64c4	Tümü
9cce9f86	Kapalı
9ce0da05	Kurucu Kopma %
9ce82d2e	STREET X
9cf7a73c	Ağ Hata Ayıklama
9d4851bf	Kaporta Atölyesi
9d50e640	Gianelle
9d53bd10	Garaj
9d67bd2a	Tandem Drift yaparken en çok puanı partnerine olabildiğince yakın drift atarak alırsın. Ona ya da duvarlara çarparsan o anki driftten kazandığın tüm puanları kaybedersin.
9d7d9993	Mini Harita açıklaması için SMS göstergesinde aşağı bas. Haritandaki her simgenin anlamını burada görebilirsin.
9d7fd939	Rachel
9d90733f	Bayview's Best
9d9f7657	Karbon Kaputlar
9da14f06	Hey, seni önceden uyarayım dedim. Artık sponsorla sözleşmeli olduğuna göre, anlaşmanı tamamlamak için belirli yarışları bitirmen gerekiyor. Haritadaki "X" simgelerini görüyor musun - işte onlar. Hadi git, ortalığı yık. Sonra konuşuruz.
9da1f76d	Giriş yapmak için hem EA hesap adını^hem de şifreni girmelisin.
9da9e93d	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Katman Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Katmanı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
9db0a710	Turbo — Turbodan, özellikle yüksek devirlerde bolca güç alırsın. Turbo ve ECU'yu birlikte ayarlayarak bu gücü dengeleyebilir, gücü tam istediğin devirlerde alabilirsin.
9db54a80	Şehir Haritasında Gizle
9dcc6e8b	Aerodinamik, arabayı yere bastırarak lastiklerinin tutuşunu artırır. Ön ve arka yere basma kuvvetini artırmak ya da azaltmak için sürgüleri ayarla. Fazla yere basma kuvveti, arabanın tümseklere ve bordürlere sert tepki vermesine yol açabilir.
9de5aedd	Bu Yarışta Kazanılan İtibar Puanı:
9de6b485	Çıkmak istediğinden emin misin?
9de8d763	%s seni sesli sohbete davet etti.
9df2be4a	Bu sesli sohbete girersen mevcut sohbet sona erer. Devam etmek istiyor musun?
9e067677	Paketi Yükle
9e0c7313	Mesaj Sistemi
9e101f88	MAGAZINE_SETUP_AM
9e101f9e	MAGAZINE_SETUP_BB
9e101fb3	MAGAZINE_SETUP_BW
9e102056	MAGAZINE_SETUP_H4
9e102097	MAGAZINE_SETUP_IT
9e10211b	MAGAZINE_SETUP_MT
9e102177	MAGAZINE_SETUP_PM
9e1021d0	MAGAZINE_SETUP_SC
9e1021dd	MAGAZINE_SETUP_SP
9e1021e0	MAGAZINE_SETUP_SS
9e1021e1	MAGAZINE_SETUP_ST
9e274daa	Bu arabada takılı ön/arka tampon, marşpiyel ve geniş kasa kitlerini karbon fibere dönüştürmek istiyor musun?
9e4c4648	Normal
9e4f95c2	Slammed & Stretched
9e5fb82a	Konuşma ve Video Sesi
9e809a98	KICKER AMFİ - 1000 WATT
9e9f1daf	TİP 2 GÖK MAVİSİ
9ec5f82f	Sprint
9ede424e	Bunun için N2O lazım. Yok... iki tüp yap, hem de iki büyük tüp!
9f059306	KICKER AMFİ - 250 WATT
9f1b2c7a	Devam
9f231697	BEYAZ NABIZ
9f29d70d	Kimden: %s
9f730547	Seçimi Değiştir
9f7f6486	İstemci Kopma %
9fa5ec9e	Yarış Harita Modu
9fb0ac8a	Tekrar Kontrolü
9fba141d	EA sunucusuyla bağlantın koptu. Yeniden bağlanmak ister misin?
9fd2c234	Yoldaki diğer modifiyeli arabalara dikkat et. Mini haritanda turuncu üçgenlerle gösterilirler. Ekranda uyarı çıkınca Yarışa / Atölyeye Gir tuşuna basarak bu arabalara "Outrun" düellosu için meydan okuyabilirsin. Düelloda amaç, rakibinin önüne geçip sonra onu ekmek! Onu yenmek için istediğin rotayı seçmekte serbestsin.
9fd501da	Rachel
9fe6dada	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
a0345c44	Bu oyuncuya oyunlar arası davet göndermek için önce %s adlı oyuncuyu arkadaş listene eklemelisin.
a0414cff	Garaja Gel
a071beb0	Bayraklar
a074449f	Hatalı HUD metni.
a081f0cc	Hidrolik Basınç
a08a29b3	Lowenhart
a0c16cab	Arabana bu grafik tasarımını satın almak istiyor musun?
a0c5d893	Hile
a0c6ae56	Şehir Haritası
a0f26827	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Parça Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Performans Paketlerine Geç^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Parçayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
a114130e	VİNİL KATMANI SEÇ
a11f5b71	DTS
a14caf1e	DVD %d
a19617bd	Geri bildirimin gönderildi.  EA Müşteri İlişkileri durumu inceleyip gerekli önlemleri alacak.
a1b18d38	Derecesiz oyunlar eğlencelidir ama kendini zorlamak için çevrimiçi dereceli oyunlara katıl. Diğer oyuncuları yenerek sıralama tablosunda yüksel ve en iyi çevrimiçi yarışçı olduğunu kanıtla.
a1da642a	Herkesin sesi açılsın mı?
a1e95f26	Tebrikler - oyunu bitirdin! Hızlı Yarış modundaki tüm performans ve görsel modifiyelerin kilidini açtın. Şehirde tamamlanacak başka etkinlik kalmadı - Kariyer modundaki yarışlara yeniden girmek için garajına dön.
a1f4476e	Tur
a1f4835f	Yenilgi
a1f55fbf	AD
a1f64ecc	Ödüller
a1f7916a	Sıra
a1f8cc0d	Süre
a1f91080	Tür
a1fa715f	Galibiyet
a1fb776f	Yıl
a227ead5	Outrun düellosunda amaç öne geçmek ve rakibinle arana 300 metreden fazla mesafe koyarak onu ekmektir. Öndeyken istediğin^rotayı seçmekte serbestsin. Gerideysen yarışın kontrolünü ele almak için^lidere yetişip onu geçmen gerekir.
a22a2a7b	Rachel
a2323032	Mevcut özel ayarın değişti. Bu ayarı saklamak istiyor musun?
a2573673	Aksesuar Atölyelerinden biri, sanayi bölgesindeki Batı Coal Harbor'da. 3 nükleer soğutma kulesinin güneyinde. Girişi gösteren sarı ışığı ara.
a267c67f	Bu arabayı takasla almak ister misin?
a2717c2a	LAN sunucusuyla bağlantın koptu.
a277357b	Oyuncu Durumu
a2a9aed0	TİP 3 GÖK MAVİSİ
a2b1f888	Motor Sesi
a2bbdf33	Vay vay, annenin haberi var mı? Çocukları antrenmana taşıdığı arabayı aşırıp şehre çıkmışsın! Bizimle yarışacaksan başlamadan önce arkadaki market poşetlerini sıkıca bağla.
a2bbdf34	Hey birader, Bayview Briç Kulübü aylık çay partisine giderken yolunu kaybetmiş galiba. Daha önce hiç sosyete kulübü parası koklamamıştım; biraz korku kokuyor. Hala varsan parkur haritasını vereyim.
a2bbdf35	Evlat, bu ekip sadece en babasından "arazi canavarlarıyla" takılır. Paranı hemen alayım da şoför yarın sabah okul servisi için istemeden o otobüsü garajına yetiştir, olur mu?
a2bbdf36	Kafana iyi sok evlat: Burada kağnılara ne yer var ne vakit. Neye bulaştığını bilsen iyi olur, çünkü burada para iadesi yok.
a2bbdf37	Şaka yapıyorsun herhalde! O çalıntı arabayla karşımıza çıkmaya cesaretin varmış demek. Göster bakalım paraları evlat; bu yarışlarda veresiye yok.
a2bbdf38	Bu ne biçim dökük araba be dostum. Şansın olduğunu sanıyorsan kafayı yemişsin! Neyse, paranı alırım. Başlatmak için ne yapacağını biliyorsun.
a2bbdf39	Oha! Bak hele evlat, bu acemi şovların sana hiç yaramıyor. Sıradaki yarışa girersen belki biraz gururunu kurtarırsın.
a2bbdf3a	Bu iş SERT, evlaaat! SUV'larla ortalık birazdan alev alacak, sen de tam pataklanmaya yetiştin. Parayı bastır, içeridesin.
a2bbdf3b	Bindiğin o şeyin adı ne? Tekerlekli kutuya benziyor evlat. Seni almak için kuralları biraz esnetebiliriz herhalde. İyi bir kahkahaya bayılırım.
a2d77741	Denge Kontrolü
a2da0ccd	Kare hızı, dereceli oyun için çok düşük
a2ef10a5	Büyük Çaplı Viraj Demirleri
a329d7ba	Meydan Okuyan:
a33aa702	Engel kaldırılıyor: %s ...
a33d508a	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$  Oyuncu Değiştir^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
a34e13bd	Ayarları Düzenle
a3532050	Genel Kariyer İstatistikleri
a392d977	Yerel ağa bağlanılamadı
a3aa0acf	SUV Yarışları
a3e97cd2	Sürüş tercihine göre direksiyon kontrollerini Ayarlar menüsünden değiştirebilirsin. Sana en uygun olanı bulmak için farklı ayarlar arasında geçiş yap.
a3f55e1f	EA sunucusuyla bağlantın koptu. Yeniden bağlanmak ister misin?
a403c822	Diğer oyuncu uygunsuz bir ad kullanıyor ya da uygunsuz adlı bir oda oluşturmuş.
a40518e9	Liderlik Süresi
a4052182	Oyuncuların Hile Suçlaması
a40967b0	En Fazla Oyuncu
a41d9eb6	Ayrık Kaputlar
a420be7c	Neon
a42419ab	Cam Filmi
a424c082	%s şu an bir oyun oturumunda, isteğin reddedildi.
a432f70a	Aksesuar Atölyesi
a4615fbd	Underground Racing League
a46aaea8	DRIFT
a46cb187	Lobi sunucusuna yeniden bağlanırken bir sorun oluştu.^Daha sonra tekrar dene.
a47c4fd1	Kaputlar
a47d1376	Şehirdeki bütün modifiye atölyelerini mutlaka gez. Çoğu mini haritada işaretli ama "yeraltı" yarış atölyeleri "kıyıda köşede" saklı. En iyi parçaları ve yükseltmeleri satan özel atölyelere çıkan ara sokakları ve arka yolları gözden kaçırma.
a47f531c	Rachel
a49003ba	Toplam İtibar
a492ae15	Bu oyuna bağlantı kaliten ortalamanın altında.^Bu oyuna katılırsan kötü bir oyun deneyimi yaşayabilirsin.^Bu oyuna katılmak istediğine emin misin?
a4b092ee	Engel kaldırıldı: %s
a4c02484	Yok
a4ca09c8	%s, Need for Speed™ Underground 2 oynuyor
a4d88f02	J DÖNÜŞÜ
a4e5ee6c	Aksesuar Atölyesi
a4f8464e	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön
a512f58c	Performans yükseltme ödülü:
a517fd7a	Konu: Özel Parçalar
a51cd509	Performans Değerleri
a53035dd	Dereceli bir oyuna girdiğinde, bu oyun modu için uygun dereceli arabaya otomatik olarak geçilir.  Ayrıca okunmamış mesajlarını ve oyun davetlerini kaybedebilirsin.
a53039a3	Modifiye
a540d71d	Uzatma!
a57beb8f	Zıplama
a5a57eb6	TURKUAZ
a5a5f5d6	MAVİ
a5a8bf54	ALTIN
a5ab63d5	ÇAĞLA
a5ac963e	NEON YOK
a5ad5a37	DANSK
a5ad9580	FUŞYA
a5aea201	 — Yeni kişiselleştirme seçenekleri ve tonla yeni parça
a5b53f2b	Harika Oyun
a5b5fa0e	Tebrikler!^ Bedava bir kalem^ve bir kahve kupası kazandın.
a5b64b48	Egzoz Manifoldu Değişimi
a5cf4291	EA hesabı oluşturmak için gerekli bilgileri girmelisin.
a5f04bd7	Grafik Atölyesi
a632eead	Bu oyun oturumundan çıkmak istediğine emin misin?
a63a4af1	Yarış Başına Ortalama İtibar
a645a29e	Bagaj kapağını orijinal haline döndürmek istiyor musun?
a654cb8c	Ödüller / Sponsorluk
a67defd6	Oyun İpuçları
a6a78a3d	Ağustos
a6c0d334	Arabanın grafik tasarımı değişti.^Yeni grafik tasarımını satın almak istiyor musun?
a6cc56cd	Sunucu Adını Gir
a6d23c17	Race Breaker, nitro sistemine yeni eklenen bir özellik. Nitron^yüzde 100'ü geçtiğinde Race Breaker nitrosu biriktirmeye başlarsın.^Bu, arabana çok daha fazla güç ve tutuş kazandırır; bir yarışın kaderini^değiştirebilir. Normal nitro, nitro göstergende mavi renkle^gösterilir. Mavi kısım dolunca yeşil Race Breaker nitrosu, normal^nitronun üstünde dolmaya başlar.
a6d47bbd	Rachel
a73a17a8	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Araba Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Arabayı Seç^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$  Arabayı Modifiye Et / Düzenle^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$  Araba Filtresini Değiştir^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
a747ea86	Bir DVD'nin kapağına çıktın. Hemen git, bir bak!
a7884765	ECU
a7886f38	Nitro
a79139b4	1 Pist Yarışı^1 Drift Yarışı^1 Sprint Yarışı
a7a683ac	Araba Gölgesi / Neon
a7db717f	Bağlantı Koptu
a7fa00b6	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Araba Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Arabayı Seç^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$  Araba Filtresini Değiştir^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$  Arabayı Modifiye Et / Düzenle^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
a8162c11	TİP 2 SOL TEKERLEK NOZULU
a8247197	EN İYİ TUR SÜRESİ
a829d5bf	Hayvan
a8432f46	Aksesuar Atölyesi
a8477e40	CALEB: Siz sadece onun yere serilmesini sağlayın, yoksa HİÇBİRİNİZ bu işten paçayı kurtaramaz.
a85772b3	Gerçek zamanlı performans ayarı
a886e0f2	Kaputlar
a88ffeb4	Pist Yönü
a89d8f41	Sıra
a8cd6fd3	LAN sunucusu başlatılırken bir sorun oluştu. Ağ ayarlarını kontrol edip tekrar dene.
a8d823cf	ANNEX OFSET
a8da51cf	Devam etmeden önce doğum tarihini gir.
a8ddda95	SEVİYE 2 HİDROLİK
a92764b8	Harika sürüştü! Underground dergisi için kazanan arabanın fotoğrafını çekmek isteyen bir fotoğrafçı var. Yanına varmak için^45 saniyen var, yoksa çekip başka bir sürücü arayacak.^Yeri mini haritanda yanıp sönen sarı bir yıldızla işaretli, hadi acele et!
a929a45e	Rachel
a92b4ae8	Kaporta Parçalarını Değiştir
a93e10e9	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ Bileşen Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Bileşeni Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
a948a646	Arkadaş isteği gönderiliyor: %s ...
a94d67f4	Buraya Yaz
a959b6be	Kayıt Başarısız
a962aedf	Sokak yarışları yasa dışı ve tehlikelidir.^^Electronic Arts ve lisans verenleri, yasa dışı sokak yarışlarına katılımı onaylamaz ve teşvik etmez. Need for Speed™ Underground 2'de gösterilen yarışlar yalnızca evde eğlence amaçlıdır. Oyundaki sürüş sahnelerini gerçek hayatta tekrarlamaya kalkma.^^Sokak yarışı yapmanın tek güvenli yeri Need for Speed™ Underground'dur.
a96729e7	İlk arabanı seçerken iyi düşün. Onu bir süre kullanacaksın, o yüzden tarzına uyan bir araba seç. Dört çeker, önden çekişli ve arkadan itişli arabaların sürüşü ve yol tutuşu birbirinden farklıdır. Daha fazla bilgi için Araba Seçimi ekranındaki araba özelliklerine göz at.
a9877c52	Sıralama Tablosu:
a98a490d	GÖVDE 1
a98a490e	GÖVDE 2
a98a490f	GÖVDE 3
a98a4910	GÖVDE 4
a98a4911	GÖVDE 5
a98a4912	GÖVDE 6
a98a4913	GÖVDE 7
a98a4914	GÖVDE 8
a98a4915	GÖVDE 9
a98a492d	GÖVDE 10
a98a492e	GÖVDE 11
a98a492f	GÖVDE 12
a98a4930	GÖVDE 13
a98a4931	GÖVDE 14
a98a4932	GÖVDE 15
a997b866	Takılı oyun diskini çıkar ve %s diskini yerleştir.  Okunmamış mesajlarını ve kaydedilmemiş ayarlarını kaybedeceksin.
a9a76bba	Çözünürlük
a9ae9fbd	TİP 3 KIRMIZI & YEŞİL
a9ba6972	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
a9c27dfd	Alan Derinliği
a9c9c8f7	Rastgele
a9cfe581	Ekran X
a9d56ab6	PARLAK MOR
a9e93ff5	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$  Kategoriyi Varsayılana Sıfırla^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Geri^
a9e966d7	Bagaj neonu takabilmek için bagajını ÖZEL DÜZEN seviyesine yükseltmelisin.
aa3157b4	Performans Atölyesi
aa35ef4f	Race Breaker:
aa3cd907	Araba Yükle
aa3f09d8	Oyun Yükle
aa461724	400m HIZI
aa50aa02	Yarış yeniden başlatılsın mı?^Kaydedilmemiş yarış ilerlemen kaybolacak.
aa750253	GTI Magazine
aa78eb41	Bitiş Süresi:
aa816ba5	MAKAS
aa8959ad	Frenler
aa8c8e94	Galeri
aaabbd7a	Gelen Mesaj
aaae97a3	1 Pist Yarışı^1 Sprint Yarışı^1 Drag Yarışı
aab2ae0e	Sponsor ayrıntıları lazım.
aade3025	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
aae2b849	^3 Pist Yarışı
aafdff65	Direkt Port Nitro
ab0e817d	YÜKLENİYOR
ab1032fa	Atölyeye Gir /^Rakibe Meydan Oku
ab13cae4	Oyun oturumu oluşturulamadı.  Tekrar dene.
ab1f0e92	Hiç profil bulunamadı.
ab3ababa	Pigeon Park
ab432026	PARLAK MAVİ
ab44ed8b	SÜRE FARKI:
ab4fe4f5	1 Drag Yarışı^1 Sprint Yarışı^1 Street X Yarışı
ab635959	Varsayılan
ab6c5a1e	Arkadaşı Çıkar
ab7b635b	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Parça Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Yuva Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Bileşeni Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
ab7c8d59	Tebrikler!^Araban Need for Speed™^Underground 2 dergisinin kapağında yer alacak!
ab7eccff	Rachel
ab866fd6	FRANCAIS
ab868201	Bu, Bölge 1 yorumu
ab89d0f1	CALEB: Evet, ne olmuş, alt tarafı bir yarıştı! Bir daha olmayacak.
ab89d0f2	CALEB: Bunu yapamazsınız! Anlaşmamız var.
ab89d0f3	CALEB: Bakın, bana bir şans daha verin, onu yenebilirim...
ab89d0f4	CALEB: SEN...
ab89d0f5	CALEB: ...tam bir UĞURSUZLUKSUN. Seni bir kere saf dışı bıraktım, yine bırakacağım. Sana meydan okuyorum! Burada, hemen şimdi,
ab89d0f6	CALEB: Ortaya HER ŞEY konuyor! Var mısın, yok musun?!
aba1e56f	Dergi Para Ödülü
aba38cc3	TİP 3 YEŞİL
abb12765	5. SIRAYA ÇIKTIN
abb24bbc	Parça Değiştir
abba6482	Oyun Tamamlanma Oranı:
abca6aef	Lastikler
abd0ff14	Turbo
ac122037	Dördüncü oldun!
ac148579	Göstergeler
ac23ec52	Slammed & Stretched DVD Kapağı
ac399f5d	ANLAŞMA ŞARTLARI:^Sürücü şunları kazanmayı kabul eder: 5 URL yarışı, sponsorun seçeceği 3 yarış, sürücünün seçeceği 19 yarış.^^HALKLA İLİŞKİLER MADDESİ:^2 DVD kapağında yer alacak bir araba yap.^^BONUS:^Sponsor 1 araba hediye eder.
ac3a4f4c	mi
ac45fb67	Fren Dengesi — Fren dengesini arkaya kaydırmak, fren yaparken arabanın daha kolay dönmesini sağlar ama spin atmasına da yol açabilir. Kendi arabana ve sürüş tarzına uyan ayarı bul.
ac64572b	JL AUDIO AMFİ - 500 WATT
ac6dc003	SÖZLEŞME ŞARTLARI:^Sürücü şu yarışları kazanmalı: 7 URL yarışı, sürücünün seçeceği 29 yarış, sponsorun seçeceği 3 yarış.^^EK ŞARTLAR:^3 DVD kapağında yer alacak bir araba hazırla.^^BONUS:^Bayview'daki herhangi bir galeriden bedava araba.
ac7679cf	Need for Speed Underground 2'ye hoş geldin.^Bu demo, tam sürümdeki yüksek hızlı,^tempolu modifiye kültürü dünyasının küçük bir bölümünü sana yaşatıyor.^^^^^Kasım 2004'te çıkıyor
ac7937b4	Arka Cam
ac7bd52a	Dyno Grafiği
ac917213	Kabin neonu
acb8dff3	lb-ft
acc1f7da	Need for Speed™ Underground 2 sunucusuna şu an ulaşılamıyor.  Daha sonra tekrar dene.
acceab1e	Profili Kaydet
acdaecaf	ANLAŞMA ŞARTLARI:^Sürücü şunları kazanmayı kabul eder: 9 URL yarışı, sponsorun seçeceği 3 yarış, sürücünün seçeceği 34 yarış.^^HALKLA İLİŞKİLER MADDESİ:^4 DVD kapağında yer alacak bir araba yap.^^BONUS:^Sponsor 1 araba hediye eder.
aceaca19	ORİJİNAL
acf7765a	DEUTSCH
ad18d273	Doğum Tarihi Gir
ad1d90bb	Hidrolik
ad2fd00f	Yüzlerce görsel parçayla arabanı modifiye et,^tam istediğin görünümü yakala.
ad460262	Karbon fiber ya da alüminyum tavan kepçeleri boyanamaz
ad75e258	Dergi kapağı için son kareyi çekmeden önce önizleme özelliğini kullan ve araban için en iyi açıyı ve düzenlemeyi bul.
ad7f0cf9	Uygunsuz Mesaj
ad89ea7b	Varsayılana dön
ada7304b	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Renk Değiştir (Sol / Sağ)^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Rengi Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
adbbf215	DNAS doğrulanıyor, bekle...
adbc52f2	Şifremi Unuttum
adbfd917	LİDER TUR SAYISI:
ade22a0e	%s şu an oyunda ve davetini reddetti!
ade367b7	Araba Gösterisi
ae02b0ad	Tur Eleme yarışları
ae280d3d	EN İYİ TUR SÜRESİ:
ae5fc67d	Doğu Beacon Hill'deki Kaporta Atölyesini gözden kaçırma. Kafenin hemen arkasına saklanmış.
ae6a9a04	TİP 2 SAĞ TEKERLEK NOZULU
ae735e44	Frenle giriş
ae79fc42	Performans Egzozu
aeb6fd26	Yükleniyor
aec3f2e0	TİP 2 SOL ÜST VE SAĞ ALT NOZULLAR
aef20f6a	Mini Harita, ekran göstergelerinin sol alt köşesindedir. O an ulaşabileceğin yerler ve etkinlikler burada görünür. Dış halkada beliren simgeler, bulundukları yerin genel yönünü gösterir. Yeterince yaklaştığında bu simgeler haritadaki tam konumlarında belirir. Harita dönüşünü Ayarlar menüsünden değiştirebilirsin.
af000100	DNAS Doğrulaması
af089ff9	Kayıtlı Mesajlar
af0fd61d	ÇAĞLA NABIZ
af258ee8	Performans Atölyesi
af3dceee	Sesli sohbet davetinin süresi doldu.
af67346b	^^1 yıldızlı bir araba yaptığın için DVD kapağına çıktın!
af6943cb	EN İYİ TUR SÜRESİ:
af93fe34	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Özel Parçayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
afa49dec	Havalimanı
afeded91	İnd. %
aff55c52	Uyduya Ulaşılamıyor, ^ Yeniden Deneniyor...
afff7c7a	Bağlantıyı kesip çevrimiçi oynamayı bırakmak istediğine emin misin?
b054c635	240SX
b0792804	Şubat
b0819356	Diğer
b09c0334	N2O
b0bdbfee	TİP 1 İKİ SAĞ NOZUL
b0bf75ff	Tanıdıklarımdan biri az önce aradı: %s dergisinden bir fotoğrafçı şehirdeymiş, gelecek ayın kapağı için havalı arabalar arıyormuş. Haritadaki yıldıza git, oraya varınca seni arayıp ayrıntıları veririm.
b0bf7600	Güzel yarıştı dostum. Sokakta konuşulana göre %s dergisinden bir fotoğrafçı havalı arabalar arıyormuş. İlgileniyorsan mini haritadaki yıldıza git. Daha fazla bilgi alınca seni ararım.
b0dc76e7	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Parçayı Tak^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
b0fcf98e	EA Messenger
b1029122	Kazanılan URL Yarışları:
b10ae56f	Arabana Performans Ayarı / Dyno yapmak istiyor musun?
b12454ef	Oyun Oluştur
b13d6a9b	LAN Sunucusu Başlıyor ...
b18a5de4	Filtreyi Uygula
b18c1000	Bunu gerçekten takas etmek istiyor musun? ^Tüm modifiyeler gider ^ve fiyatının yalnızca yüzde 80'ini alırsın.
b1948b02	Civic
b197c58c	Corsa
b197d1f0	Coupe
b19f8a18	Hafıza Kartı
b19f8b41	Kaydet/Yükle
b1cdcf94	Focus
b1d77b95	Sesli Sohbeti Kapat
b1ee4ca9	Tamamlandı
b204477c	Arkadaş Listesi
b20601a3	IS 300
b229fa7e	Karbon Fiber Body Kitler
b236d659	Egzotik
b245f7fa	EN İYİ TUR
b2492820	MX-5
b263c898	Sponsorluklar
b285fd2b	Araban sürüşü kadar havalı da görünmeli. Çamurluk, kaput, spoiler, marşpiyel ve daha fazlası için uğrayacağın yer Kaporta Atölyesi.
b2a8d169	S2000
b2b15fc6	Bayview Aksesuar Atölyesi Doğu Beacon Hill şubesine hoş geldin. ^N2O Tahliyesi ve Ses Sistemi Düzeni 1'in kilidini açtın. ^Diğer Aksesuar Atölyelerinde açılan tüm parçaları burada da bulabilirsin.
b2bc8f3f	Supra
b2bdd862	TUR LİDERİ
b2ce8b59	Xbox Panosu
b2d0da8b	Yukarı: Gaz^Aşağı: Fren /^Geri Vites
b2f970e3	Eski araba parçalarının hepsi garaja gönderilir. Satın aldığın tüm parçaları arabana yeniden takabilirsin. Eski parçaları yeniden takmak istersen garajdaki parça değiştirme menüsüne gir
b2fad532	SARI NABIZ
b303e2b6	^^2 yıldızlı bir araba yaptığın için DVD kapağına çıktın!
b32908dc	Ön
b32f2b49	EA Hesap Adını Gir
b3421b53	6 İleri Şanzıman
b348f286	Düzen 1
b348f287	Düzen 2
b34993c9	Ayarlar
b34ab032	Şifre
b352039c	Durum
b35b3ac3	Oyuncu Seçimi
b368b7a5	Bu persona geçersiz ya da şu an kullanılamıyor.
b36e4b8d	Egzoz Uçları
b36e7c1e	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Düzen Türünü Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
b372757a	Street X yarışları dar ve teknik pistlerde yapılır. Parkurlar kısa ve sıkışık olduğundan kazanmanın en iyi yolu grubun önünde olmaktır. Bitiş çizgisini birinci geçmek için biraz kaporta sürtmekten çekinme.
b3838713	TİP 2 KIRMIZI & MAVİ
b3865091	TİP 2 KIRMIZI & ALTIN
b39c1f0b	Önceki
b3ab0d65	Alevler
b3bbb11d	Uyarı! Karbon fiber kaput takarsan arabandaki tüm kaput vinilleri kaldırılacak.
b3d1ea35	El Freni
b3da9890	İSKOÇYA
b3dc79a0	Güç
b3fb59a9	Performans Atölyesine dönülsün mü?
b4045365	Kariyer
b419c854	Araba bilgileri alınıyor ...
b423ff36	Hızlı Yarış Araba Seçimi
b44af78b	TİP 3 GÖK MAVİSİ & PARLAK KIRMIZI
b46342ba	Aksesuar Atölyesi
b4636fa7	SUV
b46377bc	U.R.L.
b49d6a3f	TİP 2 GÖK MAVİSİ & YEŞİL
b4a69455	Karbon Kaputlar
b4ebfd6f	Tek Turlu
b5074ab4	Araba Seç
b5180d22	ŞARTLAR:^3 URL galibiyeti, sponsorun belirleyeceği 3 yarışta galibiyet ve sürücünün seçeceği 9 ek galibiyetle sözleşme tamamlanır.^^TANITIM ŞARTLARI:^1 DVD kapağında yer alacak bir araba oluştur.^^BONUS:^Bayview'daki herhangi bir galeriden bedava araba.
b5205101	Sponsorlu Drift
b5242444	Yarış Kazanmak
b5423d02	Toz Boya
b55e7665	Ayrıntı Düzeyi
b55e7678	Düşük
b561dd7b	Drag İkincisi
b568418c	Maalesef bu modda GPS kullanılamıyor.
b575a5e2	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
b58fc812	Paket İçeriği
b5b3ab78	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
b5cbefb2	MAGAZINE_SETUP_GTFIN
b5d640b1	km
b5eaa702	Yanlış şifre girildi.
b6050914	Batı Beacon Hill'de, Burger King® restoranının yakınında bir Performans Atölyesi var. Girişe giden mavi ışıkları ara.
b6068c57	Çevrimiçi Yarış Modu Seç
b62e143c	Bu oyun oturumu artık mevcut değil.
b672f15a	Yoğun
b67da102	Süre
b6941c9d	^5. Aşamada 9. yarışını kazandığın için dergi kapağına çıktın!
b6aae6a6	Kişisel sıralaman sunucudan^alınırken bir hata oluştu.
b6aaecf7	Grafik Atölyesi
b6bb5e46	0-%d Süresi: %s
b6bd9c95	Az
b6cff09b	Gövde
b6d214e7	Bayrak
b6d444b4	Ön Viraj Demiri
b6d8e83b	Daveti Reddet
b6d9262d	Şifre
b6d9a479	Yırtık
b6db5bfd	Vahşi
b6de8c19	Serbestçe Gezilen Şehir
b6de8c1a	Performans Ayarı
b6de8c1b	Yeni Oyun Modları
b6de8c1c	Görsel Modifiye
b6de8c1d	Çevrimiçi Rekabet
b6f38223	Yeni/Düzenle
b709aca9	Persona siliniyor: '%s'...
b70f221f	SAMANTHA: Hey, şampiyon. Ortalığı kasıp kavuruyorsun.
b70ff4a4	El Freni
b7326e56	Burnout® 3: Takedown™ Demosu
b755f08b	En Az Oyuncu Sayısı
b75ba92c	Sokak Paketi
b75ba92d	Pro Paketi
b75ba92e	Ekstrem Paketi
b776e01c	Nisan
b7787c07	Aksesuar Atölyesi, arabanı kalabalığın içinde gerçekten öne çıkarır. Arabana hidrolik, neon, ses sistemi, spinner ve çok daha fazlasını eklemek için buraya gel.
b778dcae	ECU
b786af76	Kayıtlı profil sınırını aştın.^Yeni profil oluşturmadan önce SİL menüsünden eski profilleri sil.
b787dbc2	Street Tuner
b78e1834	TİP 3 KIRMIZI & MAVİ
b790e1b2	TİP 3 KIRMIZI & ALTIN
b791e455	JL AUDIO AMFİ - 1000 WATT
b7b75185	Pert Oldu
b7c84da4	Bu arabada takılı ön/arka tampon ve marşpiyelleri karbon fibere dönüştürme seçeneğini satın almak istiyor musun?
b7d0d273	Tuşları Varsayılana Sıfırla
b7d33921	Vites Düşür
b7f74a4c	Ara
b80e6a27	Bayview'un Performans Atölyelerindeki en iyi yükseltmelerle arabanın performansını zirveye taşı. Parçaları tek tek ya da paket ve kit halinde satın al. Paket halinde almak, parçaları tek tek almaya göre indirim sağlar.
b816dcc3	JL AUDIO AMFİ - 250 WATT
b82a976e	Race Breaker
b8387a0b	Çok Yavaş!
b847959e	Selam dostum, güzel yarıştı. Bu işi biliyorsun. Arabanı bambaşka gösterecek özel görsel parçalar ayarlayabilecek bir arkadaşım var. İlgileniyorsan haritandaki yıldıza git, seni arayıp yerini söylerim.
b847cbaf	Mart
b84a37fa	Bu performans paketi zaten takılı!
b881f9ea	Umutsuz
b884104a	Drift yarışlarında en yüksek puanları almak için pistin kenarındaki beyaz bonus alanlarında drift at. Duvarlara çarpmamaya dikkat et, yoksa tüm drift puanlarını kaybedersin.
b8a457e4	ORİJİNAL
b8cf16fc	0-100 km/sa:
b8ed90f3	Grup mesajı gönder
b8fce39a	Hotel Plaza
b8fe370e	KUMANDA BAĞLI DEĞİL
b90c04cd	Yeni egzoz uçları stoklarda. Arabana kendine has bir görünüm ve ses kazandır. Şimdi tüm Bayview Kaporta Atölyelerinde.
b9278dd5	Akıl Almaz Drift
b938cb4b	Performans Atölyesi
b94a4d03	Keşif Moduna Dön
b97124d2	Sıra:
b9ac83eb	Katmanları Yeniden Sırala
b9bcde4b	Ağ yapılandırmanda bir sorun oluştu.
b9c852e4	Sesli Sohbeti Bitir
b9d874dd	Performans parçası mağazalarının devi Megalow Parts'a hoş geldin.
ba010be9	Lastik Tutuşu — Daha fazla tutuş genelde daha iyi performans demektir. Ama Drift gibi bazı yarışlarda arabana daha kötü lastik takmak aslında işine yarayabilir.
ba0e1020	N2O Tahliye Testi
ba1cc49c	Egzoz Ucu
ba321d6e	Bu oyuncuyu engellemek için bu sesli sohbeti bitirmelisin.
ba613729	Sprint
ba7306aa	Kontrol Tipi
ba9cbe3f	Beni fena yendin kanka, ama araban sürüşü kadar iyi de görünmeli. Haritandaki yıldıza git, herkese satılmayan bomba gibi görsel modifiyeleri nereden bulacağını arayıp söylerim.
bac0f186	Başka bir oyuncu, sohbette bağırıp çağırarak oyun deneyimini bozuyor.
bad47443	Delikli Diskler
bb034ea6	Spoilerlar
bb0877c8	Doğu Coal Harbor
bb095ca1	DVD'ye Bak
bb12679e	Batı Coal Harbor
bb298a80	GEREKLİ
bb3d6d0d	KENWOOD ÇİFT LCD - 7 İNÇ
bb612d6e	Yeni tavan kepçesi tasarımları stoklarda. Okyanus ötesinden en yeni tasarımlar. Herhangi bir Bayview Kaporta Atölyesinde taktır.
bb6f0a6a	Bilgi Paylaşımı
bb836dcf	Süspansiyon
bbc2657b	KENWOOD LCD - 5.5 İNÇ
bbf1787d	Ortalama Hız:
bbf1f488	Hazır Değilim
bc0e6c55	Kariyer Zorluğu
bc25c6b1	Çevrimiçi Ana Menüye dönmek istediğine emin misin?  Bu oyun, istatistiklerine yenilgi ve bağlantı kopması olarak işlenecek.
bc2737b5	Ağ yapılandırmaları listesi alınırken bir hata oluştu.
bc3ab08e	Geri Bildirim İletildi
bc4c1f6e	Fort Union
bc4cae38	.
bc4ce12f	.
bc5662ab	EA GAMES™ TRAX
bc782557	Sıralama
bc8bf7f0	Pist İkincisi
bc964eee	HEADWIND OFSET
bcacb9a2	Vidalı Süspansiyon Sistemi
bcb18f38	Profil Yönetimi
bcdd9448	.
bcf1255f	ÇEYREK MİL HIZI:
bcf1e6e0	Kanka, sana kaybetmek koymadı ama arabana birkaç güzel dokunuş yaptırman lazım. Sana özel görsel parçalar ayarlayabilecek bir dostum var. Haritandaki yıldıza git, atölyenin yerini arayıp söylerim.
bcf9bcb2	3000GT
bd0ed1ff	SCE/Ethernet (Ağ Adaptörü)
bd383957	.
bd42a464	Önündeki arabalara dikkat et. Erken şerit değiştirirsen, olan bitenden habersiz trafikle çarpışma riskinden kurtulursun.
bd498562	.
bd620bb1	Tak
bd7ba1aa	Direksiyon (Sağ)
bd81116c	Ayarlar
bd88662d	Rahatsız Edici Davranış
bdac6a0c	Tarihi Onayla
bdaef57a	PARLAK SARI
bdb6560f	Arabanın görünümünü bir üst seviyeye taşı. En yeni jantlar az önce stoklara girdi. Tüm Bayview Kaporta Atölyelerinde.
bde2e94b	Çevre Detayı
bde6757f	Arka Koltukları Sök
be05e07f	ZAFER
be2750a0	Yarış Noktaları
be503981	Hayır
be5039a1	Açık
be70e1b7	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Parça Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Marka Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
be87ba52	Giovanna
bedf2b09	E-posta Adresi Gir
bf178f39	Konu: DVD Kapağı Fırsatı
bf23da34	KOYU SEDEF TURUNCU
bf2b2cbc	Simon
bf44adc8	360
bf470f81	Hey dostum, beni açık ara yendin. Araban da sürüşün kadar iyi görünsün diye sana yardım edeceğim. Haritadaki yıldıza git, seni arayıp daha fazla bilgi veririm.
bf47fc10	NIKKI: Aramız iyi, değil mi?
bf47fc11	RACHEL: Nikki artık BİZİM tarafta.
bf47fc12	NIKKI: Caleb kontrolü ele geçirince bir daha asla yarışamayacağını herkese söylüyor. Adam delirmiş...
bf47fc13	NIKKI: Arkanı kollasan iyi olur. Elimden geleni yaparım ama artık iş sende.
bf47fc14	CALEB: ... İnanılmaz! Siz ne işe yarıyorsunuz?! Hiçbiriniz o herifi saf dışı bırakamadı mı...? TEK biriniz bile mi?!
bf47fc15	CALEB: Kazanmaya devam ederse ne olacak sanıyorsunuz? Bütün bunlara veda edebilirsiniz, o çok değerli sponsorlarınıza...
bf47fc16	CALEB: ...avucunuza yağan bütün o yüzlüklere, HEPSİNE!
bf47fc17	WRAITHS ÜYESİ 1: Tamam, biz hallederiz.
bf47fc18	WRAITHS ÜYESİ 2: Bu sefer paçayı kurtaramayacak.
bf61e081	Arabayı Sıfırla (Aşağı)
bf8dfef0	N2O Tahliyesi
bf959bcc	Yarış Kategorisi: %s
bfb34120	Şanzımanı Sor
bfc91944	SMS'e (Kısa Mesaj Sistemi) hoş geldin. Oyun boyunca bilgileri bu sistemle alacaksın. Mesaj geldiğinde simge yanıp söner; mesajı okumak için SMS sistemini aç.^^Yarış etkinlikleri, mesaj göstergesinin üst kısmında simge olarak görünür. Atölyeye / Yarışa Gir tuşuna basarak etkinlik hakkında daha fazla bilgi alabilirsin.^^Her yarış türünün kendine ait bir simgesi vardır.^^Şehri, keşfettiğin bütün yarışları ve atölyeleri görmek için Şehir Haritasını aç. Burada etkinlikleri filtreleyebilir, GPS sistemini de etkinleştirebilirsin.
bfd1936f	Öne Geçtin!
c00b7eb0	Sokakların en keskin yol tutuşuna sahip ol. Yeni üst düzey süspansiyonlar yalnızca Bayview Performans Atölyelerinde.
c01a6f63	FENG: Varsayılan metin hatası.
c01ebece	Sesli sohbet daveti geri çekildi.
c034ce3d	Vinil Renkleri
c0398786	SMS mesajları
c03f9f19	Puan
c042c11c	Girilen şifre geçersiz.
c04643b0	Bu persona seçilirken bir sorun oluştu. EA Girişi ekranına döneceksin.
c05de3ef	Kanka, polis telsizinden duyduğuma göre Beacon Hill'e giden yollar artık açık. Garanti veriyorum, oradaki yarışlar yakında alev alacak. Bence oraya çık ve şansını dene.
c06e138a	Gelen Kutusu
c080d534	Şifren, bu hesapla ilişkili e-posta adresine gönderilecek.
c08af0b3	City Core
c08af0b4	Beacon Hill
c08af0b5	Jackson Heights
c08af0b6	Doğu Coal Harbor
c08af0b7	Batı Coal Harbor
c090500b	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Aşama Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
c092120a	$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$  Kategori Değiştir^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
c097dd69	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
c09b6bce	Profil Yönetimi
c0bedf15	Araba Seç
c0d29020	TİP 3 GÖK MAVİSİ & YEŞİL
c101e626	SPONSOR SEÇ!
c10d7979	İç Donanım / Aksesuar Değiştir
c11d723e	V2 SOL KAPUT HARİÇ TÜMÜ
c13875b2	Performans Atölyesi
c147e3ac	bekliyor
c19c3822	Birader, hiç de köyden yeni inmiş gibi sürmüyorsun. Haritandaki yıldıza git, o arabana nadir görsel parçaları nereden ayarlayabileceğini arayıp söylerim.
c1c8fd6b	Vinil Katmanları
c1d92693	Mini haritayı, sürerken ya da yarışırken sabit kalacak veya dönecek şekilde ayarlayabilirsin. Haritanın Keşif ve Yarış modlarındaki davranışını Duraklatma menüsündeki Oynanış ayarlarından belirle.
c1e0fb6b	Simon
c1ed97cf	Yükleme Başarısız
c20a08f1	Oyuna Dön
c23410e7	İMZA PARASI:  %$d
c260a751	En yeni kabin neonu renkleri artık takılmaya hazır. Seçeneklere tüm Aksesuar Atölyelerinde göz at.
c26bceb2	SÖZLEŞME ŞARTLARI:^Sürücü şu yarışları kazanmalı: 9 URL yarışı, sürücünün seçeceği 34 yarış, sponsorun seçeceği 3 yarış.^^EK ŞARTLAR:^4 DVD kapağında yer alacak bir araba hazırla.^^BONUS:^Bayview'daki herhangi bir galeriden ücretsiz araba.
c2867f37	Bu Yarışta Kazanılan Puanın Ortalamadan Farkı:
c2878ebc	Süren:
c2aefa2b	Sesli Sohbet Davetini Yanıtla
c2bb742c	TİP 2 KIRMIZI
c2be294d	0-%d Süresi:
c2cd8cad	TİP 3 KIRMIZI
c2e59520	LAN modundan çıkmak istediğine emin misin?
c304fa53	Odadan şimdi ayrılırsan bu oyun oturumu sona erer. Ayrılmak istediğine emin misin?
c32b0a50	Modified to the Max DVD Kapağı
c3303625	Grafik Atölyesi
c33d7ae7	Diğer oyuncu, kazansın ya da kaybetsin oyunu centilmence oynayan iyi bir rakip.
c35dd09e	Dergi Kapakları:
c35e2357	Burnout Mesafesi: %$3.2f %s!
c3755f6d	Kazanılan Yarışlar
c3836997	Motor Yönetim Ünitesi
c3989011	Jantlar
c3a914f6	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Geri^
c3cabafd	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Araba Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Arabayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Keşif Moduna Dön^
c3cd7c45	Speed Demons 3
c3e5bcdc	Keşif Moduna Dön
c3e9ae58	Tampon
c4144667	ANLAŞMA KOŞULLARI:^3 URL yarışı, sponsorun seçeceği 3 yarış ve sürücünün seçeceği 9 ek yarış kazanılınca sözleşme tamamlanır.^^MEDYA ŞARTLARI:^1 DVD kapağında yer alacak bir araba yap.^^BONUS:^Bayview galerisinden bedava araba.
c419592e	Pist Adı:
c42392f4	Vites Oranları — Orijinal vites oranların günlük sürüş için iyidir ama onları ayarlamak daha iyi hızlanma ve daha yüksek azami hız sağlayabilir. En iyi sonuç için tüm viteslerini ve Son Dişli Oranını birlikte ayarla.
c4260f7c	BREZİLYA
c42eaba0	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
c431600c	BURNOUT MESAFESİ:
c43176d4	Karbon Fiber Spoilerlar
c436f812	Modern
c43cb6fb	HAFIZA KARTI yuvası 1'deki hafıza kartı (PS2) ^çıkarıldı. Otomatik Kayıt açıkken ^devam etmek istiyor musun?
c4476a7b	Şanzıman tipi
c44a6515	Serbest Sürüşe Dön
c44a7ee2	Kurulan Oyun:
c44d3943	Tur Rekoru
c4553f70	Viraj demirleri, arabanın sol ve sağ tarafı arasındaki ağırlık aktarımını etkiler. Ön ve arka viraj demirlerinin sertliğini sürgülerle ayarla. Yumuşak demirler arabanın yatmasına izin verir, sert demirler ise arabaya go-kart hissi verir.
c476882b	Drift Ayarı
c48a4103	Daveti Oku
c49c11fe	Weld
c4afdea1	TİP 3 SAĞ ÜST VE SOL ALT NOZULLAR
c4b5cff2	Yeni cam filmi renklerimizden biriyle şehrin en taze görünümüne kavuş. Seninkini bugün herhangi bir Bayview Aksesuar Atölyesinde taktır.
c4c2638c	STANDART DÜZEN
c4c5d271	Bu boyayı mevcut seçimine eklemek istiyor musun?
c4c7edbe	Başka bir oyuncu, oyunun olağan ve kabul görmüş kurallarının dışına çıkarak kazanmaya çalışıyor.
c4cc1a95	TİP 2 FUŞYA & MAVİ
c4df3b44	Hedef bölgeye zamanında varamadın. ^Tekrar denemek istiyor musun?
c4e42eb4	Fotoğraf Çek
c4f4678e	Bu arabayla yarışmak istiyor musun?
c50fa35f	Mono
c5146fe8	Siyah
c54e4d70	KANADA
c572f4e9	İlk Araba
c583d824	Kaporta Atölyesi
c5ac0f31	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
c5c25c87	Bu EA hesabı bir CD anahtarıyla doğrulanmamış.  Çevrimiçi oynayabilmek için CD anahtarını bir EA hesabına bağlaman gerekiyor.  Bir CD anahtarı yalnızca tek bir EA hesabına bağlanabilir ve bu işlem geri alınamaz.  CD anahtarını bu EA hesabına bağlamak istiyor musun?
c5c27a17	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
c5f7902c	Sponsorlu StreetX
c6089ca7	Boya / Vinil Değiştir
c613b25f	Grafik Atölyesi
c6141ca1	Underground 2'de sadeden çılgına uzanan bir sürü yepyeni^parça tasarımı bulacaksın! Demo sürümünde burada iki^özel kit var. İkisini de takıp bir dene!
c6269082	Keşif Harita Modu
c628beca	ENGLISH
c6462d9a	TİP 1 İKİ KAPUT NOZULU
c6588e19	DNAS logosu, Sony Computer Entertainment Inc. şirketinin ticari markasıdır.
c6590bc2	Özel Oyunlar
c6644a5f	SPREY ŞOVU
c6923ecd	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
c6b7eb02	Şehir Haritasında Göster
c70af893	Yeni far tasarımlarımızdan biriyle modifiyeli görünümünü bir üst seviyeye taşı. En yeni modeller Bayview Kaporta Atölyelerinde. Seninkini hemen al.
c7228aa0	KOYU TURUNCU
c744b7ab	Arkadaş isteği reddediliyor: %s ...
c76c65b4	400m Süresi: %s^400m Hızı: %$3.2f km/sa
c786c4e7	Underground Racing League
c7993f9a	Dergileri Gör
c7a32132	Motor neonu
c7ca52ed	Ayarlar
c7da078e	Yarış Sonrası İstatistikler
c7e1420c	Ana Menüye Çık
c7e6e649	Lastiklerinin seviyesi, arabanın yola ne kadar iyi tutunacağını belirler. Daha az ya da daha fazla tutuşlu lastikler arasında seçim yapmak için sürgüleri ayarla.
c8054ce0	Yeni Araba Modifiye Et
c82976ea	Yön Tuşları
c835538e	Bagaj Düzenini Değiştir
c85f0389	Kabul Ediyorum
c8983262	Kime: %s
c8988f48	V1 SOL TEKERLEK HARİÇ TÜMÜ
c8a8009c	GTI Magazine
c8b8fbf1	ECU Tork Eğrisi
c8b91418	Grafik Atölyesi
c8bfcf5d	Stage 1 Turbo Kiti
c8d23393	Bagaj Düzeni
c8eb64b7	Başka biri senin hesabınla giriş yaptığı için Xbox Live oturumun kapatıldı.
c913bf6f	TİP 3 FUŞYA
c91a3fde	LAN sunucusuyla bağlantın koptu. Ağ kablonun takılı olduğundan emin ol. Ana menüye döndürüleceksin.
c91b17f1	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
c91d620f	Sportmenlik
c923c8ff	Gizli yarış bilgileri
c92db340	Son özel ayarını geri yüklemek istediğine emin misin?
c93f1717	Çeyrek Mil Süresi:
c93fbfb5	Sıralama Tablosu
c9602134	Makinene en yeni neon renklerini taktır, ekibinin yanına ışıl ışıl gel. Şimdi tüm Bayview Aksesuar Atölyelerinde.
c967aee0	Katılınan Yarış:
c96f4170	Daha iyi frenler takarak arabanın duruş mesafesini kısalt.
c975960a	TİP 3 YEŞİL & MAVİ
c9785f88	TİP 3 YEŞİL & ALTIN
c97a2d22	Bitiş Süresi
c9a64efb	İkinci oldun!
c9a967c4	Sağ Kapı
c9ba9e3e	Garaja gidilsin mi?
c9c5976e	Kayıtlı Mesajlar %d / %d
c9dc5bb7	Daveti Kabul Et
c9e0946b	Bayview Kaporta Atölyesi
c9e362a2	%s daveti iptal etti.
c9f7f7e5	KİLİTLİ
c9fd0980	Xbox Live bağlantın koptu. Ağ kablonun takılı olduğundan emin ol. Ana menüye döneceksin.
c9fe8f8f	BREZİLYA
ca169c60	Street X Ayarı
ca38d55f	Çevrimiçi Ana Menü
ca3ab03f	TİP 3 TÜM NOZULLAR
ca495b29	Semtler
ca50bbc6	Arabanın "yıldız puanını" yükselterek her dergi kapağından kazandığın parayı artır. Arabanın puanı ne kadar yüksekse o kadar çok para kazanırsın.
ca538367	^4. Aşamada 3. yarışını kazandığın için dergi kapağına çıktın!
ca89507e	SPONSOR ARABASI YERİ
cab262de	Orta
cabfc328	A3
cabfc5bc	TT
cadb45d2	Favori Sürüş Kamerası:
caee48f5	EA sunucusuyla bağlantın koptu. Yeniden bağlanmak ister misin?
caf6d39e	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  İmleci Sola / Sağa Taşı^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$  Sil^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön
cb22b3f5	Hız göstergesini mil yerine kilometre gösterecek şekilde değiştirmek için Duraklatma menüsünde önce Ayarlar'ı, sonra Oynanış'ı seç.
cb26cd83	KANADA
cb2afc50	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Pisti Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
cb35c4de	Asıl para Underground Racing League'de. Bu yarışlar kapalı pistlerde yapılır ve en üst düzey sürüş becerisi ister. URL rakipleri sokakların en iyi yarışçılarından oluşur; o yüzden bir vites yükselt.
cb3817de	Kaporta Atölyesi
cb5d2fcd	Outrun Düellosunda amaç, rakibinin önüne geçmek... ve sonra onu atlatmak! Öndeyken istediğin yoldan gidebilirsin. Gerideysen lidere yetişip onu geçmeli ve yarışın kontrolünü ele almalısın.
cb5e3178	Ana menüye dönmek istediğinden emin misin?
cb5e7e4a	İlk Sürüş
cb6b7cff	Cinsiyet
cb881919	Gamertag
cbadb253	Karbon Aynalar, Spoilerlar, Tavan Kepçeleri
cbb549d5	Sokakların gördüğü en müthiş spoilerlar stoklara girdi; şimdi herhangi bir Bayview Kaporta Atölyesinde.
cbbc6512	bg
cbbc8bf8	KM/SA
cbbc92fe	Maksimum
cbbc93fc	Minimum
cbbcb1c5	İpucu
cc01c4e7	DRIFT
cc3401e9	Toz Boya
cc3c446a	KURUKAFA 4
cc3c798b	Titreşim:
cc3d71e7	TOMMY: Hey, bak dostum, elimizdeki her şeyin özünde sokak drag yarışları var!
cc3d71e8	TOMMY: Şimdi kulak ver--rakiplerin önüne geçmenin anahtarı devir.
cc3d71e9	TOMMY: Kalkıştan sonra sıra vitese gelir; başarının babası odur, yani azami güç için vitesi tam zamanında at!
cc3d7202	TOMMY: Öteki herif seni geçerse kafana takma, arkasına yapış ve rüzgar arkasına gir. Değerli hızı topla, sonra hamleni yap ve yanından süzülüp geç.
cc3d7203	TOMMY: Bu iş BÜYÜK olacak kanka! Hazır mısın?! Güzel, çık ve kendini kanıtla.
cc3d720a	TOMMY: Bak şimdi--drift tamamen tarz ve kontrol işidir.
cc3d7222	TOMMY: Şu üç kelimeyi aklına yaz: hız, direksiyon ve el freni. Sana yüklü puanları getirecek o tatlı hareketleri kurmanın sırrı bunlarda!
cc3d7223	TOMMY: Frene fazla asılma, çünkü ne kadar hızlı gider ve ne kadar çok kayarsan puanın da o kadar yüksek olur.
cc3d7224	TOMMY: Bu puan alacağın çarpanı belirler; o çarpan da bir sonraki driftinin puanını etkiler, yani yüksek tut!
cc3d7225	TOMMY: Bütün bu detayları bir araya getirdikten sonra driftleri birbirine bağlamaya başlaman lazım.
cc3d7226	TOMMY: Kendine güveniyorsan, şimdi B-Ü-Y-Ü-K oynama zamanı! Bonus puan için lastiklerini banketten sarkıtmayı dene!
cc3d7227	TOMMY: Hadi birader, işe koyulalım ve şu sokakları ısıtalım!
cc3d7266	TOMMY: Bu driftte dağdan aşağı kaya kaya ineceksin; evet, zirveden başlayıp en dibe kadar yolunu açacaksın.
cc3d7267	TOMMY: Her şey üstüne hızla gelecek; o yüzden daha önce de duyduğun gibi hız, direksiyon ve el freni burada çok önemli.
cc3d7268	TOMMY: Yalnız trafiğe çakılmamaya dikkat et; yerliler olaydan habersiz, yani eninde sonunda önüne çıkacaklar.
cc3d7269	TOMMY: Ama aynı zamanda, bu saflar karşına çıktığında arabalarına ikinci derileri gibi olabildiğince yakın sokul; çünkü yanlarına kayıp virajlarda onlara sarılırsan, bu şov için yüklü puanlar kaparsın!
cc3d726a	TOMMY: Tabii ki hız, çarpanını yüksek tutar. Puanlar yağmaya devam etsin istiyorsan o çarpanı alabildiğine yukarıda tut.
cc3d726b	TOMMY: Artık ne yaptığını biliyorsun; gaza sonuna kadar bas ve BÜYÜK oyna! Dağın eteğinde görüşürüz!
cc3d7289	TOMMY: Hey, dinle! Street X'i iliklerine kadar hissetmek üzeresin. Bu, yarış dünyasını sallayan en ateşli yeni akım!
cc3d728a	TOMMY: Bu pistler DAR. Virajları dönmek için çok az yer var, o yüzden arabanın ayarlarının tam oturduğundan emin ol.
cc3d728b	TOMMY: Öteki herifi burnunun dibinden atmak için ne gerekiyorsa yap, çünkü olman gereken yer iç çizgi.
cc3d728c	TOMMY: Yani arabanı kısa ataklara ve sıkı, yere yapışan bir kontrole göre ayarla.
cc3d728d	TOMMY: Ne dediğimi anlıyor musun? Tamamdır, çık ve ortalığı yık birader!
cc438b1e	Mesaj %d / %d
cc62c8be	MAKS
cc6c959f	Oyun oluşturuluyor...
cc76dee5	URL Ayarı
cc89dc24	İç Panelleri Sök
ccbc22b3	0-60 mph:
ccc6b264	EA sunucuları şu an sorun yaşıyor. Daha sonra tekrar dene.
ccd1a5d8	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$  Sohbeti Kaydır^$JOY_EVENT_FENG_BUTTON2$ $ICON_SPACER$  Sohbet^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
cd085170	Tork eğrisi, turbonun devir aralığı boyunca ürettiği gücü gösteren bir grafiktir. Gücü, yarışta en çok kullanacağın devir aralığına kaydırmak için eğrinin şeklini ayarla.
cd432be5	Tur Bilgisi:
cd738a1a	Dergi Fotoğraf Çekimi
cd787311	Bu kişiyi EA Messenger'dan çıkarmak istediğine emin misin? Bu kişiden gelen okunmamış tüm mesajlar kaybolacak.
cd87aa12	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  İmleci Sola / Sağa Taşı^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$  Sil^$JOY_EVENT_FENG_RTRIGGER$ $ICON_SPACER$  BÜYÜK HARF^$JOY_EVENT_FENG_LTRIGGER$ $ICON_SPACER$  Özel Karakterler^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön
cd9fdafd	Auto Motor
cda93fae	Dostum, cidden bizimle drift atmayı düşünmüyorsun, değil mi? Şansın olması için bile çok yüksek puan toplaman gerekecek. O çıtaya uzanabilir misin, bilmiyorum. Belki bu seferlik pas geçmelisin.
cda93faf	Dostum, sokaklarda sürüşünü gördüm; yolun bir o yanına bir bu yanına yalpalayıp duruyorsun. Zaten düz gidemediğine göre bu Drift yarışı tam sana göre.
cda93fb0	Şaka yapıyorsun, değil mi? O hurdanın drift atmasına imkan yok. Burası çiftlik değil dostum, burası büyük lig. Hakkını versen iyi olur.
cda93fb1	Şaka mı bu? Bizimle yarışmak için D-R-İ-F-T arabası lazım. Sırf o hurdayı kaydırabilesin diye parkuru yağa bulayacak değiliz. Evine gitsene sen?
cda93fb2	Efendi bir çocuğa benziyorsun. Evine koşup annenin arabasını geri versene? Hala yarışmak istiyorsan, anneciğinin arabasını kaybettiğin için ev hapsi yemeye hazır ol. Karar senin kanka, yeter ki beni sabaha kadar bekletme.
cda93fb3	O kafanın içinde neler dönüyor oğlum? Buraya acınası bir hurdayla gelip yarışmana izin vermemizi mi bekliyorsun? Neyse, bütün gece stoplarımı seyretmek istiyorsan bunu yasaklayan bir kanun yok.
cda93fb4	Bak dostum, galiba sen de olaya dahil olmak istiyorsun. Şöyle yapalım: Sırf sana bir şans tanımak için 4. vitesin üstüne çıkmayacağım. Böylece belki bitiş çizgisini birinci geçişimi görebilirsin. Yetişmeye çalış, taşralı.
cda93fb5	Hooop, sürücü! Sana diyorum ezik! Biraz drift atmaya hazır mısın oğlum? Seni sabaha kadar bekleyemeyiz. Var mısın, yok musun?
cda93fb6	Hey oğlum! Bu Drift yarışına girmeden önce iki kere düşün, çünkü bu tipler üstüne çok sert gelecek. Katılacak kadar deli misin, değil misin?
ce04c2fc	Okunmamış Mesajlar %d / %d
ce0a7276	N2O tahliyesi için yepyeni yerleşim seçenekleriyle tarzda çıtayı yükselt. Bölgedeki tüm Bayview Aksesuar Atölyeleri sana müthiş bir kurulum ayarlayabilir.
ce497c51	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Önizle^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
ce50da14	Çevrimiçi Ana Menüye dönmek istediğine emin misin?
ce5a65dd	^3. Aşamada 2. yarışını kazandığın için dergi kapağına çıktın!
ce62c0bf	Ödülleri Gör
ce678ad3	İsim
ce77d7c8	Vites Oranları
ce7ce385	YIRTIK 1
ce7ce386	YIRTIK 2
ce7ce387	YIRTIK 3
ce7ffaac	Gövde Vinili
ce8edab8	ft.
ce9a2532	Oyun Lobisi
ce9f1a96	Ne haber güzelim? Hop, sen Rachel değilsin. Onun evinde kalan şu köylü sen olmalısın. Sprint yarışı yapıyoruz, girmek istiyorsan çıkar paraları. Köyde de büyük şehirdeki parayı kullanıyorsunuz, değil mi? Parkur için haritaya bak. Kalıyor musun, gidiyor musun?
cea71f0e	Bölge
ceb35461	MODİFİYE HATA AYIKLAMA
ceb3ff94	Oynanan^Oyun
ceb58b89	VAHŞİ 1
ceb58b8a	VAHŞİ 2
ceb58b8b	VAHŞİ 3
cebde67f	Navigator
cebfaa36	Azami Hız
cee2f041	Yarış
cf3b2d70	ÜCRETSİZ sponsor arabanı^ yakındaki galeriden al.
cf41cc19	Ağ Sorun Giderici
cf4e278c	SHIFT
cf4f80c2	Profil Yok
cf52681a	BOŞLUK
cf758326	SMS Kullanımı
cf8cb898	Selam birader. Kendime yeni bir araba almayı düşünüyorum ve biraz bağışa ihtiyacım var. Davaya ufak bir katkıda bulunmaya hazır iki kişiyi şimdiden ayarladım. Sen de parayı ortaya koy, ben de seni fazla rezil etmemeye bakarım, ne dersin?
cf8cb899	Hey, adını duyduğum şu yeni çocuk sensin. Söylentiye göre biraz yeteneğin varmış. Ortaya para koyup büyük abilerle aynı masada oynayabilir misin, görmeye ne dersin? Hadi parayı bas, parkuru sana yollayayım.
cf8cb89a	Hoppala enayi! Araban bir poker eli olsaydı, şu an kartları atıp çekilirdim. Benim kent rengimi yenecek elin olduğunu mu sanıyorsun? Hadi kartları açalım da parkurda görelim.
cf8cb89b	Hey birader, ceplerimde senin paran için hala yer var. Şu yarışı bitirelim de senin paranla sevgilimi yemeğe çıkarayım, ne dersin?
cf8cb89c	Bak buraya ezik. Bu iş şakaya gelmez. Yeşilleri ortaya koy ve kaybetmek için sıraya gir. Ciddi olduğunu anladığımız an rotayı alırsın.
cf8cb89d	Buyur gel birader. Kaybedenlere her zaman yer var. Burası köye benzemez. Paranı koyduğun an parkur haritası sende. Eee, var mısın, yok musun?
cf8cb89e	Kısa keseceğim. Sen parayı koyarsın, biz de rotayı veririz. Gerçek yarışlara hazır mısın?
cf8cb89f	Hey dostum, korkak olmadığını kanıtlama şansın bu. Pist yarışı yapıyoruz ve daha fazla sürücüye yer var. Katıldığın an parkur haritası belirecek. Hadi, anneni gururlandır.
cf8cb8a0	Hey, sen!... Buralı değilsin sen! Ama fark etmez. Pist yarışında kapışıyoruz. Paraları ortaya koy, parkur haritasını SMS'le yollayalım. Karar vermek için iki saniyen var!
cfbedb50	Araba Farları
cfcc5d73	Dış Halka Ters
cfcc5d74	Batı Otoyolu Ters
cfcc5d75	Doğu Otoyolu Ters
cfcc5d76	Jackpot Ters
cfcc5d77	Garibaldi Run Ters
cfcc5db6	Serpantin Ters
cfcc5db7	Sahil Boyu Ters
cfcc5db8	Park Drive Ters
cfcc5e39	Gözlemevi Ters
cfcc5e3a	Bellavista Ters
cfcc5e7b	Palm Highway Ters
cfcc5e7c	Ambassador Ridge Ters
cfcc5e7d	University Hill Ters
cfcc5e7e	Marine & 25th Ters
cfcc5e80	Woodbine Park Ters
cfcc5e81	12th & Arbutus Ters
cfcc5e82	Bayview International Ters
cfcc61b5	Palomino & 16th Ters
cfcc61b6	Güney Kavşağı Ters
cfcc61b7	Üst Tribün Ters
cfcc61b9	Cypress Bowl Ters
cfcc61ba	Maraton Ters
cfcc61f8	Wall Center Ters
cfcc61f9	Tampon Tampona Ters
cfcc61fa	Sentinel Hill Ters
cfcc61fc	2nd & Bellevue Ters
cfcc627b	Eagleridge Estates Ters
cfcc627c	4163 Ters
cfcc65f5	4201 Ters
cfcc65f6	4202 Ters
cfcc65f7	4203 Ters
cfcc6616	Merkez Garı Ters
cfcc6617	Sahil Ekspresi Ters
cfcc6618	Manevra Sahası Ters
cfcc6637	Güney Pisti Ters
cfcc6638	Pist 15 Ters
cfcc6639	Pist 9 Ters
cfcc6e77	4401 Ters
cfcc6e78	4402 Ters
cfcc6e79	4403 Ters
cfcc6e7a	4404 Ters
cfcc76f9	Sanayi Bölgesi Pisti 1 Ters
cfcc76fa	Sanayi Bölgesi Pisti 2 Ters
cfcc76fb	Sanayi Bölgesi Pisti 3 Ters
cfcc76fc	Sanayi Bölgesi Pisti 4 Ters
cfcc76fd	Otopark Pisti 1 Ters
cfcc76fe	Otopark Pisti 2 Ters
cfcc76ff	Otopark Pisti 3 Ters
cfcc7700	Otopark Pisti 4 Ters
cfcc7b3b	Bayview Speedway Pisti 2 Ters
cfcc7b3c	Bayview Speedway Pisti 3 Ters
cfcc7b3d	Bayview Speedway Pisti 4 Ters
cfcc7b5c	Havalimanı Pisti 2 Ters
cfcc7b5d	Havalimanı Pisti 3 Ters
cfcc7b5e	Havalimanı Pisti 4 Ters
cfcc7b5f	Havalimanı Pisti 5 Ters
cfd1b203	YUNANİSTAN
cfec91a2	Şehir Haritası
d00905f2	Tüm Harita
d02c18bc	Dikiz Aynası:
d0547a0d	JETSTREAM OFSET
d07cac18	İşler ciddi evlat. URL öyle hafife alınacak bir yarış değil. Bu adamlar sonuna kadar bastıracak, kazanmak için eğip bükmedikleri kural kalmayacak. Sıkı dur ve sakın arkalarda kalma.
d07cac19	Bu sefer işini ciddiye alsan iyi olur, çünkü URL hızın daniskası. Burada caka satan çaylaklara yer yok. Şov yapayım derken çuvallarsan burada bir daha yüzüne bakan olmaz.
d07cac1a	Şöyle bak: Bu sürücüler buraların en iyi asfalt kurtları. Onlara karşı sonuna kadar bastır, yoksa caka sattığını hemen sezer ve seni fena patlatırlar. Şimdi dağılırsan URL senin için hayal olur. Bu işi hakkıyla yapsan iyi edersin.
d08ddc6b	Başka bir oyuncu rahatsız edici davranıyor.
d0942448	Denk
d0ad7875	Gizli Atölyeler
d0b3953b	En Yüksek Oyuncu Seviyesi:
d0b86077	ft
d0ba5d76	%s davetini reddetti!
d0cf6ee1	Oynanış
d0efbea3	EA Messenger
d0f75ade	%s adlı profili kaydetmek istediğinden emin misin?
d1009b34	Zayıf Bağlantı Uyarısı
d104ad36	Çıkartmalar yalnızca orijinal kaputa uygulanabilir.^Çıkartma uygulamak için orijinal kaputu geri takmalısın.
d10d7477	Fragmanlar
d11ecd79	Tamamlanmadı
d132a6fe	Tasarımı Yükle
d13bd9ce	Yön Tuşları
d14ddf21	Ara
d152ed92	Başka bir oyuncu sohbet odalarında sürekli müstehcen veya kaba bir dil kullanıyor.
d155595a	Bu oyun oturumu dolu.
d157c200	Bir oyun odasına girersen okunmamış mesajlarını ve oyun davetlerini kaybedebilirsin.
d1619868	TOMMY: Doğru anda kalkış yap ve roket gibi liderliğe fırla.
d1619869	TOMMY: Ama ağır davranırsan kendini grubun en arkasında bulursun.
d1619ca9	TOMMY: Unutma, çok erken--ya da çok geç--basarsan sonuncu gelirsin.
d1629be5	TOMMY: Driftlerini tek bir uzun, kesintisiz kaymada birleştir, skor tablosu resmen yanıp tutuşsun!
d162a026	TOMMY: Şeritlerden ne kadar çok lastikle kayarsan puanı o kadar hızlı toplarsın. Yalnız duvarlardan uzak dur, yoksa o serinin bütün puanlarını kaybedersin.
d1644dcb	TOMMY: Virajlara giriş ve çıkışta en iyi çizgiyi tutturmak sana ciddi zaman kazandırır.
d16d5d1e	Kayıtlı oyunun üzerine yazılsın mı?
d183936b	Profilin kaydedilemedi.^Otomatik Kayıt kapatılacak.
d1ac60be	Bunu satın almak için yeterli paran yok.
d21d4e8a	Yeni Gövde Vinili koleksiyonumuzla kalabalıktan sıyrıl, arabana taze bir görünüm kazandır. Herhangi bir Grafik Atölyesinde.
d23814c6	Yorumlar:
d24b682e	Araban
d24c5678	Sıçrama
d2822102	Sohbet Sesi
d286be3a	Motor detayı renklerini seçebilmek için arabanda tüm 3. seviye^motor, ECU ve turbo yükseltmeleri takılı olmalı.
d28a8bcd	Kabin neonu
d2982464	Şeritler
d29a1a18	Şifre uzunluğu geçersiz.^Şifre %lu ile %lu karakter arasında olmalı.
d2e7035e	Avus
d2e889da	Donz
d2e9a3e4	Foxx
d2ed7917	Momo
d2eddffb	NFSU 2
d2f037d5	Rota
d2f2685b	Volk
d2f2f582	Work
d306272f	CALEB: Sana 'Ne gerekiyorsa yap' DEDİM. Bunun neresi kafana girmedi?!
d3062730	NIKKI: Çekil önümden! Ben temiz yarışırım!
d3062731	CALEB: Kiminle konuştuğunu unutmasan iyi olur--
d3062732	NIKKI: Yoksa? Sana ihtiyacım yok.
d3062733	CALEB: Ya, öyle mi? Bensiz ne yapacaksın? Sen bir hiçsin.
d3062734	CALEB: Her şeyin kontrolünü ele geçirmem an meselesi.
d3062735	NIKKI: O zaman belki de buna ben engel olurum.
d31407e7	Şanzıman
d3213604	Bu gece ortalığı alev alev yakıyoruz oğlum. İşine baksan iyi olur, çünkü sponsor parlak bir galibiyet bekliyor. Altıncı vites, gaz dibe; yoksa bu gece kimse mutlu dönmez.
d33186ad	POWERSLIDE
d333fde2	^2. Aşamada 4. yarışını kazandığın için dergi kapağına çıktın!
d352fe3a	FRANSA
d3588630	Geniş Ekran
d36620fe	Yeni profil oluşturursan mevcut profildeki kaydedilmemiş tüm değişiklikler kaybolur. Yeni profil oluşturmak istediğinden emin misin?
d3764387	Filtreyi Uygula
d37939df	Stage 3 Turbo Kiti
d38df194	Kamera Değiştir
d3a4d4e0	Sprint yarışını kabul etmek istiyor musun?
d3e04e45	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ Parça Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Parçayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
d3e8b668	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ Kaydır^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Seçimi Onayla
d4261e6d	Xbox Live hizmeti şu an çok yoğun.  Daha sonra tekrar dene.
d4293449	Bitirdi
d447b268	Yanıtla
d44eb6ca	ALPINE 1 ÇİFT LCD - 7 İNÇ
d4568855	WRAITHS ÜYESİ 1: Şuna bak! Kuzeyin koca şampiyonu gelmiş!
d4568856	WRAITHS ÜYESİ 2: Yok be, olamaz! Bu şampiyondan çok şamar oğlanına benziyor!
d4568857	NIKKI: Demek bütün bu yaygara SENİN için koparılıyor? Heh, bana pek matah görünmedin.
d4568858	CALEB: Heh, aynen öyle.
d4568859	NIKKI: Hiç şansın yok, kahraman--ne pistte ne de dışında.
d461c58a	BAŞLA
d472772b	Arabana en yeni ışıkları tak, dostun düşmanın kimin geldiğini anlasın. Yeni renkler şimdi tüm Aksesuar Atölyelerinde.
d47554e5	İNTİHAR
d478421f	Kamera Değiştir
d4827e5f	Sürüş kontrollerini Ayarlar menüsünden kendine göre düzenle. Sürüş tarzına en uygun düzeni seç; otomatik ya da manuel şanzımana karar ver ve denge kontrolünü aç.
d48fba40	Oyuna katılınıyor: '%s'
d4966f2c	Bu e-posta adresiyle ilişkili tüm EA hesap adları kısa süre içinde gönderilecek.
d4978f8c	Mini Harita Kullanımı
d49fed27	Aşama %d - %s Gizli Atölyeleri:
d4abf03d	Davet Eden:
d4c40ceb	Tribal
d4d01b7e	Yarış Sonuçları
d4d3af38	ALPINE 1 LCD - 5.5 İNÇ
d5344356	Ağ başlatılıyor ...
d553e45a	Özel Performans Yükseltmesi
d55ad357	Tribal Seti
d56afe23	Giriş Durumu
d59232b4	KOYU SEDEF SARI
d5aa3216	YUNANİSTAN
d5d46fdf	Çevrimiçi oynamayı bırakmak istediğinden emin misin? Okunmamış tüm mesajlar silinebilir ve bekleyen tüm meydan okumalar iptal edilir.
d5f3f0e0	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
d616e55a	Hazır olmayan oyuncular çıkarıldıktan sonra oyunu başlatmaya yetecek oyuncu kalmadı!
d63b6982	LAN ana menüsüne dönmek istediğine emin misin?
d649be08	Motor neonunu kullanabilmek için tüm 3. seviye motor, ECU ve turbo yükseltmelerini takmalısın.
d655df00	Sürüş Yüksekliği — Çok alçak bir sürüş yüksekliği, disiplinli sürersen karşılığını verir; yeter ki arabanın dengesini kolayca bozabilecek tümseklerden ve bordürlerden uzak dur.
d677fcf8	Ses Seviyesi:
d68ea0c1	KOYU SİYAH
d6951cee	N2O
d6a265f7	Yakıt Filtresi
d6c79fcc	Okyanus ötesinden yeni geldi! En yeni ayarlanabilir ECU'lar artık tüm Bayview Performans Atölyelerinin ve Megalow Parts mağazalarının raflarında.
d6d115e4	Özel
d6dfcf20	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_SELECT$$ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^
d6ec6733	KOYU MERCAN
d6ec76d5	KOYU YEŞİL
d6f5819b	Performans Atölyesi
d6f5f38c	Aşırı Parlaklık
d707383d	Yeni parça SMS'leri
d7123a0a	DVD Kapakları:
d7162cfa	Drift
d72bc791	Yarış Oluştur
d7681229	Selam Rachel! Hop, kanka sen Rachel değilsin. Neyse, bana fark etmez. Bizimle yarışmak istiyorsan ve yeşillerin varsa, içeridesin. Rachel'la sonra kendin uğraşırsın. İki tur atıyoruz. Çizgiyi ilk geçen mangırı alır. Var mısın?
d768122a	Kanka, Rachel'ın arabasıyla çıkıp geliyorsun, bir de kendini bomba mı sanıyorsun? Buraya ait olduğunu kanıtlamak için güzel bir arabadan fazlası lazım. Çıkar yeşilleri, başlayalım. İki tur. Parkur haritana yüklenecek.
d76e0b5a	Keşif Moduna dönmek istediğinden emin misin?
d77a22d8	Kontroller
d7832e9e	BURNOUT
d7a26411	Engellenenler listende çok fazla oyuncu var!
d7c2416a	Yaylar, arabanın genel olarak ne kadar yumuşak ya da sert olacağını belirler. Ön ve arka yay sertliğini sürgülerle ayarla. Düzgün pistlerde sert yayları, bordürlü ve rampalı pistlerde yumuşak yayları dene.
d7d8ca79	EN İYİ DRIFT PUANI:
d7e713d7	Bu kaputu takarsan kaputtaki tüm çıkartmalar^kaldırılacak. Parçayı şimdi satın alıp takmak istiyor musun?
d7eab3d8	Power Magazine
d8089c82	Yeni Race Breaker özelliğinden yararlanmak için arabana Nitro yükseltmesi tak. Havalı sürüş göstergene ekstra N2O ekler; böylece nitron yarış boyunca yeniden dolar ve sana ek hız kazandırır.
d8244725	Kısa Pist
d831eab3	Oyun daveti göndermek için bir oyun odasında olmalısın.
d84fe2eb	Kaydetmek istediğin profile^bir ad vermen gerek.
d857ce14	Lobi sunucusuna bağlanmayı iptal edersen çevrimdışı olacak ve ana menüye döneceksin.^Bunu yapmak istediğine emin misin?
d87133bc	Oyuncu 1
d87133bd	Oyuncu 2
d8b8402a	Maalesef bu viniller karbon fiber geniş kasa parçalarıyla kullanılamıyor.
d8bc8820	Outrun Düellosunda rakibinin gerisindeysen en iyi strateji biraz geride durmaktır; böylece ani dönüşlere ve yön değişikliklerine tepki verebilirsin. Sollamayı denemek için virajsız bir düzlüğü bekle.
d8c66783	KUMANDA BAĞLI DEĞİL
d8ca8137	KUMANDA BAĞLI DEĞİL
d8d26325	%s kapak fırsatı
d8d26326	%s kapak fırsatı
d8ea6d2f	Şasi Altı Neonu
d8f5edf7	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Önizle^$JOY_EVENT_FENG_BUTTON1$ $ICON_SPACER$ Seçili Şarkıyı Taşı^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
d91cc86d	Fuarlardan taze döndük: en son far tasarımları stoklarımızda. Arabana yakışanı herhangi bir Bayview Kaporta Atölyesinden al.
d91fe7ea	Otomatik Kayıt özelliği, bir şeyi değiştirdiğinde ya da kariyerinde ilerlediğinde oyunu kendiliğinden kaydeder. Otomatik Kayıt ayarını Duraklatma menüsündeki Oynanış bölümünde bulabilirsin.
d924586d	Sol Analog Çubuk
d92807be	Yakıt Basınç Regülatörü
d92ef843	Hava
d93bb359	Çok Turlu
d93f8f55	Lider
d951d84a	Katılmaya çalıştığın oyun artık yok
d95b07db	Aralık
d972d70a	Xbox Live Ana Menüsü
d99150fd	TİP 3 İKİ SOL NOZUL
d99cfe5e	Oyun başlatılamadı.  Başka bir oyun oluşturmayı ya da başka bir oyuna katılmayı dene.
d99fc2e4	Ön Yere Basma Kuvveti
d9b267dd	Gizli Yarışlar
d9c35dd7	Hotel Plaza bölgesindeki Kaporta Atölyelerinden birini bul. Yeşilimsi sarı ışığı ve büyük mavi Kaporta Atölyesi tabelasını ara.
d9d137f6	SEVİYE 3 HİDROLİK
d9d8184f	Bu sesli sohbete girersen mevcut sohbet sona erer.  Devam etmek istiyor musun?
d9dc2f12	OYUNCU
d9dd2a50	Sunucu son yarışın sonuçlarını reddetti.^Ya oyunun süresi dolmuş ya da^sonuçlar geçersiz.
d9ff5230	Özel Ayarlar
da15d7e5	Takmaya çalıştığın parça zaten takılı!
da2b33af	[Özel mesaj]
da32284e	Underground Speed Zone DVD Kapağı
da3a368f	Tarih girişi
da3cddbb	Bilgilerin EA ortaklarıyla paylaşılsın mı?
da850671	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
da88b711	Sol Kapı
da8f3e96	Bu orijinal %s olsun mu?
da9fae0f	Egzoz Uçları
daac95f9	Etkinlik Seç
dab13dfd	Çevrimiçi oynarken oyununu kendine göre ayarlayabilirsin. Filtreleme sistemiyle yalnızca sana ve yarış becerine uygun oyunları listele.
dacd9fff	Frenler
dacf52c1	ECU tork eğrisi, motorun devir aralığı boyunca ürettiği gücü gösteren bir grafiktir. Gücü, yarışta en çok kullanacağın devir aralığına kaydırmak için eğrinin şeklini ayarla.
daf58a4c	Hesap Kurtarma
db0c5efd	En İyi Süre:
db4e3c0d	Keşif Moduna Dön
db71f10e	En yeni Bayrak Vinilleriyle gururunu kapılarında taşı, herkes nereli olduğunu bilsin. Geniş çeşitlerimiz tüm Grafik Atölyelerinde.
dbbb4e8f	Kolay
dbbcf37c	Zor
dbff7776	Bağırma
dc089c64	Outrun'ı Kazandın!
dc0d10c6	3. Sponsor
dc188678	Kaporta Atölyelerinden biri Fort Union bölgesinde. Yeşilimsi sarı ışığı ve büyük mavi Kaporta Atölyesi tabelasını ara.
dc1cd97d	Vites Yükselt
dc1df72a	SARI
dc2588ef	Pist
dc764d91	Diğer oyuncu, ister oyun sırasında ister çevrimiçi sohbet ederken sana yardımcı oldu.
dc92757b	Grafik Atölyesi
dcb9f861	Sprint
dcbc9b42	Ağ adaptörü başlatılırken bir hata oluştu.
dccd75f8	Performans Parça Deposu
dcd8e7f0	Aksiyon Kameraları:
dcfb6b36	EA GAMES™ TRAX
dd242bb5	Erişiliyor. A yuvasındaki hafıza kartına veya^ POWER düğmesine dokunma.
dd3bebf9	Spinner
dd43c1c0	Alınan Mesajlar
dd54f549	Drift Yarışı
dd68eabb	Bekliyor
dd8927b0	TAYLAND
dd90e320	KOYU SARI
dda280ca	Manuel şanzımanlı bir araba kullanırken viraja girmeden önce bir vites düşürerek hızını azalt. Doğru yaparsan fren yapmana gerek kalmayacak kadar yavaşlayabilirsin.
dda5b898	Spoiler
ddc719af	En havalı yeni jant tasarımlarını arabana tak. Yeni modeller ve ölçüler tüm Bayview Kaporta Atölyelerine az önce ulaştı.
dddc5e1b	Titreşim
de02cf84	Devam
de126e0b	Devam etmeye yetecek oyuncu kalmadığı için yarış sona erdi.
de28f2cf	Büyük Çaplı Diskler
de3bcb92	Hızlı Yarış Mod Ayarları
de4f2480	Arabandan sıkıldın mı? Herhangi bir galeride onu başka bir arabayla takas et. Unutma, bir arabayı takas ettiğinde o araba için aldığın tüm parçaları da kaybedersin.
de5cdfb2	Ayar Modundan Çık
de5ff65f	Oyunlar Aranıyor
de6daf19	Doğu Beacon Hill'deki Kaporta Atölyesini gözden kaçırma. Kafenin hemen arkasına saklanmış.
de7acec2	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Yuva Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Yuvayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
de9e588c	Street X İkincisi
deaa3f30	Stoplar
deaf63f4	TİP 2 GÖK MAVİSİ & ALTIN
ded7ca79	Kadran Rengini Seç
df05eb0c	Yeni Hesap Oluştur
df06ed22	Denge Kontrolü
df21eac2	Oyun Müziği Sesi
df327e35	Filtrelemeyi Etkinleştir
df3a33d6	Oyun daveti göndermek için ÖZEL bir oyun odasının kurucusu olmalısın!
df3fd1d6	Parçaları Tek Tek Seç
df4f296f	Mini haritayı, sürerken ya da yarışırken sabit kalacak veya dönecek şekilde ayarlayabilirsin. Haritanın Keşif ve Yarış modlarındaki davranışını Duraklatma menüsündeki Oynanış ayarlarından belirle.
df5aef26	Nitro
df6d355b	GPS sistemi sayesinde yarışlara ve atölyelere giden yolu bul. GPS'e Şehir Haritası tuşuna basarak ulaşabilirsin. Gideceğin yeri seçtikten sonra oyuna dön ve mavi oku takip et.
df6daa24	Irkçılık / Nefret Söylemi
df834843	Mesaj, işlenemeyecek kadar hızlı girildi. Tekrar dene.
df86227a	Aksesuar Atölyesi
df9a44b1	2. BONUSLAR
dfde01dd	Sıralama Sınıfı
dff01629	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Devam^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
dff3e933	ORİJİNAL
dff5a477	En Yüksek Drift Puanı
e0004602	Anlaşmalı Sponsorları Gör
e01c4250	Artık tüm fren kaliperi modelleri için özel boya hizmeti veriyoruz. Bugün herhangi bir Bayview Grafik Atölyesine uğra ve en yeni renklere göz at.
e01fb0ef	TEMİZ TUR
e03ef7a4	%dX için:
e06389a0	^^6 yıldızlı bir araba yaptığın için DVD kapağına çıktın!
e072db21	Kariyere Devam
e096f2e4	Ay
e097de5f	Kullanıcı kimliği ve şifre doğrulanamadı.  Ağ yapılandırmanı kontrol edip tekrar dene.
e0af0d6a	Açılan Parçalar
e0c2d7ba	Doğu Coal Harbor'da bir Aksesuar Atölyesi var. Binanın girişi arka tarafta. Giriş yolunu bulmak için yeşil ışığı ara.
e0e14fc0	KOYU SEDEF TURKUAZ
e0e1c6e0	KOYU SEDEF MAVİ
e0e4905e	KOYU SEDEF ALTIN
e0e734df	KOYU SEDEF ÇAĞLA YEŞİLİ
e0e9668a	KOYU SEDEF FUŞYA
e0f2e528	Konu: DVD Kapağına Bak
e0f67edc	Hey kodaman, burun buruna bir hız şovuna var mısın? Olay B-Ü-Y-Ü-K ve iki saniye sonra bir X parkurunda başlıyor.
e0f67edd	Naber delikanlı? Yine her zamanki gibi caka satıyorsun. Konuşacağına paranı ortaya koy da şu çılgın Street X'e katıl. Geliyor musun, gelmiyor musun?
e0f67ede	BÜYÜK X geliyor, hem de gümbür gümbür! Kaçacaksan şimdi kaç! Kalıyorsan da göğsünü gerip oyuna gir. Kemerini bağla, geç sıraya.
e0f67edf	Hey kafadan kontak! Birazdan dar virajlarda lastik yakacağız, sen de davetlisin. Bu iş uzun sürmez, elini çabuk tut.
e0f67ee0	Buraya bir sebeple gelmişsin: kaybetmek için. Street X'te pestilin çıkacak, hazır ol. Haritayı hemen yolluyorum. Ezilmemeye bak.
e0f68e78	Arabayı Takas Et
e1170a13	Pist
e125cb3a	Filtre Ayarları
e12e9030	MECHAMOTH
e1385c1e	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Araba Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$ Arabayı Seç^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$ Araba Filtresini Değiştir^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
e1417aca	Sponsor arabanı gerçekten takas etmek istiyor musun?^Tüm ekstralar gider ve fiyatının yalnızca yüzde 80'ini alırsın.
e1497a54	Parça Deposu
e156e946	İnternet servis sağlayıcınla bağlantı kurulamıyor.  Ağ adaptörünü, bağlantını ve/veya ağ yapılandırmanı kontrol edip tekrar dene.
e15b558a	Ana menüye çıkılsın mı?^Kaydedilmemiş yarış ilerlemen kaybolacak.
e16c24e3	Girdiğin persona adı geçersiz karakterler içeriyor.  Başka bir ad dene.
e170f115	Orijinal Kitlere Dön
e1807cc8	Underground 2'nin tam sürümünde boya atölyesi, arabana kişisel^bir dokunuş katmak için gideceğin yerdir. Arabanı özel bir^boya ya da havalı bir vinille kalabalıktan ayır. Buraya gelip^en sevdiğin üreticinin çıkartmasını da arabana^yapıştırabilirsin.^^Arabana uygulayabileceğin renklerden ve boya stillerinden^küçük bir örneği burada bulabilirsin.
e21a1373	TWISTER OFSET
e2217cae	Hop kanka, o hurdayı cidden bu yarışa sokmayı düşünmüyorsun, değil mi? Sana tur bindirirken o zavallı arabana çarpmayayım diye galibiyetimi riske atmak istemem. Haritaya dikkat et ve yolumdan uzak dur.
e22a1aaa	Parça Değiştir
e239b5b1	Mevcut Hesabı Kullan
e23f35dc	Kaporta Atölyesi
e2436ba3	TİP 1 SAĞ TEKERLEK NOZULU
e2442059	Rachel
e24b4bd5	Mesajı Oku
e25c980c	Otomatik Kayıt
e2716af1	Fabrikadan yeni çıkan yan ayna tasarımlarını ekibinde ilk sen kullan. Sınırlı sayıda, herhangi bir Bayview Kaporta Atölyesinde.
e2a74093	Arkadaş isteği iptal edildi.
e2ab0284	.
e2b4d051	Göstergeler
e2c85958	Nitro — Nitronu kısa yarışlar için daha güçlü, uzun yarışlar için daha uzun süreli olacak şekilde ayarla.
e2d18de7	NOS - 20 LB TÜP
e2d56294	Turbo
e2d5ad1e	Arabaya Bak
e2e98554	Vites oranları, her viteste elde edeceğin hızlanmayı ve ulaşabileceğin azami hızı belirler. Her vitesin oranını kendi sürgüsünden ayarla.
e2f13110	Viraj Demirleri — Yumuşak viraj demirleri arabanın gövdesinin daha fazla yatmasına ve ağırlığını daha yavaş aktarmasına izin verir. Sert viraj demirleri arabana go-kart hissi verir ama tümseklerde ve bordürlerde hata affetmez.
e2f9334d	Süre Farkı
e318005b	Sanayi bölgesindeki Batı Coal Harbor'da bulunan Kaporta Atölyesini ara. Atölyenin girişini yeşilimsi sarı bir ışık gösteriyor.
e32e4f8b	Eylül
e32ee46c	Oyun sırasında dikiz aynasını açıp kapatmak için Duraklatma menüsünde önce Ayarlar'ı, sonra Oynanış'ı seç.
e3457de3	Mini Harita Kullanımı
e35120f6	Performans Atölyesi
e3568655	NOS - 5 LB TÜP
e35cc4c0	Yarış Sonrası
e3602354	Başka bir oyuncu, sesli ya da yazılı sohbette bağırıp çağırarak oyun deneyimini bozuyor.
e3730c03	Kaporta Atölyesi, arabanın görünümünü güzelleştirip görsel yıldız puanını yükseltmek için ideal yer. Yüksek görsel yıldız puanı, bazı kariyer görevlerini tamamlamanı sağlar ve dergi kapaklarından daha fazla para kazandırır.
e3785c71	Az önce aldığın araba tam bir bomba! Bir modifiye dergisinin kapağı için^arabanın fotoğrafını çekmek isteyen bir fotoğrafçı var. Bulunduğu yer^mini haritanda sarı bir yıldızla işaretli.
e37a9c17	Rachel
e3950ac4	Şehir Haritası; şehri, keşfettiğin yerleri ve etkinlikleri ayrıntılı biçimde gösterir. Haritanın solundaki listeden etkinlikleri işaretleyip işaretini kaldırarak haritada neyin görüneceğini seçebilirsin. Ayrıca burada sırayla geçiş yapabileceğin birden fazla harita görünümü de var.
e3a9ab2a	Bu oyun oturumu artık mevcut değil.
e3d80db5	Celica
e3fa9491	KIL PAYI
e412a52c	NORTHEAST OFSET
e41917ad	TEMİZ YARIŞ
e4215d4e	Dikiz aynası
e445b20f	Mini Harita Açıklaması
e4504d8d	Jant Tipleri
e45a7387	Drag
e45f7ce9	Hesap doğrulanıyor
e47aa818	Gizli Atölyeler
e4c69392	Yeni geldi! Arabanın görünümünü değiştirecek yeni neon renkleri burada. Aynı eski, sıkıcı görüntüye mahkum kalma. Seninkini almak için bugün en yakın Aksesuar Atölyesine git.
e4eebd70	Arka Lastik Tutuşu
e4fb2c61	Seçtiğin Gamertag başkası için ayrılmış.^Başka bir Gamertag girip tekrar dene.
e50258b1	LAN Lobisi
e514579d	Yo birader, içeri gir de özel parçalarını kap.
e5240969	Bayview Performans Atölyesi Batı Beacon Hill şubesine hoş geldin. ^Sokak seviyesindeki Ağırlık Azaltma, Lastik ve Fren yükseltmelerinin kilidini açtın. ^Diğer Performans Atölyelerinde ve Megalow Parts'ta açılan tüm parçaları burada da bulabilirsin.
e52ab652	Garaja Gel...Hemen!
e530b5d9	Araba İstatistikleri
e558711c	Yeni Arabalar
e56d28fc	Kaporta Atölyelerinden biri, sanayi bölgesindeki Doğu Coal Harbor'da. Atölyenin girişini yeşilimsi sarı bir ışık gösteriyor.
e590f5a3	hafıza kartı (PS2)
e591119d	400m Süresi:
e596db16	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_LTRIGGER$ $JOY_EVENT_FENG_RTRIGGER$ Sohbeti Kaydır^$JOY_EVENT_FENG_BUTTON2$ $ICON_SPACER$  Sohbet^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
e59bfb1e	Arkadaş İsteğini İptal Et
e59e8200	Turnuva Yarış Sonuçları
e5a0d45e	Garaja dönülsün mü?
e5b2c887	Konu: Dergi Kapağı Fırsatı
e5ba928e	^^7 yıldızlı bir araba yaptığın için DVD kapağına çıktın!
e5d63bb5	Hızlı Yarış Pist Seçimi
e6110e0c	TİP 3 GÖK MAVİSİ & FUŞYA
e6381123	Selam dostum, bu gece şehirde bir sürü yarış var. Bildiğim bütün buluşma noktalarını haritana yükledim. Başka yarışlar olduğuna dair söylentiler de duydum ama tam yerlerini bilmiyorum. Gözünü dört aç.
e644d9aa	Bu oyun oturumu artık mevcut değil.  Oyun oturumu listesi güncelleniyor.
e6492e21	Önizle
e666e852	Sert
e66708f3	Yüksek
e6692b0a	Az
e669e1c6	Çok
e66c72fd	Arka
e66d2a8f	Yumuşak
e66f30db	Zayıf
e683c971	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
e6adc177	Ara Zaman:
e6c4524e	CALEB: Ne yapacağını biliyorsun, kızım. O arabanın tek bir parçası bile bitiş çizgisini geçmesin.
e6c4524f	NIKKI: Sürmekten başka bir şey yapmama gerek yok; gösteriş meraklısı bir ezik o.
e6c45250	CALEB: Onu hafife alma. Adamı darmadağın etmek için ne--ama NE gerekiyorsa--yap.
e6c45251	CALEB: Yüzümü kara çıkarma; sana güveniyorum, Nikki.
e6dff3b5	Motor
e6e0bc3f	URL:
e6ee8197	Bayview Grafik Atölyesi Doğu Coal Harbor şubesine hoş geldin. ^Ek Boya kategorilerinin ve yeni Vinillerin kilidini açtın. ^Diğer Grafik Atölyelerinde açılan tüm parçaları burada da bulabilirsin.
e71bbc33	Yeni motor yükseltmeleri artık tüm marka ve modeller için mevcut. Herhangi bir Bayview Performans Atölyesinde ya da Megalow Parts'ta en son yarış teknolojisini ekleyerek makinenden daha fazla güç al.
e720f694	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
e7286e8d	Açık
e7299c69	^5. Aşamada 20. yarışını kazandığın için dergi kapağına çıktın!
e72d5458	TİP 1 SAĞ KAPUT NOZULU
e7337e9d	Karbon fiber ya da alüminyum spoilerlar boyanamaz
e7440760	Sunucu bu oyuncuyu oyundan atamadı.
e74b7e13	km/sa
e74b86f8	mph
e761c8b8	Şehir haritasına dönülsün mü?^Kaydedilmemiş yarış ilerlemen kaybolacak.
e76cd783	Ses
e7720e22	Marka Seç
e77350a9	Sokak Performans Lastikleri
e798a2f7	Orijinal Arabalar
e79a53f8	Hata Ayıklama
e7ab43d3	Arabalarım
e7ce04a6	Mini Harita Açıklaması
e7cf5964	İNGİLTERE
e7e42ca9	Aylık sıralama alınırken bir sunucu hatası oluştu.
e8140569	Drag Lideri
e814b374	RACHEL: Evet, evet. Ortalığı yaktın, ama unutma, bu sadece tadımlıktı--burada kalmak için kazanmaya devam etmen lazım.
e814b375	RACHEL: İnsanlar seni fark etmeye başladı, ama hepsi iyi anlamda değil.
e814b376	RACHEL: Nasıl oldu sorma ama kendine yeni bir araba kazandın. Galiba sponsorlar hoşlarına giden bir şey gördü. Galeriye git ve bir tane seç; haritanda işaretli. Sonra görüşürüz!
e815bc6d	Kazandın!
e823c92a	TİP 2 GÖK MAVİSİ & PARLAK KIRMIZI
e84d4ebd	1. MEMORY CARD yuvasındaki hafıza kartında (PS2)^kullanılabilir bir Ağ Yapılandırması dosyası yok.
e84e015c	Gal. %
e863dd5c	Kesin yarış sonuçları bekleniyor...
e8647e75	OYNANIŞ
e86faf6c	Sözleşme şartı karşılandı
e87ddaa8	1. Dergi
e87df120	2. Dergi
e8867f7b	Hafif Volan
e8936126	^3 Drift Yarışı
e8a652cd	^3 Street X Yarışı
e8aebfaf	PUAN:
e8d2625c	Sponsor Bilgileri
e8da9e62	Aktarma Organları
e8e24508	Video
e8f3d566	Direksiyon
e90f40a4	Mitsubishi, Eclipse ve Lancer Evolution adları, amblemleri ve kasa tasarımları Mitsubishi Motors Corporation'ın ticari markaları ve/veya fikri mülkiyet hakları olup lisans altında^Electronic Arts Inc. tarafından kullanılır.^^"NISSAN" ile NISSAN ürünlerinin adları, logoları, markaları ve tasarımları^NISSAN MOTOR CO., LTD.'nin ticari markaları ve/veya fikri mülkiyet hakları olup lisans altında^Electronic Arts Inc. tarafından kullanılır.^^SUBARU, IMPREZA, WRX ve STi adları, amblemleri ve kasa tasarımları Fuji Heavy Industries Ltd.'nin mülkiyetindedir.^^Tüm yan sanayi oto parça şirketlerinin adları ve logoları^sahiplerinin ticari markalarıdır ve izin alınarak^kullanılır. Diğer tüm ticari markalar^sahiplerine aittir.^^© 2004 Electronic Arts Inc. Tüm hakları saklıdır.
e9641a65	Bu DVD'yi kaydetmek ister misin?
e973ea37	%s zaten senin oyun oturumunda
e99aa909	Xbox Live oturumunu kapatmak istediğine emin misin?  Okunmamış tüm mesajlar silinebilir; bekleyen tüm davetler ve sesli sohbet istekleri iptal edilecek.
e99bc583	Arabana yeni vinilleri buradan al. Dev bir desen^arşivinin yanı sıra, katman katman üst üste^binip sayısız kombinasyon oluşturan müthiş özel^viniller arasından seçim yapabileceksin.
e9cd0764	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
e9f82643	Yüksek Akışlı Egzoz Manifoldu
ea171252	2. Oyuncu, START düğmesine bas
ea33e5b6	Açılanlar
ea3748e7	TİP 3 İKİ TEKERLEK NOZULU
ea6ea8da	İptal
eaa1d5df	Kaputu Aç/Kapat
eab3f535	%s oyuna davet ediliyor ...
eac5ee5b	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
eac720d3	Sonuncu oldun!
eac74624	Hidrolik
eaea84d6	Spoilerlar
eaf13f17	2B
eaf89c18	Sadece aynı sıralamadaki oyuncular katılabilsin
eb587f14	Maalesef bu viniller karbon fiber kaporta parçalarıyla kullanılamıyor.
eb779c67	COBRA KARBON FİBER
eb9dfc09	Trafik Yoğunluğu
ebf23e40	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
ec3905c1	İstatistikler sunucudan alınıyor.
ec42ba5c	DUVARA ÇARPTIN
ec7626d4	Ayarların değişti. Bunları^profiline kaydetmek istiyor musun?
ec8616fd	Özel viniller dört vinil katmanının^hepsini kaplar. Arabandaki diğer tüm ^viniller kaldırılacak. Bu vinili^arabana uygulamak istediğine^ emin misin?
ec9488bb	Bu yarışa katılmak istiyor musun?
ec985de3	 - Yarışlar her an, her yerde başlayabilir
eca6b0cc	Performans Parçalarını Değiştir
ecad760a	^4. Aşamada 11. yarışını kazandığın için dergi kapağına çıktın!
ecd18034	Dereceli Yarış Arabaları
ecd20f7f	Direksiyon
ecd64585	Çılgın Drift
ece6c1d2	Uzatma^Outrun Kabul Edildi^Onu Atlat!
ed167f64	Duraklatma menüsünde çok uzun kaldığın için bu oyunla bağlantın kesildi.
ed1dd6d5	Doğu Beacon Hill'deki Grafik Atölyesi, Beacon Hill'e çıkan köprünün hemen kuzeyinde. Kırmızı ışığı ara.
ed1f0b2c	Ayarlar
ed21b47f	Yeni EA Hesabı Oluştur
ed55c635	Orijinale Dön
ed56be1f	Takılı
ed586157	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
ed8ca191	Yarış Durumu
ed8e446b	Oyun daveti iptal ediliyor: %s ...
ede5eb5a	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Vinil Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Vinili Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
ee176f14	Burning Wheels
ee2c85bb	Bu arabada takılı ön/arka tampon ve marşpiyelleri karbon fibere dönüştürme seçeneğini satın almak istiyor musun? Bu işlem arabandaki bazı vinillerin kaldırılmasına yol açacak.
ee3ea0d4	Atlama Kameraları:
ee46bda4	Bağlantıyı kesip çevrimiçi oynamayı bırakmak istediğine emin misin?  Okunmamış tüm mesajlar silinebilir; bekleyen tüm meydan okumalar ve sesli sohbet istekleri iptal edilecek.
ee64ab47	Okunmamış mesajlar
eeeb248e	START düğmesine bas
eef515f7	Işıklar
ef1bb23b	GÖRÜNTÜ
ef1dcf4f	Xbox Live'a giriş yapılıyor
ef317ada	Street X:
ef3772c1	Süspansiyon
ef433cad	Bu boyayı arabana uygulamak istiyor musun?
ef5b4a75	Ana Boya
ef644b90	Tavan Kepçesi
ef6679c9	Farlar
ef6e7cdb	İnternet servis sağlayıcınla bağlantın koptu. Ağ adaptörünün ve ağ kablonun takılı olduğundan emin ol. Ana menüye döneceksin.
ef72ff76	Jackson Heights girişinin yakınındaki binalara bir göz at, Grafik Atölyesini orada bulacaksın. Yoldan biraz içeride olduğu için girişini fark etmek dikkatli bir göz ister.
ef7cee30	Kurucuyla bağlantın koptu ya da kurucu oyundan çıktı.
ef8b592c	Street X bomba gibi dostum. Bu parkurlarda G kuvveti seni fena zorlayacak; buna dayanmak için arabanda süper bir süspansiyon olsa iyi olur. Katılmak ister misin? Parkur haritasını sana yollarım.
ef8b592d	Naber deli? Bizimle Street X'e mi gireceksin? İyi, sen grubun arkasında takıl da işin nasıl yapıldığını izle. Senin gibi çıtkırıldım birini hırpalarsam vicdanım sızlar. Haritayı yolluyorum ki ayağımıza dolanma.
ef8b592e	Hop, hop, hop! O acınası hurdayı gerçekten benim Street X pistime mi sokuyorsun? Bunu pistte sürmen lazım, ittirerek olmaz, biliyorsun değil mi? Paranı yatırmadan önce pist haritasına bakmak ister misin?
ef8b592f	Yarıştan önce paranı şimdiden bana versen nasıl olur? Yeni servetimin cebimdeki kalıcı yuvasına alışmak için biraz vakti olsun istiyorum.
ef8b5930	Kanka, o hurda yığınında emniyet kemeri var mı bari? Varsa lazım olacak, yoksa arabadan fırlar gidersin. Burası Street X, düpedüz vahşet. Oynamak istiyorsan bol bol G kuvveti yiyeceksin.
ef8b5931	Dostum, bunun at arabası gezisi değil de araba yarışı olduğunu biliyorsun, değil mi? Araba dediğin vın vın gider. Bu şatafatlı, atsız faytonlara alışana kadar bu yarışı pas geçsen iyi olur.
ef8b5932	Bu yarış şöyle işleyecek: Seni bir güzel yeneceğim, sen de sonunda bitişe varınca beni şekerlemeden uyandıracaksın ki paramı alayım. Bitiş çizgisinde seni beklemekten zaten canım çıkmış olur. Anlaştık mı?
ef8b5933	Sana olayı özetleyeyim: Yarışırız, ben kazanırım, sen de paranı bana verirsin. İstersen rezil olma kısmını atlayıp parayı şimdiden uzat. Ne dersin?
ef8b5934	Hey çaylak! Şanslı günündesin. Street X başlamak üzere ve bir enayiye daha ihtiyacımız var. Bir güzel ezilmeye var mısın, yok musun?
ef94affd	Filtre bilinmeyen bir nedenle güncellenip uygulanamadı.
ef9d7cb1	Diferansiyel
ef9f780d	Bölünmüş Ekran Mod Seçimi
efdb2567	Ön Amortisör
efddc126	Modifiyeli Arabayı Sil
f0559d07	Kariyer Durumu
f094132f	Blacktop Bandits
f0952942	TÜM TUR PUANLARI
f0981aa9	Yüksek Akışlı Yakıt Pompası
f0a3fea2	Hummer H2
f0a6e6b5	Bu mesajı silmek istediğinden emin misin?
f0aa1d96	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Performans Paketi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
f0aeb103	m
f0e53130	Sokak Tipi Eksantrik & Dişliler
f1139659	Bitiş Hızı:
f122e057	Yenilgi
f12a0e58	Sokak Tipi Fren Balataları
f139464c	Bayview's Best DVD Kapağı
f14900c2	NOS
f152befa	Karbon fiber ya da alüminyum aynalar boyanamaz
f155ab34	Oyuncu Listesi
f16c1df7	Hot 4's
f170c0f4	Üyelik Sözleşmesi
f18a58bd	Sprint İkincisi
f1b41aeb	Alıcının EA Messenger gelen kutusu dolu.  Bu mesaj gönderilemiyor
f1bd1a8a	Bu parça, arabanda takılı olandan daha kötü.^Yine de bu parçayı takmak istiyor musun?
f1c82817	Doğu Coal Harbor'daki Grafik Atölyesi, otoyol üst geçitlerinin hemen yanında. Otoparkın girişini bulmak için kırmızı ışığı ara.
f2029031	İSVEÇ
f20bf2f0	Xbox Live
f221d7ed	Bölünmüş Ekran Araba Seçimi
f22c5e19	Bu hesap güncel değil.  Hesabı Hesap Kurtarma bölümünden güncellemen gerekiyor.
f25d3e61	Hafıza kartı taranıyor
f26a5cbf	Atlama Kamerası
f294283e	Özel Kaputlar
f2aab6b5	Seçili araban bu oyun için geçersiz ya da oyun ayarların geçersiz.  Başka bir arabayla ya da farklı oyun ayarlarıyla tekrar dene.
f2d7ffab	Bu performans paketini takmak istiyor musun?
f2dc85bd	Gelen SMS'lere dikkat et. Haritanda görünmeyen yarışların nerede yapıldığına dair sık sık bilgi alacaksın.
f2ffa718	Nitro Tahliyesi
f3568b86	Otomatik Kaydı açmak istiyor musun? Otomatik Kayıt, aynı adlı kayıt dosyalarının üzerine sana sormadan yazar.
f35b6d7f	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön
f3843955	İnternet servis sağlayıcınla bağlantın koptu.  Ana menüye döneceksin.
f39723a1	LAN Ana Menüsüne Dön
f3acefed	^5. Aşamada 28. yarışını kazandığın için dergi kapağına çıktın!
f3b2f3f9	$JOY_EVENT_FENG_CANCEL$ Geri   $JOY_EVENT_FENG_SELECT$ Araba Seç
f3d937e1	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Ayarı Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Devam^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
f4242679	Eclipse
f42dc0bf	İKİ RENK A
f42dc0c0	İKİ RENK B
f43bb904	^5. Aşamada 4. yarışını kazandığın için dergi kapağına çıktın!
f460ba8b	NEUSPEED
f4614b27	Laf değil iş zamanı. Sponsorların seni ciddiye alması için burada kazanman lazım. Haritayı ekranına atıyorum. Bol şans.
f4614b28	Merak etme, burada rekabet sert ama bence hepsinin hakkından gelirsin. Sözleşmen için bu galibiyete ihtiyacın var, sakın batırma.
f4614b29	Dostum, sözleşmedeki bir şartı daha yerine getirmek için bu yarışı kazanmamız lazım. Arabanı geliştirmeye devam etmek istiyorsan para kazanman şart.
f4614b2a	Dinle bak yıldız çocuk, kazanıp durduğunu biliyorum ama sponsorun bu yarışı izliyor, o yüzden iyi bir şov çıkarman lazım. Birincilikten aşağısı başarısızlık sayılır.
f4614b2b	Birader, sponsor kazananı destekler. Kazanan ürün sattırır. Kazananın cebi dolar. Bizim de cebimiz dolmalı, o yüzden çık ve kazan.
f4614b2c	Olay şu: Bunu batırırsan işin biter. Konu kaybetmek olunca sponsorların şakası yok. Ciddi ol ve şovda kalmak için rakiplerini yerle bir et.
f4614b2d	Kazanırsan bir sonraki yarışa kadar rahatsın. Sponsorlar izliyor, sakın berbat etme. Harita SMS'le gelecek. Görüşürüz…
f4614b2e	Kendini BÜYÜK göstersen iyi olur oğlum, çünkü sponsorların karşısında palavra yürümez. Bu tipleri çileden çıkarmak istiyorsan acıma yok. Harita yolda.
f4614b2f	Bu iş SICAK dostum. Sponsor etrafta dolaşıp ortamı kolluyor ve bu yarış sözleşmene sayılıyor. Orada yarın yokmuş gibi gaza basman lazım.
f46a8b02	Xbox Communicator
f4aa6d5b	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Pisti Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
f4b00e99	Dönen
f4b3b4fc	Aksesuar Deposu
f4b8caab	Yani yeni sponsor araban bu mu olsun?
f4d77756	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^
f4ea444b	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Ayarı Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Devam^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
f503f0fd	Ara
f51bd160	Sürüş yüksekliği, arabanın yayları üzerinde ne kadar yüksekte durduğunu belirler; bu da ağırlık merkezini etkiler. Arabayı yükseltmek ya da alçaltmak için sürgüyü kullan. Genellikle ağırlık merkezi ne kadar alçaksa yol tutuş o kadar iyi olur.
f51e40d5	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  Boya Değiştir^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Boya Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Rengi Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
f52fa9cc	%s kapak fırsatı
f535b856	Çevrimiçi
f54cc524	Profil Oluştur
f5559d44	Özel %s
f568db09	Garaj menüsünden Ödülleri Gör menüsüne girerek DVD kapaklarını ve mevcut sponsorunu görebilirsin. Sponsorluk sözleşmeni yerine getirmek için gereken şartları da buradan takip et.
f58c0cd9	Bu bagaj ses sistemi düzenini satın alıp kurmak istiyor musun?
f5a12bc6	Otomatik Kaydı açmak istiyor musun? Otomatik Kayıt, aynı adlı kayıt dosyalarının üzerine sana sormadan yazar.
f5ac2b2a	Bu parçayı şimdi takmak istiyor musun?
f5ad01b9	%s başarıyla yüklendi.
f5ad272b	Hile cihazı algılandı! Çevrimiçi oynamak için tüm hile cihazlarını çıkarmalısın.
f5d83e92	TYPHOON OFSET
f600c82b	Sprint Lideri
f602188e	^5. Aşamada 34. yarışını kazandığın için dergi kapağına çıktın!
f605116d	Metalik
f62234ef	Test Sürüşü
f62ce3f4	Direksiyon Ayarları
f6601088	Yarışa Devam Et
f667659c	Tekrar Boya
f673dab6	Kumandayı %d numaralı kumanda girişine yeniden tak.
f68289c6	Sunucuyla bağlantın koptuğu için yarış sona erdi.
f6a08779	Oyun Filtreleri
f6a6a950	%s seni %s oynamaya davet etti
f6ccdc5f	Kamera
f6d18624	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$ İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$ Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$ Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$ Önceki Menüye Dön^
f6faff24	Dolby Pro Logic II
f70a3839	Geniş Kasa Kitleri
f7333312	Dergiler
f7363420	Karbon Fiber Kaputlar
f738c0cc	HATA AYIKLAMA
f73bc5d0	TİP 1 SOL TEKERLEK NOZULU
f73ce6d3	Kabul etmemeyi seçtin! Bu oyunun çevrimiçi özelliklerine erişmek için^ Kullanım Şartlarını kabul etmelisin.
f75595f2	Sabit
f760eabe	Oyuncu
f779c04a	Bayview Performans Atölyesi
f77e6402	DRAG YARIŞI PERFORMANSI
f7bb4269	V2 SOL TEKERLEK HARİÇ TÜMÜ
f7ccc795	Ağ Yapılandırması dosyandan bir ağ yapılandırması seç ya da yenisini oluştur.  İnternet servis sağlayıcı ve donanım ayarların burada saklanır ve belirlenir.
f7faebeb	TİP 2 GÖK MAVİSİ & FUŞYA
f8111a17	Bagajı Karbon Fibere Çevir
f81e6031	Galeriye Yeni Araba Geldi
f8224247	Need for Speed™ Underground 2 ile modifiye kültürünün yaşayan, nefes alan dünyasını keşfet. Birbirine bağlı beş farklı semtten oluşan devasa ve serbestçe gezilebilen bir şehirde geçen Need for Speed Underground 2, sokakların menü olduğu sürükleyici bir oyun dünyası sunuyor.
f82df37e	Yarış İstatistikleri
f83505e5	Grafik Atölyesinde her şey tek elden. Arabanın üzerinde önizleyebileceğin boyaları, vinilleri ve çıkartmaları seçerek görünümünü özelleştir. Sonuçtan memnun kalınca ücreti öde, seçtiklerin arabana uygulansın.
f84b1941	$JOY_EVENT_FENG_PAD_UP$ $JOY_EVENT_FENG_PAD_UP_ALTERNATE$  İmleci Yukarı / Aşağı Taşı^$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
f86a6272	Hız Birimi
f8798275	ORTA SİYAH
f88f18e9	Lancer
f8b4303b	Kullanılmıyor
f8bcee28	Arkadaş İsteğini Yanıtla
f8cb19a3	Oyun İpuçları
f8d75889	ORTA YEŞİL
f910d680	Ağ yapılandırmasını seç
f91fba4d	Kumanda Tuş Ayarları
f94653da	Kaporta Atölyesi
f9505de1	Xbox Live Giriş Hatası
f9617c3b	Garajda Görüşürüz
f9b92e68	Dergiler
f9d402e4	Vites Yükselt (Aşağı)^Vites Düşür (Yukarı)
f9d7f4c2	BİTİŞ SÜRESİ:
f9dc8092	Tavan Kepçeleri
f9f24edf	TİP 1 SAĞ ÜST VE SOL ALT NOZULLAR
fa14812c	Sonraki yarış %d saniye içinde başlıyor
fa37740b	Oyuncu
fa444e97	BİLEŞEN YOK
fa4c00a9	Özel Karakterler
fa71f3bb	Puan
fa827d6d	RACHEL: Wraiths ekibi ortalıkta rüzgar estiriyor, kazanmak için HER ŞEYİ yapıyorlar. Bir bak...
fa827d6e	RACHEL: Patronları Caleb, kontrolü ele geçirmek için perde arkasında anlaşmalar yapıyor.
fa827d6f	RACHEL: Sponsorlar her işi benim üzerimden yapıyor, yani benim de kaybedeceğim çok şey var. Ama sen? Senin kaybedeceğin daha da fazla; o kazanırsa her şey değişir.
fa827d70	RACHEL: Aranızdaki geçmişi düşünürsen, Bayview'da bir daha hiçbir yerde yarışmayı unutabilirsin.
fa827d71	RACHEL: Ama kazanmaya ve o sponsorları kapmaya devam edersen, sığınacak kimsesi kalmaz--onu kapının önüne koyarlar!
fa827d72	RACHEL: Sadece şunu unutma: Kazanmaya devam etmelisin!
fab08903	Mesaj Yönetimi
fab1b6bb	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Araba Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Arabayı Seç^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
fabfc6dc	Denk Arabalar
fac4999e	Yok
fac94705	BİLEŞEN YOK
fad22c09	Hey, arabamı geri istiyorum! Hemen oraya uçsan iyi edersin, yoksa herkese senden uzak durmalarını söylerim - bu da ben izin verene kadar yarış falan yok demek. Galeriye git...HEMEN!
faf29146	Köpük Dolgulu Kabin
fb226531	$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
fb559794	Çevrimiçi oynarken her oyun modunda on sıralama seviyesini basamak basamak tırmanabilirsin. Bakalım hepsinde elit seviyeye ulaşabilecek misin. Elit sıralamaya ulaşan oyuncular, çevrimiçi oyun odalarında diğer oyuncuların görebileceği özel ödüller kazanır.
fb75e78f	Takas edilsin mi?
fb7dfc68	O.Z.
fb81c616	Outrun Modu
fb94489b	Odadan Çık
fbb574ea	Sayı Değiştir
fbbdd223	Nitro Torku
fbd139f0	Filtrele
fbd2de93	RACHEL: Hey dostum, ortalığı fena ayağa kaldırdın! Galiba birkaç şirket seni temsil etmek istiyor; bu da sana bahsettiğim Underground Racing League'e girmeye hak kazandın demek.
fbd2de94	RACHEL: Trafik yok, sokak yok; sadece saf sürüş. Hepsi kontrollü, özel bir pistte geçiyor.
fbd2de95	RACHEL: Madem benimle çalışıyorsun, menajerliğini de ben yaparım. Hangi işin değdiğini sana söylerim, karşılığında da payımı en baştan keserim.
fbe5ad60	EA Messenger'da engelleyebileceğin en fazla oyuncu sayısına ulaştın.
fbfce084	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Seçimi Değiştir^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
fc00d963	Hazır
fc1b498a	TUR SÜRESİ
fc25c061	ECU — Motorunun tork eğrisindeki her noktayı ayarlayarak düşük devirlerde güç, tüm devir aralığında dengeli güç ya da devir sınırına yaklaştıkça daha fazla güç alabilirsin.
fc6731a6	1. Oyuncu, START'a bas
fc820867	Dyno / Performans Ayarından Çıkılsın mı?
fc89ee1f	Batı Coal Harbor
fc9b38b9	Arabanın performansı üzerinde daha fazla kontrol istiyorsan Duraklatma menüsünde önce Ayarlar'ı, sonra Oyuncu'yu seçerek şanzımanını Otomatik'ten Manuel'e geçir.
fd036061	$JOY_EVENT_FENG_PAD_LEFT$ $JOY_EVENT_FENG_PAD_LEFT_ALTERNATE$  Kategori Değiştir^$JOY_EVENT_FENG_PAD_RIGHT_ALTERNATE$ $ICON_SPACER$  Arabayı Döndür^$JOY_EVENT_FENG_SELECT$ $ICON_SPACER$  Seçimi Onayla^$JOY_EVENT_FENG_CANCEL$ $ICON_SPACER$  Önceki Menüye Dön^
fd074292	Pistin inşaat halindeki bölümlerinden uzak dur. Asfaltsız kısımlar arabanın dengesini bozar ve hızını düşürür.
fd123b59	Garaja Git
fd143578	Yarış Modu:
fd1a4dd5	KOYU SEDEF SİYAH
fd1ed7c5	Müzik Sesi
fd487543	Efekt Sesi
fd71a998	1 Street X^1 Pist Yarışı^1 Sprint Yarışı
fd73f7c8	1 Pist Yarışı^1 Sprint Yarışı^1 Street X Yarışı
fd781447	KOYU SEDEF MERCAN
fd7823e9	KOYU SEDEF YEŞİL
fd7da212	KOŞULLAR:^5 URL galibiyeti, sponsorun belirleyeceği 3 yarışta galibiyet ve sürücünün seçeceği 19 ek galibiyetle sözleşme tamamlanır.^^TANITIM ŞARTLARI:^2 DVD kapağında yer alacak bir araba oluştur.^^BONUS:^Bayview'daki herhangi bir galeriden bedava araba.
fd7ff042	SÖZLEŞME ŞARTLARI:^Sürücü şu yarışları kazanmalı: 3 URL yarışı, sürücünün seçeceği 9 yarış, sponsorun seçeceği 3 yarış.^^EK ŞARTLAR:^1 DVD kapağında yer alacak bir araba hazırla.^^BONUS:^Bayview'daki herhangi bir galeriden bedava araba.
fd81b9f7	Oyun Modu
fd820bf3	Oyun adı
fd85bcb4	Oyun Türü
fd93d884	Hareketli Doku
fd9e06cd	Xbox Panosuna çıkıp yeni bir Xbox Live™ hesabı oluşturmak istediğine emin misin?
fdb23750	Batı Beacon Hill'de, Burger King® restoranının yakınında bir Performans Atölyesi var. Girişe giden mavi ışıkları ara.
fdc3bdb6	^3 Street X Yarışı
fddd0c23	Bu pakette, sahip olduğundan daha kötü bir^parça var. Yine de bu performans paketini^satın alıp takmak istiyor musun?
fde711b3	Yan aynalar
fe122d23	Yalnızca Tam Sürümde
fe1b7d1e	Yarışçılar
fe22b6a2	Ön Yay
fe38abbc	Sesli sohbet davetin reddedildi.
fe407a18	Süre Sınırı
fe4b4cfa	Yarıştan Çık
fe641264	Sunucu bu EA hesap adını reddetti.^Başka bir ad seçip tekrar dene.
fe82fde0	Turbo Tork Eğrisi
febf45e4	^5. Aşamada 32. yarışını kazandığın için dergi kapağına çıktın!
fec151fe	Viraja girmeden ne kadar erken yavaşlarsan virajdan o kadar hızlı çıkarsın. Bu teknik, yarışta sana değerli saniyeler kazandırır.
fed0d3df	Yeni bir tuş ya da düğme atamak için Enter'a bas
ff0cbfd5	Arka Viraj Demiri
ff0e7232	Mini Harita Açıklaması
ff115fff	Yarış Sonuçları
ff12b5c5	Geri Bildirim Gönderiliyor, Bekle...
ff1c4cfe	En Fazla Oyuncu:
ff29e90f	Oyun
ff76cd6a	Sözleşme şartları karşılandı
ff7e965b	^^10 yıldızlı bir araba yaptığın için DVD kapağına çıktın!
ff8de430	Şerit Seti
ff9056dd	TAYLAND
ff956af2	Çevrimiçi Ana Menüye Dön
ff99d845	Girilen şifreler uyuşmuyor.
ffa7d360	Sağ Arka Çamurluk
ffb6955e	3. Dergi
ffc7c2b4	Bayview Aksesuar Atölyesinin Stadyum şubesine hoş geldin.
ffe08459	Mod Seçimi
"""#
}
