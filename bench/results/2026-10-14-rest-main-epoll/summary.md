## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-epoll-cm | A | serialize | 415.9K | 413.8K-416.5K | 0.59 | 0.98 | 9.6 | 7 | 0 |
| goose-epoll-cx | A | serialize | 412.1K | 407.0K-421.0K | 0.59 | 0.98 | 9.7 | 10 | 0 |
| goose-epoll-cm | A | template | 432.8K | 428.0K-432.9K | 0.57 | 0.95 | 9.2 | 8 | 0 |
| goose-epoll-cx | A | template | 430.5K | 425.0K-436.5K | 0.57 | 0.92 | 9.3 | 18 | 0 |
| goose-epoll-cm | B | serialize | 200.1K | 196.5K-208.8K | 1.26 | 1.96 | 20.0 | 29 | 0 |
| goose-epoll-cx | B | serialize | 212.5K | 212.1K-214.3K | 1.21 | 1.71 | 18.9 | 46 | 0 |
| goose-epoll-cm | B | template | 274.6K | 273.1K-277.0K | 0.92 | 1.38 | 14.6 | 50 | 0 |
| goose-epoll-cx | B | template | 270.8K | 268.9K-275.5K | 0.94 | 1.41 | 14.8 | 152 | 0 |
| goose-epoll-cm | C | serialize | 45.6K | 44.7K-47.1K | 5.32 | 11.2 | 88.1 | 69 | 0 |
| goose-epoll-cx | C | serialize | 47.7K | 47.3K-49.1K | 5.18 | 10.3 | 84.2 | 103 | 0 |
| goose-epoll-cm | C | template | 129.0K | 124.5K-131.2K | 1.91 | 3.23 | 31.0 | 58 | 0 |
| goose-epoll-cx | C | template | 128.2K | 128.0K-131.4K | 1.91 | 3.25 | 31.2 | 176 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-epoll-cm | alone | 1.1K | 16.1-17.3 |  |  | 69 | 0 |
| goose-epoll-cx | alone | 1.1K | 15.9-16.2 |  |  | 103 | 0 |
| goose-epoll-cm | beside forms | 110-114 | 164-203 | 7.0K-7.2K | 87.5-91.2 | 132 | 0 |
| goose-epoll-cx | beside forms | 109-114 | 174-243 | 6.9K-7.1K | 91.3-96.5 | 173 | 0 |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-epoll-cm | C | alone | bookings | 1.4K of 1.4K | 0.73-0.74 | 1.01-1.12 | 0 |
| goose-epoll-cm | C | alone | client | 480 of 480 | 0.11 | 0.71-0.86 | 0 |
| goose-epoll-cm | C | alone | encounter | 1.9K of 1.9K | 0.14 | 0.76-0.84 | 0 |
| goose-epoll-cm | C | alone | history | 1.9K of 1.9K | 0.18-0.19 | 0.81-0.91 | 0 |
| goose-epoll-cm | C | alone | poll | 8.8K of 8.8K | 0.10-0.11 | 0.77-0.83 | 0 |
| goose-epoll-cm | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.42-0.69 | 0 |
| goose-epoll-cx | C | alone | bookings | 1.4K of 1.4K | 0.70-0.71 | 0.99-1.01 | 0 |
| goose-epoll-cx | C | alone | client | 480 of 480 | 0.11-0.12 | 0.75-0.82 | 0 |
| goose-epoll-cx | C | alone | encounter | 1.9K of 1.9K | 0.14 | 0.74-0.77 | 0 |
| goose-epoll-cx | C | alone | history | 1.9K of 1.9K | 0.18 | 0.79-0.81 | 0 |
| goose-epoll-cx | C | alone | poll | 8.8K of 8.8K | 0.10-0.11 | 0.74-0.77 | 0 |
| goose-epoll-cx | C | alone | shifts | 1.4K of 1.4K | 0.12-0.13 | 0.71-0.74 | 0 |
| goose-epoll-cm | C | uploads | bookings | 1.4K of 1.4K | 0.96-1.02 | 2.46-2.62 | 0 |
| goose-epoll-cm | C | uploads | client | 480 of 480 | 0.36-0.41 | 1.80-1.97 | 0 |
| goose-epoll-cm | C | uploads | encounter | 1.9K of 1.9K | 0.40-0.47 | 1.95-2.06 | 0 |
| goose-epoll-cm | C | uploads | history | 1.9K of 1.9K | 0.43-0.44 | 1.98-2.15 | 0 |
| goose-epoll-cm | C | uploads | poll | 8.8K of 8.8K | 0.37-0.43 | 1.95-2.18 | 0 |
| goose-epoll-cm | C | uploads | shifts | 1.4K of 1.4K | 0.34-0.62 | 1.89-2.19 | 0 |
| goose-epoll-cx | C | uploads | bookings | 1.4K of 1.4K | 0.98-1.30 | 2.29-4.11 | 0 |
| goose-epoll-cx | C | uploads | client | 480 of 480 | 0.35-0.48 | 1.60-3.20 | 0 |
| goose-epoll-cx | C | uploads | encounter | 1.9K of 1.9K | 0.35-0.44 | 1.72-3.38 | 0 |
| goose-epoll-cx | C | uploads | history | 1.9K of 1.9K | 0.41-0.47 | 1.73-3.29 | 0 |
| goose-epoll-cx | C | uploads | poll | 8.8K of 8.8K | 0.35-0.41 | 1.77-3.30 | 0 |
| goose-epoll-cx | C | uploads | shifts | 1.4K of 1.4K | 0.32-0.50 | 1.68-3.38 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-epoll-cm | C | alone | 94.9-95.3 |  |
| goose-epoll-cx | C | alone | 91.9-92.8 |  |
| goose-epoll-cm | C | uploads | 252.6-253.2 | 649-680 |
| goose-epoll-cx | C | uploads | 251.4-252.8 | 626-676 |

