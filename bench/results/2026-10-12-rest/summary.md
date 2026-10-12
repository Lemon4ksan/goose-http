## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring | A | serialize | 572.1K | 566.8K-576.8K | 0.41 | 0.69 | 6.9 | 33 | 0 |
| goose-epoll | A | serialize | 440.7K | 436.7K-441.5K | 0.56 | 0.88 | 9.1 | 26 | 0 |
| hyper | A | serialize | 271.3K | 270.3K-275.2K | 0.91 | 2.01 | 14.8 | 13 | 0 |
| goose-uring | A | template | 587.9K | 583.6K-595.0K | 0.38 | 0.66 | 6.8 | 49 | 0 |
| goose-epoll | A | template | 459.3K | 448.1K-460.1K | 0.55 | 0.85 | 8.7 | 43 | 0 |
| hyper | A | template | 290.2K | 288.6K-298.5K | 0.85 | 1.87 | 13.8 | 17 | 0 |
| goose-uring | B | serialize | 269.2K | 266.1K-270.3K | 0.92 | 1.47 | 14.8 | 95 | 0 |
| goose-epoll | B | serialize | 219.7K | 217.3K-220.6K | 1.19 | 1.71 | 18.3 | 87 | 0 |
| hyper | B | serialize | 148.6K | 148.5K-149.7K | 1.68 | 3.70 | 27.0 | 29 | 0 |
| goose-uring | B | template | 371.8K | 360.7K-373.0K | 0.66 | 1.05 | 10.7 | 221 | 0 |
| goose-epoll | B | template | 283.3K | 282.3K-283.8K | 0.88 | 4.28 | 14.1 | 213 | 0 |
| hyper | B | template | 194.2K | 191.4K-194.9K | 1.29 | 2.82 | 20.6 | 46 | 0 |
| goose-uring | C | serialize | 52.5K | 52.4K-52.6K | 4.72 | 10.6 | 76.2 | 140 | 0 |
| goose-epoll | C | serialize | 51.1K | 51.1K-51.3K | 4.80 | 10.1 | 78.5 | 129 | 0 |
| hyper | C | serialize | 32.2K | 31.3K-32.5K | 7.77 | 18.6 | 124.8 | 37 | 0 |
| goose-uring | C | template | 145.9K | 145.5K-146.2K | 1.68 | 3.12 | 27.3 | 387 | 0 |
| goose-epoll | C | template | 138.8K | 138.8K-139.1K | 1.79 | 2.95 | 28.8 | 376 | 0 |
| hyper | C | template | 119.3K | 116.9K-120.8K | 2.09 | 4.49 | 33.4 | 75 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring | alone | 968-977 | 20.9-22.8 |  |  | 130 | 0 |
| goose-epoll | alone | 983-998 | 20.4-24.1 |  |  | 124 | 0 |
| hyper | alone | 1.1K | 15.2-15.7 |  |  | 70 | 0 |
| goose-uring | beside forms | 151-152 | 136-137 | 6.9K-7.1K | 77.5-79.0 | 207 | 0 |
| goose-epoll | beside forms | 115-116 | 157-244 | 7.3K | 87.1-92.0 | 213 | 0 |
| hyper | beside forms | 42-73 | 132-148 | 4.8K-5.0K | 135-172 | 201 | 0 |

