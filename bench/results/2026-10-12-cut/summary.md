| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose-v-before | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs | From |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| plaintext | 256 | 4 | goose-v-before | 5.689 M | 5.611–5.736 M | 1.00 | 1.23 ms | 1.59 ms | 3.429 M | 2.3 MB | 60.4 s | 88.5 s | 0 | 1 | 3 |  |
| plaintext | 256 | 4 | goose-v-cut | 5.658 M | 5.613–5.694 M | 0.99 | 1.23 ms | 1.55 ms | 3.423 M | 2.6 MB | 60.4 s | 88.2 s | 0 | 1 | 3 |  |
| plaintext | 256 | 4 | goose-v-before-uring | 6.871 M | 6.805–6.883 M | 1.21 | 1.21 ms | 1.56 ms | 3.476 M | 9.5 MB | 60.2 s | 97.2 s | 0 | 1 | 3 |  |
| plaintext | 256 | 4 | goose-v-cut-uring | 6.901 M | 6.871–6.943 M | 1.21 | 1.22 ms | 1.60 ms | 3.440 M | 9.9 MB | 60.2 s | 98.3 s | 0 | 1 | 3 |  |
| plaintext | 1,024 | 4 | goose-v-before | 5.605 M | 5.603–5.662 M | 1.00 | 4.85 ms | 5.58 ms | 3.486 M | 2.4 MB | 60.4 s | 88.8 s | 0 | 1 | 3 |  |
| plaintext | 1,024 | 4 | goose-v-cut | 5.606 M | 5.556–5.674 M | 1.00 | 4.84 ms | 5.81 ms | 3.432 M | 2.7 MB | 60.4 s | 89.2 s | 0 | 2 | 3 |  |
| plaintext | 1,024 | 4 | goose-v-before-uring | 6.722 M | 6.697–6.775 M | 1.20 | 4.80 ms | 5.68 ms | 3.512 M | 11.8 MB | 60.2 s | 97.3 s | 0 | 1 | 3 |  |
| plaintext | 1,024 | 4 | goose-v-cut-uring | 6.740 M | 6.682–6.775 M | 1.20 | 4.82 ms | 5.47 ms | 3.510 M | 12.7 MB | 60.2 s | 97.3 s | 0 | 2 | 3 |  |
| plaintext | 4,096 | 4 | goose-v-before | 5.416 M | 5.008–5.480 M | 1.00 | 18.84 ms | 21.09 ms | 3.526 M | 2.6 MB | 60.1 s | 88.5 s | 0 | 2 | 3 |  |
| plaintext | 4,096 | 4 | goose-v-cut | 5.412 M | 5.400–5.434 M | 1.00 | 18.99 ms | 21.06 ms | 3.521 M | 3.2 MB | 60.1 s | 88.5 s | 0 | 2 | 3 |  |
| plaintext | 4,096 | 4 | goose-v-before-uring | 6.240 M | 6.183–6.272 M | 1.15 | 18.93 ms | 21.22 ms | 3.538 M | 15.2 MB | 59.9 s | 94.3 s | 0 | 2 | 3 |  |
| plaintext | 4,096 | 4 | goose-v-cut-uring | 6.321 M | 6.272–6.350 M | 1.17 | 18.91 ms | 20.75 ms | 3.549 M | 15.8 MB | 59.9 s | 95.4 s | 0 | 2 | 3 |  |
| json | 256 | 4 | goose-v-before | 0.421 M | 0.415–0.428 M | 1.00 | 0.50 ms | 0.79 ms | 0.505 M | 2.4 MB | 60.1 s | 73.3 s | 0 | 2 | 3 |  |
| json | 256 | 4 | goose-v-cut | 0.422 M | 0.422–0.425 M | 1.00 | 0.51 ms | 0.80 ms | 0.508 M | 2.6 MB | 60.0 s | 72.9 s | 0 | 1 | 3 |  |
| json | 256 | 4 | goose-v-before-uring | 0.508 M | 0.488–0.511 M | 1.21 | 0.40 ms | 0.66 ms | 0.631 M | 9.4 MB | 59.8 s | 82.3 s | 0 | 2 | 3 |  |
| json | 256 | 4 | goose-v-cut-uring | 0.504 M | 0.501–0.509 M | 1.20 | 0.40 ms | 0.63 ms | 0.625 M | 9.7 MB | 59.8 s | 82.0 s | 0 | 2 | 3 |  |
| json | 1,024 | 4 | goose-v-before | 0.427 M | 0.423–0.427 M | 1.00 | 2.07 ms | 2.80 ms | 0.504 M | 2.4 MB | 60.0 s | 74.8 s | 0 | 1 | 3 |  |
| json | 1,024 | 4 | goose-v-cut | 0.421 M | 0.414–0.424 M | 0.99 | 2.07 ms | 2.83 ms | 0.502 M | 2.7 MB | 60.0 s | 74.3 s | 0 | 1 | 3 |  |
| json | 1,024 | 4 | goose-v-before-uring | 0.496 M | 0.494–0.505 M | 1.16 | 1.68 ms | 2.29 ms | 0.620 M | 12.3 MB | 59.7 s | 82.0 s | 0 | 1 | 3 |  |
| json | 1,024 | 4 | goose-v-cut-uring | 0.494 M | 0.485–0.499 M | 1.16 | 1.66 ms | 2.31 ms | 0.623 M | 11.4 MB | 59.7 s | 81.8 s | 0 | 2 | 3 |  |
