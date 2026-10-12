| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose-ef09 | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs | From |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| plaintext | 256 | 4 | goose | 5.431 M | 5.337–5.432 M | 0.97 | – | – | 0.000 M | 2.7 MB | 60.4 s | 84.5 s | 0 | 1 | 3 |  |
| plaintext | 256 | 4 | goose-ef09 | 5.605 M | 5.564–5.616 M | 1.00 | – | – | 0.000 M | 2.6 MB | 60.4 s | 86.8 s | 0 | 2 | 3 |  |
| plaintext | 256 | 4 | goose-ef09-uring | 6.873 M | 6.753–6.890 M | 1.23 | – | – | 0.000 M | 9.8 MB | 60.2 s | 96.8 s | 0 | 2 | 3 |  |
| plaintext | 256 | 4 | goose-uring | 6.665 M | 6.604–6.800 M | 1.19 | – | – | 0.000 M | 9.5 MB | 60.2 s | 94.2 s | 0 | 1 | 3 |  |
| json | 256 | 4 | goose | 0.414 M | 0.411–0.423 M | 0.99 | – | – | 0.000 M | 2.7 MB | 60.1 s | 71.4 s | 0 | 2 | 3 |  |
| json | 256 | 4 | goose-ef09 | 0.420 M | 0.418–0.421 M | 1.00 | – | – | 0.000 M | 2.6 MB | 60.1 s | 72.3 s | 0 | 2 | 3 |  |
| json | 256 | 4 | goose-ef09-uring | 0.499 M | 0.492–0.504 M | 1.19 | – | – | 0.000 M | 9.6 MB | 59.8 s | 80.6 s | 0 | 1 | 3 |  |
| json | 256 | 4 | goose-uring | 0.504 M | 0.492–0.505 M | 1.20 | – | – | 0.000 M | 8.9 MB | 59.8 s | 81.3 s | 0 | 2 | 3 |  |
