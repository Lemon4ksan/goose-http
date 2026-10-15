## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring | A | serialize | 597.9K | 594.7K-602.6K | 0.36 | 0.63 | 6.6 | 12 | 0 |
| goose-epoll | A | serialize | 444.4K | 439.8K-456.6K | 0.56 | 0.90 | 9.0 | 8 | 0 |
| goose-epoll-rest | A | serialize | 436.3K | 435.9K-440.5K | 0.57 | 0.87 | 9.2 | 27 | 0 |
| goose-uring-rest | A | serialize | 584.7K | 580.5K-585.5K | 0.38 | 0.65 | 6.8 | 33 | 0 |
| goose-uring | A | template | 603.3K | 590.4K-606.3K | 0.36 | 0.60 | 6.5 | 12 | 0 |
| goose-epoll | A | template | 467.1K | 465.6K-469.1K | 0.52 | 0.91 | 8.6 | 8 | 0 |
| goose-epoll-rest | A | template | 452.2K | 450.6K-454.1K | 0.55 | 0.83 | 8.8 | 43 | 0 |
| goose-uring-rest | A | template | 594.2K | 582.5K-594.7K | 0.37 | 0.64 | 6.7 | 49 | 0 |
| goose-uring | B | serialize | 314.5K | 311.4K-318.5K | 0.79 | 1.19 | 12.7 | 30 | 0 |
| goose-epoll | B | serialize | 243.5K | 242.5K-247.3K | 1.04 | 1.51 | 16.5 | 29 | 0 |
| goose-epoll-rest | B | serialize | 223.5K | 222.8K-223.6K | 1.15 | 1.61 | 17.9 | 87 | 0 |
| goose-uring-rest | B | serialize | 279.4K | 277.8K-279.8K | 0.89 | 1.39 | 14.3 | 96 | 0 |
| goose-uring | B | template | 394.2K | 383.0K-394.2K | 0.62 | 1.12 | 10.1 | 50 | 0 |
| goose-epoll | B | template | 290.5K | 287.3K-295.8K | 0.87 | 1.28 | 13.8 | 50 | 0 |
| goose-epoll-rest | B | template | 286.6K | 277.3K-287.0K | 0.89 | 1.26 | 14.0 | 213 | 0 |
| goose-uring-rest | B | template | 387.1K | 386.9K-390.4K | 0.64 | 0.93 | 10.3 | 222 | 0 |
| goose-uring | C | serialize | 62.4K | 61.7K-62.8K | 3.96 | 8.88 | 64.2 | 71 | 0 |
| goose-epoll | C | serialize | 60.9K | 56.9K-61.2K | 4.05 | 8.32 | 65.9 | 69 | 0 |
| goose-epoll-rest | C | serialize | 52.0K | 51.5K-52.5K | 4.74 | 9.83 | 77.1 | 129 | 0 |
| goose-uring-rest | C | serialize | 53.4K | 53.2K-54.2K | 4.65 | 10.4 | 74.9 | 140 | 0 |
| goose-uring | C | template | 146.7K | 146.1K-147.0K | 1.66 | 3.15 | 27.1 | 58 | 0 |
| goose-epoll | C | template | 136.9K | 134.1K-137.5K | 1.82 | 3.10 | 29.2 | 58 | 0 |
| goose-epoll-rest | C | template | 132.6K | 132.0K-133.4K | 1.88 | 3.18 | 30.1 | 376 | 0 |
| goose-uring-rest | C | template | 142.2K | 142.0K-142.5K | 1.72 | 3.31 | 28.0 | 387 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring | alone | 1.1K | 16.5-17.0 |  |  | 70 | 0 |
| goose-epoll | alone | 1.1K | 14.8-16.4 |  |  | 69 | 0 |
| goose-epoll-rest | alone | 979-1.0K | 21.4-22.8 |  |  | 422 | 0 |
| goose-uring-rest | alone | 969-1.0K | 21.5-22.9 |  |  | 385 | 0 |
| goose-uring | beside forms | 153-182 | 109-133 | 7.1K-7.2K | 73.6-77.2 | 126 | 0 |
| goose-epoll | beside forms | 117-120 | 170-189 | 7.4K-7.5K | 86.1-90.8 | 133 | 0 |
| goose-epoll-rest | beside forms | 108-111 | 172-195 | 7.1K-7.3K | 92.7-98.8 | 456 | 0 |
| goose-uring-rest | beside forms | 146-157 | 132-139 | 7.0K | 77.3-83.1 | 426 | 0 |

