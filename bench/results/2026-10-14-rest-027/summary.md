## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring-27b | A | serialize | 556.4K | 552.0K-587.4K | 0.38 | 0.87 | 7.1 | 33 | 0 |
| goose-uring-27m | A | serialize | 569.6K | 566.4K-572.0K | 0.39 | 0.72 | 6.9 | 33 | 0 |
| goose-uring-27q | A | serialize | 539.9K | 524.6K-584.9K | 0.42 | 0.70 | 6.8 | 33 | 0 |
| goose-uring-27b | A | template | 579.4K | 557.3K-594.9K | 0.36 | 1.11 | 6.8 | 49 | 0 |
| goose-uring-27m | A | template | 580.5K | 567.4K-594.6K | 0.36 | 0.69 | 6.8 | 49 | 0 |
| goose-uring-27q | A | template | 567.3K | 527.5K-599.9K | 0.38 | 0.68 | 6.9 | 49 | 0 |
| goose-uring-27b | B | serialize | 266.0K | 265.3K-272.0K | 0.93 | 1.71 | 15.0 | 95 | 0 |
| goose-uring-27m | B | serialize | 263.7K | 252.4K-276.9K | 0.93 | 1.79 | 15.2 | 95 | 0 |
| goose-uring-27q | B | serialize | 257.2K | 255.2K-272.1K | 0.97 | 1.54 | 15.5 | 95 | 0 |
| goose-uring-27b | B | template | 372.1K | 359.8K-381.3K | 0.66 | 1.10 | 10.7 | 221 | 0 |
| goose-uring-27m | B | template | 368.1K | 307.2K-379.0K | 0.66 | 1.43 | 10.9 | 221 | 0 |
| goose-uring-27q | B | template | 367.0K | 346.4K-372.8K | 0.67 | 1.09 | 10.9 | 221 | 0 |
| goose-uring-27b | C | serialize | 52.3K | 51.9K-53.0K | 4.74 | 10.9 | 76.5 | 140 | 0 |
| goose-uring-27m | C | serialize | 51.2K | 47.5K-51.9K | 4.84 | 10.9 | 77.9 | 140 | 0 |
| goose-uring-27q | C | serialize | 49.2K | 45.1K-51.1K | 5.02 | 11.4 | 81.1 | 140 | 0 |
| goose-uring-27b | C | template | 145.1K | 144.8K-145.9K | 1.67 | 3.39 | 27.4 | 387 | 0 |
| goose-uring-27m | C | template | 140.3K | 130.7K-144.0K | 1.75 | 3.25 | 28.3 | 387 | 0 |
| goose-uring-27q | C | template | 143.5K | 133.3K-148.8K | 1.70 | 3.34 | 27.7 | 387 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring-27b | alone | 1.0K-1.2K | 15.9-18.0 |  |  | 130 | 0 |
| goose-uring-27m | alone | 1.1K-1.2K | 16.1-16.6 |  |  | 130 | 0 |
| goose-uring-27q | alone | 1.1K-1.2K | 16.0-17.5 |  |  | 130 | 0 |
| goose-uring-27b | beside forms | 147-155 | 123-138 | 6.6K-7.4K | 73.2-78.5 | 205 | 0 |
| goose-uring-27m | beside forms | 151-162 | 116-143 | 6.7K-7.3K | 69.8-75.9 | 205 | 0 |
| goose-uring-27q | beside forms | 149-158 | 124-133 | 6.6K-7.2K | 73.2-78.5 | 206 | 0 |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring-27b | C | alone | bookings | 1.4K of 1.4K | 0.68-0.71 | 1.01-1.22 | 0 |
| goose-uring-27b | C | alone | client | 480 of 480 | 0.10-0.12 | 1.06-1.40 | 0 |
| goose-uring-27b | C | alone | encounter | 1.9K of 1.9K | 0.13-0.14 | 0.97-1.28 | 0 |
| goose-uring-27b | C | alone | history | 1.9K of 1.9K | 0.17-0.19 | 0.76-0.88 | 0 |
| goose-uring-27b | C | alone | poll | 8.8K of 8.8K | 0.10-0.11 | 0.93-1.42 | 0 |
| goose-uring-27b | C | alone | shifts | 1.4K of 1.4K | 0.12-0.13 | 0.78-1.35 | 0 |
| goose-uring-27m | C | alone | bookings | 1.4K of 1.4K | 0.68-0.85 | 0.91-2.93 | 0 |
| goose-uring-27m | C | alone | client | 480 of 480 | 0.11-0.14 | 0.63-2.53 | 0 |
| goose-uring-27m | C | alone | encounter | 1.9K of 1.9K | 0.13-0.16 | 0.78-2.20 | 0 |
| goose-uring-27m | C | alone | history | 1.9K of 1.9K | 0.17-0.23 | 0.77-2.23 | 0 |
| goose-uring-27m | C | alone | poll | 8.8K of 8.8K | 0.10-0.13 | 0.85-3.08 | 0 |
| goose-uring-27m | C | alone | shifts | 1.4K of 1.4K | 0.12-0.14 | 0.72-2.13 | 0 |
| goose-uring-27q | C | alone | bookings | 1.4K of 1.4K | 0.70-0.77 | 1.02-2.19 | 0 |
| goose-uring-27q | C | alone | client | 480 of 480 | 0.10-0.12 | 0.83-2.04 | 0 |
| goose-uring-27q | C | alone | encounter | 1.9K of 1.9K | 0.13-0.16 | 0.82-2.00 | 0 |
| goose-uring-27q | C | alone | history | 1.9K of 1.9K | 0.18-0.21 | 0.78-1.50 | 0 |
| goose-uring-27q | C | alone | poll | 8.8K of 8.8K | 0.10-0.12 | 0.88-2.38 | 0 |
| goose-uring-27q | C | alone | shifts | 1.4K of 1.4K | 0.12-0.13 | 0.53-1.84 | 0 |
| goose-uring-27b | C | uploads | bookings | 1.3K-1.4K of 1.4K | 3.36-4.64 | 10.0-1764 | 0 |
| goose-uring-27b | C | uploads | client | 412-480 of 480 | 3.46-5.21 | 11.5-2371 | 0 |
| goose-uring-27b | C | uploads | encounter | 1.6K-1.9K of 1.9K | 3.46-5.25 | 11.4-2532 | 0 |
| goose-uring-27b | C | uploads | history | 1.8K-1.9K of 1.9K | 2.67-4.52 | 9.23-1875 | 0 |
| goose-uring-27b | C | uploads | poll | 7.5K-8.8K of 8.8K | 3.47-5.29 | 11.7-2528 | 0 |
| goose-uring-27b | C | uploads | shifts | 1.2K-1.4K of 1.4K | 3.15-5.27 | 11.4-2575 | 0 |
| goose-uring-27m | C | uploads | bookings | 1.4K of 1.4K | 2.71-3.10 | 9.24-9.97 | 0 |
| goose-uring-27m | C | uploads | client | 480 of 480 | 3.07-3.38 | 10.2-12.2 | 0 |
| goose-uring-27m | C | uploads | encounter | 1.9K of 1.9K | 3.03-3.22 | 10.8-11.7 | 0 |
| goose-uring-27m | C | uploads | history | 1.9K of 1.9K | 2.29-2.42 | 8.88-9.58 | 0 |
| goose-uring-27m | C | uploads | poll | 8.8K of 8.8K | 2.92-3.33 | 10.8-11.9 | 0 |
| goose-uring-27m | C | uploads | shifts | 1.4K of 1.4K | 2.94-3.51 | 10.9-11.9 | 0 |
| goose-uring-27q | C | uploads | bookings | 1.4K of 1.4K | 2.87-3.50 | 10.8-39.2 | 0 |
| goose-uring-27q | C | uploads | client | 480 of 480 | 3.06-3.90 | 9.85-21.8 | 0 |
| goose-uring-27q | C | uploads | encounter | 1.9K of 1.9K | 3.27-3.90 | 12.3-41.3 | 0 |
| goose-uring-27q | C | uploads | history | 1.9K of 1.9K | 2.58-3.08 | 9.47-42.4 | 0 |
| goose-uring-27q | C | uploads | poll | 8.8K of 8.8K | 3.28-3.91 | 12.6-41.9 | 0 |
| goose-uring-27q | C | uploads | shifts | 1.4K of 1.4K | 3.42-3.77 | 11.5-38.2 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring-27b | C | alone | 89.9-94.6 |  |
| goose-uring-27m | C | alone | 90.4-110.5 |  |
| goose-uring-27q | C | alone | 92.7-102.6 |  |
| goose-uring-27b | C | uploads | 249.9-290.5 | 423-672 |
| goose-uring-27m | C | uploads | 248.9-252.5 | 674-736 |
| goose-uring-27q | C | uploads | 251.0-252.3 | 649-711 |

