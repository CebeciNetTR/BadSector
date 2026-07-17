# Ortak JS challenge HTML (sunucu)

Tüm sitelerde aynı challenge sayfasını göstermek için bu dizine
`template.html` koyun. Site config'teki `template` alanı boşsa engine
bu dosyayı kullanır.

## Kurulum (OVH / production)

```bash
cd /opt/badsector
cp data/challenge/template.html.example data/challenge/template.html
# HTML/CSS'inizi düzenleyin — PoW <script> otomatik enjekte edilir
nano data/challenge/template.html
docker compose up -d engine   # volume mount; restart yeterli
```

- `template.html` **git'e girmez** (gitignore). Yalnızca sunucuda yaşar.
- Site bazında UI'dan HTML yazarsanız o site global dosyayı ezer.
- Dosyayı değiştirdikten sonra ~30 sn içinde yeni HTML yüklenir (veya `docker compose restart engine`).

Env: `BADSECTOR_JS_CHALLENGE_TEMPLATE_PATH` (varsayılan `/etc/badsector/challenge/template.html`).
