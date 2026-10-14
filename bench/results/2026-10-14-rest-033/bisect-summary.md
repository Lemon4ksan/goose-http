## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring-bf | A | serialize | 576.6K | 571.4K-578.6K | 0.38 | 0.66 | 6.9 | 15 | 0 |
| goose-uring-bp | A | serialize | 574.0K | 570.8K-576.0K | 0.39 | 0.67 | 6.9 | 15 | 0 |
| goose-uring-bw | A | serialize | 576.0K | 572.9K-579.7K | 0.39 | 0.66 | 6.9 | 12 | 0 |
| goose-uring-cm | A | serialize | 570.0K | 565.1K-577.1K | 0.39 | 0.68 | 7.0 | 12 | 0 |
| goose-uring-cx | A | serialize | 576.1K | 574.5K-576.7K | 0.39 | 0.67 | 6.9 | 15 | 0 |
| goose-uring-bf | A | template | 586.2K | 585.0K-586.9K | 0.37 | 0.64 | 6.8 | 23 | 0 |
| goose-uring-bp | A | template | 583.7K | 583.1K-585.4K | 0.37 | 0.64 | 6.8 | 23 | 0 |
| goose-uring-bw | A | template | 586.3K | 583.4K-590.3K | 0.36 | 0.66 | 6.7 | 16 | 0 |
| goose-uring-cm | A | template | 586.0K | 584.7K-586.4K | 0.37 | 0.62 | 6.7 | 12 | 0 |
| goose-uring-cx | A | template | 586.5K | 586.4K-586.5K | 0.37 | 0.63 | 6.7 | 23 | 0 |
| goose-uring-bf | B | serialize | 270.7K | 268.6K-271.0K | 0.92 | 1.41 | 14.8 | 51 | 0 |
| goose-uring-bp | B | serialize | 271.9K | 270.7K-276.6K | 0.91 | 1.42 | 14.7 | 50 | 0 |
| goose-uring-bw | B | serialize | 270.4K | 270.0K-272.1K | 0.91 | 1.45 | 14.8 | 30 | 0 |
| goose-uring-cm | B | serialize | 271.3K | 268.7K-272.7K | 0.91 | 1.49 | 14.7 | 30 | 0 |
| goose-uring-cx | B | serialize | 275.6K | 275.4K-275.9K | 0.90 | 1.39 | 14.5 | 47 | 0 |
| goose-uring-bf | B | template | 376.5K | 376.4K-377.4K | 0.66 | 0.98 | 10.6 | 164 | 0 |
| goose-uring-bp | B | template | 379.1K | 373.1K-379.2K | 0.66 | 1.00 | 10.5 | 164 | 0 |
| goose-uring-bw | B | template | 374.2K | 372.9K-377.2K | 0.66 | 1.00 | 10.7 | 110 | 0 |
| goose-uring-cm | B | template | 374.8K | 374.6K-377.2K | 0.66 | 0.99 | 10.7 | 50 | 0 |
| goose-uring-cx | B | template | 370.6K | 368.5K-371.4K | 0.67 | 1.02 | 10.8 | 153 | 0 |
| goose-uring-bf | C | serialize | 49.6K | 49.5K-49.8K | 5.01 | 11.1 | 80.7 | 104 | 0 |
| goose-uring-bp | C | serialize | 49.7K | 48.9K-49.8K | 4.99 | 11.0 | 80.4 | 104 | 0 |
| goose-uring-bw | C | serialize | 49.7K | 48.7K-49.8K | 5.00 | 11.2 | 80.5 | 70 | 0 |
| goose-uring-cm | C | serialize | 49.2K | 48.9K-49.5K | 5.05 | 11.2 | 81.3 | 70 | 0 |
| goose-uring-cx | C | serialize | 51.1K | 50.7K-51.4K | 4.85 | 10.7 | 78.2 | 105 | 0 |
| goose-uring-bf | C | template | 142.5K | 141.9K-142.9K | 1.72 | 3.19 | 27.9 | 176 | 0 |
| goose-uring-bp | C | template | 142.0K | 141.6K-142.3K | 1.73 | 3.22 | 28.0 | 177 | 0 |
| goose-uring-bw | C | template | 142.0K | 141.2K-143.5K | 1.73 | 3.23 | 28.0 | 109 | 0 |
| goose-uring-cm | C | template | 143.8K | 140.7K-143.9K | 1.70 | 3.17 | 27.7 | 58 | 0 |
| goose-uring-cx | C | template | 142.1K | 141.8K-143.7K | 1.70 | 3.30 | 28.0 | 177 | 0 |

