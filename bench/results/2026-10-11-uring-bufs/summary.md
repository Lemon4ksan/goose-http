| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose-uring | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs | From |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| plaintext | 1,024 | 4 | goose-uring | 6.934 M | 6.923–6.984 M | 1.00 | – | – | 0.000 M | 21.9 MB | 40.3 s | 65.5 s | 0 | 0 | 3 |  |
| plaintext | 1,024 | 4 | goose-uring-256 | 6.934 M | 6.823–7.005 M | 1.00 | – | – | 0.000 M | 9.5 MB | 40.2 s | 65.2 s | 0 | 1 | 3 |  |
| plaintext | 4,096 | 4 | goose-uring | 6.354 M | 6.270–6.499 M | 1.00 | – | – | 0.000 M | 32.9 MB | 40.0 s | 62.9 s | 0 | 2 | 3 |  |
| plaintext | 4,096 | 4 | goose-uring-256 | 6.454 M | 6.347–6.544 M | 1.02 | – | – | 0.000 M | 15.3 MB | 40.0 s | 63.2 s | 0 | 0 | 3 |  |
| json | 256 | 4 | goose-uring | 0.479 M | 0.479–0.495 M | 1.00 | – | – | 0.000 M | 21.5 MB | 39.9 s | 52.2 s | 0 | 0 | 3 |  |
| json | 256 | 4 | goose-uring-256 | 0.489 M | 0.488–0.496 M | 1.02 | – | – | 0.000 M | 9.4 MB | 39.8 s | 52.7 s | 0 | 1 | 3 |  |
