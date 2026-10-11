| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs | From |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| json | 256 | 3 | goose | 0.749 M | 0.733–0.754 M | 1.00 | 0.25 ms | 1.67 ms | 0.760 M | 23.6 MB | 30.0 s | 49.0 s | 0 | 1 | 3 |  |
| json | 256 | 3 | may-minihttp | 0.579 M | 0.579–0.582 M | 0.77 | 0.36 ms | 0.84 ms | 0.664 M | 49.5 MB | 30.0 s | 39.4 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-json |
| json | 256 | 3 | hyper | 0.334 M | 0.330–0.340 M | 0.45 | 0.61 ms | 1.20 ms | 0.414 M | 14.3 MB | 30.1 s | 29.9 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-json |
| json | 256 | 3 | odin-http | 0.335 M | 0.327–0.346 M | 0.45 | 0.59 ms | 1.76 ms | 0.369 M | 10.7 MB | 30.3 s | 26.2 s | 0 | 1 | 3 | 2026-10-11-m1pro-docker-field-json |
| json | 256 | 3 | tokio | 0.624 M | 0.623–0.634 M | 0.83 | 0.33 ms | 1.06 ms | 0.704 M | 19.9 MB | 30.0 s | 42.7 s | 0 | 2 | 3 | 2026-10-11-m1pro-docker-field-json |
| json | 256 | 3 | vanilla-io_uring | 0.539 M | 0.536–0.539 M | 0.72 | 0.41 ms | 2.56 ms | 0.554 M | 107.2 MB | 28.2 s | 32.5 s | 0 | 1 | 3 | 2026-10-11-m1pro-docker-field-json |
| json | 256 | 3 | xitca-web | 0.504 M | 0.498–0.509 M | 0.67 | 0.49 ms | 0.96 ms | 0.503 M | 30.7 MB | 30.0 s | 30.2 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-json |
| json | 256 | 3 | zeemo | 0.737 M | 0.736–0.738 M | 0.98 | 0.34 ms | 0.99 ms | 0.679 M | 7.3 MB | 30.0 s | 43.6 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-json |
| json | 256 | 3 | libreactorng | 0.721 M | 0.718–0.730 M | 0.96 | 0.35 ms | 0.99 ms | 0.667 M | 9.4 MB | 30.2 s | 42.7 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-json |
| json | 256 | 3 | goose-uring | 0.826 M | 0.826–0.828 M | 1.10 | 0.24 ms | 1.64 ms | 0.777 M | 29.1 MB | 29.9 s | 52.7 s | 0 | 3 | 3 |  |
| json | 256 | 3 | dusty | 0.474 M | 0.469–0.499 M | 0.63 | 0.42 ms | 0.86 ms | 0.575 M | 12.9 MB | 30.2 s | 31.3 s | 0 | 1 | 3 |  |
| json | 256 | 3 | zix | 0.742 M | 0.737–0.744 M | 0.99 | 0.32 ms | 1.01 ms | 0.727 M | 9.9 MB | 30.1 s | 43.8 s | 0 | 1 | 3 |  |
