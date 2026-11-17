# TweetNaCl (vendored, unchanged)

Used by the admin web page (`port/xbox/xg_admin.m`, `port/xbox/admin/admin.html`): the page encrypts
the Steam password to the Apple TV's per-launch key with `nacl.box` (X25519, XSalsa20-Poly1305), and the
app opens it with `crypto_box_open`.

| File | Source | SHA-256 |
| --- | --- | --- |
| `tweetnacl.c`, `tweetnacl.h` | https://tweetnacl.cr.yp.to/20140427/ (Bernstein, van Gastel, Janssen, Lange, Schwabe, Smetsers) | `02e65bc3…a17175c4`, `43f29ad7…31244287` |
| `nacl.min.js`, `LICENSE` | npm `tweetnacl` 1.0.3 (tweetnacl-js, Dmitry Chestnykh, Devi Mandiri), integrity `sha512-6rt+RN7a…YOn9rhaiE5yw==` checked | see `shasum -a 256` |

Licence: public domain (TweetNaCl); the Unlicense (tweetnacl-js, `LICENSE`).
The C version needs a `randombytes` function from its host: `xg_admin.m` supplies one using `arc4random_buf`.
