| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose-uring | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs | From |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| plaintext | 1,024 | 4 | goose-uring | 7.266 M | 7.257–7.327 M | 1.00 | – | – | 0.000 M | 12.1 MB | 40.3 s | 68.6 s | 0 | 2 | 3 |  |
| plaintext | 1,024 | 4 | goose-uring-1024 | 7.309 M | 7.286–7.353 M | 1.01 | – | – | 0.000 M | 24.1 MB | 40.3 s | 68.9 s | 0 | 0 | 3 |  |
| plaintext | 4,096 | 4 | goose-uring | 6.699 M | 6.694–6.771 M | 1.00 | – | – | 0.000 M | 15.0 MB | 40.0 s | 66.5 s | 0 | 0 | 3 |  |
| plaintext | 4,096 | 4 | goose-uring-1024 | 6.604 M | 6.545–6.608 M | 0.99 | – | – | 0.000 M | 30.7 MB | 39.9 s | 65.5 s | 0 | 1 | 3 |  |
| json | 256 | 4 | goose-uring | 0.519 M | 0.506–0.520 M | 1.00 | – | – | 0.000 M | 9.4 MB | 39.9 s | 55.5 s | 0 | 1 | 3 |  |
| json | 256 | 4 | goose-uring-1024 | 0.516 M | 0.516–0.521 M | 0.99 | – | – | 0.000 M | 21.4 MB | 39.9 s | 55.4 s | 0 | 1 | 3 |  |
