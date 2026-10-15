## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring | A | serialize | 586.3K | 583.1K-592.4K | 0.38 | 0.64 | 6.8 | 12 | 0 |
| goose-epoll | A | serialize | 432.3K | 431.1K-446.7K | 0.56 | 0.96 | 9.2 | 8 | 0 |
| hyper | A | serialize | 268.5K | 266.9K-270.8K | 0.92 | 2.02 | 14.9 | 13 | 0 |
| actix-web | A | serialize | 260.4K | 256.7K-263.9K | 1.04 | 1.36 | 15.4 | 19 | 0 |
| axum | A | serialize | 243.9K | 240.0K-245.4K | 1.05 | 1.55 | 16.4 | 27 | 0 |
| dusty | A | serialize | 340.5K | 338.9K-344.8K | 0.68 | 1.32 | 11.8 | 16 | 0 |
| dusty-routes | A | serialize | 339.3K | 337.9K-343.1K | 0.69 | 1.27 | 11.8 | 15 | 0 |
| goose-epoll-rest | A | serialize | 430.1K | 425.4K-431.6K | 0.59 | 0.86 | 9.3 | 27 | 0 |
| goose-uring-rest | A | serialize | 581.8K | 578.2K-582.6K | 0.38 | 0.66 | 6.8 | 33 | 0 |
| goose-uring | A | template | 593.8K | 593.7K-601.2K | 0.36 | 0.62 | 6.6 | 12 | 0 |
| goose-epoll | A | template | 443.5K | 443.0K-459.8K | 0.55 | 0.98 | 9.0 | 8 | 0 |
| hyper | A | template | 288.1K | 286.2K-291.6K | 0.86 | 1.89 | 13.9 | 16 | 0 |
| actix-web | A | template | 278.7K | 271.4K-281.0K | 0.97 | 1.47 | 14.4 | 22 | 0 |
| axum | A | template | 250.8K | 249.6K-251.3K | 0.99 | 1.58 | 16.0 | 35 | 0 |
| dusty | A | template | 389.7K | 372.3K-397.4K | 0.58 | 1.17 | 10.3 | 18 | 0 |
| dusty-routes | A | template | 396.0K | 382.5K-406.5K | 0.62 | 1.11 | 10.1 | 16 | 0 |
| goose-epoll-rest | A | template | 441.6K | 438.4K-443.9K | 0.56 | 0.91 | 9.1 | 43 | 0 |
| goose-uring-rest | A | template | 591.7K | 580.4K-593.2K | 0.37 | 0.61 | 6.7 | 49 | 0 |
| goose-uring | B | serialize | 312.7K | 312.7K-314.0K | 0.79 | 1.20 | 12.8 | 30 | 0 |
| goose-epoll | B | serialize | 242.6K | 240.7K-246.0K | 1.06 | 1.44 | 16.5 | 29 | 0 |
| hyper | B | serialize | 149.3K | 148.0K-150.4K | 1.68 | 3.68 | 26.8 | 29 | 0 |
| actix-web | B | serialize | 142.2K | 141.9K-142.5K | 1.75 | 2.56 | 28.2 | 57 | 0 |
| axum | B | serialize | 134.5K | 134.4K-135.3K | 1.85 | 2.73 | 29.8 | 59 | 0 |
| dusty | B | serialize | 161.0K | 155.7K-164.2K | 1.49 | 2.98 | 24.9 | 42 | 0 |
| dusty-routes | B | serialize | 159.6K | 155.6K-162.2K | 1.52 | 2.96 | 25.2 | 41 | 0 |
| goose-epoll-rest | B | serialize | 220.6K | 213.1K-221.3K | 1.18 | 1.63 | 18.2 | 87 | 0 |
| goose-uring-rest | B | serialize | 276.5K | 275.9K-277.9K | 0.90 | 1.38 | 14.5 | 96 | 0 |
| goose-uring | B | template | 383.3K | 381.2K-383.6K | 0.65 | 0.96 | 10.4 | 50 | 0 |
| goose-epoll | B | template | 295.5K | 287.2K-296.0K | 0.87 | 1.29 | 13.6 | 50 | 0 |
| hyper | B | template | 191.4K | 190.1K-196.3K | 1.31 | 2.84 | 20.9 | 47 | 0 |
| actix-web | B | template | 180.7K | 180.5K-180.8K | 1.46 | 1.96 | 22.2 | 71 | 0 |
| axum | B | template | 159.7K | 159.6K-161.0K | 1.59 | 2.38 | 25.1 | 84 | 0 |
| dusty | B | template | 274.0K | 273.3K-279.4K | 0.88 | 1.56 | 14.6 | 54 | 0 |
| dusty-routes | B | template | 291.2K | 286.5K-295.6K | 0.79 | 1.56 | 13.8 | 54 | 0 |
| goose-epoll-rest | B | template | 286.6K | 278.5K-287.0K | 0.90 | 1.23 | 14.0 | 213 | 0 |
| goose-uring-rest | B | template | 382.8K | 377.3K-382.9K | 0.65 | 0.96 | 10.4 | 222 | 0 |
| goose-uring | C | serialize | 61.8K | 61.5K-62.4K | 3.99 | 8.95 | 64.6 | 70 | 0 |
| goose-epoll | C | serialize | 60.3K | 59.6K-60.4K | 4.11 | 8.39 | 66.5 | 69 | 0 |
| hyper | C | serialize | 32.4K | 32.1K-32.7K | 7.71 | 18.4 | 124.0 | 37 | 0 |
| actix-web | C | serialize | 31.3K | 30.9K-31.5K | 7.88 | 17.1 | 128.3 | 334 | 0 |
| axum | C | serialize | 34.3K | 34.1K-34.5K | 7.18 | 15.4 | 117.0 | 477 | 0 |
| dusty | C | serialize | 25.2K | 24.8K-25.3K | 10.8 | 33.1 | 159.0 | 216 | 0 |
| dusty-routes | C | serialize | 24.0K | 23.8K-24.3K | 10.9 | 36.4 | 167.7 | 216 | 0 |
| goose-epoll-rest | C | serialize | 51.3K | 51.3K-51.8K | 4.81 | 9.92 | 78.1 | 129 | 0 |
| goose-uring-rest | C | serialize | 52.7K | 52.3K-52.9K | 4.70 | 10.5 | 75.8 | 140 | 0 |
| goose-uring | C | template | 144.0K | 142.7K-144.6K | 1.70 | 3.22 | 27.6 | 58 | 0 |
| goose-epoll | C | template | 136.1K | 134.4K-137.3K | 1.83 | 3.00 | 29.4 | 58 | 0 |
| hyper | C | template | 118.2K | 117.6K-120.1K | 2.10 | 4.53 | 33.7 | 75 | 0 |
| actix-web | C | template | 91.6K | 88.0K-92.7K | 2.73 | 4.43 | 43.7 | 388 | 0 |
| axum | C | template | 87.3K | 87.2K-89.8K | 2.85 | 4.75 | 45.9 | 587 | 0 |
| dusty | C | template | 130.1K | 129.6K-132.2K | 1.86 | 3.76 | 30.7 | 241 | 0 |
| dusty-routes | C | template | 130.3K | 128.5K-131.1K | 1.90 | 3.49 | 30.7 | 242 | 0 |
| goose-epoll-rest | C | template | 131.7K | 131.2K-132.1K | 1.89 | 3.12 | 30.4 | 376 | 0 |
| goose-uring-rest | C | template | 140.7K | 139.6K-142.9K | 1.75 | 3.26 | 28.3 | 387 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring | alone | 1.1K | 16.2-18.3 |  |  | 70 | 0 |
| goose-epoll | alone | 1.1K-1.2K | 14.7-15.2 |  |  | 69 | 0 |
| hyper | alone | 1.1K | 14.9-15.3 |  |  | 75 | 0 |
| actix-web | alone | 1.1K | 18.7-19.0 |  |  | 57 | 0 |
| axum | alone | 1.1K | 15.2-16.3 |  |  | 163 | 0 |
| dusty | alone | 1.1K | 15.1-16.6 |  |  | 31 | 0 |
| dusty-routes | alone | 1.2K | 14.5-14.9 |  |  | 31 | 0 |
| goose-epoll-rest | alone | 979-1.0K | 21.8-22.5 |  |  | 395 | 0 |
| goose-uring-rest | alone | 965-979 | 22.6-23.6 |  |  | 385 | 0 |
| goose-uring | beside forms | 159-165 | 118-124 | 6.9K-7.1K | 76.1-82.6 | 125 | 0 |
| goose-epoll | beside forms | 112-123 | 166-180 | 7.4K-7.5K | 89.4-95.7 | 132 | 0 |
| hyper | beside forms | 44-73 | 100-150 | 4.9K-5.0K | 143-167 | 197 | 0 |
| actix-web | beside forms | 92-93 | 202-222 | 4.6K-4.7K | 115-118 | 196 | 0 |
| axum | beside forms | 33-34 | 166-317 | 4.8K-5.0K | 119-127 | 259 | 0 |
| dusty | beside forms | 26-42 | 439-569 | 2.9K | 329-366 | 815 | 0 |
| dusty-routes | beside forms | 30-45 | 425-563 | 2.9K | 350-361 | 781 | 0 |
| goose-epoll-rest | beside forms | 111-113 | 171-217 | 7.1K-7.2K | 90.8-102 | 449 | 0 |
| goose-uring-rest | beside forms | 151-158 | 123-137 | 6.7K-6.8K | 82.3-86.1 | 442 | 0 |