## Fixed rate

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | A | serialize | item | 77.7K-77.9K of 78.0K | 0.10 | 0.16-0.18 | 0 |
| goose-uring | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.16-0.17 | 0 |
| goose-uring | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.16-0.18 | 0 |
| goose-epoll | A | serialize | item | 77.8K of 78.0K | 0.10 | 0.16-7.18 | 0 |
| goose-epoll | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.15-9.36 | 0 |
| goose-epoll | A | serialize | write | 6.0K of 6.0K | 0.10-0.11 | 0.16-9.48 | 0 |
| goose-epoll-rest | A | serialize | item | 77.8K-77.9K of 78.0K | 0.10 | 0.15-0.18 | 0 |
| goose-epoll-rest | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.16-0.17 | 0 |
| goose-epoll-rest | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.16-0.18 | 0 |
| goose-uring-rest | A | serialize | item | 77.8K of 78.0K | 0.10 | 0.16 | 0 |
| goose-uring-rest | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.16 | 0 |
| goose-uring-rest | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.16 | 0 |
| goose-uring | A | template | item | 77.8K-77.9K of 78.0K | 0.10 | 0.16-2.48 | 0 |
| goose-uring | A | template | me | 16.0K of 16.0K | 0.09-0.10 | 0.15-1.58 | 0 |
| goose-uring | A | template | write | 6.0K of 6.0K | 0.11 | 0.16-1.34 | 0 |
| goose-epoll | A | template | item | 77.8K-77.9K of 78.0K | 0.10 | 0.16 | 0 |
| goose-epoll | A | template | me | 16.0K of 16.0K | 0.09 | 0.15-0.16 | 0 |
| goose-epoll | A | template | write | 6.0K of 6.0K | 0.11 | 0.16-0.17 | 0 |
| goose-epoll-rest | A | template | item | 77.8K of 78.0K | 0.10 | 0.16-0.17 | 0 |
| goose-epoll-rest | A | template | me | 16.0K of 16.0K | 0.09 | 0.15-0.16 | 0 |
| goose-epoll-rest | A | template | write | 6.0K of 6.0K | 0.11 | 0.17-0.18 | 0 |
| goose-uring-rest | A | template | item | 77.8K of 78.0K | 0.10 | 0.16-0.19 | 0 |
| goose-uring-rest | A | template | me | 16.0K of 16.0K | 0.09 | 0.15-0.17 | 0 |
| goose-uring-rest | A | template | write | 6.0K of 6.0K | 0.11 | 0.16-0.18 | 0 |
| goose-uring | B | serialize | entries | 6.0K of 6.0K | 0.11 | 0.15 | 0 |
| goose-uring | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-uring | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-uring | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-uring | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-epoll | B | serialize | entries | 6.0K of 6.0K | 0.10-0.11 | 0.15 | 0 |
| goose-epoll | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-epoll | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-epoll | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-epoll | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-epoll-rest | B | serialize | entries | 6.0K of 6.0K | 0.11 | 0.15-0.18 | 0 |
| goose-epoll-rest | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.14-0.17 | 0 |
| goose-epoll-rest | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.14-0.16 | 0 |
| goose-epoll-rest | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.14-0.17 | 0 |
| goose-epoll-rest | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.13-0.17 | 0 |
| goose-uring-rest | B | serialize | entries | 6.0K of 6.0K | 0.11 | 0.17-0.18 | 0 |
| goose-uring-rest | B | serialize | patch | 2.4K of 2.4K | 0.10-0.11 | 0.16-0.17 | 0 |
| goose-uring-rest | B | serialize | projects | 3.6K of 3.6K | 0.10-0.11 | 0.17 | 0 |
| goose-uring-rest | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.16-0.17 | 0 |
| goose-uring-rest | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.16 | 0 |
| goose-uring | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-uring | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-uring | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-uring | B | template | session | 6.0K of 6.0K | 0.10 | 0.13-0.14 | 0 |
| goose-uring | B | template | timer | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-epoll | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-epoll | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-epoll | B | template | session | 6.0K of 6.0K | 0.10 | 0.13 | 0 |
| goose-epoll | B | template | timer | 6.0K of 6.0K | 0.10 | 0.13-0.14 | 0 |
| goose-epoll-rest | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14-0.17 | 0 |
| goose-epoll-rest | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14-0.16 | 0 |
| goose-epoll-rest | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14-0.16 | 0 |
| goose-epoll-rest | B | template | session | 6.0K of 6.0K | 0.10 | 0.13-0.16 | 0 |
| goose-epoll-rest | B | template | timer | 6.0K of 6.0K | 0.10 | 0.14-0.16 | 0 |
| goose-uring-rest | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-uring-rest | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-uring-rest | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-uring-rest | B | template | session | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-uring-rest | B | template | timer | 6.0K of 6.0K | 0.10 | 0.13-0.14 | 0 |
| goose-uring | C | serialize | bookings | 153 of 153 | 0.69-0.70 | 0.85-0.86 | 0 |
| goose-uring | C | serialize | client | 51 of 51 | 0.11-0.12 | 0.15-0.70 | 0 |
| goose-uring | C | serialize | encounter | 204 of 204 | 0.12 | 0.18 | 0 |
| goose-uring | C | serialize | history | 204 of 204 | 0.14-0.15 | 0.20-0.73 | 0 |
| goose-uring | C | serialize | poll | 933 of 935 | 0.10 | 0.47-0.52 | 0 |
| goose-uring | C | serialize | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.18 | 0 |
| goose-epoll | C | serialize | bookings | 153 of 153 | 0.70-0.71 | 0.86-0.88 | 0 |
| goose-epoll | C | serialize | client | 51 of 51 | 0.10-0.12 | 0.14-0.72 | 0 |
| goose-epoll | C | serialize | encounter | 204 of 204 | 0.12 | 0.17-0.64 | 0 |
| goose-epoll | C | serialize | history | 204 of 204 | 0.14-0.15 | 0.20-0.67 | 0 |
| goose-epoll | C | serialize | poll | 933-934 of 935 | 0.10 | 0.49-0.51 | 0 |
| goose-epoll | C | serialize | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.18 | 0 |
| goose-epoll-rest | C | serialize | bookings | 153 of 153 | 0.76-0.77 | 0.91-0.92 | 0 |
| goose-epoll-rest | C | serialize | client | 51 of 51 | 0.11-0.12 | 0.15-0.81 | 0 |
| goose-epoll-rest | C | serialize | encounter | 204 of 204 | 0.14 | 0.19-0.71 | 0 |
| goose-epoll-rest | C | serialize | history | 204 of 204 | 0.18 | 0.24-0.78 | 0 |
| goose-epoll-rest | C | serialize | poll | 933 of 935 | 0.10-0.11 | 0.54-0.55 | 0 |
| goose-epoll-rest | C | serialize | shifts | 153 of 153 | 0.12 | 0.17-0.22 | 0 |
| goose-uring-rest | C | serialize | bookings | 153 of 153 | 0.73-0.77 | 0.90-0.93 | 0 |
| goose-uring-rest | C | serialize | client | 51 of 51 | 0.10-0.12 | 0.15-0.43 | 0 |
| goose-uring-rest | C | serialize | encounter | 204 of 204 | 0.14 | 0.19-0.43 | 0 |
| goose-uring-rest | C | serialize | history | 204 of 204 | 0.18 | 0.27-0.79 | 0 |
| goose-uring-rest | C | serialize | poll | 933-934 of 935 | 0.10 | 0.54-0.57 | 0 |
| goose-uring-rest | C | serialize | shifts | 153 of 153 | 0.12-0.13 | 0.17-0.20 | 0 |
| goose-uring | C | template | bookings | 153 of 153 | 0.29-0.30 | 0.42-0.45 | 0 |
| goose-uring | C | template | client | 51 of 51 | 0.11-0.12 | 0.15-0.27 | 0 |
| goose-uring | C | template | encounter | 204 of 204 | 0.11-0.12 | 0.17 | 0 |
| goose-uring | C | template | history | 204 of 204 | 0.13-0.14 | 0.18-0.30 | 0 |
| goose-uring | C | template | poll | 933-934 of 935 | 0.10 | 0.17-0.18 | 0 |
| goose-uring | C | template | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.17 | 0 |
| goose-epoll | C | template | bookings | 153 of 153 | 0.28-0.30 | 0.44-0.48 | 0 |
| goose-epoll | C | template | client | 51 of 51 | 0.10-0.12 | 0.15-0.22 | 0 |
| goose-epoll | C | template | encounter | 204 of 204 | 0.12 | 0.16-0.18 | 0 |
| goose-epoll | C | template | history | 204 of 204 | 0.13-0.14 | 0.18-0.28 | 0 |
| goose-epoll | C | template | poll | 934 of 935 | 0.10 | 0.17-0.23 | 0 |
| goose-epoll | C | template | shifts | 153 of 153 | 0.11-0.12 | 0.15-0.18 | 0 |
| goose-epoll-rest | C | template | bookings | 153 of 153 | 0.29-0.30 | 0.44-0.48 | 0 |
| goose-epoll-rest | C | template | client | 51 of 51 | 0.10-0.12 | 0.14-0.16 | 0 |
| goose-epoll-rest | C | template | encounter | 204 of 204 | 0.12 | 0.17-0.23 | 0 |
| goose-epoll-rest | C | template | history | 204 of 204 | 0.13-0.14 | 0.24-0.28 | 0 |
| goose-epoll-rest | C | template | poll | 933-935 of 935 | 0.10 | 0.17-0.18 | 0 |
| goose-epoll-rest | C | template | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.17 | 0 |
| goose-uring-rest | C | template | bookings | 153 of 153 | 0.28-0.29 | 0.45-0.47 | 0 |
| goose-uring-rest | C | template | client | 51 of 51 | 0.10-0.11 | 0.15-0.16 | 0 |
| goose-uring-rest | C | template | encounter | 204 of 204 | 0.12 | 0.17-0.22 | 0 |
| goose-uring-rest | C | template | history | 204 of 204 | 0.13 | 0.18-0.26 | 0 |
| goose-uring-rest | C | template | poll | 933-935 of 935 | 0.10 | 0.17 | 0 |
| goose-uring-rest | C | template | shifts | 153 of 153 | 0.11-0.12 | 0.17 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | A | serialize | 21.0-21.3 |  |
| goose-epoll | A | serialize | 20.2-21.3 |  |
| goose-epoll-rest | A | serialize | 20.3-21.8 |  |
| goose-uring-rest | A | serialize | 21.1-21.4 |  |
| goose-uring | A | template | 20.8-21.0 |  |
| goose-epoll | A | template | 20.4-21.1 |  |
| goose-epoll-rest | A | template | 20.7-21.0 |  |
| goose-uring-rest | A | template | 20.9-21.4 |  |
| goose-uring | B | serialize | 32.4-32.8 |  |
| goose-epoll | B | serialize | 32.0-32.5 |  |
| goose-epoll-rest | B | serialize | 32.8-33.3 |  |
| goose-uring-rest | B | serialize | 33.7-35.4 |  |
| goose-uring | B | template | 30.5-30.9 |  |
| goose-epoll | B | template | 30.5-30.9 |  |
| goose-epoll-rest | B | template | 30.5-31.3 |  |
| goose-uring-rest | B | template | 30.9-31.6 |  |
| goose-uring | C | serialize | 92.6-93.8 |  |
| goose-epoll | C | serialize | 92.3-93.8 |  |
| goose-epoll-rest | C | serialize | 104.4-104.8 |  |
| goose-uring-rest | C | serialize | 104.4-106.0 |  |
| goose-uring | C | template | 54.2-54.9 |  |
| goose-epoll | C | template | 53.0-54.2 |  |
| goose-epoll-rest | C | template | 54.5-55.3 |  |
| goose-uring-rest | C | template | 54.2-55.3 |  |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | C | alone | bookings | 153 of 153 | 0.70-0.71 | 0.85-0.88 | 0 |
| goose-uring | C | alone | client | 51 of 51 | 0.10-0.12 | 0.14-0.51 | 0 |
| goose-uring | C | alone | encounter | 204 of 204 | 0.12 | 0.17-0.70 | 0 |
| goose-uring | C | alone | history | 204 of 204 | 0.14-0.15 | 0.53-0.69 | 0 |
| goose-uring | C | alone | poll | 933-934 of 935 | 0.10 | 0.48-0.51 | 0 |
| goose-uring | C | alone | shifts | 153 of 153 | 0.12 | 0.17-0.18 | 0 |
| goose-epoll | C | alone | bookings | 153 of 153 | 0.69-0.70 | 0.84-0.96 | 0 |
| goose-epoll | C | alone | client | 51 of 51 | 0.10-0.12 | 0.15-0.57 | 0 |
| goose-epoll | C | alone | encounter | 204 of 204 | 0.12 | 0.17-0.43 | 0 |
| goose-epoll | C | alone | history | 204 of 204 | 0.14-0.15 | 0.21-0.68 | 0 |
| goose-epoll | C | alone | poll | 933-934 of 935 | 0.10-0.11 | 0.47-0.51 | 0 |
| goose-epoll | C | alone | shifts | 153 of 153 | 0.11-0.12 | 0.17-0.21 | 0 |
| goose-epoll-rest | C | alone | bookings | 153 of 153 | 0.70-0.74 | 0.90-0.92 | 0 |
| goose-epoll-rest | C | alone | client | 51 of 51 | 0.11-0.12 | 0.16-0.46 | 0 |
| goose-epoll-rest | C | alone | encounter | 204 of 204 | 0.14 | 0.19-0.20 | 0 |
| goose-epoll-rest | C | alone | history | 204 of 204 | 0.18 | 0.36-0.77 | 0 |
| goose-epoll-rest | C | alone | poll | 933-934 of 935 | 0.10 | 0.49-0.56 | 0 |
| goose-epoll-rest | C | alone | shifts | 153 of 153 | 0.12-0.13 | 0.16-0.17 | 0 |
| goose-uring-rest | C | alone | bookings | 153 of 153 | 0.71-0.77 | 0.91-0.96 | 0 |
| goose-uring-rest | C | alone | client | 51 of 51 | 0.11-0.12 | 0.17-0.80 | 0 |
| goose-uring-rest | C | alone | encounter | 204 of 204 | 0.14 | 0.19-0.21 | 0 |
| goose-uring-rest | C | alone | history | 204 of 204 | 0.17-0.18 | 0.25-0.75 | 0 |
| goose-uring-rest | C | alone | poll | 933-934 of 935 | 0.10-0.11 | 0.55-0.56 | 0 |
| goose-uring-rest | C | alone | shifts | 153 of 153 | 0.12 | 0.17-0.18 | 0 |
| goose-uring | C | uploads | bookings | 153 of 153 | 2.31-2.43 | 5.53-5.99 | 0 |
| goose-uring | C | uploads | client | 51 of 51 | 1.97-2.16 | 5.91-6.05 | 0 |
| goose-uring | C | uploads | encounter | 204 of 204 | 1.99-2.40 | 5.72-7.47 | 0 |
| goose-uring | C | uploads | history | 204 of 204 | 1.81-1.89 | 4.76-5.32 | 0 |
| goose-uring | C | uploads | poll | 933-934 of 935 | 2.17-2.28 | 6.73-7.41 | 0 |
| goose-uring | C | uploads | shifts | 153 of 153 | 2.11-2.38 | 5.91-6.91 | 0 |
| goose-epoll | C | uploads | bookings | 153 of 153 | 0.76-0.78 | 1.27-1.35 | 0 |
| goose-epoll | C | uploads | client | 51 of 51 | 0.18-0.21 | 0.40-1.16 | 0 |
| goose-epoll | C | uploads | encounter | 204 of 204 | 0.18-0.19 | 0.49-0.89 | 0 |
| goose-epoll | C | uploads | history | 204 of 204 | 0.21-0.25 | 0.79-0.88 | 0 |
| goose-epoll | C | uploads | poll | 934 of 935 | 0.17 | 0.77-0.84 | 0 |
| goose-epoll | C | uploads | shifts | 153 of 153 | 0.16-0.18 | 0.47-0.60 | 0 |
| goose-epoll-rest | C | uploads | bookings | 153 of 153 | 2.49-2.58 | 14.9-16.1 | 0 |
| goose-epoll-rest | C | uploads | client | 51 of 51 | 1.40-1.96 | 13.8-15.9 | 0 |
| goose-epoll-rest | C | uploads | encounter | 204 of 204 | 1.71-1.93 | 13.9-15.6 | 0 |
| goose-epoll-rest | C | uploads | history | 204 of 204 | 1.77-2.06 | 14.0-15.9 | 0 |
| goose-epoll-rest | C | uploads | poll | 933 of 935 | 1.90-2.04 | 14.3-16.1 | 0 |
| goose-epoll-rest | C | uploads | shifts | 153 of 153 | 1.71-2.08 | 14.6-15.2 | 0 |
| goose-uring-rest | C | uploads | bookings | 153 of 153 | 4.02-4.50 | 20.4-25.0 | 0 |
| goose-uring-rest | C | uploads | client | 51 of 51 | 4.48-4.80 | 23.0-27.7 | 0 |
| goose-uring-rest | C | uploads | encounter | 204 of 204 | 4.50-4.95 | 23.8-28.1 | 0 |
| goose-uring-rest | C | uploads | history | 204 of 204 | 3.41-4.06 | 21.7-23.6 | 0 |
| goose-uring-rest | C | uploads | poll | 933-934 of 935 | 4.28-4.52 | 23.9-26.4 | 0 |
| goose-uring-rest | C | uploads | shifts | 153 of 153 | 3.96-4.22 | 24.0-25.1 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | C | alone | 93.0-93.8 |  |
| goose-epoll | C | alone | 91.5-94.6 |  |
| goose-epoll-rest | C | alone | 101.7-103.6 |  |
| goose-uring-rest | C | alone | 103.2-105.6 |  |
| goose-uring | C | uploads | 2284.1-2304.4 | 1.1K |
| goose-epoll | C | uploads | 2292.9-2335.1 | 1.1K |
| goose-epoll-rest | C | uploads | 2320.2-2368.6 | 945-956 |
| goose-uring-rest | C | uploads | 2311.7-2353.2 | 935-942 |

