## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring | A | serialize | 584.9K | 580.5K-600.6K | 0.39 | 0.67 | 6.8 | 33 | 0 |
| goose-epoll | A | serialize | 455.5K | 437.0K-462.4K | 0.56 | 0.83 | 8.8 | 26 | 0 |
| hyper | A | serialize | 274.5K | 273.5K-281.3K | 0.90 | 1.99 | 14.6 | 13 | 0 |
| tokio | A | serialize | 394.2K | 388.2K-406.3K | 0.64 | 0.97 | 10.1 | 16 | 0 |
| may-minihttp | A | serialize | 383.5K | 378.5K-388.9K | 0.68 | 0.93 | 10.4 | 45 | 0 |
| xitca-web | A | serialize | 403.6K | 401.6K-415.4K | 0.63 | 0.89 | 9.9 | 32 | 0 |
| odin-http | A | serialize | 209.6K | 207.8K-211.9K | 1.10 | 3.11 | 19.1 | 11 | 0 |
| tina | A | serialize | 311.8K | 296.9K-317.6K | 0.80 | 1.17 | 12.9 | 482 | 0 |
| goose-uring | A | template | 594.5K | 584.4K-602.8K | 0.38 | 0.66 | 6.7 | 49 | 0 |
| goose-epoll | A | template | 470.9K | 464.1K-489.2K | 0.54 | 0.84 | 8.5 | 43 | 0 |
| hyper | A | template | 293.1K | 291.8K-295.6K | 0.84 | 1.88 | 13.7 | 16 | 0 |
| tokio | A | template | 427.7K | 424.2K-444.7K | 0.57 | 1.06 | 9.4 | 19 | 0 |
| may-minihttp | A | template | 412.6K | 412.4K-422.9K | 0.63 | 0.88 | 9.7 | 67 | 0 |
| xitca-web | A | template | 424.9K | 423.0K-439.1K | 0.58 | 0.96 | 9.4 | 34 | 0 |
| odin-http | A | template | 253.8K | 253.2K-259.3K | 0.89 | 2.51 | 15.8 | 14 | 0 |
| tina | A | template | 439.2K | 438.6K-443.8K | 0.56 | 0.77 | 9.1 | 485 | 0 |
| goose-uring | B | serialize | 268.0K | 265.8K-269.0K | 0.93 | 1.46 | 14.9 | 95 | 0 |
| goose-epoll | B | serialize | 222.0K | 218.3K-222.8K | 1.15 | 1.64 | 18.1 | 87 | 0 |
| hyper | B | serialize | 150.2K | 148.9K-152.3K | 1.67 | 3.70 | 26.7 | 29 | 0 |
| tokio | B | serialize | 183.4K | 182.2K-185.7K | 1.37 | 2.11 | 21.9 | 30 | 0 |
| may-minihttp | B | serialize | 186.1K | 183.6K-186.5K | 1.42 | 1.87 | 21.6 | 72 | 0 |
| xitca-web | B | serialize | 232.6K | 226.3K-234.5K | 1.07 | 1.85 | 17.2 | 70 | 0 |
| odin-http | B | serialize | 47.4K | 47.2K-48.0K | 4.91 | 14.4 | 84.6 | 83 | 0 |
| tina | B | serialize | 52.2K | 51.2K-52.5K | 4.64 | 9.83 | 77.2 | 518 | 0 |
| goose-uring | B | template | 376.3K | 369.3K-377.8K | 0.66 | 1.01 | 10.6 | 221 | 0 |
| goose-epoll | B | template | 295.2K | 288.0K-295.9K | 0.89 | 1.19 | 13.6 | 213 | 0 |
| hyper | B | template | 196.7K | 196.7K-196.9K | 1.27 | 2.79 | 20.3 | 46 | 0 |
| tokio | B | template | 268.7K | 265.1K-268.8K | 0.98 | 1.28 | 14.9 | 49 | 0 |
| may-minihttp | B | template | 273.0K | 272.5K-276.3K | 0.97 | 1.23 | 14.7 | 100 | 0 |
| xitca-web | B | template | 304.8K | 302.3K-308.7K | 0.83 | 1.14 | 13.1 | 78 | 0 |
| odin-http | B | template | 190.3K | 189.1K-194.2K | 1.23 | 3.20 | 21.1 | 101 | 0 |
| tina | B | template | 337.5K | 333.2K-341.1K | 0.74 | 1.12 | 11.9 | 538 | 0 |
| goose-uring | C | serialize | 51.8K | 51.7K-52.9K | 4.76 | 10.9 | 77.2 | 140 | 0 |
| goose-epoll | C | serialize | 51.9K | 51.2K-52.5K | 4.74 | 9.82 | 77.2 | 129 | 0 |
| hyper | C | serialize | 32.0K | 31.8K-32.5K | 7.81 | 18.8 | 125.5 | 36 | 0 |
| tokio | C | serialize | 31.7K | 30.1K-31.9K | 7.80 | 17.5 | 126.6 | 300 | 0 |
| may-minihttp | C | serialize | 32.3K | 31.6K-32.4K | 7.65 | 16.9 | 124.2 | 438 | 0 |
| xitca-web | C | serialize | 37.9K | 37.4K-38.1K | 6.42 | 15.3 | 105.4 | 476 | 0 |
| odin-http | C | serialize | 3.4K | 3.4K-3.5K | 69.0 | 221 | 1171.1 | 413 | 0 |
| tina | C | serialize | 3.4K | 3.3K-3.5K | 59.2 | 417 | 1179.9 | 648 | 0 |
| goose-uring | C | template | 143.9K | 140.5K-145.2K | 1.71 | 3.19 | 27.6 | 387 | 0 |
| goose-epoll | C | template | 140.0K | 138.6K-140.8K | 1.77 | 3.09 | 28.6 | 376 | 0 |
| hyper | C | template | 119.2K | 117.6K-120.4K | 2.08 | 4.58 | 33.4 | 75 | 0 |
| tokio | C | template | 101.5K | 101.2K-104.5K | 2.39 | 4.30 | 39.5 | 368 | 0 |
| may-minihttp | C | template | 100.4K | 99.9K-101.4K | 2.48 | 4.12 | 39.9 | 490 | 0 |
| xitca-web | C | template | 109.5K | 107.8K-109.7K | 2.23 | 4.20 | 36.1 | 505 | 0 |
| odin-http | C | template | 38.3K | 38.2K-38.6K | 6.20 | 17.5 | 98.0 | 476 | 0 |
| tina | C | template | 99.8K | 99.4K-101.2K | 1.86 | 13.1 | 39.9 | 672 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring | alone | 1.1K-1.2K | 15.9-16.1 |  |  | 130 | 0 |
| goose-epoll | alone | 1.1K-1.2K | 14.4-15.4 |  |  | 124 | 0 |
| hyper | alone | 1.1K | 14.9-15.3 |  |  | 78 | 0 |
| tokio | alone | 1.0K-1.1K | 19.7-20.2 |  |  | 368 | 0 |
| xitca-web | alone | 986-1.0K | 17.4-23.4 |  |  | 56 | 0 |
| odin-http | alone | 704-715 | 37.2-37.5 |  |  | 821 | 0 |
| goose-uring | beside forms | 160-166 | 127-131 | 7.1K-7.3K | 74.3-77.8 | 205 | 0 |
| goose-epoll | beside forms | 113-117 | 172-213 | 7.4K-7.6K | 85.4-94.8 | 214 | 0 |
| hyper | beside forms | 51-60 | 143-150 | 4.9K | 143-155 | 195 | 0 |
| tokio | beside forms | 264-271 | 78.3-82.0 | 3.7K-3.8K | 110-120 | 477 | 0 |
| xitca-web | beside forms | 47-71 | 270-348 | 4.3K-4.5K | 166-177 | 185 | 0 |
| odin-http | beside forms | 120-121 | 207-209 | 820-826 | 1110-1140 | 1255 | 0 |

