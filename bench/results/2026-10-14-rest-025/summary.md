## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring-25b | A | serialize | 594.1K | 588.0K-598.7K | 0.37 | 0.63 | 6.7 | 15 | 0 |
| goose-uring-25c | A | serialize | 584.7K | 576.9K-590.7K | 0.38 | 0.68 | 6.8 | 15 | 0 |
| goose-uring-25m | A | serialize | 589.2K | 585.7K-591.9K | 0.37 | 0.65 | 6.7 | 33 | 0 |
| goose-uring-25b | A | template | 600.7K | 597.5K-604.8K | 0.35 | 0.60 | 6.5 | 23 | 0 |
| goose-uring-25c | A | template | 599.3K | 596.0K-603.8K | 0.35 | 0.62 | 6.6 | 23 | 0 |
| goose-uring-25m | A | template | 599.7K | 597.3K-600.6K | 0.36 | 0.63 | 6.6 | 49 | 0 |
| goose-uring-25b | B | serialize | 276.1K | 271.4K-278.7K | 0.90 | 1.41 | 14.5 | 47 | 0 |
| goose-uring-25c | B | serialize | 277.0K | 275.9K-282.8K | 0.89 | 1.42 | 14.4 | 47 | 0 |
| goose-uring-25m | B | serialize | 268.7K | 263.7K-270.5K | 0.92 | 1.49 | 14.9 | 95 | 0 |
| goose-uring-25b | B | template | 374.3K | 373.2K-376.7K | 0.66 | 0.99 | 10.7 | 153 | 0 |
| goose-uring-25c | B | template | 379.3K | 376.6K-380.3K | 0.66 | 0.97 | 10.5 | 152 | 0 |
| goose-uring-25m | B | template | 372.2K | 371.6K-376.0K | 0.66 | 1.01 | 10.7 | 221 | 0 |
| goose-uring-25b | C | serialize | 52.0K | 51.1K-52.4K | 4.76 | 10.9 | 76.8 | 104 | 0 |
| goose-uring-25c | C | serialize | 52.0K | 51.4K-52.6K | 4.78 | 11.6 | 76.9 | 104 | 0 |
| goose-uring-25m | C | serialize | 50.7K | 49.9K-51.1K | 4.89 | 11.4 | 78.8 | 140 | 0 |
| goose-uring-25b | C | template | 142.9K | 142.6K-146.2K | 1.71 | 3.22 | 27.8 | 257 | 0 |
| goose-uring-25c | C | template | 145.6K | 142.9K-146.0K | 1.70 | 3.20 | 27.4 | 176 | 0 |
| goose-uring-25m | C | template | 145.6K | 144.5K-146.2K | 1.67 | 3.17 | 27.3 | 387 | 0 |