## Fixed rate

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | A | serialize | item | 108.9K-109.0K of 109.2K | 0.10 | 0.17-0.91 | 0 |
| goose-uring | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.16-0.91 | 0 |
| goose-uring | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.16-0.70 | 0 |
| goose-epoll | A | serialize | item | 108.9K of 109.2K | 0.10 | 0.18-0.19 | 0 |
| goose-epoll | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.17-0.18 | 0 |
| goose-epoll | A | serialize | write | 8.4K of 8.4K | 0.10-0.11 | 0.17-0.18 | 0 |
| hyper | A | serialize | item | 108.9K-109.0K of 109.2K | 0.11 | 0.37-0.80 | 0 |
| hyper | A | serialize | me | 22.4K of 22.4K | 0.10-0.11 | 0.32-0.59 | 0 |
| hyper | A | serialize | write | 8.4K of 8.4K | 0.12-0.13 | 0.32-0.61 | 0 |
| goose-uring | A | template | item | 108.9K-109.0K of 109.2K | 0.10 | 0.18-0.71 | 0 |
| goose-uring | A | template | me | 22.4K of 22.4K | 0.09 | 0.17-0.69 | 0 |
| goose-uring | A | template | write | 8.4K of 8.4K | 0.11 | 0.17-0.58 | 0 |
| goose-epoll | A | template | item | 108.9K-109.0K of 109.2K | 0.10 | 0.19-0.26 | 0 |
| goose-epoll | A | template | me | 22.4K of 22.4K | 0.09 | 0.18-0.22 | 0 |
| goose-epoll | A | template | write | 8.4K of 8.4K | 0.11 | 0.18-0.22 | 0 |
| hyper | A | template | item | 108.9K-109.0K of 109.2K | 0.11 | 0.31-9.62 | 0 |
| hyper | A | template | me | 22.4K of 22.4K | 0.10 | 0.27-8.80 | 0 |
| hyper | A | template | write | 8.4K of 8.4K | 0.12 | 0.28-7.99 | 0 |
| goose-uring | B | serialize | entries | 18.5K of 18.5K | 0.12 | 0.19-0.20 | 0 |
| goose-uring | B | serialize | patch | 7.4K of 7.4K | 0.11 | 0.18-0.19 | 0 |
| goose-uring | B | serialize | projects | 11.1K of 11.1K | 0.11 | 0.19-0.20 | 0 |
| goose-uring | B | serialize | session | 18.5K of 18.5K | 0.11 | 0.18-0.19 | 0 |
| goose-uring | B | serialize | timer | 18.5K of 18.5K | 0.10-0.11 | 0.18-0.19 | 0 |
| goose-epoll | B | serialize | entries | 18.5K of 18.5K | 0.11-0.12 | 0.19-0.38 | 0 |
| goose-epoll | B | serialize | patch | 7.4K of 7.4K | 0.11 | 0.17-0.32 | 0 |
| goose-epoll | B | serialize | projects | 11.1K of 11.1K | 0.11 | 0.18-0.31 | 0 |
| goose-epoll | B | serialize | session | 18.5K of 18.5K | 0.10-0.11 | 0.18-0.36 | 0 |
| goose-epoll | B | serialize | timer | 18.5K of 18.5K | 0.10 | 0.17-0.32 | 0 |
| hyper | B | serialize | entries | 18.5K of 18.5K | 0.14 | 0.26-2.07 | 0 |
| hyper | B | serialize | patch | 7.4K of 7.4K | 0.12-0.13 | 0.23-0.91 | 0 |
| hyper | B | serialize | projects | 11.1K of 11.1K | 0.12 | 0.23-1.30 | 0 |
| hyper | B | serialize | session | 18.5K of 18.5K | 0.12 | 0.23-1.88 | 0 |
| hyper | B | serialize | timer | 18.5K of 18.5K | 0.11-0.12 | 0.24-2.09 | 0 |
| goose-uring | B | template | entries | 18.5K of 18.5K | 0.11 | 0.17-0.19 | 0 |
| goose-uring | B | template | patch | 7.4K of 7.4K | 0.11 | 0.17 | 0 |
| goose-uring | B | template | projects | 11.1K of 11.1K | 0.11 | 0.17 | 0 |
| goose-uring | B | template | session | 18.5K of 18.5K | 0.10 | 0.17-0.18 | 0 |
| goose-uring | B | template | timer | 18.5K of 18.5K | 0.10 | 0.17-0.18 | 0 |
| goose-epoll | B | template | entries | 18.5K of 18.5K | 0.10-0.11 | 0.17 | 0 |
| goose-epoll | B | template | patch | 7.4K of 7.4K | 0.11 | 0.17 | 0 |
| goose-epoll | B | template | projects | 11.1K of 11.1K | 0.10-0.11 | 0.16-0.17 | 0 |
| goose-epoll | B | template | session | 18.5K of 18.5K | 0.10 | 0.16-0.17 | 0 |
| goose-epoll | B | template | timer | 18.5K of 18.5K | 0.10 | 0.16-0.17 | 0 |
| hyper | B | template | entries | 18.5K of 18.5K | 0.12 | 0.21-0.24 | 0 |
| hyper | B | template | patch | 7.4K of 7.4K | 0.12-0.13 | 0.20-0.22 | 0 |
| hyper | B | template | projects | 11.1K of 11.1K | 0.12 | 0.21-0.22 | 0 |
| hyper | B | template | session | 18.5K of 18.5K | 0.11 | 0.20-0.22 | 0 |
| hyper | B | template | timer | 18.5K of 18.5K | 0.11 | 0.20-0.23 | 0 |
| goose-uring | C | serialize | bookings | 1.4K of 1.4K | 0.67 | 0.85-1.36 | 0 |
| goose-uring | C | serialize | client | 480 of 480 | 0.11 | 0.49-1.00 | 0 |
| goose-uring | C | serialize | encounter | 1.9K of 1.9K | 0.13 | 0.74-1.27 | 0 |
| goose-uring | C | serialize | history | 1.9K of 1.9K | 0.17 | 0.71-0.85 | 0 |
| goose-uring | C | serialize | poll | 8.8K of 8.8K | 0.10 | 0.74-1.58 | 0 |
| goose-uring | C | serialize | shifts | 1.4K of 1.4K | 0.12 | 0.57-1.32 | 0 |
| goose-epoll | C | serialize | bookings | 1.4K of 1.4K | 0.67 | 0.86-0.93 | 0 |
| goose-epoll | C | serialize | client | 480 of 480 | 0.10-0.11 | 0.62-0.71 | 0 |
| goose-epoll | C | serialize | encounter | 1.9K of 1.9K | 0.13-0.14 | 0.66-0.72 | 0 |
| goose-epoll | C | serialize | history | 1.9K of 1.9K | 0.17-0.18 | 0.71-0.74 | 0 |
| goose-epoll | C | serialize | poll | 8.8K of 8.8K | 0.10 | 0.66-0.69 | 0 |
| goose-epoll | C | serialize | shifts | 1.4K of 1.4K | 0.12 | 0.26-0.74 | 0 |
| hyper | C | serialize | bookings | 1.4K of 1.4K | 1.14-1.17 | 1.48-2.06 | 0 |
| hyper | C | serialize | client | 480 of 480 | 0.12-0.13 | 0.21-0.85 | 0 |
| hyper | C | serialize | encounter | 1.9K of 1.9K | 0.14 | 0.51-0.82 | 0 |
| hyper | C | serialize | history | 1.9K of 1.9K | 0.19 | 0.59-0.96 | 0 |
| hyper | C | serialize | poll | 8.8K of 8.8K | 0.11-0.12 | 0.49-2.04 | 0 |
| hyper | C | serialize | shifts | 1.4K of 1.4K | 0.15-0.16 | 0.58-0.97 | 0 |
| goose-uring | C | template | bookings | 1.4K of 1.4K | 0.25 | 0.33-0.39 | 0 |
| goose-uring | C | template | client | 480 of 480 | 0.10-0.11 | 0.24-0.28 | 0 |
| goose-uring | C | template | encounter | 1.9K of 1.9K | 0.11 | 0.23-0.25 | 0 |
| goose-uring | C | template | history | 1.9K of 1.9K | 0.12 | 0.23-0.25 | 0 |
| goose-uring | C | template | poll | 8.8K of 8.8K | 0.10 | 0.23-0.24 | 0 |
| goose-uring | C | template | shifts | 1.4K of 1.4K | 0.10-0.11 | 0.14-0.17 | 0 |
| goose-epoll | C | template | bookings | 1.4K of 1.4K | 0.25 | 0.34-0.35 | 0 |
| goose-epoll | C | template | client | 480 of 480 | 0.10 | 0.14-0.22 | 0 |
| goose-epoll | C | template | encounter | 1.9K of 1.9K | 0.11 | 0.22-0.23 | 0 |
| goose-epoll | C | template | history | 1.9K of 1.9K | 0.12 | 0.24-0.25 | 0 |
| goose-epoll | C | template | poll | 8.8K of 8.8K | 0.10 | 0.22 | 0 |
| goose-epoll | C | template | shifts | 1.4K of 1.4K | 0.10-0.11 | 0.14-0.26 | 0 |
| hyper | C | template | bookings | 1.4K of 1.4K | 0.26 | 0.37-0.42 | 0 |
| hyper | C | template | client | 480 of 480 | 0.11-0.12 | 0.21-0.28 | 0 |
| hyper | C | template | encounter | 1.9K of 1.9K | 0.12 | 0.27-0.28 | 0 |
| hyper | C | template | history | 1.9K of 1.9K | 0.13-0.14 | 0.28-0.31 | 0 |
| hyper | C | template | poll | 8.8K of 8.8K | 0.11 | 0.27-0.28 | 0 |
| hyper | C | template | shifts | 1.4K of 1.4K | 0.12-0.15 | 0.18-0.31 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | A | serialize | 17.9-18.3 |  |
| goose-epoll | A | serialize | 17.5-18.0 |  |
| hyper | A | serialize | 22.6-23.0 |  |
| goose-uring | A | template | 17.9-18.5 |  |
| goose-epoll | A | template | 17.3-17.9 |  |
| hyper | A | template | 22.4 |  |
| goose-uring | B | serialize | 28.4-29.3 |  |
| goose-epoll | B | serialize | 29.0-29.8 |  |
| hyper | B | serialize | 38.9-39.5 |  |
| goose-uring | B | template | 26.7-27.0 |  |
| goose-epoll | B | template | 26.1-26.9 |  |
| hyper | B | template | 35.6-35.7 |  |
| goose-uring | C | serialize | 86.8-89.2 |  |
| goose-epoll | C | serialize | 86.7-87.1 |  |
| hyper | C | serialize | 141.0-144.3 |  |
| goose-uring | C | template | 43.3-43.7 |  |
| goose-epoll | C | template | 42.7-43.2 |  |
| hyper | C | template | 54.0-54.4 |  |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | C | alone | bookings | 1.4K of 1.4K | 0.67 | 0.87-1.00 | 0 |
| goose-uring | C | alone | client | 480 of 480 | 0.10-0.11 | 0.65-0.76 | 0 |
| goose-uring | C | alone | encounter | 1.9K of 1.9K | 0.13 | 0.82-0.94 | 0 |
| goose-uring | C | alone | history | 1.9K of 1.9K | 0.17 | 0.71-0.75 | 0 |
| goose-uring | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.82-0.93 | 0 |
| goose-uring | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.77-0.90 | 0 |
| goose-epoll | C | alone | bookings | 1.4K of 1.4K | 0.67-0.68 | 0.86-0.94 | 0 |
| goose-epoll | C | alone | client | 480 of 480 | 0.11 | 0.44-0.72 | 0 |
| goose-epoll | C | alone | encounter | 1.9K of 1.9K | 0.13 | 0.68-0.69 | 0 |
| goose-epoll | C | alone | history | 1.9K of 1.9K | 0.17 | 0.71-0.75 | 0 |
| goose-epoll | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.66-0.71 | 0 |
| goose-epoll | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.36-0.77 | 0 |
| hyper | C | alone | bookings | 1.4K of 1.4K | 1.16-1.17 | 1.46-37.9 | 0 |
| hyper | C | alone | client | 480 of 480 | 0.13-0.15 | 0.61-19.2 | 0 |
| hyper | C | alone | encounter | 1.9K of 1.9K | 0.14-0.16 | 0.59-24.2 | 0 |
| hyper | C | alone | history | 1.9K of 1.9K | 0.20 | 0.63-33.0 | 0 |
| hyper | C | alone | poll | 8.8K of 8.8K | 0.12 | 0.58-23.0 | 0 |
| hyper | C | alone | shifts | 1.4K of 1.4K | 0.14-0.19 | 0.50-21.3 | 0 |
| goose-uring | C | uploads | bookings | 1.4K of 1.4K | 3.15-3.54 | 10.2-14.8 | 0 |
| goose-uring | C | uploads | client | 480 of 480 | 3.33-3.64 | 12.6-17.4 | 0 |
| goose-uring | C | uploads | encounter | 1.9K of 1.9K | 3.33-3.44 | 11.7-16.6 | 0 |
| goose-uring | C | uploads | history | 1.9K of 1.9K | 2.55-2.63 | 8.91-11.7 | 0 |
| goose-uring | C | uploads | poll | 8.8K of 8.8K | 3.40-3.56 | 12.0-15.2 | 0 |
| goose-uring | C | uploads | shifts | 1.4K of 1.4K | 3.31-3.48 | 11.7-13.7 | 0 |
| goose-epoll | C | uploads | bookings | 1.4K of 1.4K | 0.92-0.94 | 2.32-2.69 | 0 |
| goose-epoll | C | uploads | client | 480 of 480 | 0.38-0.47 | 1.80-2.37 | 0 |
| goose-epoll | C | uploads | encounter | 1.9K of 1.9K | 0.37-0.40 | 1.78-2.23 | 0 |
| goose-epoll | C | uploads | history | 1.9K of 1.9K | 0.38-0.45 | 1.78-2.08 | 0 |
| goose-epoll | C | uploads | poll | 8.8K of 8.8K | 0.34-0.40 | 1.89-2.17 | 0 |
| goose-epoll | C | uploads | shifts | 1.4K of 1.4K | 0.32-0.58 | 1.64-2.06 | 0 |
| hyper | C | uploads | bookings | 1.4K of 1.4K | 6.71-6.95 | 18.7-20.8 | 0 |
| hyper | C | uploads | client | 480 of 480 | 5.89-6.32 | 17.5-20.0 | 0 |
| hyper | C | uploads | encounter | 1.9K of 1.9K | 6.17-6.35 | 18.2-20.1 | 0 |
| hyper | C | uploads | history | 1.9K of 1.9K | 6.20-6.41 | 18.2-20.0 | 0 |
| hyper | C | uploads | poll | 8.8K of 8.8K | 6.26-6.43 | 18.4-20.6 | 0 |
| hyper | C | uploads | shifts | 1.4K of 1.4K | 6.10-6.14 | 18.2-19.7 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | C | alone | 87.3-88.0 |  |
| goose-epoll | C | alone | 86.8-87.7 |  |
| hyper | C | alone | 142.5-146.0 |  |
| goose-uring | C | uploads | 251.9-252.4 | 636-650 |
| goose-epoll | C | uploads | 252.0-252.7 | 627-651 |
| hyper | C | uploads | 252.9-253.5 | 555-567 |

