## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring-cm | A | serialize | 579.0K | 555.8K-579.1K | 0.38 | 0.70 | 6.9 | 12 | 0 |
| goose-uring-cs | A | serialize | 576.7K | 576.6K-580.1K | 0.38 | 0.66 | 6.9 | 12 | 0 |
| goose-uring-cm | A | template | 586.3K | 568.4K-589.1K | 0.36 | 0.65 | 6.7 | 12 | 0 |
| goose-uring-cs | A | template | 587.9K | 587.2K-588.1K | 0.37 | 0.62 | 6.7 | 12 | 0 |
| goose-uring-cm | B | serialize | 268.9K | 258.8K-271.3K | 0.93 | 1.47 | 14.9 | 30 | 0 |
| goose-uring-cs | B | serialize | 308.3K | 306.2K-310.2K | 0.81 | 1.22 | 13.0 | 30 | 0 |
| goose-uring-cm | B | template | 377.8K | 349.7K-378.8K | 0.66 | 0.99 | 10.6 | 50 | 0 |
| goose-uring-cs | B | template | 378.4K | 378.2K-378.4K | 0.65 | 0.99 | 10.6 | 50 | 0 |
| goose-uring-cm | C | serialize | 48.9K | 45.7K-49.2K | 5.07 | 11.7 | 81.7 | 70 | 0 |
| goose-uring-cs | C | serialize | 60.3K | 60.1K-60.5K | 4.11 | 9.03 | 66.3 | 70 | 0 |
| goose-uring-cm | C | template | 143.4K | 142.8K-144.0K | 1.71 | 3.17 | 27.7 | 58 | 0 |
| goose-uring-cs | C | template | 143.9K | 143.7K-144.4K | 1.70 | 3.16 | 27.6 | 58 | 0 |

