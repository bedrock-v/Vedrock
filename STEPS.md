# STEPS.md — Vedrock İnşa Yol Haritası

Vedrock, V dilinde yazılmış bir Minecraft Bedrock Edition sunucu yazılımıdır.
Kullanılan kütüphaneler: `raknet` (taşıma katmanı), `bedrock-protocol` / `src` (paket
kodlama-çözme), `nbt` (ağ-NBT codec). Mimari ilhamı: `inspirations/PocketMine-MP` (PHP)
ve `inspirations/dragonfly` (Go). Kod yorum satırı içermez; tüm açıklamalar bu dosyadadır.

## Bağımlılık Çözümü

`raknet`, `bedrock-protocol/src`, `nbt` ayrı sibling projelerdir. V modül çözümü için
symlink şarttır:

```
ln -sfn ~/Masaüstü/Projects/raknet            ~/.vmodules/raknet
ln -sfn ~/Masaüstü/Projects/raknet/message    ~/.vmodules/message
ln -sfn ~/Masaüstü/Projects/vedrock-protocol/src ~/.vmodules/src
ln -sfn ~/Masaüstü/Projects/nbt               ~/.vmodules/nbt
```

İçe aktarma: `import raknet`, `import src as protocol`, `import nbt`. Üretim
komutlarında Türkçe yerel ayar nedeniyle `LC_ALL=C` kullan. Üretilen `*.so`/`*.c`
artıklarını sonradan sil.

## Paket Düzeni

```
v.mod                 -> modül kökü (name: vedrock)
main.v                -> module main, giriş noktası
logger/               -> module logger    (renkli, seviyeli kayıt)
config/               -> module config     (vedrock.toml okuma/üretme)
server/               -> module server     (Server, yaşam döngüsü, pong/MOTD)
network/              -> module network    (batch + sıkıştırma + Session)
session/              -> module session    (oturum durum makinesi, login akışı)
world/                -> module world      (World, Chunk, blok depolama)
player/               -> module player     (Player, kimlik, gamemode)
command/              -> module command    (komut kayıt + konsol)
```

## Mimari Kalıp

PocketMine'ın `Server` + `NetworkSession` + `Player` ayrımı ve Dragonfly'ın
`server` + `session` + `world` modülerliği örnek alınır. `Server` üst düzey
orkestratör; her bağlantı bir `Session`; oyuncu kimliği doğrulanınca bir `Player`
nesnesi oluşur.

## Fazlar

### Faz 1 — İskelet, Logger, Config, RakNet Pong  ✅
- `v.mod`, `.gitignore`.
- `logger`: seviyeler (debug/info/warn/error), ANSI renk, zaman damgası.
- `config`: `vedrock.toml` yoksa varsayılan üret, varsa oku (motd, port, max-players,
  view-distance, gamemode).
- `server`: RakNet listener bağla, Bedrock MOTD pong verisi kur (`MCPE;...`),
  accept döngüsü bağlantıları kaydeder, SIGINT ile düzgün kapanış.
- `main.v`: bootstrap.
- Çıktı: sunucu LAN listesinde görünür, ping'e yanıt verir.

### Faz 2 — Network Katmanı: Batch + Sıkıştırma
- `network`: 0xFE oyun-paketi sarmalayıcı, deflate sıkıştırma (zlib algoritması),
  uzunluk-önekli batch çözme/derleme.
- `Session`: RakNet `Conn` üstüne oturur; ham bayttan `protocol.Packet` listesine.
- PacketPool ile gelen paket çözme; giden paket derleme + sıkıştırma.

### Faz 3 — Login El Sıkışma Akışı
- RequestNetworkSettings -> NetworkSettings (sıkıştırma eşiği/algoritması).
- Login paketi: JWT zincirinden kimlik (xuid, isim, uuid) çıkar (offline doğrulama).
- PlayStatus(LoginSuccess). Şifreleme atlanır (ServerToClientHandshake yok).
- Disconnect yardımcıları.

### Faz 4 — Resource Pack + StartGame
- ResourcePacksInfo -> ResourcePackClientResponse döngüsü -> ResourcePackStack ->
  tamamlandı -> StartGame.
- StartGame alanlarını boş dünya için doldur (oyun kuralları, spawn, seed).
- CreativeContent / BiomeDefinition / ItemRegistry asgari gönderimi.

### Faz 5 — Spawn Akışı + Boş Dünya
- RequestChunkRadius -> ChunkRadiusUpdated.
- Boş LevelChunk paketleri (yarıçap içi).
- PlayStatus(PlayerSpawn), SetLocalPlayerAsInitialized işle.
- Oyuncu boş dünyada spawn olur.

### Faz 6 — World + Chunk Depolama
- `world`: Chunk (alt-yığın paletli blok depolama), World yöneticisi.
- Düz dünya üretimi (bedrock + taş + çim katmanları).
- LevelChunk seri hale getirme.

### Faz 7 — Oyuncu Yönetimi + Yayın
- `player`: PlayerList (Add/Remove), hareket (MovePlayer/PlayerAuthInput).
- Sohbet (TextPacket yayını), spawn/despawn yayını.
- Tick döngüsü (20 TPS), zaman ilerletme.

### Faz 8 — Komut Sistemi + Konsol
- `command`: kayıt, ayrıştırma, konsol gönderici.
- Yerleşik komutlar: help, stop, list, say, tp, gamemode.
- Konsol giriş okuma döngüsü.

## Doğrulama

Her faz: `LC_ALL=C v .` ile derle; mümkünse gerçek istemciyle el ile dene.
Üretilen ikili/`.so`/`.c` artıklarını temizle. Her faz kendi conventional commit'i
ile push edilir.
