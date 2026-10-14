| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose-27main | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs | From |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| plaintext | 256 | 1 | goose-27main | 1.597 M | 1.597–1.622 M | 1.00 | – | – | 0.000 M | 3.4 MB | 15.2 s | 23.7 s | 0 | 3 | 3 |  |
| plaintext | 256 | 1 | goose-27cold | 1.614 M | 1.590–1.657 M | 1.01 | – | – | 0.000 M | 3.4 MB | 15.2 s | 23.6 s | 0 | 0 | 3 |  |
| plaintext | 256 | 1 | goose-27hot | 1.620 M | 1.585–1.638 M | 1.01 | – | – | 0.000 M | 3.4 MB | 15.2 s | 23.9 s | 0 | 1 | 3 |  |
| plaintext | 256 | 4 | goose-27main | 5.178 M | 5.174–5.204 M | 1.00 | – | – | 0.000 M | 3.9 MB | 60.4 s | 83.5 s | 0 | 3 | 3 |  |
| plaintext | 256 | 4 | goose-27cold | 5.119 M | 4.887–5.122 M | 0.99 | – | – | 0.000 M | 3.9 MB | 60.4 s | 82.0 s | 0 | 0 | 3 |  |
| plaintext | 256 | 4 | goose-27hot | 5.135 M | 5.116–5.139 M | 0.99 | – | – | 0.000 M | 3.8 MB | 60.4 s | 82.3 s | 0 | 1 | 3 |  |