## Fixed rate

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | A | serialize | item | 77.8K-77.9K of 78.0K | 0.10 | 0.16-0.17 | 0 |
| goose-uring | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.16-0.17 | 0 |
| goose-uring | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.17 | 0 |
| goose-epoll | A | serialize | item | 77.7K-77.9K of 78.0K | 0.10 | 0.16-0.18 | 0 |
| goose-epoll | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.16-0.17 | 0 |
| goose-epoll | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.16-0.18 | 0 |
| hyper | A | serialize | item | 77.7K-77.8K of 78.0K | 0.11-0.12 | 0.20-6.94 | 0 |
| hyper | A | serialize | me | 16.0K of 16.0K | 0.10-0.11 | 0.19-5.19 | 0 |
| hyper | A | serialize | write | 6.0K of 6.0K | 0.12-0.13 | 0.20-1.35 | 0 |
| actix-web | A | serialize | item | 77.8K of 78.0K | 0.11-0.12 | 0.22-0.29 | 0 |
| actix-web | A | serialize | me | 16.0K of 16.0K | 0.11 | 0.22-0.27 | 0 |
| actix-web | A | serialize | write | 6.0K of 6.0K | 0.13 | 0.21-0.28 | 0 |
| axum | A | serialize | item | 77.7K-77.9K of 78.0K | 0.12 | 0.26-0.41 | 0 |
| axum | A | serialize | me | 16.0K of 16.0K | 0.10-0.11 | 0.24-0.38 | 0 |
| axum | A | serialize | write | 6.0K of 6.0K | 0.13 | 0.25-0.36 | 0 |
| dusty | A | serialize | item | 77.8K of 78.0K | 0.11 | 0.18-3.58 | 0 |
| dusty | A | serialize | me | 16.0K of 16.0K | 0.10 | 0.17-1.36 | 0 |
| dusty | A | serialize | write | 6.0K of 6.0K | 0.12-0.13 | 0.19-1.39 | 0 |
| dusty-routes | A | serialize | item | 77.8K-77.9K of 78.0K | 0.11 | 0.20-2.10 | 0 |
| dusty-routes | A | serialize | me | 16.0K of 16.0K | 0.10 | 0.19-1.18 | 0 |
| dusty-routes | A | serialize | write | 6.0K of 6.0K | 0.12 | 0.20-0.51 | 0 |
| goose-epoll-rest | A | serialize | item | 77.7K-77.8K of 78.0K | 0.10 | 0.17-5.01 | 0 |
| goose-epoll-rest | A | serialize | me | 16.0K of 16.0K | 0.09-0.10 | 0.17-6.21 | 0 |
| goose-epoll-rest | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.17-6.49 | 0 |
| goose-uring-rest | A | serialize | item | 77.8K-77.9K of 78.0K | 0.10 | 0.17-0.21 | 0 |
| goose-uring-rest | A | serialize | me | 16.0K of 16.0K | 0.09-0.10 | 0.17-0.19 | 0 |
| goose-uring-rest | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.17-0.20 | 0 |
| goose-uring | A | template | item | 77.8K of 78.0K | 0.10 | 0.15-1.93 | 0 |
| goose-uring | A | template | me | 16.0K of 16.0K | 0.09 | 0.15-1.20 | 0 |
| goose-uring | A | template | write | 6.0K of 6.0K | 0.11 | 0.16-0.70 | 0 |
| goose-epoll | A | template | item | 77.8K of 78.0K | 0.10 | 0.16-0.17 | 0 |
| goose-epoll | A | template | me | 16.0K of 16.0K | 0.09 | 0.16-0.17 | 0 |
| goose-epoll | A | template | write | 6.0K of 6.0K | 0.11 | 0.16-0.17 | 0 |
| hyper | A | template | item | 77.7K-77.8K of 78.0K | 0.11 | 0.21-24.1 | 0 |
| hyper | A | template | me | 16.0K of 16.0K | 0.10-0.11 | 0.20-13.9 | 0 |
| hyper | A | template | write | 6.0K of 6.0K | 0.12-0.13 | 0.21-3.35 | 0 |
| actix-web | A | template | item | 77.8K-77.9K of 78.0K | 0.11-0.12 | 0.22-16.6 | 0 |
| actix-web | A | template | me | 16.0K of 16.0K | 0.10-0.11 | 0.21-14.1 | 0 |
| actix-web | A | template | write | 6.0K of 6.0K | 0.12-0.13 | 0.21-8.32 | 0 |
| axum | A | template | item | 77.8K of 78.0K | 0.12 | 0.24-9.94 | 0 |
| axum | A | template | me | 16.0K of 16.0K | 0.11 | 0.23-5.34 | 0 |
| axum | A | template | write | 6.0K of 6.0K | 0.13-0.14 | 0.23-4.61 | 0 |
| dusty | A | template | item | 77.8K of 78.0K | 0.10-0.11 | 0.18-0.20 | 0 |
| dusty | A | template | me | 16.0K of 16.0K | 0.10 | 0.17-0.20 | 0 |
| dusty | A | template | write | 6.0K of 6.0K | 0.12 | 0.19-0.20 | 0 |
| dusty-routes | A | template | item | 77.8K of 78.0K | 0.10-0.11 | 0.20-1.95 | 0 |
| dusty-routes | A | template | me | 16.0K of 16.0K | 0.10 | 0.19-0.99 | 0 |
| dusty-routes | A | template | write | 6.0K of 6.0K | 0.12 | 0.20-0.89 | 0 |
| goose-epoll-rest | A | template | item | 77.7K-77.8K of 78.0K | 0.10 | 0.18-7.85 | 0 |
| goose-epoll-rest | A | template | me | 16.0K of 16.0K | 0.09-0.10 | 0.17-4.13 | 0 |
| goose-epoll-rest | A | template | write | 6.0K of 6.0K | 0.11 | 0.17-18.7 | 0 |
| goose-uring-rest | A | template | item | 77.8K of 78.0K | 0.10 | 0.18 | 0 |
| goose-uring-rest | A | template | me | 16.0K of 16.0K | 0.09-0.10 | 0.17 | 0 |
| goose-uring-rest | A | template | write | 6.0K of 6.0K | 0.11 | 0.17-0.18 | 0 |
| goose-uring | B | serialize | entries | 6.0K of 6.0K | 0.11 | 0.15-0.17 | 0 |
| goose-uring | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.15-0.16 | 0 |
| goose-uring | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.14-0.17 | 0 |
| goose-uring | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.14-0.17 | 0 |
| goose-uring | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.14-0.16 | 0 |
| goose-epoll | B | serialize | entries | 6.0K of 6.0K | 0.10-0.11 | 0.15-0.18 | 0 |
| goose-epoll | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.14-0.18 | 0 |
| goose-epoll | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.14-0.17 | 0 |
| goose-epoll | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.14-0.17 | 0 |
| goose-epoll | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.15-0.17 | 0 |
| hyper | B | serialize | entries | 6.0K of 6.0K | 0.13 | 0.20-0.24 | 0 |
| hyper | B | serialize | patch | 2.4K of 2.4K | 0.12 | 0.18-0.21 | 0 |
| hyper | B | serialize | projects | 3.6K of 3.6K | 0.12 | 0.18-0.21 | 0 |
| hyper | B | serialize | session | 6.0K of 6.0K | 0.11-0.12 | 0.18-0.22 | 0 |
| hyper | B | serialize | timer | 6.0K of 6.0K | 0.11 | 0.18-0.20 | 0 |
| actix-web | B | serialize | entries | 6.0K of 6.0K | 0.13 | 0.19-0.21 | 0 |
| actix-web | B | serialize | patch | 2.4K of 2.4K | 0.12 | 0.18-0.20 | 0 |
| actix-web | B | serialize | projects | 3.6K of 3.6K | 0.12 | 0.18-0.20 | 0 |
| actix-web | B | serialize | session | 6.0K of 6.0K | 0.11-0.12 | 0.18-0.19 | 0 |
| actix-web | B | serialize | timer | 6.0K of 6.0K | 0.11 | 0.18-0.19 | 0 |
| axum | B | serialize | entries | 6.0K of 6.0K | 0.13 | 0.20-0.29 | 0 |
| axum | B | serialize | patch | 2.4K of 2.4K | 0.12 | 0.19-0.26 | 0 |
| axum | B | serialize | projects | 3.6K of 3.6K | 0.12 | 0.19-0.26 | 0 |
| axum | B | serialize | session | 6.0K of 6.0K | 0.11-0.12 | 0.18-0.27 | 0 |
| axum | B | serialize | timer | 6.0K of 6.0K | 0.11 | 0.18-0.26 | 0 |
| dusty | B | serialize | entries | 6.0K of 6.0K | 0.13 | 0.18-0.20 | 0 |
| dusty | B | serialize | patch | 2.4K of 2.4K | 0.11 | 0.17-0.19 | 0 |
| dusty | B | serialize | projects | 3.6K of 3.6K | 0.11-0.12 | 0.17-0.19 | 0 |
| dusty | B | serialize | session | 6.0K of 6.0K | 0.11 | 0.16-0.18 | 0 |
| dusty | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.16-0.17 | 0 |
| dusty-routes | B | serialize | entries | 6.0K of 6.0K | 0.13 | 0.18-0.20 | 0 |
| dusty-routes | B | serialize | patch | 2.4K of 2.4K | 0.11 | 0.17-0.19 | 0 |
| dusty-routes | B | serialize | projects | 3.6K of 3.6K | 0.11-0.12 | 0.17-0.19 | 0 |
| dusty-routes | B | serialize | session | 6.0K of 6.0K | 0.11 | 0.16-0.18 | 0 |
| dusty-routes | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.16-0.18 | 0 |
| goose-epoll-rest | B | serialize | entries | 6.0K of 6.0K | 0.11 | 0.16-0.18 | 0 |
| goose-epoll-rest | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.15-0.16 | 0 |
| goose-epoll-rest | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.15-0.17 | 0 |
| goose-epoll-rest | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.15-0.16 | 0 |
| goose-epoll-rest | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.15-0.17 | 0 |
| goose-uring-rest | B | serialize | entries | 6.0K of 6.0K | 0.11 | 0.16-0.18 | 0 |
| goose-uring-rest | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.15-0.17 | 0 |
| goose-uring-rest | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.15-0.16 | 0 |
| goose-uring-rest | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.15-0.17 | 0 |
| goose-uring-rest | B | serialize | timer | 6.0K of 6.0K | 0.10 | 0.15-0.16 | 0 |
| goose-uring | B | template | entries | 6.0K of 6.0K | 0.10 | 0.15 | 0 |
| goose-uring | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14-0.15 | 0 |
| goose-uring | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14-0.15 | 0 |
| goose-uring | B | template | session | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-uring | B | template | timer | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | template | session | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | template | timer | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| hyper | B | template | entries | 6.0K of 6.0K | 0.12 | 0.18-0.20 | 0 |
| hyper | B | template | patch | 2.4K of 2.4K | 0.11 | 0.18-0.20 | 0 |
| hyper | B | template | projects | 3.6K of 3.6K | 0.11 | 0.17-0.19 | 0 |
| hyper | B | template | session | 6.0K of 6.0K | 0.11 | 0.18-0.19 | 0 |
| hyper | B | template | timer | 6.0K of 6.0K | 0.11 | 0.17-0.19 | 0 |
| actix-web | B | template | entries | 6.0K of 6.0K | 0.12 | 0.18 | 0 |
| actix-web | B | template | patch | 2.4K of 2.4K | 0.12 | 0.17-0.18 | 0 |
| actix-web | B | template | projects | 3.6K of 3.6K | 0.11-0.12 | 0.17-0.18 | 0 |
| actix-web | B | template | session | 6.0K of 6.0K | 0.11 | 0.17 | 0 |
| actix-web | B | template | timer | 6.0K of 6.0K | 0.11 | 0.16-0.17 | 0 |
| axum | B | template | entries | 6.0K of 6.0K | 0.12 | 0.17-0.19 | 0 |
| axum | B | template | patch | 2.4K of 2.4K | 0.12 | 0.18-0.19 | 0 |
| axum | B | template | projects | 3.6K of 3.6K | 0.12 | 0.17-0.19 | 0 |
| axum | B | template | session | 6.0K of 6.0K | 0.11 | 0.17-0.18 | 0 |
| axum | B | template | timer | 6.0K of 6.0K | 0.11 | 0.17-0.18 | 0 |
| dusty | B | template | entries | 6.0K of 6.0K | 0.11 | 0.15-0.18 | 0 |
| dusty | B | template | patch | 2.4K of 2.4K | 0.11 | 0.16-0.18 | 0 |
| dusty | B | template | projects | 3.6K of 3.6K | 0.11 | 0.15-0.18 | 0 |
| dusty | B | template | session | 6.0K of 6.0K | 0.10 | 0.15-0.17 | 0 |
| dusty | B | template | timer | 6.0K of 6.0K | 0.10 | 0.15-0.17 | 0 |
| dusty-routes | B | template | entries | 6.0K of 6.0K | 0.10-0.11 | 0.15-0.17 | 0 |
| dusty-routes | B | template | patch | 2.4K of 2.4K | 0.11 | 0.15-0.17 | 0 |
| dusty-routes | B | template | projects | 3.6K of 3.6K | 0.10-0.11 | 0.15-0.17 | 0 |
| dusty-routes | B | template | session | 6.0K of 6.0K | 0.10 | 0.15-0.17 | 0 |
| dusty-routes | B | template | timer | 6.0K of 6.0K | 0.10 | 0.14-0.17 | 0 |
| goose-epoll-rest | B | template | entries | 6.0K of 6.0K | 0.10 | 0.15-0.16 | 0 |
| goose-epoll-rest | B | template | patch | 2.4K of 2.4K | 0.10 | 0.15-0.16 | 0 |
| goose-epoll-rest | B | template | projects | 3.6K of 3.6K | 0.10 | 0.15 | 0 |
| goose-epoll-rest | B | template | session | 6.0K of 6.0K | 0.10 | 0.14-0.17 | 0 |
| goose-epoll-rest | B | template | timer | 6.0K of 6.0K | 0.10 | 0.14-0.16 | 0 |
| goose-uring-rest | B | template | entries | 6.0K of 6.0K | 0.10 | 0.15-0.17 | 0 |
| goose-uring-rest | B | template | patch | 2.4K of 2.4K | 0.10 | 0.15-0.17 | 0 |
| goose-uring-rest | B | template | projects | 3.6K of 3.6K | 0.10 | 0.15-0.17 | 0 |
| goose-uring-rest | B | template | session | 6.0K of 6.0K | 0.10 | 0.15-0.16 | 0 |
| goose-uring-rest | B | template | timer | 6.0K of 6.0K | 0.10 | 0.14-0.16 | 0 |
| goose-uring | C | serialize | bookings | 153 of 153 | 0.66-0.70 | 0.87-0.95 | 0 |
| goose-uring | C | serialize | client | 51 of 51 | 0.10-0.11 | 0.16-0.17 | 0 |
| goose-uring | C | serialize | encounter | 204 of 204 | 0.12 | 0.18-0.26 | 0 |
| goose-uring | C | serialize | history | 204 of 204 | 0.14-0.15 | 0.21-0.73 | 0 |
| goose-uring | C | serialize | poll | 933-934 of 935 | 0.10 | 0.47-0.54 | 0 |
| goose-uring | C | serialize | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.18 | 0 |
| goose-epoll | C | serialize | bookings | 153 of 153 | 0.67-0.69 | 0.85-0.87 | 0 |
| goose-epoll | C | serialize | client | 51 of 51 | 0.10-0.11 | 0.15-0.17 | 0 |
| goose-epoll | C | serialize | encounter | 204 of 204 | 0.12 | 0.17-0.20 | 0 |
| goose-epoll | C | serialize | history | 204 of 204 | 0.14 | 0.20-0.66 | 0 |
| goose-epoll | C | serialize | poll | 933-934 of 935 | 0.10 | 0.43-0.51 | 0 |
| goose-epoll | C | serialize | shifts | 153 of 153 | 0.11-0.12 | 0.15-0.17 | 0 |
| hyper | C | serialize | bookings | 153 of 153 | 1.21-1.23 | 1.44-1.57 | 0 |
| hyper | C | serialize | client | 51 of 51 | 0.12 | 0.17-0.20 | 0 |
| hyper | C | serialize | encounter | 204 of 204 | 0.14-0.15 | 1.04-1.30 | 0 |
| hyper | C | serialize | history | 204 of 204 | 0.19-0.20 | 0.50-1.24 | 0 |
| hyper | C | serialize | poll | 933 of 935 | 0.11-0.12 | 1.24-1.29 | 0 |
| hyper | C | serialize | shifts | 153 of 153 | 0.14-0.17 | 0.23-0.40 | 0 |
| actix-web | C | serialize | bookings | 153 of 153 | 1.16-1.21 | 1.45-1.67 | 0 |
| actix-web | C | serialize | client | 51 of 51 | 0.12-0.13 | 0.18-0.23 | 0 |
| actix-web | C | serialize | encounter | 204 of 204 | 0.15 | 0.79-0.95 | 0 |
| actix-web | C | serialize | history | 204 of 204 | 0.20-0.21 | 0.34-1.20 | 0 |
| actix-web | C | serialize | poll | 934 of 935 | 0.11-0.12 | 0.98-1.05 | 0 |
| actix-web | C | serialize | shifts | 153 of 153 | 0.14-0.15 | 0.21 | 0 |
| axum | C | serialize | bookings | 153 of 153 | 1.05-1.09 | 1.33-1.37 | 0 |
| axum | C | serialize | client | 51 of 51 | 0.12-0.13 | 0.18-0.19 | 0 |
| axum | C | serialize | encounter | 204 of 204 | 0.14-0.15 | 0.20-0.35 | 0 |
| axum | C | serialize | history | 204 of 204 | 0.18-0.19 | 0.26-0.63 | 0 |
| axum | C | serialize | poll | 933 of 935 | 0.12 | 0.88-0.91 | 0 |
| axum | C | serialize | shifts | 153 of 153 | 0.14 | 0.19-0.21 | 0 |
| dusty | C | serialize | bookings | 153 of 153 | 1.47-1.55 | 1.78-1.83 | 0 |
| dusty | C | serialize | client | 51 of 51 | 0.11-0.12 | 0.17-0.18 | 0 |
| dusty | C | serialize | encounter | 204 of 204 | 0.17 | 1.06-1.59 | 0 |
| dusty | C | serialize | history | 204 of 204 | 0.24-0.27 | 0.98-1.68 | 0 |
| dusty | C | serialize | poll | 933-934 of 935 | 0.11-0.12 | 1.28-1.32 | 0 |
| dusty | C | serialize | shifts | 153 of 153 | 0.14-0.16 | 0.20-0.59 | 0 |
| dusty-routes | C | serialize | bookings | 153 of 153 | 1.56-1.57 | 1.83-1.86 | 0 |
| dusty-routes | C | serialize | client | 51 of 51 | 0.11-0.12 | 0.16-0.21 | 0 |
| dusty-routes | C | serialize | encounter | 204 of 204 | 0.16-0.17 | 0.67-1.20 | 0 |
| dusty-routes | C | serialize | history | 204 of 204 | 0.27 | 0.91-1.63 | 0 |
| dusty-routes | C | serialize | poll | 933-934 of 935 | 0.11-0.12 | 1.35-1.41 | 0 |
| dusty-routes | C | serialize | shifts | 153 of 153 | 0.15 | 0.22-0.43 | 0 |
| goose-epoll-rest | C | serialize | bookings | 153 of 153 | 0.72-0.77 | 0.94-1.02 | 0 |
| goose-epoll-rest | C | serialize | client | 51 of 51 | 0.11-0.12 | 0.15-0.16 | 0 |
| goose-epoll-rest | C | serialize | encounter | 204 of 204 | 0.13-0.14 | 0.19-0.49 | 0 |
| goose-epoll-rest | C | serialize | history | 204 of 204 | 0.17-0.18 | 0.24-0.42 | 0 |
| goose-epoll-rest | C | serialize | poll | 933-934 of 935 | 0.10-0.11 | 0.54-0.55 | 0 |
| goose-epoll-rest | C | serialize | shifts | 153 of 153 | 0.12 | 0.16-0.18 | 0 |
| goose-uring-rest | C | serialize | bookings | 153 of 153 | 0.72-0.76 | 0.92-0.98 | 0 |
| goose-uring-rest | C | serialize | client | 51 of 51 | 0.11-0.12 | 0.17-0.20 | 0 |
| goose-uring-rest | C | serialize | encounter | 204 of 204 | 0.14 | 0.24-0.35 | 0 |
| goose-uring-rest | C | serialize | history | 204 of 204 | 0.18 | 0.29-0.31 | 0 |
| goose-uring-rest | C | serialize | poll | 933-934 of 935 | 0.10-0.11 | 0.53-0.58 | 0 |
| goose-uring-rest | C | serialize | shifts | 153 of 153 | 0.12 | 0.17-0.22 | 0 |
| goose-uring | C | template | bookings | 153 of 153 | 0.28-0.29 | 0.42-0.44 | 0 |
| goose-uring | C | template | client | 51 of 51 | 0.11 | 0.15-0.16 | 0 |
| goose-uring | C | template | encounter | 204 of 204 | 0.11-0.12 | 0.16-0.17 | 0 |
| goose-uring | C | template | history | 204 of 204 | 0.13-0.14 | 0.18-0.21 | 0 |
| goose-uring | C | template | poll | 933-934 of 935 | 0.10 | 0.17-0.18 | 0 |
| goose-uring | C | template | shifts | 153 of 153 | 0.10-0.11 | 0.14-0.16 | 0 |
| goose-epoll | C | template | bookings | 153 of 153 | 0.27-0.30 | 0.45-0.47 | 0 |
| goose-epoll | C | template | client | 51 of 51 | 0.11 | 0.15-0.17 | 0 |
| goose-epoll | C | template | encounter | 204 of 204 | 0.12 | 0.17-0.20 | 0 |
| goose-epoll | C | template | history | 204 of 204 | 0.13 | 0.18-0.21 | 0 |
| goose-epoll | C | template | poll | 934-935 of 935 | 0.10 | 0.17-0.21 | 0 |
| goose-epoll | C | template | shifts | 153 of 153 | 0.10-0.12 | 0.15-0.17 | 0 |
| hyper | C | template | bookings | 153 of 153 | 0.28-0.29 | 0.47-0.50 | 0 |
| hyper | C | template | client | 51 of 51 | 0.11-0.12 | 0.17-0.20 | 0 |
| hyper | C | template | encounter | 204 of 204 | 0.12-0.13 | 0.18-0.24 | 0 |
| hyper | C | template | history | 204 of 204 | 0.13-0.14 | 0.20-0.33 | 0 |
| hyper | C | template | poll | 933-934 of 935 | 0.11 | 0.24-0.28 | 0 |
| hyper | C | template | shifts | 153 of 153 | 0.12 | 0.18-0.22 | 0 |
| actix-web | C | template | bookings | 153 of 153 | 0.36-0.38 | 0.56-0.61 | 0 |
| actix-web | C | template | client | 51 of 51 | 0.12 | 0.17-0.18 | 0 |
| actix-web | C | template | encounter | 204 of 204 | 0.12-0.13 | 0.18-0.31 | 0 |
| actix-web | C | template | history | 204 of 204 | 0.14-0.15 | 0.20-0.23 | 0 |
| actix-web | C | template | poll | 933 of 935 | 0.11-0.12 | 0.23-0.26 | 0 |
| actix-web | C | template | shifts | 153 of 153 | 0.12 | 0.17-0.18 | 0 |
| axum | C | template | bookings | 153 of 153 | 0.33-0.34 | 0.64-0.78 | 0 |
| axum | C | template | client | 51 of 51 | 0.12-0.13 | 0.17-0.18 | 0 |
| axum | C | template | encounter | 204 of 204 | 0.13 | 0.18-0.19 | 0 |
| axum | C | template | history | 204 of 204 | 0.14 | 0.20 | 0 |
| axum | C | template | poll | 933 of 935 | 0.12 | 0.21-0.22 | 0 |
| axum | C | template | shifts | 153 of 153 | 0.12 | 0.17-0.19 | 0 |
| dusty | C | template | bookings | 153 of 153 | 0.27-0.28 | 0.44-0.51 | 0 |
| dusty | C | template | client | 51 of 51 | 0.12 | 0.17 | 0 |
| dusty | C | template | encounter | 204 of 204 | 0.12-0.13 | 0.23-0.28 | 0 |
| dusty | C | template | history | 204 of 204 | 0.13-0.14 | 0.19-0.31 | 0 |
| dusty | C | template | poll | 933 of 935 | 0.11-0.12 | 0.18-0.25 | 0 |
| dusty | C | template | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.21 | 0 |
| dusty-routes | C | template | bookings | 153 of 153 | 0.27-0.28 | 0.44-0.45 | 0 |
| dusty-routes | C | template | client | 51 of 51 | 0.12 | 0.16-0.17 | 0 |
| dusty-routes | C | template | encounter | 204 of 204 | 0.12-0.13 | 0.17-0.26 | 0 |
| dusty-routes | C | template | history | 204 of 204 | 0.13-0.14 | 0.18-0.21 | 0 |
| dusty-routes | C | template | poll | 933-934 of 935 | 0.11-0.12 | 0.17-0.20 | 0 |
| dusty-routes | C | template | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.18 | 0 |
| goose-epoll-rest | C | template | bookings | 153 of 153 | 0.29-0.30 | 0.44-0.54 | 0 |
| goose-epoll-rest | C | template | client | 51 of 51 | 0.10-0.11 | 0.15-0.18 | 0 |
| goose-epoll-rest | C | template | encounter | 204 of 204 | 0.12 | 0.17-0.27 | 0 |
| goose-epoll-rest | C | template | history | 204 of 204 | 0.13 | 0.20-0.27 | 0 |
| goose-epoll-rest | C | template | poll | 933-934 of 935 | 0.10 | 0.17-0.25 | 0 |
| goose-epoll-rest | C | template | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.19 | 0 |
| goose-uring-rest | C | template | bookings | 153 of 153 | 0.29 | 0.46-0.48 | 0 |
| goose-uring-rest | C | template | client | 51 of 51 | 0.11-0.12 | 0.15-0.27 | 0 |
| goose-uring-rest | C | template | encounter | 204 of 204 | 0.12-0.13 | 0.18-0.27 | 0 |
| goose-uring-rest | C | template | history | 204 of 204 | 0.13-0.14 | 0.19-0.25 | 0 |
| goose-uring-rest | C | template | poll | 933-934 of 935 | 0.10-0.12 | 0.19-0.25 | 0 |
| goose-uring-rest | C | template | shifts | 153 of 153 | 0.11-0.12 | 0.17-0.20 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | A | serialize | 20.8-21.6 |  |
| goose-epoll | A | serialize | 20.8-21.3 |  |
| hyper | A | serialize | 27.2-28.0 |  |
| actix-web | A | serialize | 26.6-28.0 |  |
| axum | A | serialize | 26.7-27.6 |  |
| dusty | A | serialize | 27.8-30.0 |  |
| dusty-routes | A | serialize | 28.1-29.2 |  |
| goose-epoll-rest | A | serialize | 21.5-21.9 |  |
| goose-uring-rest | A | serialize | 20.9-21.5 |  |
| goose-uring | A | template | 21.1-21.6 |  |
| goose-epoll | A | template | 20.8-21.1 |  |
| hyper | A | template | 26.3-27.9 |  |
| actix-web | A | template | 26.3-27.6 |  |
| axum | A | template | 27.1-27.5 |  |
| dusty | A | template | 27.3-28.8 |  |
| dusty-routes | A | template | 28.1-28.8 |  |
| goose-epoll-rest | A | template | 20.8-21.5 |  |
| goose-uring-rest | A | template | 20.3-21.6 |  |
| goose-uring | B | serialize | 32.5-33.4 |  |
| goose-epoll | B | serialize | 31.9-32.5 |  |
| hyper | B | serialize | 48.4-49.5 |  |
| actix-web | B | serialize | 45.5-47.0 |  |
| axum | B | serialize | 46.0-46.5 |  |
| dusty | B | serialize | 48.4-49.7 |  |
| dusty-routes | B | serialize | 48.0-49.2 |  |
| goose-epoll-rest | B | serialize | 33.5-33.8 |  |
| goose-uring-rest | B | serialize | 33.3-34.3 |  |
| goose-uring | B | template | 30.8-31.5 |  |
| goose-epoll | B | template | 30.4-30.9 |  |
| hyper | B | template | 43.1-44.1 |  |
| actix-web | B | template | 41.4-42.8 |  |
| axum | B | template | 43.2-43.5 |  |
| dusty | B | template | 41.3-42.1 |  |
| dusty-routes | B | template | 40.5-41.9 |  |
| goose-epoll-rest | B | template | 30.6-31.6 |  |
| goose-uring-rest | B | template | 31.4-31.7 |  |
| goose-uring | C | serialize | 92.6-94.2 |  |
| goose-epoll | C | serialize | 90.7-92.6 |  |
| hyper | C | serialize | 157.8 |  |
| actix-web | C | serialize | 157.3-162.5 |  |
| axum | C | serialize | 144.9-148.4 |  |
| dusty | C | serialize | 197.0-201.4 |  |
| dusty-routes | C | serialize | 204.8-206.8 |  |
| goose-epoll-rest | C | serialize | 102.1-105.6 |  |
| goose-uring-rest | C | serialize | 103.6-106.0 |  |
| goose-uring | C | template | 53.7-54.6 |  |
| goose-epoll | C | template | 54.1-55.3 |  |
| hyper | C | template | 60.9-61.6 |  |
| actix-web | C | template | 71.5-75.0 |  |
| axum | C | template | 71.1-71.8 |  |
| dusty | C | template | 65.2-68.7 |  |
| dusty-routes | C | template | 63.6-67.9 |  |
| goose-epoll-rest | C | template | 53.7-56.1 |  |
| goose-uring-rest | C | template | 56.1-58.9 |  |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | C | alone | bookings | 153 of 153 | 0.67-0.70 | 0.83-0.88 | 0 |
| goose-uring | C | alone | client | 51 of 51 | 0.11 | 0.15 | 0 |
| goose-uring | C | alone | encounter | 204 of 204 | 0.12 | 0.17-0.38 | 0 |
| goose-uring | C | alone | history | 204 of 204 | 0.14-0.15 | 0.19-0.22 | 0 |
| goose-uring | C | alone | poll | 934 of 935 | 0.10 | 0.46-0.53 | 0 |
| goose-uring | C | alone | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.17 | 0 |
| goose-epoll | C | alone | bookings | 153 of 153 | 0.66-0.68 | 0.83-0.90 | 0 |
| goose-epoll | C | alone | client | 51 of 51 | 0.11 | 0.15-0.18 | 0 |
| goose-epoll | C | alone | encounter | 204 of 204 | 0.12 | 0.18-0.32 | 0 |
| goose-epoll | C | alone | history | 204 of 204 | 0.14 | 0.19-0.26 | 0 |
| goose-epoll | C | alone | poll | 933-934 of 935 | 0.10 | 0.47-0.52 | 0 |
| goose-epoll | C | alone | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.18 | 0 |
| hyper | C | alone | bookings | 153 of 153 | 1.20-1.23 | 1.49-1.51 | 0 |
| hyper | C | alone | client | 51 of 51 | 0.12 | 0.18-0.19 | 0 |
| hyper | C | alone | encounter | 204 of 204 | 0.14-0.15 | 0.38-1.41 | 0 |
| hyper | C | alone | history | 204 of 204 | 0.19-0.21 | 0.62-1.01 | 0 |
| hyper | C | alone | poll | 932-935 of 935 | 0.11-0.12 | 1.20-1.24 | 0 |
| hyper | C | alone | shifts | 153 of 153 | 0.17-0.30 | 0.47-0.61 | 0 |
| actix-web | C | alone | bookings | 153 of 153 | 1.19-1.22 | 1.46-1.75 | 0 |
| actix-web | C | alone | client | 51 of 51 | 0.12-0.13 | 0.17-0.25 | 0 |
| actix-web | C | alone | encounter | 204 of 204 | 0.15-0.16 | 0.52-1.20 | 0 |
| actix-web | C | alone | history | 204 of 204 | 0.20-0.21 | 0.83-1.22 | 0 |
| actix-web | C | alone | poll | 933-934 of 935 | 0.12 | 0.97-1.01 | 0 |
| actix-web | C | alone | shifts | 153 of 153 | 0.14-0.15 | 0.19-0.24 | 0 |
| axum | C | alone | bookings | 153 of 153 | 1.06-1.09 | 1.32-1.44 | 0 |
| axum | C | alone | client | 51 of 51 | 0.12-0.13 | 0.17-0.18 | 0 |
| axum | C | alone | encounter | 204 of 204 | 0.15 | 0.21-0.55 | 0 |
| axum | C | alone | history | 204 of 204 | 0.18-0.20 | 0.31-1.12 | 0 |
| axum | C | alone | poll | 933-934 of 935 | 0.12 | 0.90-0.93 | 0 |
| axum | C | alone | shifts | 153 of 153 | 0.14-0.15 | 0.21-0.28 | 0 |
| dusty | C | alone | bookings | 153 of 153 | 1.47-1.49 | 1.75-1.79 | 0 |
| dusty | C | alone | client | 51 of 51 | 0.12 | 0.16-0.17 | 0 |
| dusty | C | alone | encounter | 204 of 204 | 0.17 | 1.00-1.43 | 0 |
| dusty | C | alone | history | 204 of 204 | 0.25-0.27 | 0.73-1.39 | 0 |
| dusty | C | alone | poll | 934-935 of 935 | 0.11-0.12 | 1.20-1.33 | 0 |
| dusty | C | alone | shifts | 153 of 153 | 0.14-0.16 | 0.21-0.43 | 0 |
| dusty-routes | C | alone | bookings | 153 of 153 | 1.54-1.56 | 1.83-1.88 | 0 |
| dusty-routes | C | alone | client | 51 of 51 | 0.11-0.13 | 0.16-0.26 | 0 |
| dusty-routes | C | alone | encounter | 204 of 204 | 0.17 | 0.73-1.41 | 0 |
| dusty-routes | C | alone | history | 204 of 204 | 0.27 | 0.66-1.68 | 0 |
| dusty-routes | C | alone | poll | 934 of 935 | 0.11-0.12 | 1.36-1.37 | 0 |
| dusty-routes | C | alone | shifts | 153 of 153 | 0.14-0.15 | 0.29-0.31 | 0 |
| goose-epoll-rest | C | alone | bookings | 153 of 153 | 0.73-0.75 | 0.96-1.00 | 0 |
| goose-epoll-rest | C | alone | client | 51 of 51 | 0.11-0.12 | 0.16-0.21 | 0 |
| goose-epoll-rest | C | alone | encounter | 204 of 204 | 0.14 | 0.23-0.74 | 0 |
| goose-epoll-rest | C | alone | history | 204 of 204 | 0.17 | 0.24-0.34 | 0 |
| goose-epoll-rest | C | alone | poll | 933-934 of 935 | 0.10 | 0.52-0.56 | 0 |
| goose-epoll-rest | C | alone | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.19 | 0 |
| goose-uring-rest | C | alone | bookings | 153 of 153 | 0.73-0.74 | 0.94-1.00 | 0 |
| goose-uring-rest | C | alone | client | 51 of 51 | 0.11-0.12 | 0.16-0.18 | 0 |
| goose-uring-rest | C | alone | encounter | 204 of 204 | 0.14 | 0.21-0.63 | 0 |
| goose-uring-rest | C | alone | history | 204 of 204 | 0.18 | 0.40-0.71 | 0 |
| goose-uring-rest | C | alone | poll | 933-934 of 935 | 0.10-0.11 | 0.53-0.56 | 0 |
| goose-uring-rest | C | alone | shifts | 153 of 153 | 0.12-0.13 | 0.17-0.19 | 0 |
| goose-uring | C | uploads | bookings | 153 of 153 | 2.44-2.56 | 6.79-6.95 | 0 |
| goose-uring | C | uploads | client | 51 of 51 | 1.94-3.62 | 7.53-8.51 | 0 |
| goose-uring | C | uploads | encounter | 204 of 204 | 2.12-2.52 | 8.06-8.30 | 0 |
| goose-uring | C | uploads | history | 204 of 204 | 1.90-2.50 | 5.59-6.80 | 0 |
| goose-uring | C | uploads | poll | 933-934 of 935 | 2.44-2.67 | 8.10-8.44 | 0 |
| goose-uring | C | uploads | shifts | 153 of 153 | 2.08-2.77 | 5.97-8.19 | 0 |
| goose-epoll | C | uploads | bookings | 153 of 153 | 0.77-0.79 | 1.32-1.53 | 0 |
| goose-epoll | C | uploads | client | 51 of 51 | 0.16-0.20 | 0.52-0.58 | 0 |
| goose-epoll | C | uploads | encounter | 204 of 204 | 0.18-0.19 | 0.55-1.04 | 0 |
| goose-epoll | C | uploads | history | 204 of 204 | 0.21-0.23 | 0.56-0.86 | 0 |
| goose-epoll | C | uploads | poll | 933-934 of 935 | 0.17-0.18 | 0.77-0.95 | 0 |
| goose-epoll | C | uploads | shifts | 153 of 153 | 0.19-0.21 | 0.53-0.63 | 0 |
| hyper | C | uploads | bookings | 153 of 153 | 1.33-1.35 | 4.42-4.85 | 0 |
| hyper | C | uploads | client | 51 of 51 | 0.15 | 3.68-4.04 | 0 |
| hyper | C | uploads | encounter | 204 of 204 | 0.23-0.27 | 3.59-3.90 | 0 |
| hyper | C | uploads | history | 204 of 204 | 0.29-0.31 | 3.88-4.15 | 0 |
| hyper | C | uploads | poll | 933 of 935 | 0.21-0.22 | 4.05-4.11 | 0 |
| hyper | C | uploads | shifts | 153 of 153 | 0.20-0.32 | 3.71-4.02 | 0 |
| actix-web | C | uploads | bookings | 153 of 153 | 7.79-7.99 | 20.9-21.0 | 0 |
| actix-web | C | uploads | client | 51 of 51 | 7.01-7.35 | 20.5-21.8 | 0 |
| actix-web | C | uploads | encounter | 204 of 204 | 7.16-7.34 | 20.4-20.6 | 0 |
| actix-web | C | uploads | history | 204 of 204 | 7.22-7.25 | 20.9-21.2 | 0 |
| actix-web | C | uploads | poll | 932-933 of 935 | 7.10-7.31 | 20.6-20.9 | 0 |
| actix-web | C | uploads | shifts | 153 of 153 | 7.33-7.74 | 21.2-21.7 | 0 |
| axum | C | uploads | bookings | 153 of 153 | 3.83-3.97 | 10.6-11.2 | 0 |
| axum | C | uploads | client | 51 of 51 | 2.94-3.21 | 8.60-9.47 | 0 |
| axum | C | uploads | encounter | 204 of 204 | 2.91-3.15 | 9.52-9.70 | 0 |
| axum | C | uploads | history | 204 of 204 | 2.94-3.32 | 9.40-9.48 | 0 |
| axum | C | uploads | poll | 933 of 935 | 3.08-3.15 | 9.68-10.0 | 0 |
| axum | C | uploads | shifts | 153 of 153 | 2.96-3.27 | 9.27-10.1 | 0 |
| dusty | C | uploads | bookings | 153 of 153 | 1.70-1.72 | 3.04-3.10 | 0 |
| dusty | C | uploads | client | 51 of 51 | 0.38-0.39 | 0.70-0.80 | 0 |
| dusty | C | uploads | encounter | 204 of 204 | 0.43-0.44 | 1.77-2.47 | 0 |
| dusty | C | uploads | history | 204 of 204 | 0.51-0.52 | 1.87-2.16 | 0 |
| dusty | C | uploads | poll | 933-934 of 935 | 0.39-0.40 | 2.07-2.28 | 0 |
| dusty | C | uploads | shifts | 153 of 153 | 0.38-0.44 | 0.95-2.94 | 0 |
| dusty-routes | C | uploads | bookings | 153 of 153 | 1.62-1.64 | 3.16-3.23 | 0 |
| dusty-routes | C | uploads | client | 51 of 51 | 0.20-0.21 | 0.58-0.78 | 0 |
| dusty-routes | C | uploads | encounter | 204 of 204 | 0.25-0.26 | 1.46-1.96 | 0 |
| dusty-routes | C | uploads | history | 204 of 204 | 0.34-0.35 | 1.25-1.99 | 0 |
| dusty-routes | C | uploads | poll | 933-934 of 935 | 0.19-0.21 | 1.82-2.38 | 0 |
| dusty-routes | C | uploads | shifts | 153 of 153 | 0.24-0.26 | 0.82-1.96 | 0 |
| goose-epoll-rest | C | uploads | bookings | 153 of 153 | 2.61-2.68 | 14.6-15.0 | 0 |
| goose-epoll-rest | C | uploads | client | 51 of 51 | 2.02-2.21 | 14.0-14.6 | 0 |
| goose-epoll-rest | C | uploads | encounter | 204 of 204 | 1.76-2.08 | 14.1-14.8 | 0 |
| goose-epoll-rest | C | uploads | history | 204 of 204 | 1.68-2.02 | 13.6-15.0 | 0 |
| goose-epoll-rest | C | uploads | poll | 933-934 of 935 | 1.85-2.03 | 14.5-15.4 | 0 |
| goose-epoll-rest | C | uploads | shifts | 153 of 153 | 1.84-1.90 | 14.3-14.6 | 0 |
| goose-uring-rest | C | uploads | bookings | 153 of 153 | 4.23-4.77 | 23.3-24.1 | 0 |
| goose-uring-rest | C | uploads | client | 51 of 51 | 4.23-5.95 | 23.7-27.4 | 0 |
| goose-uring-rest | C | uploads | encounter | 204 of 204 | 4.48-4.67 | 25.0-26.6 | 0 |
| goose-uring-rest | C | uploads | history | 204 of 204 | 3.43-4.12 | 21.8-23.8 | 0 |
| goose-uring-rest | C | uploads | poll | 933 of 935 | 4.32-4.85 | 24.4-26.5 | 0 |
| goose-uring-rest | C | uploads | shifts | 153 of 153 | 3.74-4.90 | 25.7-26.5 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | C | alone | 91.8-93.4 |  |
| goose-epoll | C | alone | 90.3-91.5 |  |
| hyper | C | alone | 156.9-160.0 |  |
| actix-web | C | alone | 158.3-160.5 |  |
| axum | C | alone | 146.8-149.1 |  |
| dusty | C | alone | 196.6-199.3 |  |
| dusty-routes | C | alone | 204.4-205.6 |  |
| goose-epoll-rest | C | alone | 102.9-104.0 |  |
| goose-uring-rest | C | alone | 104.8-105.5 |  |
| goose-uring | C | uploads | 2225.5-2310.5 | 1.1K |
| goose-epoll | C | uploads | 2318.4-2341.7 | 1.1K |
| hyper | C | uploads | 2069.5-2081.0 | 1.1K |
| actix-web | C | uploads | 2300.6-2321.1 | 1.1K |
| axum | C | uploads | 2124.4-2142.6 | 1.1K |
| dusty | C | uploads | 2359.5-2369.6 | 1.0K |
| dusty-routes | C | uploads | 2314.0-2333.9 | 1.2K |
| goose-epoll-rest | C | uploads | 2324.9-2348.0 | 929-937 |
| goose-uring-rest | C | uploads | 2343.2-2358.4 | 922-941 |

