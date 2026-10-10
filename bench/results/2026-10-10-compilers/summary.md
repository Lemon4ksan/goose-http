| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose-gcc-swar | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| plaintext | 256 | 1 | goose-gcc-swar | 1.711 M | 1.687–1.715 M | 1.00 | – | – | 0.000 M | 6.1 MB | 15.1 s | 23.1 s | 0 | 2 | 3 |
| plaintext | 256 | 1 | goose-gcc | 1.781 M | 1.749–1.782 M | 1.04 | – | – | 0.000 M | 6.1 MB | 15.2 s | 23.4 s | 0 | 3 | 3 |
| plaintext | 256 | 1 | goose-gcc-native | 1.743 M | 1.737–1.765 M | 1.02 | – | – | 0.000 M | 6.1 MB | 15.2 s | 23.5 s | 0 | 0 | 3 |
| plaintext | 256 | 4 | goose-gcc-swar | 4.879 M | 4.823–4.944 M | 1.00 | – | – | 0.000 M | 6.8 MB | 60.4 s | 76.5 s | 0 | 2 | 3 |
| plaintext | 256 | 4 | goose-gcc | 5.079 M | 4.861–5.095 M | 1.04 | – | – | 0.000 M | 6.6 MB | 60.5 s | 79.2 s | 0 | 3 | 3 |
| plaintext | 256 | 4 | goose-gcc-native | 5.034 M | 4.927–5.052 M | 1.03 | – | – | 0.000 M | 6.8 MB | 60.5 s | 78.5 s | 0 | 0 | 3 |
