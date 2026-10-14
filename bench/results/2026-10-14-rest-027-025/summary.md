## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring-27f | A | serialize | 580.5K | 576.6K-584.7K | 0.38 | 0.66 | 6.8 | 15 | 0 |
| goose-uring-27h | A | serialize | 578.1K | 551.4K-581.8K | 0.38 | 0.65 | 6.8 | 15 | 0 |
| goose-uring-27n | A | serialize | 569.8K | 558.1K-584.9K | 0.39 | 0.71 | 7.0 | 15 | 0 |
| goose-uring-27s | A | serialize | 580.6K | 573.8K-580.9K | 0.38 | 0.65 | 6.8 | 12 | 0 |
| goose-uring-27w | A | serialize | 579.2K | 551.0K-580.6K | 0.38 | 0.65 | 6.8 | 12 | 0 |
| goose-uring-27f | A | template | 593.0K | 591.7K-597.4K | 0.36 | 0.62 | 6.6 | 23 | 0 |
| goose-uring-27h | A | template | 580.7K | 559.2K-593.3K | 0.37 | 0.66 | 6.8 | 23 | 0 |
| goose-uring-27n | A | template | 585.9K | 575.5K-589.5K | 0.37 | 0.71 | 6.7 | 23 | 0 |
| goose-uring-27s | A | template | 588.7K | 583.9K-593.4K | 0.36 | 0.64 | 6.7 | 12 | 0 |
| goose-uring-27w | A | template | 576.8K | 567.8K-590.2K | 0.38 | 0.70 | 6.8 | 16 | 0 |
| goose-uring-27f | B | serialize | 274.2K | 268.9K-274.9K | 0.90 | 1.47 | 14.6 | 51 | 0 |
| goose-uring-27h | B | serialize | 272.7K | 254.0K-275.6K | 0.90 | 1.57 | 14.7 | 51 | 0 |
| goose-uring-27n | B | serialize | 269.9K | 259.2K-271.8K | 0.92 | 1.45 | 14.8 | 51 | 0 |
| goose-uring-27s | B | serialize | 271.7K | 269.9K-277.5K | 0.91 | 1.43 | 14.7 | 30 | 0 |
| goose-uring-27w | B | serialize | 269.3K | 266.0K-270.5K | 0.92 | 1.46 | 14.8 | 30 | 0 |
| goose-uring-27f | B | template | 380.4K | 369.9K-385.4K | 0.65 | 0.99 | 10.5 | 165 | 0 |
| goose-uring-27h | B | template | 373.0K | 336.9K-387.6K | 0.65 | 1.04 | 10.7 | 164 | 0 |
| goose-uring-27n | B | template | 371.6K | 340.7K-378.8K | 0.66 | 1.07 | 10.7 | 165 | 0 |
| goose-uring-27s | B | template | 380.7K | 375.5K-392.3K | 0.65 | 0.99 | 10.5 | 50 | 0 |
| goose-uring-27w | B | template | 374.8K | 357.4K-377.0K | 0.67 | 1.03 | 10.7 | 111 | 0 |
| goose-uring-27f | C | serialize | 49.9K | 49.8K-50.5K | 4.95 | 11.0 | 80.1 | 104 | 0 |
| goose-uring-27h | C | serialize | 49.8K | 44.7K-50.1K | 5.00 | 11.0 | 80.3 | 105 | 0 |
| goose-uring-27n | C | serialize | 49.0K | 46.8K-50.0K | 5.05 | 11.4 | 81.6 | 104 | 0 |
| goose-uring-27s | C | serialize | 49.7K | 49.1K-50.3K | 5.00 | 11.1 | 80.5 | 71 | 0 |
| goose-uring-27w | C | serialize | 49.5K | 49.3K-50.1K | 5.02 | 11.2 | 80.9 | 70 | 0 |
| goose-uring-27f | C | template | 143.5K | 142.6K-144.7K | 1.71 | 3.17 | 27.7 | 177 | 0 |
| goose-uring-27h | C | template | 144.0K | 143.3K-144.2K | 1.70 | 3.37 | 27.6 | 177 | 0 |
| goose-uring-27n | C | template | 141.9K | 133.2K-142.1K | 1.74 | 3.29 | 28.0 | 177 | 0 |
| goose-uring-27s | C | template | 144.8K | 142.7K-146.4K | 1.69 | 3.17 | 27.5 | 58 | 0 |
| goose-uring-27w | C | template | 143.0K | 142.3K-146.3K | 1.71 | 3.26 | 27.8 | 112 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring-27f | alone | 1.1K | 16.4-16.9 |  |  | 103 | 0 |
| goose-uring-27h | alone | 1.1K | 16.0-17.3 |  |  | 104 | 0 |
| goose-uring-27n | alone | 1.1K | 16.3-18.6 |  |  | 104 | 0 |
| goose-uring-27s | alone | 1.1K | 16.4-17.1 |  |  | 70 | 0 |
| goose-uring-27w | alone | 1.1K | 16.2-16.7 |  |  | 70 | 0 |
| goose-uring-27f | beside forms | 145-151 | 138-141 | 6.9K-7.2K | 79.7-81.5 | 164 | 0 |
| goose-uring-27h | beside forms | 163-168 | 113-123 | 7.2K | 72.0-74.2 | 165 | 0 |
| goose-uring-27n | beside forms | 159-164 | 125-132 | 7.1K-7.3K | 72.7-77.6 | 164 | 0 |
| goose-uring-27s | beside forms | 151-160 | 126-139 | 7.1K-7.2K | 72.0-77.2 | 125 | 0 |
| goose-uring-27w | beside forms | 156-162 | 119-128 | 7.1K-7.2K | 71.2-73.8 | 125 | 0 |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring-27f | C | alone | bookings | 1.4K of 1.4K | 0.71-0.72 | 0.93-1.07 | 0 |
| goose-uring-27f | C | alone | client | 480 of 480 | 0.11 | 0.87-1.38 | 0 |
| goose-uring-27f | C | alone | encounter | 1.9K of 1.9K | 0.13-0.14 | 0.99-1.30 | 0 |
| goose-uring-27f | C | alone | history | 1.9K of 1.9K | 0.18 | 0.79-0.86 | 0 |
| goose-uring-27f | C | alone | poll | 8.8K of 8.8K | 0.10 | 1.05-1.31 | 0 |
| goose-uring-27f | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.87-1.30 | 0 |
| goose-uring-27h | C | alone | bookings | 1.4K of 1.4K | 0.71-0.72 | 0.95-0.99 | 0 |
| goose-uring-27h | C | alone | client | 480 of 480 | 0.11 | 1.02-1.32 | 0 |
| goose-uring-27h | C | alone | encounter | 1.9K of 1.9K | 0.13-0.14 | 1.05-1.22 | 0 |
| goose-uring-27h | C | alone | history | 1.9K of 1.9K | 0.18 | 0.78-0.79 | 0 |
| goose-uring-27h | C | alone | poll | 8.8K of 8.8K | 0.10 | 1.12-1.21 | 0 |
| goose-uring-27h | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.81-1.32 | 0 |
| goose-uring-27n | C | alone | bookings | 1.4K of 1.4K | 0.72 | 0.91-0.94 | 0 |
| goose-uring-27n | C | alone | client | 480 of 480 | 0.10-0.11 | 0.61-0.91 | 0 |
| goose-uring-27n | C | alone | encounter | 1.9K of 1.9K | 0.13-0.14 | 0.86-0.88 | 0 |
| goose-uring-27n | C | alone | history | 1.9K of 1.9K | 0.18 | 0.76-0.78 | 0 |
| goose-uring-27n | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.87-0.96 | 0 |
| goose-uring-27n | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.85-1.06 | 0 |
| goose-uring-27s | C | alone | bookings | 1.4K of 1.4K | 0.71 | 0.91-0.93 | 0 |
| goose-uring-27s | C | alone | client | 480 of 480 | 0.11 | 0.56-0.90 | 0 |
| goose-uring-27s | C | alone | encounter | 1.9K of 1.9K | 0.13-0.14 | 0.80-0.99 | 0 |
| goose-uring-27s | C | alone | history | 1.9K of 1.9K | 0.18 | 0.77-0.78 | 0 |
| goose-uring-27s | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.83-0.96 | 0 |
| goose-uring-27s | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.78-0.94 | 0 |
| goose-uring-27w | C | alone | bookings | 1.4K of 1.4K | 0.71-0.72 | 0.91-0.98 | 0 |
| goose-uring-27w | C | alone | client | 480 of 480 | 0.11 | 0.80-1.13 | 0 |
| goose-uring-27w | C | alone | encounter | 1.9K of 1.9K | 0.13-0.14 | 0.84-1.10 | 0 |
| goose-uring-27w | C | alone | history | 1.9K of 1.9K | 0.18 | 0.78-0.80 | 0 |
| goose-uring-27w | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.86-1.20 | 0 |
| goose-uring-27w | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.36-1.24 | 0 |
| goose-uring-27f | C | uploads | bookings | 1.4K of 1.4K | 2.87-2.97 | 8.31-11.8 | 0 |
| goose-uring-27f | C | uploads | client | 480 of 480 | 3.12-3.29 | 10.3-13.9 | 0 |
| goose-uring-27f | C | uploads | encounter | 1.9K of 1.9K | 2.87-3.21 | 10.6-12.1 | 0 |
| goose-uring-27f | C | uploads | history | 1.9K of 1.9K | 2.25-2.50 | 8.18-10.9 | 0 |
| goose-uring-27f | C | uploads | poll | 8.8K of 8.8K | 3.15-3.29 | 11.0-13.3 | 0 |
| goose-uring-27f | C | uploads | shifts | 1.4K of 1.4K | 2.76-3.27 | 9.94-12.3 | 0 |
| goose-uring-27h | C | uploads | bookings | 1.4K of 1.4K | 2.87-3.06 | 8.02-11.0 | 0 |
| goose-uring-27h | C | uploads | client | 480 of 480 | 3.06-3.83 | 9.74-13.1 | 0 |
| goose-uring-27h | C | uploads | encounter | 1.9K of 1.9K | 3.26-3.43 | 10.2-11.6 | 0 |
| goose-uring-27h | C | uploads | history | 1.9K of 1.9K | 2.38-2.65 | 8.05-9.98 | 0 |
| goose-uring-27h | C | uploads | poll | 8.8K of 8.8K | 3.33-3.49 | 10.7-12.0 | 0 |
| goose-uring-27h | C | uploads | shifts | 1.4K of 1.4K | 3.26-3.42 | 10.2-13.0 | 0 |
| goose-uring-27n | C | uploads | bookings | 1.4K of 1.4K | 2.76-2.88 | 8.67-10.6 | 0 |
| goose-uring-27n | C | uploads | client | 480 of 480 | 2.94-3.26 | 9.21-12.4 | 0 |
| goose-uring-27n | C | uploads | encounter | 1.9K of 1.9K | 3.00-3.27 | 10.4-11.9 | 0 |
| goose-uring-27n | C | uploads | history | 1.9K of 1.9K | 2.29-2.38 | 7.71-9.18 | 0 |
| goose-uring-27n | C | uploads | poll | 8.8K of 8.8K | 2.99-3.15 | 10.5-12.4 | 0 |
| goose-uring-27n | C | uploads | shifts | 1.4K of 1.4K | 3.04-3.32 | 9.91-12.5 | 0 |
| goose-uring-27s | C | uploads | bookings | 1.4K of 1.4K | 2.86-2.95 | 8.08-9.84 | 0 |
| goose-uring-27s | C | uploads | client | 480 of 480 | 3.18-3.56 | 9.28-11.7 | 0 |
| goose-uring-27s | C | uploads | encounter | 1.9K of 1.9K | 3.11-3.33 | 9.71-11.6 | 0 |
| goose-uring-27s | C | uploads | history | 1.9K of 1.9K | 2.43-2.56 | 7.82-9.22 | 0 |
| goose-uring-27s | C | uploads | poll | 8.8K of 8.8K | 3.25-3.27 | 10.1-11.5 | 0 |
| goose-uring-27s | C | uploads | shifts | 1.4K of 1.4K | 3.12-3.39 | 9.69-11.4 | 0 |
| goose-uring-27w | C | uploads | bookings | 1.4K of 1.4K | 2.87-3.25 | 9.16-13.9 | 0 |
| goose-uring-27w | C | uploads | client | 480 of 480 | 3.15-3.63 | 11.3-16.0 | 0 |
| goose-uring-27w | C | uploads | encounter | 1.9K of 1.9K | 3.17-3.43 | 11.0-12.7 | 0 |
| goose-uring-27w | C | uploads | history | 1.9K of 1.9K | 2.40-2.99 | 8.87-13.9 | 0 |
| goose-uring-27w | C | uploads | poll | 8.8K of 8.8K | 3.33-3.53 | 11.4-14.3 | 0 |
| goose-uring-27w | C | uploads | shifts | 1.4K of 1.4K | 3.23-3.68 | 11.0-15.8 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring-27f | C | alone | 92.3-92.5 |  |
| goose-uring-27h | C | alone | 92.3-93.3 |  |
| goose-uring-27n | C | alone | 92.9-93.8 |  |
| goose-uring-27s | C | alone | 92.9-93.6 |  |
| goose-uring-27w | C | alone | 92.7-93.3 |  |
| goose-uring-27f | C | uploads | 250.2-252.6 | 705-715 |
| goose-uring-27h | C | uploads | 251.0-252.0 | 716-720 |
| goose-uring-27n | C | uploads | 250.8-252.4 | 726-727 |
| goose-uring-27s | C | uploads | 251.4-252.4 | 697-712 |
| goose-uring-27w | C | uploads | 250.9-252.0 | 718-732 |

