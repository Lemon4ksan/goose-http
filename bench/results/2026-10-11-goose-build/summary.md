| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose-o | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs | From |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| plaintext | 256 | 1 | goose-o | 1.701 M | 1.613–1.887 M | 1.00 | – | – | 0.000 M | 2.1 MB | 10.1 s | 16.8 s | 0 | 1 | 5 |  |
| plaintext | 256 | 1 | goose-gb | 1.688 M | 1.604–1.813 M | 0.99 | – | – | 0.000 M | 2.1 MB | 10.2 s | 16.7 s | 0 | 1 | 5 |  |
| plaintext | 256 | 4 | goose-o | 5.188 M | 4.735–5.669 M | 1.00 | – | – | 0.000 M | 2.3 MB | 40.4 s | 59.6 s | 0 | 1 | 5 |  |
| plaintext | 256 | 4 | goose-gb | 5.628 M | 5.363–5.711 M | 1.08 | – | – | 0.000 M | 2.3 MB | 40.4 s | 60.0 s | 0 | 2 | 5 |  |
| plaintext | 1,024 | 1 | goose-o | 1.733 M | 1.481–1.845 M | 1.00 | – | – | 0.000 M | 2.2 MB | 10.1 s | 16.6 s | 0 | 2 | 5 |  |
| plaintext | 1,024 | 1 | goose-gb | 1.802 M | 1.695–1.874 M | 1.04 | – | – | 0.000 M | 2.2 MB | 10.1 s | 17.1 s | 0 | 3 | 5 |  |
| plaintext | 1,024 | 4 | goose-o | 5.244 M | 5.047–5.516 M | 1.00 | – | – | 0.000 M | 2.4 MB | 40.4 s | 59.1 s | 0 | 2 | 5 |  |
| plaintext | 1,024 | 4 | goose-gb | 5.467 M | 5.113–5.651 M | 1.04 | – | – | 0.000 M | 2.4 MB | 40.4 s | 60.1 s | 0 | 2 | 5 |  |
