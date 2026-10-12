## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring | A | serialize | 582.4K | 570.2K-587.7K | 0.39 | 0.68 | 6.8 | 33 | 0 |
| goose-uring | A | template | 594.3K | 583.6K-595.7K | 0.38 | 0.63 | 6.7 | 49 | 0 |
| goose-uring | B | serialize | 270.0K | 268.8K-270.4K | 0.92 | 1.45 | 14.8 | 95 | 0 |
| goose-uring | B | template | 376.5K | 369.0K-379.0K | 0.67 | 0.99 | 10.6 | 221 | 0 |
| goose-uring | C | serialize | 52.4K | 52.4K-52.5K | 4.72 | 10.9 | 76.3 | 140 | 0 |
| goose-uring | C | template | 147.6K | 145.8K-148.4K | 1.66 | 3.10 | 27.0 | 387 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring | alone | 1.1K-1.2K | 15.9-16.3 |  |  | 130 | 0 |
| goose-uring | beside forms | 156-160 | 124-144 | 7.0K-7.1K | 75.2-77.6 | 206 | 0 |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | C | alone | bookings | 1.4K of 1.4K | 0.67 | 0.85-1.39 | 0 |
| goose-uring | C | alone | client | 480 of 480 | 0.11 | 0.50-1.18 | 0 |
| goose-uring | C | alone | encounter | 1.9K of 1.9K | 0.13 | 0.74-1.33 | 0 |
| goose-uring | C | alone | history | 1.9K of 1.9K | 0.17-0.18 | 0.71-0.87 | 0 |
| goose-uring | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.73-1.59 | 0 |
| goose-uring | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.76-0.82 | 0 |
| goose-uring | C | uploads | bookings | 1.4K of 1.4K | 2.60-2.77 | 8.59-10.9 | 0 |
| goose-uring | C | uploads | client | 480 of 480 | 2.85-3.09 | 9.02-12.0 | 0 |
| goose-uring | C | uploads | encounter | 1.9K of 1.9K | 2.94-3.04 | 10.1-12.8 | 0 |
| goose-uring | C | uploads | history | 1.9K of 1.9K | 2.15-2.39 | 8.52-10.8 | 0 |
| goose-uring | C | uploads | poll | 8.8K of 8.8K | 2.87-3.10 | 10.3-12.3 | 0 |
| goose-uring | C | uploads | shifts | 1.4K of 1.4K | 2.77-3.24 | 9.68-12.6 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | C | alone | 87.2-87.9 |  |
| goose-uring | C | uploads | 250.7-251.6 | 762-772 |

