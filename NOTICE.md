# NOTICE

## Upstream

Bu depodaki `kaynak/` klasörü ve ondan derlenen `bitchord-jam.exe`, aşağıdaki projenin
`backend/` dizininden türetilmiştir:

- **Proje:** BitChord
- **Kaynak:** https://github.com/kushagrasinghx/BitChord
- **Lisans:** GNU General Public License v3.0
- **Telif:** BitChord katkıcıları

Orijinal kod GPL-3.0 altında dağıtılmaktadır. Bu depo da aynı lisansla (GPL-3.0) dağıtılır;
tam metin `LICENSE` dosyasındadır.

## Yapılan değişiklik

`kaynak/main.go` içinde tek satır:

```diff
- maxMembers := 5
+ maxMembers := config.MaxMembers
```

**Gerekçe:** `handleCreateParty` fonksiyonu parti boyutunu sabit `5` ile başlatıyordu, bu yüzden
`JAM_MAX_MEMBERS` ortam değişkeni yok sayılıyordu. Bu değişiklikle ayar gerçekten uygulanıyor.

Bunun dışında sunucu kodunda hiçbir değişiklik yapılmamıştır.

## Bu depoda yazılan kod

`kur.bat`, `kur.ps1`, `baslat.bat`, `baslat.ps1`, `durdur.bat`, `durdur.ps1`,
`sunucu-baslat.bat`, `tunel-baslat.bat` ve `README.md` bu depoya aittir ve GPL-3.0 ile lisanslanmıştır.

## Ticari marka

"BitChord" adı ilgili projenin sahiplerine aittir. Bu depo resmî bir BitChord sürümü değildir;
topluluk tarafından hazırlanmış bir kurulum aracıdır.

## Üçüncü taraf bileşenler

| Bileşen | Lisans | Kaynak |
|---|---|---|
| cloudflared | Apache-2.0 | https://github.com/cloudflare/cloudflared |
| gorilla/websocket | BSD-3-Clause | https://github.com/gorilla/websocket |
