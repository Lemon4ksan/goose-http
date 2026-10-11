| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose-before | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs | From |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| plaintext | 256 | 3 | goose | 6.684 M | 6.643–6.841 M | 1.00 | 2.20 ms | 7.03 ms | 1.629 M | 23.6 MB | 26.6 s | 61.1 s | 0 | 2 | 3 |  |
| plaintext | 256 | 3 | goose-before | 6.712 M | 6.606–6.826 M | 1.00 | 2.19 ms | 7.13 ms | 1.595 M | 23.6 MB | 26.5 s | 60.6 s | 0 | 2 | 3 |  |
| plaintext | 1,024 | 3 | goose | 6.912 M | 6.738–6.961 M | 0.99 | 8.91 ms | 25.68 ms | 1.573 M | 23.6 MB | 27.5 s | 63.7 s | 0 | 7 | 3 |  |
| plaintext | 1,024 | 3 | goose-before | 6.957 M | 6.754–6.994 M | 1.00 | 9.01 ms | 24.73 ms | 1.570 M | 21.7 MB | 27.6 s | 64.0 s | 0 | 6 | 3 |  |
| json | 256 | 3 | goose | 0.763 M | 0.742–0.763 M | 1.00 | 0.28 ms | 1.67 ms | 0.696 M | 23.6 MB | 29.6 s | 48.5 s | 0 | 3 | 3 |  |
| json | 256 | 3 | goose-before | 0.762 M | 0.746–0.768 M | 1.00 | 0.26 ms | 1.80 ms | 0.706 M | 27.6 MB | 29.8 s | 49.2 s | 0 | 0 | 3 |  |
