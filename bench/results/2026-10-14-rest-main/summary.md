## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring-cm | A | serialize | 562.4K | 556.6K-562.4K | 0.39 | 0.74 | 7.1 | 12 | 0 |
| goose-uring-cx | A | serialize | 564.0K | 556.2K-568.8K | 0.39 | 0.73 | 7.0 | 15 | 0 |
| goose-uring-cm | A | template | 577.6K | 573.3K-579.7K | 0.37 | 0.68 | 6.8 | 12 | 0 |
| goose-uring-cx | A | template | 576.8K | 561.9K-579.9K | 0.37 | 0.67 | 6.8 | 23 | 0 |
| goose-uring-cm | B | serialize | 264.0K | 262.9K-264.5K | 0.94 | 1.52 | 15.2 | 30 | 0 |
| goose-uring-cx | B | serialize | 271.2K | 271.1K-273.1K | 0.92 | 1.43 | 14.7 | 52 | 0 |
| goose-uring-cm | B | template | 365.6K | 359.7K-366.4K | 0.68 | 1.11 | 10.9 | 50 | 0 |
| goose-uring-cx | B | template | 356.4K | 355.1K-357.5K | 0.70 | 1.09 | 11.2 | 154 | 0 |
| goose-uring-cm | C | serialize | 48.1K | 47.5K-48.3K | 5.18 | 11.4 | 83.1 | 70 | 0 |
| goose-uring-cx | C | serialize | 49.8K | 49.2K-49.9K | 4.99 | 10.9 | 80.4 | 105 | 0 |
| goose-uring-cm | C | template | 140.1K | 138.9K-140.6K | 1.75 | 3.25 | 28.4 | 58 | 0 |
| goose-uring-cx | C | template | 140.3K | 139.9K-140.4K | 1.75 | 3.26 | 28.4 | 176 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring-cm | alone | 1.1K | 17.0-17.8 |  |  | 70 | 0 |
| goose-uring-cx | alone | 1.1K | 16.7-18.0 |  |  | 104 | 0 |
| goose-uring-cm | beside forms | 149-159 | 123-138 | 6.8K-7.0K | 75.6-77.2 | 126 | 0 |
| goose-uring-cx | beside forms | 150-157 | 123-126 | 6.8K-6.9K | 75.5-77.2 | 164 | 0 |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring-cm | C | alone | bookings | 1.4K of 1.4K | 0.73-0.75 | 1.09-1.28 | 0 |
| goose-uring-cm | C | alone | client | 480 of 480 | 0.11 | 0.92-1.20 | 0 |
| goose-uring-cm | C | alone | encounter | 1.9K of 1.9K | 0.14-0.16 | 1.04-1.48 | 0 |
| goose-uring-cm | C | alone | history | 1.9K of 1.9K | 0.18-0.20 | 0.83-1.00 | 0 |
| goose-uring-cm | C | alone | poll | 8.8K of 8.8K | 0.11 | 1.17-1.42 | 0 |
| goose-uring-cm | C | alone | shifts | 1.4K of 1.4K | 0.12-0.13 | 0.91-1.54 | 0 |
| goose-uring-cx | C | alone | bookings | 1.4K of 1.4K | 0.71-0.73 | 1.04-1.35 | 0 |
| goose-uring-cx | C | alone | client | 480 of 480 | 0.11-0.12 | 0.90-1.08 | 0 |
| goose-uring-cx | C | alone | encounter | 1.9K of 1.9K | 0.13-0.14 | 1.05-1.39 | 0 |
| goose-uring-cx | C | alone | history | 1.9K of 1.9K | 0.18 | 0.82-0.88 | 0 |
| goose-uring-cx | C | alone | poll | 8.8K of 8.8K | 0.11 | 0.97-1.46 | 0 |
| goose-uring-cx | C | alone | shifts | 1.4K of 1.4K | 0.12-0.13 | 0.88-1.44 | 0 |
| goose-uring-cm | C | uploads | bookings | 1.4K of 1.4K | 3.14-3.85 | 9.96-14.5 | 0 |
| goose-uring-cm | C | uploads | client | 480 of 480 | 3.48-4.05 | 11.5-14.3 | 0 |
| goose-uring-cm | C | uploads | encounter | 1.9K of 1.9K | 3.65-4.24 | 11.8-18.0 | 0 |
| goose-uring-cm | C | uploads | history | 1.9K of 1.9K | 2.52-3.10 | 8.47-14.3 | 0 |
| goose-uring-cm | C | uploads | poll | 8.8K of 8.8K | 3.56-3.88 | 11.9-16.3 | 0 |
| goose-uring-cm | C | uploads | shifts | 1.4K of 1.4K | 3.37-4.18 | 11.7-16.6 | 0 |
| goose-uring-cx | C | uploads | bookings | 1.4K of 1.4K | 3.05-3.17 | 9.22-13.5 | 0 |
| goose-uring-cx | C | uploads | client | 480 of 480 | 3.33-4.03 | 10.5-16.4 | 0 |
| goose-uring-cx | C | uploads | encounter | 1.9K of 1.9K | 3.04-3.46 | 11.3-14.0 | 0 |
| goose-uring-cx | C | uploads | history | 1.9K of 1.9K | 2.28-2.48 | 9.37-11.7 | 0 |
| goose-uring-cx | C | uploads | poll | 8.8K of 8.8K | 3.20-3.43 | 11.2-14.9 | 0 |
| goose-uring-cx | C | uploads | shifts | 1.4K of 1.4K | 3.19-3.88 | 11.3-15.5 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring-cm | C | alone | 95.5-96.2 |  |
| goose-uring-cx | C | alone | 92.8-94.4 |  |
| goose-uring-cm | C | uploads | 251.1-251.5 | 625-663 |
| goose-uring-cx | C | uploads | 250.3-251.1 | 670-704 |

