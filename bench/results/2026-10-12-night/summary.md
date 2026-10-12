| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs goose-v-end | p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | Errors | Steps | Runs | From |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| plaintext | 256 | 4 | goose-v-end | 5.599 M | 5.597–5.601 M | 1.00 | 1.22 ms | 1.46 ms | 3.473 M | 2.6 MB | 60.4 s | 86.0 s | 0 | 2 | 3 |  |
| plaintext | 256 | 4 | goose-v-night | 5.559 M | 5.482–5.673 M | 0.99 | 1.22 ms | 1.44 ms | 3.485 M | 2.6 MB | 60.4 s | 86.0 s | 0 | 1 | 3 |  |
| plaintext | 256 | 4 | goose-v-end-uring | 7.056 M | 6.902–7.062 M | 1.26 | 1.20 ms | 1.44 ms | 3.533 M | 9.7 MB | 60.2 s | 98.3 s | 0 | 1 | 3 |  |
| plaintext | 256 | 4 | goose-v-night-uring | 6.971 M | 6.970–6.994 M | 1.25 | 1.21 ms | 1.47 ms | 3.480 M | 9.8 MB | 60.2 s | 97.5 s | 0 | 2 | 3 |  |
| plaintext | 1,024 | 4 | goose-v-end | 5.525 M | 5.438–5.542 M | 1.00 | 4.80 ms | 5.25 ms | 3.551 M | 2.7 MB | 60.4 s | 86.5 s | 0 | 2 | 3 |  |
| plaintext | 1,024 | 4 | goose-v-night | 5.508 M | 5.493–5.582 M | 1.00 | 4.82 ms | 5.25 ms | 3.545 M | 2.7 MB | 60.4 s | 86.4 s | 0 | 1 | 3 |  |
| plaintext | 1,024 | 4 | goose-v-end-uring | 6.816 M | 6.812–6.844 M | 1.23 | 4.79 ms | 5.31 ms | 3.537 M | 12.6 MB | 60.2 s | 96.8 s | 0 | 1 | 3 |  |
| plaintext | 1,024 | 4 | goose-v-night-uring | 6.786 M | 6.775–6.795 M | 1.23 | 4.77 ms | 5.27 ms | 3.565 M | 10.1 MB | 60.2 s | 96.5 s | 0 | 1 | 3 |  |
| plaintext | 4,096 | 4 | goose-v-end | 5.396 M | 5.370–5.397 M | 1.00 | 18.83 ms | 20.62 ms | 3.572 M | 3.0 MB | 60.1 s | 87.0 s | 0 | 2 | 3 |  |
| plaintext | 4,096 | 4 | goose-v-night | 5.386 M | 5.307–5.492 M | 1.00 | 18.65 ms | 20.21 ms | 3.597 M | 3.2 MB | 60.1 s | 86.1 s | 0 | 2 | 3 |  |
| plaintext | 4,096 | 4 | goose-v-end-uring | 6.355 M | 6.332–6.395 M | 1.18 | 18.81 ms | 20.23 ms | 3.574 M | 15.6 MB | 59.9 s | 94.4 s | 0 | 1 | 3 |  |
| plaintext | 4,096 | 4 | goose-v-night-uring | 6.351 M | 6.297–6.382 M | 1.18 | 18.62 ms | 20.25 ms | 3.615 M | 15.9 MB | 59.9 s | 94.4 s | 0 | 1 | 3 |  |
| json | 256 | 4 | goose-v-end | 0.433 M | 0.421–0.433 M | 1.00 | 0.48 ms | 0.75 ms | 0.522 M | 2.6 MB | 60.0 s | 73.9 s | 0 | 1 | 3 |  |
| json | 256 | 4 | goose-v-night | 0.431 M | 0.427–0.433 M | 1.00 | 0.49 ms | 0.76 ms | 0.519 M | 2.6 MB | 60.1 s | 73.8 s | 0 | 2 | 3 |  |
| json | 256 | 4 | goose-v-end-uring | 0.515 M | 0.510–0.517 M | 1.19 | 0.40 ms | 0.61 ms | 0.641 M | 9.6 MB | 59.8 s | 82.7 s | 0 | 2 | 3 |  |
| json | 256 | 4 | goose-v-night-uring | 0.515 M | 0.514–0.519 M | 1.19 | 0.39 ms | 0.61 ms | 0.637 M | 9.7 MB | 59.8 s | 83.0 s | 0 | 1 | 3 |  |
| json | 1,024 | 4 | goose-v-end | 0.419 M | 0.419–0.422 M | 1.00 | 2.06 ms | 2.80 ms | 0.506 M | 2.7 MB | 60.0 s | 73.5 s | 0 | 1 | 3 |  |
| json | 1,024 | 4 | goose-v-night | 0.423 M | 0.413–0.428 M | 1.01 | 2.03 ms | 2.73 ms | 0.515 M | 2.7 MB | 60.0 s | 73.9 s | 0 | 1 | 3 |  |
| json | 1,024 | 4 | goose-v-end-uring | 0.505 M | 0.502–0.507 M | 1.21 | 1.65 ms | 2.19 ms | 0.637 M | 11.8 MB | 59.8 s | 82.5 s | 0 | 2 | 3 |  |
| json | 1,024 | 4 | goose-v-night-uring | 0.502 M | 0.495–0.505 M | 1.20 | 1.66 ms | 2.23 ms | 0.631 M | 11.4 MB | 59.7 s | 82.2 s | 0 | 1 | 3 |  |
