## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring-cm | A | serialize | 563.8K | 559.0K-563.9K | 0.40 | 0.70 | 7.1 | 12 | 0 |
| goose-uring-cn | A | serialize | 559.7K | 556.2K-562.5K | 0.40 | 0.70 | 7.1 | 13 | 0 |
| goose-uring-cr | A | serialize | 564.3K | 551.3K-566.2K | 0.40 | 0.69 | 7.0 | 12 | 0 |
| goose-uring-cm | A | template | 572.9K | 572.0K-583.7K | 0.38 | 0.68 | 6.9 | 12 | 0 |
| goose-uring-cn | A | template | 575.7K | 566.4K-577.6K | 0.37 | 0.71 | 6.9 | 12 | 0 |
| goose-uring-cr | A | template | 572.0K | 569.4K-574.4K | 0.38 | 0.71 | 6.9 | 12 | 0 |
| goose-uring-cm | B | serialize | 265.9K | 264.7K-267.0K | 0.93 | 1.46 | 15.0 | 30 | 0 |
| goose-uring-cn | B | serialize | 265.9K | 263.9K-266.3K | 0.92 | 1.56 | 15.0 | 32 | 0 |
| goose-uring-cr | B | serialize | 265.7K | 264.6K-266.4K | 0.94 | 1.47 | 15.1 | 30 | 0 |
| goose-uring-cm | B | template | 366.4K | 365.3K-367.6K | 0.67 | 1.07 | 10.9 | 50 | 0 |
| goose-uring-cn | B | template | 364.5K | 362.0K-367.4K | 0.67 | 1.09 | 11.0 | 50 | 0 |
| goose-uring-cr | B | template | 371.2K | 355.7K-372.8K | 0.67 | 1.03 | 10.8 | 50 | 0 |
| goose-uring-cm | C | serialize | 48.5K | 48.1K-48.8K | 5.11 | 11.3 | 82.4 | 70 | 0 |
| goose-uring-cn | C | serialize | 48.0K | 47.7K-48.4K | 5.13 | 11.6 | 83.3 | 72 | 0 |
| goose-uring-cr | C | serialize | 48.4K | 47.8K-48.6K | 5.16 | 11.2 | 82.5 | 70 | 0 |
| goose-uring-cm | C | template | 140.1K | 136.3K-142.0K | 1.75 | 3.24 | 28.4 | 58 | 0 |
| goose-uring-cn | C | template | 140.8K | 138.0K-140.9K | 1.75 | 3.27 | 28.2 | 58 | 0 |
| goose-uring-cr | C | template | 140.7K | 140.0K-141.7K | 1.74 | 3.21 | 28.3 | 58 | 0 |

