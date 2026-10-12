## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring | A | serialize | 586.5K | 577.9K-590.0K | 0.39 | 0.66 | 6.8 | 33 | 0 |
| goose-uring | A | template | 596.6K | 596.5K-601.7K | 0.37 | 0.63 | 6.6 | 49 | 0 |
| goose-uring | B | serialize | 271.7K | 268.9K-271.9K | 0.92 | 1.43 | 14.7 | 95 | 0 |
| goose-uring | B | template | 376.3K | 374.4K-379.1K | 0.66 | 0.98 | 10.6 | 221 | 0 |
| goose-uring | C | serialize | 53.0K | 52.5K-53.4K | 4.67 | 10.6 | 75.4 | 140 | 0 |
| goose-uring | C | template | 147.1K | 142.8K-147.9K | 1.66 | 3.36 | 27.0 | 387 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring | alone | 275-282 | 99.0-103 |  |  | 146 | 0 |
| goose-uring | beside forms | 70-72 | 243-270 | 3.9K-4.1K | 142-149 | 234 | 0 |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | C | alone | bookings | 1.4K of 1.4K | 0.67 | 0.86-5.49 | 0 |
| goose-uring | C | alone | client | 480 of 480 | 0.10-0.11 | 0.78-1.57 | 0 |
| goose-uring | C | alone | encounter | 1.9K of 1.9K | 0.13 | 0.75-2.66 | 0 |
| goose-uring | C | alone | history | 1.9K of 1.9K | 0.17 | 0.71-2.06 | 0 |
| goose-uring | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.76-3.92 | 0 |
| goose-uring | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.59-1.98 | 0 |
| goose-uring | C | uploads | bookings | 1.4K of 1.4K | 1.28-1.51 | 4.19-5.26 | 0 |
| goose-uring | C | uploads | client | 480 of 480 | 1.85-2.65 | 6.55-9.60 | 0 |
| goose-uring | C | uploads | encounter | 1.9K of 1.9K | 2.09-2.23 | 7.09-9.34 | 0 |
| goose-uring | C | uploads | history | 1.9K of 1.9K | 1.03-1.11 | 4.00-5.14 | 0 |
| goose-uring | C | uploads | poll | 8.8K of 8.8K | 2.08-2.49 | 7.63-10.0 | 0 |
| goose-uring | C | uploads | shifts | 1.4K of 1.4K | 2.07-2.56 | 7.25-9.38 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | C | alone | 86.9-88.8 |  |
| goose-uring | C | uploads | 251.6-251.8 | 177-181 |