## Fixed rate

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | A | serialize | item | 77.8K-77.9K of 78.0K | 0.10 | 0.16-0.18 | 0 |
| goose-uring | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.16 | 0 |
| goose-uring | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.17 | 0 |
| goose-epoll | A | serialize | item | 77.7K-77.8K of 78.0K | 0.09-0.10 | 0.16-0.17 | 0 |
| goose-epoll | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.16 | 0 |
| goose-epoll | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.16-0.17 | 0 |
| hyper | A | serialize | item | 77.8K-77.9K of 78.0K | 0.11 | 0.21-2.62 | 0 |
| hyper | A | serialize | me | 16.0K of 16.0K | 0.10-0.11 | 0.20-6.48 | 0 |
| hyper | A | serialize | write | 6.0K of 6.0K | 0.12 | 0.21-2.10 | 0 |
| tokio | A | serialize | item | 77.8K of 78.0K | 0.10 | 0.17-0.19 | 0 |
| tokio | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.16-0.18 | 0 |
| tokio | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.17-0.20 | 0 |
| may-minihttp | A | serialize | item | 77.8K of 78.0K | 0.10 | 0.16-0.17 | 0 |
| may-minihttp | A | serialize | me | 16.0K of 16.0K | 0.09-0.10 | 0.16-0.17 | 0 |
| may-minihttp | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.17 | 0 |
| xitca-web | A | serialize | item | 77.8K of 78.0K | 0.12 | 0.21-0.28 | 0 |
| xitca-web | A | serialize | me | 16.0K of 16.0K | 0.10-0.11 | 0.20-0.25 | 0 |
| xitca-web | A | serialize | write | 6.0K of 6.0K | 0.13 | 0.21-0.25 | 0 |
| odin-http | A | serialize | item | 77.8K of 78.0K | 0.14 | 0.64-1.31 | 0 |
| odin-http | A | serialize | me | 16.0K of 16.0K | 0.13 | 0.58-1.25 | 0 |
| odin-http | A | serialize | write | 6.0K of 6.0K | 0.14 | 0.53-1.14 | 0 |
| tina | A | serialize | item | 77.7K-77.8K of 78.0K | 0.10 | 0.24-0.29 | 0 |
| tina | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.20-0.23 | 0 |
| tina | A | serialize | write | 6.0K of 6.0K | 0.10 | 0.20-0.22 | 0 |
| goose-uring | A | template | item | 77.8K of 78.0K | 0.10 | 0.16 | 0 |
| goose-uring | A | template | me | 16.0K of 16.0K | 0.09 | 0.16 | 0 |
| goose-uring | A | template | write | 6.0K of 6.0K | 0.11 | 0.16-0.17 | 0 |
| goose-epoll | A | template | item | 77.8K of 78.0K | 0.09-0.10 | 0.16 | 0 |
| goose-epoll | A | template | me | 16.0K of 16.0K | 0.09 | 0.15-0.16 | 0 |
| goose-epoll | A | template | write | 6.0K of 6.0K | 0.11 | 0.16-0.17 | 0 |
| hyper | A | template | item | 77.8K-77.9K of 78.0K | 0.11 | 0.21-0.52 | 0 |
| hyper | A | template | me | 16.0K of 16.0K | 0.10 | 0.20-0.39 | 0 |
| hyper | A | template | write | 6.0K of 6.0K | 0.12-0.13 | 0.21-0.36 | 0 |
| tokio | A | template | item | 77.8K-77.9K of 78.0K | 0.10 | 0.17-0.30 | 0 |
| tokio | A | template | me | 16.0K of 16.0K | 0.09-0.10 | 0.16-0.26 | 0 |
| tokio | A | template | write | 6.0K of 6.0K | 0.11-0.12 | 0.17-0.27 | 0 |
| may-minihttp | A | template | item | 77.8K-77.9K of 78.0K | 0.10 | 0.16 | 0 |
| may-minihttp | A | template | me | 16.0K of 16.0K | 0.09 | 0.16 | 0 |
| may-minihttp | A | template | write | 6.0K of 6.0K | 0.11 | 0.17 | 0 |
| xitca-web | A | template | item | 77.8K-77.9K of 78.0K | 0.11-0.12 | 0.21-0.23 | 0 |
| xitca-web | A | template | me | 16.0K of 16.0K | 0.10-0.11 | 0.20-0.21 | 0 |
| xitca-web | A | template | write | 6.0K of 6.0K | 0.12-0.13 | 0.20-0.22 | 0 |
| odin-http | A | template | item | 77.7K-77.8K of 78.0K | 0.12 | 0.45-1.15 | 0 |
| odin-http | A | template | me | 16.0K of 16.0K | 0.11-0.12 | 0.38-1.08 | 0 |
| odin-http | A | template | write | 6.0K of 6.0K | 0.13-0.14 | 0.37-0.59 | 0 |
| tina | A | template | item | 77.8K of 78.0K | 0.08 | 0.18-0.26 | 0 |
| tina | A | template | me | 16.0K of 16.0K | 0.08 | 0.16-0.20 | 0 |
| tina | A | template | write | 6.0K of 6.0K | 0.09-0.10 | 0.16-0.20 | 0 |
| goose-uring | B | serialize | entries | 6.0K of 6.0K | 0.11 | 0.16-0.17 | 0 |
| goose-uring | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.15 | 0 |
| goose-uring | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.15 | 0 |
| goose-uring | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.15 | 0 |
| goose-uring | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | serialize | entries | 6.0K of 6.0K | 0.11 | 0.15 | 0 |
| goose-epoll | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| hyper | B | serialize | entries | 6.0K of 6.0K | 0.12-0.13 | 0.19-0.20 | 0 |
| hyper | B | serialize | patch | 2.4K of 2.4K | 0.12 | 0.18-0.19 | 0 |
| hyper | B | serialize | projects | 3.6K of 3.6K | 0.12 | 0.19 | 0 |
| hyper | B | serialize | session | 6.0K of 6.0K | 0.11 | 0.18-0.19 | 0 |
| hyper | B | serialize | timer | 6.0K of 6.0K | 0.11 | 0.17-0.19 | 0 |
| tokio | B | serialize | entries | 6.0K of 6.0K | 0.12 | 0.17-0.18 | 0 |
| tokio | B | serialize | patch | 2.4K of 2.4K | 0.11 | 0.16 | 0 |
| tokio | B | serialize | projects | 3.6K of 3.6K | 0.11 | 0.15-0.16 | 0 |
| tokio | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.16 | 0 |
| tokio | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.14-0.16 | 0 |
| may-minihttp | B | serialize | entries | 6.0K of 6.0K | 0.11-0.12 | 0.16-0.18 | 0 |
| may-minihttp | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.15-0.16 | 0 |
| may-minihttp | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.15-0.16 | 0 |
| may-minihttp | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.14-0.16 | 0 |
| may-minihttp | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| xitca-web | B | serialize | entries | 6.0K of 6.0K | 0.12-0.13 | 0.17-0.18 | 0 |
| xitca-web | B | serialize | patch | 2.4K of 2.4K | 0.11-0.12 | 0.17 | 0 |
| xitca-web | B | serialize | projects | 3.6K of 3.6K | 0.12 | 0.16-0.17 | 0 |
| xitca-web | B | serialize | session | 6.0K of 6.0K | 0.11 | 0.16 | 0 |
| xitca-web | B | serialize | timer | 6.0K of 6.0K | 0.11 | 0.15-0.16 | 0 |
| odin-http | B | serialize | entries | 6.0K of 6.0K | 0.28-0.29 | 0.76-1.13 | 0 |
| odin-http | B | serialize | patch | 2.4K of 2.4K | 0.13 | 0.67-0.90 | 0 |
| odin-http | B | serialize | projects | 3.6K of 3.6K | 0.17 | 0.67-0.85 | 0 |
| odin-http | B | serialize | session | 6.0K of 6.0K | 0.14-0.15 | 0.61-0.85 | 0 |
| odin-http | B | serialize | timer | 6.0K of 6.0K | 0.12-0.14 | 0.71-0.92 | 0 |
| tina | B | serialize | entries | 6.0K of 6.0K | 0.26-0.29 | 1.84-2.69 | 0 |
| tina | B | serialize | patch | 2.4K of 2.4K | 0.10 | 1.46-1.85 | 0 |
| tina | B | serialize | projects | 3.6K of 3.6K | 0.14 | 1.46-2.21 | 0 |
| tina | B | serialize | session | 6.0K of 6.0K | 0.12 | 1.70-2.46 | 0 |
| tina | B | serialize | timer | 6.0K of 6.0K | 0.07-0.08 | 1.71-2.38 | 0 |
| goose-uring | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-uring | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14-0.15 | 0 |
| goose-uring | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14-0.15 | 0 |
| goose-uring | B | template | session | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-uring | B | template | timer | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-epoll | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-epoll | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-epoll | B | template | session | 6.0K of 6.0K | 0.10 | 0.13-0.14 | 0 |
| goose-epoll | B | template | timer | 6.0K of 6.0K | 0.10 | 0.13-0.14 | 0 |
| hyper | B | template | entries | 6.0K of 6.0K | 0.11-0.12 | 0.18-0.19 | 0 |
| hyper | B | template | patch | 2.4K of 2.4K | 0.11-0.12 | 0.18 | 0 |
| hyper | B | template | projects | 3.6K of 3.6K | 0.11 | 0.18 | 0 |
| hyper | B | template | session | 6.0K of 6.0K | 0.10-0.11 | 0.17-0.18 | 0 |
| hyper | B | template | timer | 6.0K of 6.0K | 0.11 | 0.17-0.18 | 0 |
| tokio | B | template | entries | 6.0K of 6.0K | 0.10-0.11 | 0.15 | 0 |
| tokio | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14-0.15 | 0 |
| tokio | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14-0.15 | 0 |
| tokio | B | template | session | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| tokio | B | template | timer | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| may-minihttp | B | template | entries | 6.0K of 6.0K | 0.10 | 0.15-0.17 | 0 |
| may-minihttp | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14-0.17 | 0 |
| may-minihttp | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14-0.16 | 0 |
| may-minihttp | B | template | session | 6.0K of 6.0K | 0.10 | 0.14-0.16 | 0 |
| may-minihttp | B | template | timer | 6.0K of 6.0K | 0.10 | 0.14-0.16 | 0 |
| xitca-web | B | template | entries | 6.0K of 6.0K | 0.11-0.12 | 0.16-0.17 | 0 |
| xitca-web | B | template | patch | 2.4K of 2.4K | 0.11 | 0.16-0.17 | 0 |
| xitca-web | B | template | projects | 3.6K of 3.6K | 0.11 | 0.16 | 0 |
| xitca-web | B | template | session | 6.0K of 6.0K | 0.11 | 0.15-0.17 | 0 |
| xitca-web | B | template | timer | 6.0K of 6.0K | 0.11 | 0.15-0.17 | 0 |
| odin-http | B | template | entries | 6.0K of 6.0K | 0.11-0.12 | 0.19-0.20 | 0 |
| odin-http | B | template | patch | 2.4K of 2.4K | 0.11-0.12 | 0.18-0.20 | 0 |
| odin-http | B | template | projects | 3.6K of 3.6K | 0.11 | 0.18-0.20 | 0 |
| odin-http | B | template | session | 6.0K of 6.0K | 0.11 | 0.17-0.19 | 0 |
| odin-http | B | template | timer | 6.0K of 6.0K | 0.11 | 0.17-0.19 | 0 |
| tina | B | template | entries | 6.0K of 6.0K | 0.07 | 0.13-0.14 | 0 |
| tina | B | template | patch | 2.4K of 2.4K | 0.08 | 0.13-0.14 | 0 |
| tina | B | template | projects | 3.6K of 3.6K | 0.08 | 0.12-0.13 | 0 |
| tina | B | template | session | 6.0K of 6.0K | 0.06 | 0.12-0.14 | 0 |
| tina | B | template | timer | 6.0K of 6.0K | 0.06 | 0.12-0.14 | 0 |
| goose-uring | C | serialize | bookings | 153 of 153 | 0.72-0.74 | 0.91-1.03 | 0 |
| goose-uring | C | serialize | client | 51 of 51 | 0.11 | 0.15-0.17 | 0 |
| goose-uring | C | serialize | encounter | 204 of 204 | 0.14 | 0.41-0.45 | 0 |
| goose-uring | C | serialize | history | 204 of 204 | 0.17-0.18 | 0.31-0.67 | 0 |
| goose-uring | C | serialize | poll | 934 of 935 | 0.10 | 0.51-0.54 | 0 |
| goose-uring | C | serialize | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.20 | 0 |
| goose-epoll | C | serialize | bookings | 153 of 153 | 0.73-0.76 | 0.93-1.03 | 0 |
| goose-epoll | C | serialize | client | 51 of 51 | 0.11-0.12 | 0.15-0.18 | 0 |
| goose-epoll | C | serialize | encounter | 204 of 204 | 0.14 | 0.31-0.68 | 0 |
| goose-epoll | C | serialize | history | 204 of 204 | 0.17 | 0.56-0.81 | 0 |
| goose-epoll | C | serialize | poll | 934 of 935 | 0.10 | 0.52-0.54 | 0 |
| goose-epoll | C | serialize | shifts | 153 of 153 | 0.12 | 0.17-0.18 | 0 |
| hyper | C | serialize | bookings | 153 of 153 | 1.21-1.24 | 1.46-1.59 | 0 |
| hyper | C | serialize | client | 51 of 51 | 0.11 | 0.17 | 0 |
| hyper | C | serialize | encounter | 204 of 204 | 0.14-0.15 | 0.49-1.02 | 0 |
| hyper | C | serialize | history | 204 of 204 | 0.19 | 0.74-1.31 | 0 |
| hyper | C | serialize | poll | 933-934 of 935 | 0.11 | 1.24-1.29 | 0 |
| hyper | C | serialize | shifts | 153 of 153 | 0.14-0.25 | 0.20-0.67 | 0 |
| tokio | C | serialize | bookings | 153 of 153 | 1.23-1.25 | 1.50-1.51 | 0 |
| tokio | C | serialize | client | 51 of 51 | 0.10-0.12 | 0.14-0.16 | 0 |
| tokio | C | serialize | encounter | 204 of 204 | 0.13-0.14 | 0.80-1.15 | 0 |
| tokio | C | serialize | history | 204 of 204 | 0.19-0.20 | 0.72-1.07 | 0 |
| tokio | C | serialize | poll | 933-934 of 935 | 0.11 | 1.01-1.12 | 0 |
| tokio | C | serialize | shifts | 153 of 153 | 0.14-0.17 | 0.20-0.90 | 0 |
| may-minihttp | C | serialize | bookings | 153 of 153 | 1.16-1.19 | 1.55-1.59 | 0 |
| may-minihttp | C | serialize | client | 51 of 51 | 0.11 | 0.15-0.17 | 0 |
| may-minihttp | C | serialize | encounter | 204 of 204 | 0.13-0.14 | 0.24-0.88 | 0 |
| may-minihttp | C | serialize | history | 204 of 204 | 0.20 | 0.32-0.82 | 0 |
| may-minihttp | C | serialize | poll | 934 of 935 | 0.10-0.11 | 0.99-1.00 | 0 |
| may-minihttp | C | serialize | shifts | 153 of 153 | 0.13 | 0.19 | 0 |
| xitca-web | C | serialize | bookings | 153 of 153 | 1.04-1.05 | 1.30-1.50 | 0 |
| xitca-web | C | serialize | client | 51 of 51 | 0.12 | 0.16-0.23 | 0 |
| xitca-web | C | serialize | encounter | 204 of 204 | 0.14-0.15 | 0.37-0.68 | 0 |
| xitca-web | C | serialize | history | 204 of 204 | 0.18-0.20 | 0.37-1.03 | 0 |
| xitca-web | C | serialize | poll | 933-934 of 935 | 0.11-0.12 | 0.85-0.89 | 0 |
| xitca-web | C | serialize | shifts | 153 of 153 | 0.14 | 0.19-0.22 | 0 |
| odin-http | C | serialize | bookings | 102-135 of 153 | 725-2436 | 2313-5192 | 0 |
| odin-http | C | serialize | client | 51 of 51 | 0.13-1.16 | 10.8-43.9 | 0 |
| odin-http | C | serialize | encounter | 204 of 204 | 0.57-1.86 | 12.0-46.9 | 0 |
| odin-http | C | serialize | history | 199-204 of 204 | 1.11-1.32 | 25.0-4454 | 0 |
| odin-http | C | serialize | poll | 927-929 of 935 | 0.12-0.13 | 44.0-2481 | 0 |
| odin-http | C | serialize | shifts | 148-152 of 153 | 0.50-3.01 | 2639-5081 | 0 |
| tina | C | serialize | bookings | 153 of 153 | 11.7-22.3 | 98.8-133 | 0 |
| tina | C | serialize | client | 51 of 51 | 1.19-1.60 | 40.8-44.0 | 0 |
| tina | C | serialize | encounter | 204 of 204 | 0.74-1.51 | 37.0-40.0 | 0 |
| tina | C | serialize | history | 204 of 204 | 2.10-2.36 | 42.4-63.7 | 0 |
| tina | C | serialize | poll | 934 of 935 | 0.53-0.57 | 37.8-42.7 | 0 |
| tina | C | serialize | shifts | 153 of 153 | 0.79-2.80 | 40.6-49.7 | 0 |
| goose-uring | C | template | bookings | 153 of 153 | 0.28 | 0.41-0.42 | 0 |
| goose-uring | C | template | client | 51 of 51 | 0.11-0.12 | 0.15-0.17 | 0 |
| goose-uring | C | template | encounter | 204 of 204 | 0.12 | 0.16-0.17 | 0 |
| goose-uring | C | template | history | 204 of 204 | 0.12-0.13 | 0.18 | 0 |
| goose-uring | C | template | poll | 933-934 of 935 | 0.10 | 0.16-0.17 | 0 |
| goose-uring | C | template | shifts | 153 of 153 | 0.10 | 0.15 | 0 |
| goose-epoll | C | template | bookings | 153 of 153 | 0.28 | 0.41-0.46 | 0 |
| goose-epoll | C | template | client | 51 of 51 | 0.11-0.12 | 0.15-0.19 | 0 |
| goose-epoll | C | template | encounter | 204 of 204 | 0.11-0.12 | 0.16-0.18 | 0 |
| goose-epoll | C | template | history | 204 of 204 | 0.13-0.14 | 0.18-0.23 | 0 |
| goose-epoll | C | template | poll | 934 of 935 | 0.10 | 0.17-0.21 | 0 |
| goose-epoll | C | template | shifts | 153 of 153 | 0.10 | 0.15-0.19 | 0 |
| hyper | C | template | bookings | 153 of 153 | 0.28-0.30 | 0.43-0.47 | 0 |
| hyper | C | template | client | 51 of 51 | 0.11-0.12 | 0.16-0.20 | 0 |
| hyper | C | template | encounter | 204 of 204 | 0.12-0.13 | 0.18-0.19 | 0 |
| hyper | C | template | history | 204 of 204 | 0.13-0.14 | 0.20-0.30 | 0 |
| hyper | C | template | poll | 933-934 of 935 | 0.11 | 0.22-0.24 | 0 |
| hyper | C | template | shifts | 153 of 153 | 0.11-0.12 | 0.17 | 0 |
| tokio | C | template | bookings | 153 of 153 | 0.30-0.31 | 0.48-0.49 | 0 |
| tokio | C | template | client | 51 of 51 | 0.11-0.12 | 0.16-0.19 | 0 |
| tokio | C | template | encounter | 204 of 204 | 0.12 | 0.17-0.21 | 0 |
| tokio | C | template | history | 204 of 204 | 0.13-0.14 | 0.18-0.22 | 0 |
| tokio | C | template | poll | 933-934 of 935 | 0.10-0.11 | 0.18-0.24 | 0 |
| tokio | C | template | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.18 | 0 |
| may-minihttp | C | template | bookings | 153 of 153 | 0.32-0.33 | 0.76-0.98 | 0 |
| may-minihttp | C | template | client | 51 of 51 | 0.10-0.11 | 0.15 | 0 |
| may-minihttp | C | template | encounter | 204 of 204 | 0.12 | 0.17 | 0 |
| may-minihttp | C | template | history | 204 of 204 | 0.13-0.14 | 0.20-0.23 | 0 |
| may-minihttp | C | template | poll | 933-934 of 935 | 0.10 | 0.19-0.21 | 0 |
| may-minihttp | C | template | shifts | 153 of 153 | 0.11 | 0.16 | 0 |
| xitca-web | C | template | bookings | 153 of 153 | 0.32-0.33 | 0.52-0.58 | 0 |
| xitca-web | C | template | client | 51 of 51 | 0.11-0.14 | 0.16-0.34 | 0 |
| xitca-web | C | template | encounter | 204 of 204 | 0.12-0.13 | 0.18-0.21 | 0 |
| xitca-web | C | template | history | 204 of 204 | 0.14-0.15 | 0.20-0.24 | 0 |
| xitca-web | C | template | poll | 933-934 of 935 | 0.11-0.12 | 0.21-0.22 | 0 |
| xitca-web | C | template | shifts | 153 of 153 | 0.12 | 0.18 | 0 |
| odin-http | C | template | bookings | 153 of 153 | 0.86-0.89 | 1.19-1.24 | 0 |
| odin-http | C | template | client | 51 of 51 | 0.12-0.13 | 0.18-0.19 | 0 |
| odin-http | C | template | encounter | 204 of 204 | 0.14 | 0.21-0.96 | 0 |
| odin-http | C | template | history | 204 of 204 | 0.14-0.15 | 0.24-1.01 | 0 |
| odin-http | C | template | poll | 933-934 of 935 | 0.12 | 0.84-0.86 | 0 |
| odin-http | C | template | shifts | 153 of 153 | 0.12-0.13 | 0.18-0.23 | 0 |
| tina | C | template | bookings | 153 of 153 | 0.27-0.28 | 0.44-0.45 | 0 |
| tina | C | template | client | 51 of 51 | 0.08-0.09 | 0.12 | 0 |
| tina | C | template | encounter | 204 of 204 | 0.09-0.10 | 0.14 | 0 |
| tina | C | template | history | 204 of 204 | 0.11 | 0.16 | 0 |
| tina | C | template | poll | 934 of 935 | 0.08 | 0.13-0.14 | 0 |
| tina | C | template | shifts | 153 of 153 | 0.09 | 0.13-0.14 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | A | serialize | 20.5-20.9 |  |
| goose-epoll | A | serialize | 20.2-20.6 |  |
| hyper | A | serialize | 26.5-27.2 |  |
| tokio | A | serialize | 21.7-21.9 |  |
| may-minihttp | A | serialize | 21.5-22.1 |  |
| xitca-web | A | serialize | 26.3-27.9 |  |
| odin-http | A | serialize | 30.9-32.0 |  |
| tina | A | serialize | 40.3 |  |
| goose-uring | A | template | 20.3-20.9 |  |
| goose-epoll | A | template | 20.2-20.3 |  |
| hyper | A | template | 26.2-27.0 |  |
| tokio | A | template | 20.6-21.9 |  |
| may-minihttp | A | template | 20.6-21.6 |  |
| xitca-web | A | template | 25.9-26.8 |  |
| odin-http | A | template | 27.9-29.2 |  |
| tina | A | template | 40.3 |  |
| goose-uring | B | serialize | 32.8-33.2 |  |
| goose-epoll | B | serialize | 32.3-32.8 |  |
| hyper | B | serialize | 47.4-47.6 |  |
| tokio | B | serialize | 36.1-37.0 |  |
| may-minihttp | B | serialize | 34.0-34.9 |  |
| xitca-web | B | serialize | 44.7-45.5 |  |
| odin-http | B | serialize | 89.3-90.0 |  |
| tina | B | serialize | 167.4 |  |
| goose-uring | B | template | 30.6-30.9 |  |
| goose-epoll | B | template | 29.5-30.1 |  |
| hyper | B | template | 42.3-43.6 |  |
| tokio | B | template | 32.2-32.4 |  |
| may-minihttp | B | template | 29.9-30.6 |  |
| xitca-web | B | template | 41.4-42.3 |  |
| odin-http | B | template | 41.2-42.0 |  |
| tina | B | template | 167.4 |  |
| goose-uring | C | serialize | 100.1-102.4 |  |
| goose-epoll | C | serialize | 100.4-102.4 |  |
| hyper | C | serialize | 155.8-158.2 |  |
| tokio | C | serialize | 154.2-154.7 |  |
| may-minihttp | C | serialize | 145.2-146.4 |  |
| xitca-web | C | serialize | 144.8-146.4 |  |
| odin-http | C | serialize | 902.8-1097.5 |  |
| tina | C | serialize | 2363.7-2365.3 |  |
| goose-uring | C | template | 51.8-52.6 |  |
| goose-epoll | C | template | 50.2-51.8 |  |
| hyper | C | template | 59.7-60.1 |  |
| tokio | C | template | 56.5-58.1 |  |
| may-minihttp | C | template | 58.5-59.6 |  |
| xitca-web | C | template | 71.0-73.0 |  |
| odin-http | C | template | 131.4-133.8 |  |
| tina | C | template | 2363.9-2364.7 |  |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | C | alone | bookings | 153 of 153 | 0.72-0.75 | 0.90-0.93 | 0 |
| goose-uring | C | alone | client | 51 of 51 | 0.11 | 0.15-0.16 | 0 |
| goose-uring | C | alone | encounter | 204 of 204 | 0.14 | 0.30-0.72 | 0 |
| goose-uring | C | alone | history | 204 of 204 | 0.17-0.18 | 0.33-0.56 | 0 |
| goose-uring | C | alone | poll | 933-935 of 935 | 0.10 | 0.53-0.58 | 0 |
| goose-uring | C | alone | shifts | 153 of 153 | 0.12-0.13 | 0.16-0.25 | 0 |
| goose-epoll | C | alone | bookings | 153 of 153 | 0.72-0.74 | 0.90-0.91 | 0 |
| goose-epoll | C | alone | client | 51 of 51 | 0.11 | 0.15-0.16 | 0 |
| goose-epoll | C | alone | encounter | 204 of 204 | 0.13-0.14 | 0.26-0.40 | 0 |
| goose-epoll | C | alone | history | 204 of 204 | 0.17-0.18 | 0.24-0.38 | 0 |
| goose-epoll | C | alone | poll | 933-934 of 935 | 0.10 | 0.54-0.57 | 0 |
| goose-epoll | C | alone | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.18 | 0 |
| hyper | C | alone | bookings | 153 of 153 | 1.20-1.25 | 1.47-1.77 | 0 |
| hyper | C | alone | client | 51 of 51 | 0.12 | 0.17-0.18 | 0 |
| hyper | C | alone | encounter | 204 of 204 | 0.15 | 0.67-1.11 | 0 |
| hyper | C | alone | history | 204 of 204 | 0.19-0.20 | 1.24-1.36 | 0 |
| hyper | C | alone | poll | 933-934 of 935 | 0.11-0.12 | 1.25-1.29 | 0 |
| hyper | C | alone | shifts | 153 of 153 | 0.15-0.35 | 0.23-0.94 | 0 |
| tokio | C | alone | bookings | 153 of 153 | 1.24-1.28 | 1.50-1.57 | 0 |
| tokio | C | alone | client | 51 of 51 | 0.11-0.12 | 0.16 | 0 |
| tokio | C | alone | encounter | 204 of 204 | 0.14 | 0.20-1.10 | 0 |
| tokio | C | alone | history | 204 of 204 | 0.19 | 0.61-1.19 | 0 |
| tokio | C | alone | poll | 933-934 of 935 | 0.11 | 1.08-1.11 | 0 |
| tokio | C | alone | shifts | 153 of 153 | 0.14 | 0.19-0.22 | 0 |
| xitca-web | C | alone | bookings | 153 of 153 | 1.05-1.07 | 1.28-1.30 | 0 |
| xitca-web | C | alone | client | 51 of 51 | 0.11-0.12 | 0.16-0.17 | 0 |
| xitca-web | C | alone | encounter | 204 of 204 | 0.14-0.15 | 0.75-0.89 | 0 |
| xitca-web | C | alone | history | 204 of 204 | 0.18-0.19 | 0.34-1.02 | 0 |
| xitca-web | C | alone | poll | 933-934 of 935 | 0.12 | 0.91-0.95 | 0 |
| xitca-web | C | alone | shifts | 153 of 153 | 0.14 | 0.18-0.23 | 0 |
| odin-http | C | alone | bookings | 142-153 of 153 | 10.8-18.3 | 23.5-2004 | 0 |
| odin-http | C | alone | client | 35-51 of 51 | 1.25-2457 | 27.0-4553 | 0 |
| odin-http | C | alone | encounter | 178-204 of 204 | 1.46-762 | 28.3-1962 | 0 |
| odin-http | C | alone | history | 172-204 of 204 | 1.66-1475 | 26.5-2309 | 0 |
| odin-http | C | alone | poll | 917-933 of 935 | 0.13-0.15 | 23.4-2786 | 0 |
| odin-http | C | alone | shifts | 132-153 of 153 | 2.00-1241 | 30.3-2618 | 0 |
| goose-uring | C | uploads | bookings | 153 of 153 | 1.86-2.30 | 5.28-6.76 | 0 |
| goose-uring | C | uploads | client | 51 of 51 | 1.68-3.42 | 5.58-7.64 | 0 |
| goose-uring | C | uploads | encounter | 204 of 204 | 1.71-3.10 | 5.61-7.90 | 0 |
| goose-uring | C | uploads | history | 204 of 204 | 1.41-1.78 | 4.41-6.08 | 0 |
| goose-uring | C | uploads | poll | 933-934 of 935 | 1.80-2.17 | 6.00-7.82 | 0 |
| goose-uring | C | uploads | shifts | 153 of 153 | 1.72-2.43 | 5.41-7.74 | 0 |
| goose-epoll | C | uploads | bookings | 153 of 153 | 0.78-0.81 | 1.33-1.48 | 0 |
| goose-epoll | C | uploads | client | 51 of 51 | 0.13-0.15 | 0.43-0.45 | 0 |
| goose-epoll | C | uploads | encounter | 204 of 204 | 0.16-0.21 | 0.58-0.87 | 0 |
| goose-epoll | C | uploads | history | 204 of 204 | 0.21-0.22 | 0.54-0.92 | 0 |
| goose-epoll | C | uploads | poll | 933-934 of 935 | 0.13-0.15 | 0.77-1.05 | 0 |
| goose-epoll | C | uploads | shifts | 153 of 153 | 0.14-0.17 | 0.47-0.83 | 0 |
| hyper | C | uploads | bookings | 153 of 153 | 1.30-1.40 | 4.01-4.81 | 0 |
| hyper | C | uploads | client | 51 of 51 | 0.14-0.18 | 3.26-4.12 | 0 |
| hyper | C | uploads | encounter | 204 of 204 | 0.19-0.34 | 3.55-3.82 | 0 |
| hyper | C | uploads | history | 204 of 204 | 0.27-0.33 | 3.43-3.81 | 0 |
| hyper | C | uploads | poll | 932-934 of 935 | 0.18-0.28 | 3.66-4.03 | 0 |
| hyper | C | uploads | shifts | 153 of 153 | 0.31-0.72 | 3.75-4.15 | 0 |
| tokio | C | uploads | bookings | 153 of 153 | 9.25-11.4 | 39.6-46.8 | 0 |
| tokio | C | uploads | client | 51 of 51 | 8.88-10.4 | 37.6-43.4 | 0 |
| tokio | C | uploads | encounter | 204 of 204 | 8.15-9.21 | 37.6-42.4 | 0 |
| tokio | C | uploads | history | 204 of 204 | 8.12-9.99 | 38.4-41.4 | 0 |
| tokio | C | uploads | poll | 932-933 of 935 | 8.01-9.38 | 36.9-44.6 | 0 |
| tokio | C | uploads | shifts | 153 of 153 | 7.04-9.96 | 39.4-39.5 | 0 |
| xitca-web | C | uploads | bookings | 153 of 153 | 1.12-1.15 | 2.35-2.46 | 0 |
| xitca-web | C | uploads | client | 51 of 51 | 0.17-0.20 | 0.30-0.37 | 0 |
| xitca-web | C | uploads | encounter | 204 of 204 | 0.20-0.21 | 1.09-1.39 | 0 |
| xitca-web | C | uploads | history | 204 of 204 | 0.24-0.26 | 1.04-1.68 | 0 |
| xitca-web | C | uploads | poll | 933-934 of 935 | 0.17 | 1.20-1.28 | 0 |
| xitca-web | C | uploads | shifts | 153 of 153 | 0.18-0.20 | 0.36-0.84 | 0 |
| odin-http | C | uploads | bookings | 91-150 of 153 | 44.8-3073 | 506-6285 | 0 |
| odin-http | C | uploads | client | 28-51 of 51 | 0.15-3329 | 393-6814 | 0 |
| odin-http | C | uploads | encounter | 141-204 of 204 | 1.16-2160 | 110-4635 | 0 |
| odin-http | C | uploads | history | 140-204 of 204 | 1.29-2889 | 45.3-4872 | 0 |
| odin-http | C | uploads | poll | 831-920 of 935 | 22.5-84.4 | 778-4839 | 0 |
| odin-http | C | uploads | shifts | 80-151 of 153 | 42.8-4095 | 1179-6900 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | C | alone | 100.5-101.6 |  |
| goose-epoll | C | alone | 100.4-100.9 |  |
| hyper | C | alone | 156.2-159.4 |  |
| tokio | C | alone | 154.2-156.7 |  |
| xitca-web | C | alone | 146.0-146.8 |  |
| odin-http | C | alone | 1166.9-1185.6 |  |
| goose-uring | C | uploads | 2202.6-2221.2 | 1.1K |
| goose-epoll | C | uploads | 2189.5-2204.8 | 1.1K-1.2K |
| hyper | C | uploads | 2045.7-2108.3 | 1.1K |
| tokio | C | uploads | 2263.8-2329.2 | 1.0K |
| xitca-web | C | uploads | 2358.0-2366.7 | 962-975 |
| odin-http | C | uploads | 2230.1-2820.9 | 352-419 |

