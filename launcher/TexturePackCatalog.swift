// The Texture Packs window's list: the community's NFSU2 texture mods, most popular first
// (nfsmods.xyz's "All Time Best" in Textures and Interfaces, and the large packs hosted
// elsewhere), checked 2026-10-31.  A JSON document, so entries are easy to add.
//
// Fields: id, name, author, category (ui | world | sky | cars), kind (what the mod is
// made of), description, page (the author's page), fileName and size (as downloaded),
// releases (EU and NA: tested with both), note, include / exclude (parts of the
// download used or left out: a mod's variants, the originals it keeps for uninstalling).
// download + sha256: only for releases that were downloaded from the author's page and
// tested in the game; the launcher refuses any other file.  knownSHA256: tested releases
// without a direct link, so Import… recognizes them.  Entries without download are
// "Details and Import": the player downloads the file on the page and imports it.
//
// Adding an entry: download the release from the author's page, import it with
// NFSU2_LAUNCHER_TEST=texpack:<file>:<game>:<pack> (it says which textures it found),
// run the game with NFSU2_TEXPACKS=<pack> NFSU2_TEXPACKS_LOG=1 on both builds, then add the
// URL, size and SHA-256 here.
import Foundation

enum TexturePackCatalog {
    static let packs: [CatalogPack] = {
        do { return try JSONDecoder().decode([CatalogPack].self, from: Data(json.utf8)) }
        catch { fatalError("TexturePackCatalog.json: \(error)") }
    }()
    static func pack(_ id: String) -> CatalogPack? { packs.first { $0.id == id } }
    /// The catalog entry a file the player imports is a tested release of.
    static func pack(sha256: String) -> CatalogPack? {
        packs.first { $0.sha256 == sha256 || ($0.knownSHA256 ?? []).contains(sha256) }
    }

