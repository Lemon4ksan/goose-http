| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs | From |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| plaintext | 256 | 3 | goose | 6.898 M | 6.714–7.130 M | 1.00 | 2.22 ms | 7.13 ms | 1.619 M | 23.6 MB | 27.2 s | 63.1 s | 0 | 0 | 3 |  |
| plaintext | 256 | 3 | may-minihttp | 2.920 M | 2.768–2.927 M | 0.42 | 1.93 ms | 7.80 ms | 1.612 M | 80.2 MB | 20.1 s | 33.3 s | 0 | 2 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 256 | 3 | hyper | 2.241 M | 2.226–2.250 M | 0.32 | 2.12 ms | 7.29 ms | 1.608 M | 14.3 MB | 30.3 s | 26.6 s | 0 | 2 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 256 | 3 | odin-http | 0.369 M | 0.364–0.371 M | 0.05 | 8.12 ms | 13.16 ms | 0.501 M | 8.8 MB | 30.3 s | 20.4 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 256 | 3 | tokio | 5.255 M | 5.169–5.454 M | 0.76 | 2.43 ms | 7.84 ms | 1.440 M | 17.9 MB | 28.7 s | 60.4 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 256 | 3 | vanilla-epoll | 6.034 M | 5.783–6.085 M | 0.87 | 2.57 ms | 7.71 ms | 1.408 M | 13.7 MB | 27.8 s | 63.1 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 256 | 3 | vanilla-io_uring | 6.201 M | 5.367–6.744 M | 0.90 | 2.46 ms | 7.57 ms | 1.472 M | 34.6 MB | 26.0 s | 60.0 s | 0 | 4 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 256 | 3 | xitca-web | 1.875 M | 1.811–1.878 M | 0.27 | 2.86 ms | 6.88 ms | 1.336 M | 30.8 MB | 30.3 s | 16.1 s | 0 | 3 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 256 | 3 | zeemo | 2.739 M | 2.575–2.893 M | 0.40 | 2.37 ms | 7.95 ms | 1.475 M | 7.2 MB | 30.1 s | 31.8 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 256 | 3 | libreactorng | 4.598 M | 4.581–6.449 M | 0.67 | 2.35 ms | 7.63 ms | 1.501 M | 9.7 MB | 26.8 s | 55.0 s | 0 | 4 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 256 | 3 | goose-uring | 6.654 M | 6.558–6.969 M | 0.96 | 2.25 ms | 7.21 ms | 1.560 M | 29.1 MB | 28.4 s | 62.3 s | 0 | 1 | 3 |  |
| plaintext | 256 | 3 | dusty | 0.413 M | 0.367–0.511 M | 0.06 | 5.01 ms | 11.06 ms | 0.793 M | 11.2 MB | 30.3 s | 21.6 s | 0 | 2 | 3 |  |
| plaintext | 256 | 3 | zix | 4.651 M | 4.519–4.656 M | 0.67 | 2.02 ms | 6.97 ms | 1.673 M | 9.9 MB | 30.2 s | 40.6 s | 0 | 0 | 3 |  |
| plaintext | 1,024 | 3 | goose | 7.085 M | 6.596–7.361 M | 1.00 | 8.35 ms | 22.82 ms | 1.647 M | 21.6 MB | 28.4 s | 65.6 s | 0 | 3 | 3 |  |
| plaintext | 1,024 | 3 | may-minihttp | 5.475 M | 4.525–5.585 M | 0.77 | 7.83 ms | 25.86 ms | 1.617 M | 200.1 MB | 29.5 s | 54.5 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 1,024 | 3 | hyper | 2.147 M | 2.141–2.212 M | 0.30 | 9.09 ms | 26.13 ms | 1.555 M | 30.3 MB | 30.0 s | 26.4 s | 0 | 1 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 1,024 | 3 | odin-http | 0.347 M | 0.312–0.354 M | 0.05 | 40.74 ms | 54.67 ms | 0.401 M | 17.8 MB | 30.1 s | 18.5 s | 0 | 2 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 1,024 | 3 | tokio | 5.219 M | 5.051–5.242 M | 0.74 | 9.13 ms | 27.14 ms | 1.527 M | 55.8 MB | 29.7 s | 62.3 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 1,024 | 3 | vanilla-epoll | 6.026 M | 5.745–6.798 M | 0.85 | 9.31 ms | 25.68 ms | 1.549 M | 31.7 MB | 28.1 s | 64.3 s | 0 | 5 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 1,024 | 3 | vanilla-io_uring | 6.158 M | 5.261–6.839 M | 0.87 | 10.35 ms | 26.36 ms | 1.409 M | 57.6 MB | 27.7 s | 64.1 s | 0 | 1 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 1,024 | 3 | xitca-web | 1.708 M | 1.688–1.778 M | 0.24 | 12.44 ms | 28.18 ms | 1.264 M | 40.7 MB | 30.1 s | 17.8 s | 0 | 3 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 1,024 | 3 | zeemo | 2.722 M | 2.648–2.785 M | 0.38 | 9.70 ms | 28.62 ms | 1.470 M | 13.4 MB | 30.0 s | 29.6 s | 0 | 0 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 1,024 | 3 | libreactorng | 5.165 M | 4.554–6.524 M | 0.73 | 9.37 ms | 26.60 ms | 1.548 M | 27.3 MB | 28.8 s | 62.5 s | 0 | 4 | 3 | 2026-10-11-m1pro-docker-field-plaintext |
| plaintext | 1,024 | 3 | goose-uring | 6.998 M | 6.511–7.034 M | 0.99 | 8.59 ms | 25.38 ms | 1.650 M | 33.2 MB | 29.3 s | 65.2 s | 0 | 1 | 3 |  |
| plaintext | 1,024 | 3 | dusty | 0.280 M | 0.276–0.282 M | 0.04 | 32.21 ms | 80.60 ms | 0.492 M | 49.2 MB | 29.8 s | 20.4 s | 0 | 1 | 3 |  |
| plaintext | 1,024 | 3 | zix | 4.336 M | 4.310–4.434 M | 0.61 | 8.04 ms | 25.83 ms | 1.617 M | 16.1 MB | 30.0 s | 38.3 s | 0 | 1 | 3 |  |