    static let json = """
[
 {
  "id": "scout-ui",
  "name": "Scout's UI Remaster",
  "author": "BlackScout",
  "category": "ui",
  "kind": "texture files",
  "description": "Menus, HUD, fonts, speedometers and part of the map redrawn at four times the detail.",
  "page": "https://nfsmods.xyz/mod/378",
  "download": "https://nfsmods.xyz/uploads/mods/378/af6d1b-ScoutNFSU2UIRemaster1.0.1.zip",
  "fileName": "ScoutNFSU2UIRemaster1.0.1.zip",
  "size": 11685588,
  "sha256": "57cd1ca8ff93df4c4d155eabe57c40587f8925c50f19e17ce8452ae3e39e8f23",
  "exclude": [
   "old tpf version/"
  ],
  "releases": "EU and NA",
  "note": "Its textures may be reused with credit to BlackScout. The HD Content Support plugin it asks for is not needed here."
 },
 {
  "id": "nfsmods-896",
  "name": "New HD Textures Pack",
  "author": "I_NEED_SPEED",
  "category": "world",
  "kind": "TexMod pack",
  "description": "HD remake of most ground textures, some buildings, palm trees and walls.",
  "page": "https://nfsmods.xyz/mod/896",
  "fileName": "",
  "size": 0,
  "note": "Import only: the mod's page links to another file host. Download it there, then Import its .tpf.",
  "releases": "not checked"
 },
 {
  "id": "last-breath",
  "name": "Last Breath Final",
  "author": "Stre1itzia",
  "category": "world",
  "kind": "TexMod pack",
  "description": "4K roads, remastered map and tracks, 250+ HD textures, HD HUD.",
  "page": "https://nfsmods.xyz/mod/1717",
  "fileName": "U2_LastBreath_Final.rar",
  "size": 0,
  "note": "Import only: the mod's page links to a file host that needs a browser (about 372 MB). Import the .rar or its .tpf. The author asks that its textures are not repacked; the pack made here stays on this Mac.",
  "releases": "not checked"
 },
 {
  "id": "remastered-ug2",
  "name": "Remastered Underground 2",
  "author": "instanity",
  "category": "world",
  "kind": "TexMod pack and texture files",
  "description": "Roads, walls, sky, vegetation, billboards, car textures, HUD and effects.",
  "page": "https://www.gamepressure.com/download/need-for-speed-underground-2-remastered-underground-2-v10-mod/z014c4d",
  "fileName": "underground2rem10.zip",
  "size": 121453867,
  "note": "Import only: gamepressure.com gives the file to a browser after a wait. Its ReShade preset and plugins are not used.",
  "releases": "EU and NA",
  "knownSHA256": [
   "5085717e9a17b96048dd0621c67ec441ad816768e050707c21c9e4457bfbc76f"
  ]
 },
 {
  "id": "nfsmods-4485",
  "name": "Detailed Map",
  "author": "JeansBig",
  "category": "ui",
  "kind": "textures by name",
  "description": "The race and free roam maps upscaled from 512 to 2048 pixels, with missing shortcuts added.",
  "page": "https://nfsmods.xyz/mod/4485",
  "download": "https://nfsmods.xyz/uploads/mods/4485/2d7d87-NFSU2%20Detailed%20Map%20v1%20Reup.zip",
  "fileName": "NFSU2 Detailed Map v1 Reup.zip",
  "size": 44673138,
  "sha256": "098ac4c3e914f60569020dcbd433b7aae0ce224c2e2d5a69bd3644981c2b1035",
  "releases": "EU and NA",
  "exclude": [
   "/beta/"
  ],
  "note": "The version without the beta tunnel."
 },
 {
  "id": "nfsmods-1655",
  "name": "8K HDRI Skyboxes (original)",
  "author": "BadassBaboon",
  "category": "sky",
  "kind": "texture files",
  "description": "The sky as 8K HDRI photos; the original release for the game's files.",
  "page": "https://nfsmods.xyz/mod/1655",
  "fileName": "",
  "size": 0,
  "note": "Import only: the mod's page links to another file host. The TexWizard port below is the same sky.",
  "releases": "not checked"
 },
 {
  "id": "nfsmods-801",
  "name": "HD Maps Project",
  "author": "Speedforneed",
  "category": "ui",
  "kind": "TexMod pack and texture files",
  "description": "The free roam map upscaled two times, with less noise.",
  "page": "https://nfsmods.xyz/mod/801",
  "fileName": "NFSUG2_HD_ MAPS_beta_Speedforneed .7z",
  "size": 1328452,
  "releases": "not checked in the game",
  "exclude": [
   "texmod version/"
  ],
  "knownSHA256": [
   "cb78bc405e8d6db3caa4aca143d02c847c43eea5585a35dc896d09cfea59ee18"
  ],
  "note": "Import only for now: it converts, but its textures did not show in the test run (they appear with the free roam map). Download it on its page, then import it."
 },
 {
  "id": "nfsmods-6156",
  "name": "Next-Gen Visuals",
  "author": "ATIRONS & EDUARDA",
  "category": "world",
  "kind": "not checked",
  "description": "Retexture of roads, buildings, the menu lobby, garages, shops and billboards.",
  "page": "https://nfsmods.xyz/mod/6156",
  "fileName": "",
  "size": 0,
  "note": "Import only: the mod's page links to another file host; its format was not checked.",
  "releases": "not checked"
 },
 {
  "id": "nfsmods-1593",
  "name": "HD Fonts",
  "author": "MR80",
  "category": "ui",
  "kind": "not checked",
  "description": "The game's fonts upscaled four to eight times.",
  "page": "https://nfsmods.xyz/mod/1593",
  "fileName": "",
  "size": 0,
  "note": "Import only: the mod's page links to another file host; its format was not checked. The font plugin it asks for is not needed here.",
  "releases": "not checked"
 },
 {
  "id": "nfsmods-1810",
  "name": "NFS 2015 Style Map",
  "author": "BadassBaboon",
  "category": "ui",
  "kind": "texture files",
  "description": "A Ventura Bay style free roam map, redrawn at 4K.",
  "page": "https://nfsmods.xyz/mod/1810",
  "download": "https://nfsmods.xyz/uploads/mods/1810/00a4e2-UG2015.rar",
  "fileName": "UG2015.rar",
  "size": 903664,
  "sha256": "b230e7739e5bb8b48081f7fd9fd9344b6e6e0f554d197c1219315ea0d9082188",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-1312",
  "name": "Remastered Car Logos",
  "author": "Lisao10",
  "category": "ui",
  "kind": "texture files",
  "description": "The car select manufacturer logos, remastered.",
  "page": "https://nfsmods.xyz/mod/1312",
  "download": "https://nfsmods.xyz/uploads/mods/1312/ef9ab7-New%20Car%20Logos.zip",
  "fileName": "New Car Logos.zip",
  "size": 1674508,
  "sha256": "c9bf51d5d79d205802e0dfdbb43a3ec96e48cdcbd3e37cb2a4bf46055f8f8d93",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-1681",
  "name": "350Z Loading Screen",
  "author": "KylaAngelineKZYeng",
  "category": "ui",
  "kind": "texture files",
  "description": "The loading screen shows Rachel's Nissan 350Z from NFS Heat.",
  "page": "https://nfsmods.xyz/mod/1681",
  "download": "https://nfsmods.xyz/uploads/mods/1681/ec5979-NFSU2-350ZLS.rar",
  "fileName": "NFSU2-350ZLS.rar",
  "size": 5795561,
  "sha256": "bb633e32fd1afd929f7cfb22921f786cd36e8388fbf5c74502d7fefc31e38678",
  "releases": "EU and NA",
  "exclude": [
   "olympic"
  ]
 },
 {
  "id": "nfsmods-349",
  "name": "PLUS World Texture Mod",
  "author": "AJLethal",
  "category": "world",
  "kind": "texture files",
  "description": "Crisper road textures, new shop signs and billboards.",
  "page": "https://nfsmods.xyz/mod/349",
  "download": "https://nfsmods.xyz/uploads/mods/349/504bb9-%5BNFSU2-Misc%5D%20PLUS%20World%20Texture%20Mod%20%5Bwww.nfsridescr.blogspot.com%5D%29.7z",
  "fileName": "[NFSU2-Misc] PLUS World Texture Mod [www.nfsridescr.blogspot.com]).7z",
  "size": 36540224,
  "sha256": "d977b524888a313c46f8e513c4e0c40520c67fbf6d2fffd3b0cd8fc9cb8605ed",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-1851",
  "name": "High Res Minimap",
  "author": "JMD",
  "category": "ui",
  "kind": "texture files",
  "description": "The main minimap and many race maps at a higher resolution.",
  "page": "https://nfsmods.xyz/mod/1851",
  "download": "https://nfsmods.xyz/uploads/mods/1851/ee3a0d-High%20Res%20Minimap%20v1.3.zip",
  "fileName": "High Res Minimap v1.3.zip",
  "size": 21784879,
  "sha256": "63064808cd8a8c60d7dbbe9b5beaada33569263a3b9cb6716e7d48e319e0631c",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-369",
  "name": "HD Gauge and Menu Textures",
  "author": "NFS Business",
  "category": "ui",
  "kind": "TexMod pack",
  "description": "The default gauge and the menu boxes' corners at high resolution.",
  "page": "https://nfsmods.xyz/mod/369",
  "download": "https://nfsmods.xyz/uploads/mods/369/5aa938-HD%20Gauge%20%26%20Menu.zip",
  "fileName": "HD Gauge & Menu.zip",
  "size": 4115142,
  "sha256": "6f2f6e40f5b038bd2d80a4d5ce148d557e9755eb6c47827d27febcde8205aef0",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-5081",
  "name": "Always Lighter Sunrise, Night, Sunset",
  "author": "oldman777",
  "category": "sky",
  "kind": "textures by name",
  "description": "Sunrise, night and sunset a little lighter than the original.",
  "page": "https://nfsmods.xyz/mod/5081",
  "download": "https://nfsmods.xyz/uploads/mods/5081/fd771e-NFSU2%20-%20Always%20Lighter%20Sunrise%2C%20Night%2C%20Sunset%20v1.2.zip",
  "fileName": "NFSU2 - Always Lighter Sunrise, Night, Sunset v1.2.zip",
  "size": 1636039,
  "sha256": "a9e92d2675dcf2e2e1331a490dd9a6e0cb387838fc597ca605b53507eef6d041",
  "releases": "EU and NA",
  "include": [
   "/original mod/"
  ],
  "note": "The default cycle of the times of day; its other variants are not used."
 },
 {
  "id": "nfsmods-1212",
  "name": "New Performance Icons",
  "author": "Jayzee",
  "category": "ui",
  "kind": "textures by name",
  "description": "New icons for the performance parts.",
  "page": "https://nfsmods.xyz/mod/1212",
  "download": "https://nfsmods.xyz/uploads/mods/1212/09fa8c-NFSUG2%20Perf%20icons.zip",
  "fileName": "NFSUG2 Perf icons.zip",
  "size": 931669,
  "sha256": "52eb1daa1c2adf30a90b2aaeeb9ece6b0a7f3f1c06c055efc00d390a1e47add5",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-4396",
  "name": "LA Skybox",
  "author": "JeansBig",
  "category": "sky",
  "kind": "textures by name",
  "description": "Los Angeles skyline and distant mountains on the horizon at sunrise, night and sunset.",
  "page": "https://nfsmods.xyz/mod/4396",
  "download": "https://nfsmods.xyz/uploads/mods/4396/ea1bf8-LA%20Skybox%201.0.zip",
  "fileName": "LA Skybox 1.0.zip",
  "size": 2615385,
  "sha256": "bbb7ee90535bf7a5609ff77ea7ef307037cef67cfa5c3ff5d6a1434b52b91189",
  "releases": "EU and NA",
  "exclude": [
   "/uninstall/"
  ]
 },
 {
  "id": "hdri-sky-8k",
  "name": "8K HDRI Skyboxes (TexWizard port)",
  "author": "BadassBaboon, TexWizard port by RKBDI",
  "category": "sky",
  "kind": "TexWizard pack",
  "description": "The sky at sunrise, sunset and night as 8192 × 2048 HDRI photos.",
  "page": "https://nfsmods.xyz/mod/7417",
  "download": "https://nfsmods.xyz/uploads/mods/7417/e318e2-UG2HDR8KSKY_UPDATE.7z",
  "fileName": "UG2HDR8KSKY_UPDATE.7z",
  "size": 42963808,
  "sha256": "c62d71ab1742cb97d0598f69be1449afeda59747b27f65ff56c455486d9911b8",
  "exclude": [
   "optional/"
  ],
  "releases": "EU and NA",
  "note": "Uses about 205 MB on disk. In this port the night sky looks darker and greyer than the original; LA Skybox is a brighter one."
 },
 {
  "id": "nfsmods-1216",
  "name": "New Secondary Logos",
  "author": "Jayzee",
  "category": "ui",
  "kind": "textures by name",
  "description": "New secondary logos for every car.",
  "page": "https://nfsmods.xyz/mod/1216",
  "download": "https://nfsmods.xyz/uploads/mods/1216/5c2101-NFSU2%20SECONDARY%20LOGOS.zip",
  "fileName": "NFSU2 SECONDARY LOGOS.zip",
  "size": 4308932,
  "sha256": "6f6435815fdcefe3216b70d473ca785c85fb19590cc7cc749386e3dd0bc8e5d8",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-1674",
  "name": "Winter Mod",
  "author": "2fast4u_dk",
  "category": "world",
  "kind": "texture files",
  "description": "Bayview in winter: snowy roads and surroundings.",
  "page": "https://nfsmods.xyz/mod/1674",
  "download": "https://nfsmods.xyz/uploads/mods/1674/655817-2012%20Winter%20Mod.rar",
  "fileName": "2012 Winter Mod.rar",
  "size": 48662357,
  "sha256": "205ed1782d808f6b95c4b4418ad93c9a85ec4983a5ff637e8d903ba754d8b80c",
  "releases": "EU and NA",
  "note": "Only its textures are used; its other changes (text, scenes) are not."
 },
 {
  "id": "nfsmods-345",
  "name": "PLUS Gauges",
  "author": "AJLethal",
  "category": "ui",
  "kind": "texture files",
  "description": "A set of improved custom gauges.",
  "page": "https://nfsmods.xyz/mod/345",
  "fileName": "[NFSU2-Misc] PLUS Gauges [www.nfsridescr.blogspot.com]).rar",
  "size": 365892,
  "releases": "not checked in the game",
  "exclude": [
   "stock+/"
  ],
  "knownSHA256": [
   "bae97cf9224c1996a4e945c3cd441e05a087fd8fd3c81f069b40e64036a987e6"
  ],
  "note": "Import only for now: it converts, but its textures did not show in the test run (they appear with the custom gauges). Download it on its page, then import it."
 },
 {
  "id": "nfsmods-2638",
  "name": "Sha_Do Splash Screen",
  "author": "AdrienShadow",
  "category": "ui",
  "kind": "textures by name",
  "description": "The Sha_Do splash screen upscaled from 256 to 1024 pixels.",
  "page": "https://nfsmods.xyz/mod/2638",
  "download": "https://nfsmods.xyz/uploads/mods/2638/518f27-Sha_do%20Loading%20Screen.zip",
  "fileName": "Sha_do Loading Screen.zip",
  "size": 3142988,
  "sha256": "123c96affe4ab3f14bae49b5daeed55e2b4c8eab904b059dfc6b1421e536d10c",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-320",
  "name": "Beta Title Screen",
  "author": "NFS Business",
  "category": "ui",
  "kind": "texture files",
  "description": "The loading and title screen from the game's beta.",
  "page": "https://nfsmods.xyz/mod/320",
  "download": "https://nfsmods.xyz/uploads/mods/320/b89375-Beta_load_screen.zip",
  "fileName": "Beta_load_screen.zip",
  "size": 3900416,
  "sha256": "2fec9668e6c0a36bfb6a9d6634b36cc8a984f1c2213285325e43718f0d09f0cd",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-2194",
  "name": "New Carbon Fiber",
  "author": "Archless",
  "category": "cars",
  "kind": "textures by name",
  "description": "The carbon fibre texture at 4096 × 4096.",
  "page": "https://nfsmods.xyz/mod/2194",
  "download": "https://nfsmods.xyz/uploads/mods/2194/f7d919-Carbon%20Fiber%20MOD%20NFSU2.rar",
  "fileName": "Carbon Fiber MOD NFSU2.rar",
  "size": 4384171,
  "sha256": "40ddc29e8bb621db70e2c044ff5be6c1dd5af297b23eb4598165d1fc68752d18",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-1220",
  "name": "New Stickers",
  "author": "Jayzee",
  "category": "cars",
  "kind": "texture files",
  "description": "Modified car stickers.",
  "page": "https://nfsmods.xyz/mod/1220",
  "fileName": "NFSU2 New stickers.zip",
  "size": 1745900,
  "releases": "not checked in the game",
  "knownSHA256": [
   "969b470b61d976a9e4e4626a55630944785a0c59ef14a7858517b366fcdb4103"
  ],
  "note": "Import only for now: it converts, but its textures did not show in the test run (they appear with stickers on a car). Download it on its page, then import it."
 },
 {
  "id": "nfsmods-375",
  "name": "HD Text",
  "author": "NFS Business",
  "category": "ui",
  "kind": "TexMod pack",
  "description": "The game's text drawn in new HD fonts.",
  "page": "https://nfsmods.xyz/mod/375",
  "download": "https://nfsmods.xyz/uploads/mods/375/a2c6c9-HD%20Text.zip",
  "fileName": "HD Text.zip",
  "size": 3321903,
  "sha256": "5a66ad72bce2f6cd8ad6c1922f2192d758a263edfa4689cd9dda535b01adbde8",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-319",
  "name": "Green Nitrous Bar",
  "author": "NFS Business",
  "category": "ui",
  "kind": "texture files",
  "description": "The nitrous bar in green instead of blue.",
  "page": "https://nfsmods.xyz/mod/319",
  "download": "https://nfsmods.xyz/uploads/mods/319/8a7bce-NfSU2_Green_N20.zip",
  "fileName": "NfSU2_Green_N20.zip",
  "size": 331045,
  "sha256": "860c74cf5b2d19805b1dceb478546a1383dd5e5bca6c2cc9740259594efdd8ef",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-2016",
  "name": "New Car Select Logos",
  "author": "Jayzee",
  "category": "ui",
  "kind": "texture files",
  "description": "New car select logos.",
  "page": "https://nfsmods.xyz/mod/2016",
  "download": "https://nfsmods.xyz/uploads/mods/2016/45ccc1-CARSELECTLOGOS.rar",
  "fileName": "CARSELECTLOGOS.rar",
  "size": 1210085,
  "sha256": "09ee8804df050e8a32bb1a7fca95e59ff4a5ccc8dad3aa9cdfee192c9b2b68a8",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-2297",
  "name": "Permanent Night Time",
  "author": "Halagini",
  "category": "sky",
  "kind": "textures by name",
  "description": "The sunrise and sunset skies replaced by night skies.",
  "page": "https://nfsmods.xyz/mod/2297",
  "download": "https://nfsmods.xyz/uploads/mods/2297/2cc599-Permanent%20Night%20Time.rar",
  "fileName": "Permanent Night Time.rar",
  "size": 114081,
  "sha256": "de19827cf62365169c4761003a0a7dd969097b1a393ef017b486163252516820",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-2228",
  "name": "HD RX8 Style Gauge",
  "author": "NFS Business",
  "category": "ui",
  "kind": "texture files",
  "description": "The tachometer as an HD adaptation of the RX-8's.",
  "page": "https://nfsmods.xyz/mod/2228",
  "download": "https://nfsmods.xyz/uploads/mods/2228/3de4a2-HD%20RX8%20style%20guage.zip",
  "fileName": "HD RX8 style guage.zip",
  "size": 3086565,
  "sha256": "dc69c80c42d2b56abeebe4647de44e98174e9348edd0ca401a36a4b8f8176ce3",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-7486",
  "name": "UHD Sponsor Vinyls",
  "author": "}{๏Ł$ȶ",
  "category": "cars",
  "kind": "textures by name",
  "description": "Sponsor vinyls redrawn from 256 to 2048 pixels.",
  "page": "https://nfsmods.xyz/mod/7486",
  "download": "https://nfsmods.xyz/uploads/mods/7486/f0408c-UHD_SPONSORS_VINYLS.zip",
  "fileName": "UHD_SPONSORS_VINYLS.zip",
  "size": 15221356,
  "sha256": "69b080aae0c11b36b379b1fcd1b66089b59c068f0681ebf59fa04be521f9405e",
  "releases": "EU and NA",
  "include": [
   "2048/"
  ]
 },
 {
  "id": "nfsmods-7342",
  "name": "Upscaled Freeway Signs",
  "author": "}{๏Ł$ȶ",
  "category": "world",
  "kind": "texture files",
  "description": "Highway, parking and speed limit signs from 256 to 2048 pixels.",
  "page": "https://nfsmods.xyz/mod/7342",
  "download": "https://nfsmods.xyz/uploads/mods/7342/9d1294-Upscaled%20Freeway%20Signs.zip",
  "fileName": "Upscaled Freeway Signs.zip",
  "size": 52408411,
  "sha256": "aa7523da445c63d876520fa295df1dbdf34ee9a5e56d2ee421b48b89b0273f1a",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-2192",
  "name": "Brake Textures v2.0",
  "author": "Archless",
  "category": "cars",
  "kind": "textures by name",
  "description": "Brake textures redrawn at 1024 × 1024.",
  "page": "https://nfsmods.xyz/mod/2192",
  "download": "https://nfsmods.xyz/uploads/mods/2192/4150fa-Brake%20Texture%20Mod%20v2.0%20NFSU2.rar",
  "fileName": "Brake Texture Mod v2.0 NFSU2.rar",
  "size": 1755728,
  "sha256": "17d0fd4f3085b53cd84d2081e9e0507a5f110e39d0fb5c2008a91dc89840094e",
  "releases": "EU and NA"
 },
 {
  "id": "nfsmods-7036",
  "name": "Billboard JDMification",
  "author": "UGHashiriya",
  "category": "world",
  "kind": "textures by name",
  "description": "Billboards with Japanese tuning brands instead of unrelated products.",
  "page": "https://nfsmods.xyz/mod/7036",
  "download": "https://nfsmods.xyz/uploads/mods/7036/812142-Billboard%20JDMification%20v2.00.zip",
  "fileName": "Billboard JDMification v2.00.zip",
  "size": 1116837,
  "sha256": "03bf93532af7d2514047b4ceb1981b1486a28d15e2fe1b481cb32c2bcdd28c57",
  "releases": "EU and NA",
  "exclude": [
   "photos/"
  ]
 },
 {
  "id": "nfsmods-2878",
  "name": "Sport Tires for VOLK and ADVAN",
  "author": "craig",
  "category": "cars",
  "kind": "texture files",
  "description": "Sport tire textures for the VOLK and ADVAN rims, with more contrast.",
  "page": "https://nfsmods.xyz/mod/2878",
  "fileName": "sport tire texture for volk and advan.rar",
  "size": 3218659,
  "releases": "not checked in the game",
  "exclude": [
   "alternate volk decal/"
  ],
  "knownSHA256": [
   "093004900c870fe897f1c6e58041f61fe7413337873e43f5d28732ff941d6007"
  ],
  "note": "Import only for now: it converts, but its textures did not show in the test run (they appear with those rims). Download it on its page, then import it."
 },
 {
  "id": "nfsmods-7399",
  "name": "License Plate Bayview",
  "author": "}{๏Ł$ȶ",
  "category": "cars",
  "kind": "textures by name",
  "description": "The license plate from 128 to 2048 pixels.",
  "page": "https://nfsmods.xyz/mod/7399",
  "download": "https://nfsmods.xyz/uploads/mods/7399/9e67d1-License_Plate_Bayview.zip",
  "fileName": "License_Plate_Bayview.zip",
  "size": 3837536,
  "sha256": "fbc6dce8146ad20228f4902cb8cb66c2679231ef5b97ca1da96f5f5ca0712fbe",
  "releases": "EU and NA"
 },
 {
  "id": "retextured",
  "name": "RETextured v2.0",
  "author": "Dragozool",
  "category": "world",
  "kind": "TexMod pack",
  "description": "Higher-resolution roads, fences, trees and buildings.",
  "page": "https://www.gamepressure.com/download/need-for-speed-underground-2-retextured-v20-mod/ze142be",
  "fileName": "nfsu2retex20.zip",
  "size": 140432669,
  "note": "Import only: gamepressure.com gives the file to a browser after a wait.",
  "releases": "EU and NA",
  "knownSHA256": [
   "ae5cec4b208d037790fac41bb057cfea1ff03f15c262ffb305f124315749f031"
  ]
 }
]

"""
}
