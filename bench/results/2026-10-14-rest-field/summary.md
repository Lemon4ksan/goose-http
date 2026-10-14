## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring | A | serialize | 588.0K | 587.4K-590.0K | 0.37 | 0.65 | 6.7 | 15 | 0 |
| goose-epoll | A | serialize | 448.3K | 437.5K-448.8K | 0.54 | 0.92 | 8.9 | 9 | 0 |
| hyper | A | serialize | 270.7K | 266.3K-272.9K | 0.92 | 2.02 | 14.8 | 13 | 0 |
| tokio | A | serialize | 392.5K | 387.9K-394.0K | 0.66 | 0.94 | 10.2 | 16 | 0 |
| xitca-web | A | serialize | 406.7K | 403.0K-412.0K | 0.62 | 0.86 | 9.8 | 32 | 0 |
| dusty | A | serialize | 343.1K | 343.0K-352.2K | 0.72 | 1.17 | 11.7 | 16 | 0 |
| goose-uring | A | template | 600.5K | 598.3K-605.3K | 0.36 | 0.61 | 6.6 | 23 | 0 |
| goose-epoll | A | template | 468.6K | 463.3K-469.8K | 0.53 | 0.81 | 8.5 | 18 | 0 |
| hyper | A | template | 289.1K | 286.1K-290.5K | 0.86 | 1.89 | 13.9 | 16 | 0 |
| tokio | A | template | 429.7K | 426.4K-437.5K | 0.57 | 0.91 | 9.3 | 19 | 0 |
| xitca-web | A | template | 427.2K | 422.0K-430.4K | 0.58 | 0.84 | 9.4 | 34 | 0 |
| dusty | A | template | 382.8K | 378.0K-383.9K | 0.65 | 1.05 | 10.5 | 18 | 0 |
| goose-uring | B | serialize | 277.8K | 274.8K-279.2K | 0.89 | 1.41 | 14.4 | 47 | 0 |
| goose-epoll | B | serialize | 222.0K | 220.2K-222.7K | 1.14 | 1.63 | 18.1 | 46 | 0 |
| hyper | B | serialize | 150.5K | 150.3K-151.6K | 1.66 | 3.66 | 26.6 | 29 | 0 |
| tokio | B | serialize | 182.9K | 167.3K-183.8K | 1.37 | 2.17 | 21.9 | 30 | 0 |
| xitca-web | B | serialize | 235.4K | 234.5K-237.6K | 1.05 | 1.58 | 17.0 | 68 | 0 |
| dusty | B | serialize | 162.2K | 159.5K-163.1K | 1.51 | 2.87 | 24.7 | 42 | 0 |
| goose-uring | B | template | 379.6K | 376.3K-379.8K | 0.65 | 0.98 | 10.5 | 153 | 0 |
| goose-epoll | B | template | 289.3K | 284.9K-293.3K | 0.90 | 1.32 | 13.8 | 151 | 0 |
| hyper | B | template | 196.8K | 195.4K-197.5K | 1.27 | 2.77 | 20.3 | 45 | 0 |
| tokio | B | template | 262.8K | 240.8K-264.8K | 1.00 | 1.46 | 15.3 | 49 | 0 |
| xitca-web | B | template | 309.5K | 308.1K-309.9K | 0.82 | 1.12 | 12.9 | 78 | 0 |
| dusty | B | template | 275.0K | 274.7K-279.9K | 0.87 | 1.49 | 14.6 | 54 | 0 |
| goose-uring | C | serialize | 52.3K | 52.3K-52.4K | 4.75 | 10.6 | 76.5 | 104 | 0 |
| goose-epoll | C | serialize | 51.3K | 50.7K-51.7K | 4.80 | 10.0 | 78.1 | 102 | 0 |
| hyper | C | serialize | 32.1K | 31.5K-32.4K | 7.80 | 18.9 | 125.1 | 37 | 0 |
| tokio | C | serialize | 31.6K | 31.2K-31.7K | 7.79 | 17.3 | 127.1 | 307 | 0 |
| xitca-web | C | serialize | 38.2K | 37.3K-38.4K | 6.50 | 15.1 | 104.6 | 490 | 0 |
| dusty | C | serialize | 24.6K | 24.6K | 11.1 | 34.4 | 163.2 | 216 | 0 |
| goose-uring | C | template | 142.2K | 140.6K-143.9K | 1.73 | 3.30 | 28.0 | 177 | 0 |
| goose-epoll | C | template | 135.6K | 135.5K-136.2K | 1.83 | 3.33 | 29.5 | 176 | 0 |
| hyper | C | template | 119.8K | 119.4K-119.9K | 2.08 | 4.47 | 33.3 | 74 | 0 |
| tokio | C | template | 100.1K | 99.2K-103.0K | 2.49 | 4.32 | 40.0 | 365 | 0 |
| xitca-web | C | template | 113.2K | 109.8K-113.9K | 2.14 | 4.83 | 34.9 | 512 | 0 |
| dusty | C | template | 125.0K | 124.9K-129.7K | 2.02 | 3.56 | 32.0 | 241 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring | alone | 1.2K | 15.9-16.6 |  |  | 103 | 0 |
| goose-epoll | alone | 1.1K-1.2K | 14.8-16.0 |  |  | 103 | 0 |
| hyper | alone | 1.1K | 14.8-15.3 |  |  | 72 | 0 |
| tokio | alone | 1.0K-1.1K | 19.7-22.4 |  |  | 412 | 0 |
| xitca-web | alone | 1.0K | 18.6-20.0 |  |  | 56 | 0 |
| dusty | alone | 1.1K | 15.5-16.0 |  |  | 31 | 0 |
| goose-uring | beside forms | 159-163 | 123-128 | 7.1K-7.2K | 74.0-77.3 | 165 | 0 |
| goose-epoll | beside forms | 116-121 | 150-188 | 7.4K-7.5K | 89.8-93.8 | 173 | 0 |
| hyper | beside forms | 36-50 | 126-217 | 5.0K | 118-145 | 182 | 0 |
| tokio | beside forms | 252-279 | 76.1-83.1 | 3.7K-3.9K | 109-110 | 469 | 0 |
| xitca-web | beside forms | 47-64 | 251-417 | 4.3K-4.4K | 162-205 | 185 | 0 |
| dusty | beside forms | 27-41 | 443-557 | 2.9K-3.0K | 336-363 | 815 | 0 |

## Fixed rate

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | A | serialize | item | 108.9K-109.0K of 109.2K | 0.10 | 0.17-0.18 | 0 |
| goose-uring | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.16-0.17 | 0 |
| goose-uring | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.16-0.17 | 0 |
| goose-epoll | A | serialize | item | 108.9K-109.0K of 109.2K | 0.10 | 0.18-0.19 | 0 |
| goose-epoll | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.17 | 0 |
| goose-epoll | A | serialize | write | 8.4K of 8.4K | 0.10-0.11 | 0.17 | 0 |
| hyper | A | serialize | item | 108.9K of 109.2K | 0.11 | 0.35-0.44 | 0 |
| hyper | A | serialize | me | 22.4K of 22.4K | 0.10 | 0.30-0.32 | 0 |
| hyper | A | serialize | write | 8.4K of 8.4K | 0.12 | 0.29-0.32 | 0 |
| tokio | A | serialize | item | 108.9K-109.0K of 109.2K | 0.10 | 0.19-0.27 | 0 |
| tokio | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.18-0.21 | 0 |
| tokio | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.17-0.24 | 0 |
| xitca-web | A | serialize | item | 108.9K-109.0K of 109.2K | 0.12-0.13 | 0.33-1.56 | 0 |
| xitca-web | A | serialize | me | 22.4K of 22.4K | 0.11-0.12 | 0.30-0.71 | 0 |
| xitca-web | A | serialize | write | 8.4K of 8.4K | 0.13-0.14 | 0.33-0.85 | 0 |
| dusty | A | serialize | item | 108.8K-109.1K of 109.2K | 0.11 | 0.19-0.23 | 0 |
| dusty | A | serialize | me | 22.4K of 22.4K | 0.10 | 0.18-0.21 | 0 |
| dusty | A | serialize | write | 8.4K of 8.4K | 0.12 | 0.18-0.22 | 0 |
| goose-uring | A | template | item | 108.8K-109.0K of 109.2K | 0.09-0.10 | 0.17-4.89 | 0 |
| goose-uring | A | template | me | 22.4K of 22.4K | 0.09 | 0.16-2.72 | 0 |
| goose-uring | A | template | write | 8.4K of 8.4K | 0.10-0.11 | 0.16-2.85 | 0 |
| goose-epoll | A | template | item | 108.9K-109.0K of 109.2K | 0.10 | 0.18-20.7 | 0 |
| goose-epoll | A | template | me | 22.4K of 22.4K | 0.09 | 0.17-25.9 | 0 |
| goose-epoll | A | template | write | 8.4K of 8.4K | 0.10-0.11 | 0.17-9.49 | 0 |
| hyper | A | template | item | 108.9K-109.0K of 109.2K | 0.11 | 0.49-0.55 | 0 |
| hyper | A | template | me | 22.4K of 22.4K | 0.10 | 0.39-0.44 | 0 |
| hyper | A | template | write | 8.4K of 8.4K | 0.12 | 0.39-0.47 | 0 |
| tokio | A | template | item | 108.8K-108.9K of 109.2K | 0.10 | 0.20-0.21 | 0 |
| tokio | A | template | me | 22.4K of 22.4K | 0.09 | 0.18-0.19 | 0 |
| tokio | A | template | write | 8.4K of 8.4K | 0.11 | 0.18-0.20 | 0 |
| xitca-web | A | template | item | 108.9K-109.0K of 109.2K | 0.12 | 0.31-6.36 | 0 |
| xitca-web | A | template | me | 22.4K of 22.4K | 0.11-0.12 | 0.31-7.01 | 0 |
| xitca-web | A | template | write | 8.4K of 8.4K | 0.13 | 0.29-3.20 | 0 |
| dusty | A | template | item | 108.9K-109.0K of 109.2K | 0.11 | 0.20 | 0 |
| dusty | A | template | me | 22.4K of 22.4K | 0.09-0.10 | 0.18-0.19 | 0 |
| dusty | A | template | write | 8.4K of 8.4K | 0.12 | 0.18-0.19 | 0 |
| goose-uring | B | serialize | entries | 18.7K of 18.8K | 0.12 | 0.19-0.20 | 0 |
| goose-uring | B | serialize | patch | 7.5K of 7.5K | 0.11 | 0.18 | 0 |
| goose-uring | B | serialize | projects | 11.2K of 11.2K | 0.11 | 0.19 | 0 |
| goose-uring | B | serialize | session | 18.7K of 18.8K | 0.11 | 0.19-0.20 | 0 |
| goose-uring | B | serialize | timer | 18.7K of 18.8K | 0.10 | 0.18-0.19 | 0 |
| goose-epoll | B | serialize | entries | 18.7K of 18.8K | 0.11-0.12 | 0.19-0.20 | 0 |
| goose-epoll | B | serialize | patch | 7.5K of 7.5K | 0.11 | 0.17-0.18 | 0 |
| goose-epoll | B | serialize | projects | 11.2K of 11.2K | 0.11 | 0.18-0.19 | 0 |
| goose-epoll | B | serialize | session | 18.7K of 18.8K | 0.10 | 0.17-0.19 | 0 |
| goose-epoll | B | serialize | timer | 18.7K of 18.8K | 0.10 | 0.18-0.19 | 0 |
| hyper | B | serialize | entries | 18.7K of 18.8K | 0.14 | 0.25-0.58 | 0 |
| hyper | B | serialize | patch | 7.5K of 7.5K | 0.12-0.13 | 0.23-0.34 | 0 |
| hyper | B | serialize | projects | 11.2K of 11.2K | 0.12 | 0.23-0.40 | 0 |
| hyper | B | serialize | session | 18.7K of 18.8K | 0.12 | 0.23-0.44 | 0 |
| hyper | B | serialize | timer | 18.7K of 18.8K | 0.11-0.12 | 0.23-0.59 | 0 |
| tokio | B | serialize | entries | 18.7K of 18.8K | 0.13 | 0.25-11.7 | 0 |
| tokio | B | serialize | patch | 7.5K of 7.5K | 0.12 | 0.23-15.7 | 0 |
| tokio | B | serialize | projects | 11.2K of 11.2K | 0.12 | 0.23-24.7 | 0 |
| tokio | B | serialize | session | 18.7K of 18.8K | 0.11 | 0.23-10.9 | 0 |
| tokio | B | serialize | timer | 18.7K of 18.8K | 0.11 | 0.23-9.34 | 0 |
| xitca-web | B | serialize | entries | 18.7K of 18.8K | 0.14-0.15 | 0.29-0.39 | 0 |
| xitca-web | B | serialize | patch | 7.5K of 7.5K | 0.13 | 0.29-0.36 | 0 |
| xitca-web | B | serialize | projects | 11.2K of 11.2K | 0.12-0.13 | 0.27-0.35 | 0 |
| xitca-web | B | serialize | session | 18.7K of 18.8K | 0.12-0.13 | 0.28-0.34 | 0 |
| xitca-web | B | serialize | timer | 18.7K of 18.8K | 0.13 | 0.29-0.36 | 0 |
| dusty | B | serialize | entries | 18.7K of 18.8K | 0.14 | 0.25-0.28 | 0 |
| dusty | B | serialize | patch | 7.5K of 7.5K | 0.12-0.13 | 0.23-0.26 | 0 |
| dusty | B | serialize | projects | 11.2K of 11.2K | 0.12 | 0.23-0.26 | 0 |
| dusty | B | serialize | session | 18.7K of 18.8K | 0.12 | 0.23-0.27 | 0 |
| dusty | B | serialize | timer | 18.7K of 18.8K | 0.11-0.12 | 0.22-0.26 | 0 |
| goose-uring | B | template | entries | 18.7K of 18.8K | 0.11 | 0.17 | 0 |
| goose-uring | B | template | patch | 7.5K of 7.5K | 0.11 | 0.17 | 0 |
| goose-uring | B | template | projects | 11.2K of 11.2K | 0.10 | 0.16-0.17 | 0 |
| goose-uring | B | template | session | 18.7K of 18.8K | 0.10 | 0.17 | 0 |
| goose-uring | B | template | timer | 18.7K of 18.8K | 0.10 | 0.16-0.17 | 0 |
| goose-epoll | B | template | entries | 18.7K of 18.8K | 0.11 | 0.17-0.18 | 0 |
| goose-epoll | B | template | patch | 7.5K of 7.5K | 0.11 | 0.17 | 0 |
| goose-epoll | B | template | projects | 11.2K of 11.2K | 0.10 | 0.17-0.18 | 0 |
| goose-epoll | B | template | session | 18.7K of 18.8K | 0.10 | 0.17-0.18 | 0 |
| goose-epoll | B | template | timer | 18.7K of 18.8K | 0.10 | 0.17-0.18 | 0 |
| hyper | B | template | entries | 18.7K of 18.8K | 0.12 | 0.22 | 0 |
| hyper | B | template | patch | 7.5K of 7.5K | 0.12 | 0.20-0.21 | 0 |
| hyper | B | template | projects | 11.2K of 11.2K | 0.12 | 0.21 | 0 |
| hyper | B | template | session | 18.7K of 18.8K | 0.11 | 0.20-0.21 | 0 |
| hyper | B | template | timer | 18.7K of 18.8K | 0.11 | 0.21 | 0 |
| tokio | B | template | entries | 18.7K of 18.8K | 0.11 | 0.17-0.23 | 0 |
| tokio | B | template | patch | 7.5K of 7.5K | 0.11 | 0.17-0.20 | 0 |
| tokio | B | template | projects | 11.2K of 11.2K | 0.11 | 0.17-0.21 | 0 |
| tokio | B | template | session | 18.7K of 18.8K | 0.10 | 0.17-0.22 | 0 |
| tokio | B | template | timer | 18.7K of 18.8K | 0.10 | 0.17-0.22 | 0 |
| xitca-web | B | template | entries | 18.7K of 18.8K | 0.13 | 0.21-2.61 | 0 |
| xitca-web | B | template | patch | 7.5K of 7.5K | 0.12 | 0.20-2.36 | 0 |
| xitca-web | B | template | projects | 11.2K of 11.2K | 0.12 | 0.21-3.60 | 0 |
| xitca-web | B | template | session | 18.7K of 18.8K | 0.12 | 0.21-3.03 | 0 |
| xitca-web | B | template | timer | 18.7K of 18.8K | 0.12 | 0.21-3.80 | 0 |
| dusty | B | template | entries | 18.7K of 18.8K | 0.11 | 0.18 | 0 |
| dusty | B | template | patch | 7.5K of 7.5K | 0.12 | 0.18 | 0 |
| dusty | B | template | projects | 11.2K of 11.2K | 0.11 | 0.18 | 0 |
| dusty | B | template | session | 18.7K of 18.8K | 0.10-0.11 | 0.18 | 0 |
| dusty | B | template | timer | 18.7K of 18.8K | 0.10-0.11 | 0.18 | 0 |
| goose-uring | C | serialize | bookings | 1.1K of 1.1K | 0.69 | 0.85-0.87 | 0 |
| goose-uring | C | serialize | client | 360 of 360 | 0.10 | 0.36-0.68 | 0 |
| goose-uring | C | serialize | encounter | 1.4K of 1.4K | 0.12-0.13 | 0.70-0.73 | 0 |
| goose-uring | C | serialize | history | 1.4K of 1.4K | 0.17 | 0.74 | 0 |
| goose-uring | C | serialize | poll | 6.6K of 6.6K | 0.10 | 0.70-0.71 | 0 |
| goose-uring | C | serialize | shifts | 1.1K of 1.1K | 0.12 | 0.34-0.84 | 0 |
| goose-epoll | C | serialize | bookings | 1.1K of 1.1K | 0.69 | 0.87-0.88 | 0 |
| goose-epoll | C | serialize | client | 360 of 360 | 0.10 | 0.48-0.72 | 0 |
| goose-epoll | C | serialize | encounter | 1.4K of 1.4K | 0.12-0.13 | 0.67-0.69 | 0 |
| goose-epoll | C | serialize | history | 1.4K of 1.4K | 0.17 | 0.74-0.75 | 0 |
| goose-epoll | C | serialize | poll | 6.6K of 6.6K | 0.10 | 0.66-0.67 | 0 |
| goose-epoll | C | serialize | shifts | 1.1K of 1.1K | 0.11-0.12 | 0.26-0.60 | 0 |
| hyper | C | serialize | bookings | 1.1K of 1.1K | 1.12-1.16 | 1.57-16.2 | 0 |
| hyper | C | serialize | client | 360 of 360 | 0.11-0.12 | 0.31-9.09 | 0 |
| hyper | C | serialize | encounter | 1.4K of 1.4K | 0.14-0.15 | 0.40-9.66 | 0 |
| hyper | C | serialize | history | 1.4K of 1.4K | 0.18-0.19 | 0.41-10.8 | 0 |
| hyper | C | serialize | poll | 6.6K of 6.6K | 0.11 | 0.41-11.0 | 0 |
| hyper | C | serialize | shifts | 1.1K of 1.1K | 0.14 | 0.27-8.36 | 0 |
| tokio | C | serialize | bookings | 1.1K of 1.1K | 1.17-1.18 | 1.74-12.2 | 0 |
| tokio | C | serialize | client | 360 of 360 | 0.11-0.12 | 1.26-1.38 | 0 |
| tokio | C | serialize | encounter | 1.4K of 1.4K | 0.13-0.14 | 1.28-3.97 | 0 |
| tokio | C | serialize | history | 1.4K of 1.4K | 0.18-0.19 | 1.45-4.76 | 0 |
| tokio | C | serialize | poll | 6.6K of 6.6K | 0.10-0.11 | 1.34-11.3 | 0 |
| tokio | C | serialize | shifts | 1.1K of 1.1K | 0.14-0.15 | 1.35-5.60 | 0 |
| xitca-web | C | serialize | bookings | 1.1K of 1.1K | 1.00-1.02 | 1.27-1.53 | 0 |
| xitca-web | C | serialize | client | 360 of 360 | 0.12 | 1.35-1.82 | 0 |
| xitca-web | C | serialize | encounter | 1.4K of 1.4K | 0.14 | 1.32-1.76 | 0 |
| xitca-web | C | serialize | history | 1.4K of 1.4K | 0.18-0.19 | 1.08-1.88 | 0 |
| xitca-web | C | serialize | poll | 6.6K of 6.6K | 0.11-0.12 | 1.65-1.70 | 0 |
| xitca-web | C | serialize | shifts | 1.1K of 1.1K | 0.14-0.15 | 1.21-1.50 | 0 |
| dusty | C | serialize | bookings | 1.1K of 1.1K | 1.44-1.45 | 1.91-2.60 | 0 |
| dusty | C | serialize | client | 360 of 360 | 0.14-0.16 | 1.32-2.31 | 0 |
| dusty | C | serialize | encounter | 1.4K of 1.4K | 0.16-0.17 | 1.45-1.56 | 0 |
| dusty | C | serialize | history | 1.4K of 1.4K | 0.25 | 1.55-1.67 | 0 |
| dusty | C | serialize | poll | 6.6K of 6.6K | 0.11 | 0.96-1.64 | 0 |
| dusty | C | serialize | shifts | 1.1K of 1.1K | 0.14 | 0.93-1.47 | 0 |
| goose-uring | C | template | bookings | 1.1K of 1.1K | 0.25-0.26 | 0.36-0.38 | 0 |
| goose-uring | C | template | client | 360 of 360 | 0.10 | 0.24-0.29 | 0 |
| goose-uring | C | template | encounter | 1.4K of 1.4K | 0.11 | 0.24-0.26 | 0 |
| goose-uring | C | template | history | 1.4K of 1.4K | 0.12 | 0.24-0.25 | 0 |
| goose-uring | C | template | poll | 6.6K of 6.6K | 0.09-0.10 | 0.23-0.24 | 0 |
| goose-uring | C | template | shifts | 1.1K of 1.1K | 0.10-0.11 | 0.14-0.27 | 0 |
| goose-epoll | C | template | bookings | 1.1K of 1.1K | 0.26 | 0.35-0.44 | 0 |
| goose-epoll | C | template | client | 360 of 360 | 0.10 | 0.14-0.19 | 0 |
| goose-epoll | C | template | encounter | 1.4K of 1.4K | 0.11 | 0.22-0.23 | 0 |
| goose-epoll | C | template | history | 1.4K of 1.4K | 0.12 | 0.24-0.26 | 0 |
| goose-epoll | C | template | poll | 6.6K of 6.6K | 0.09-0.10 | 0.22-0.23 | 0 |
| goose-epoll | C | template | shifts | 1.1K of 1.1K | 0.10 | 0.14-0.17 | 0 |
| hyper | C | template | bookings | 1.1K of 1.1K | 0.26-0.27 | 0.38-0.43 | 0 |
| hyper | C | template | client | 360 of 360 | 0.11-0.12 | 0.17-0.30 | 0 |
| hyper | C | template | encounter | 1.4K of 1.4K | 0.12 | 0.29 | 0 |
| hyper | C | template | history | 1.4K of 1.4K | 0.13-0.14 | 0.28-0.31 | 0 |
| hyper | C | template | poll | 6.6K of 6.6K | 0.11 | 0.28 | 0 |
| hyper | C | template | shifts | 1.1K of 1.1K | 0.11-0.12 | 0.18-0.19 | 0 |
| tokio | C | template | bookings | 1.1K of 1.1K | 0.27-0.28 | 0.37-0.44 | 0 |
| tokio | C | template | client | 360 of 360 | 0.10-0.11 | 0.14-0.23 | 0 |
| tokio | C | template | encounter | 1.4K of 1.4K | 0.11 | 0.26 | 0 |
| tokio | C | template | history | 1.4K of 1.4K | 0.12-0.13 | 0.27-0.28 | 0 |
| tokio | C | template | poll | 6.6K of 6.6K | 0.10 | 0.24-0.26 | 0 |
| tokio | C | template | shifts | 1.1K of 1.1K | 0.11 | 0.15-0.29 | 0 |
| xitca-web | C | template | bookings | 1.1K of 1.1K | 0.29-0.30 | 0.41-0.50 | 0 |
| xitca-web | C | template | client | 360 of 360 | 0.11 | 0.15-0.18 | 0 |
| xitca-web | C | template | encounter | 1.4K of 1.4K | 0.12 | 0.27-0.29 | 0 |
| xitca-web | C | template | history | 1.4K of 1.4K | 0.14 | 0.28-0.32 | 0 |
| xitca-web | C | template | poll | 6.6K of 6.6K | 0.11 | 0.27-0.30 | 0 |
| xitca-web | C | template | shifts | 1.1K of 1.1K | 0.12 | 0.16-0.34 | 0 |
| dusty | C | template | bookings | 1.1K of 1.1K | 0.25 | 0.38-0.41 | 0 |
| dusty | C | template | client | 360 of 360 | 0.10-0.11 | 0.15-0.17 | 0 |
| dusty | C | template | encounter | 1.4K of 1.4K | 0.11-0.12 | 0.25-0.26 | 0 |
| dusty | C | template | history | 1.4K of 1.4K | 0.13 | 0.25-0.27 | 0 |
| dusty | C | template | poll | 6.6K of 6.6K | 0.10 | 0.23-0.24 | 0 |
| dusty | C | template | shifts | 1.1K of 1.1K | 0.11 | 0.16-0.21 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | A | serialize | 17.8-18.5 |  |
| goose-epoll | A | serialize | 18.2-18.9 |  |
| hyper | A | serialize | 22.9-23.0 |  |
| tokio | A | serialize | 19.1-19.6 |  |
| xitca-web | A | serialize | 22.3-22.9 |  |
| dusty | A | serialize | 23.3-23.8 |  |
| goose-uring | A | template | 18.0-18.6 |  |
| goose-epoll | A | template | 17.8-18.3 |  |
| hyper | A | template | 22.5-22.8 |  |
| tokio | A | template | 18.4-18.7 |  |
| xitca-web | A | template | 22.7-23.2 |  |
| dusty | A | template | 23.0-23.1 |  |
| goose-uring | B | serialize | 28.7-29.1 |  |
| goose-epoll | B | serialize | 28.3-28.6 |  |
| hyper | B | serialize | 39.2-39.7 |  |
| tokio | B | serialize | 31.5-31.9 |  |
| xitca-web | B | serialize | 36.2-36.7 |  |
| dusty | B | serialize | 39.6-40.2 |  |
| goose-uring | B | template | 26.7-27.3 |  |
| goose-epoll | B | template | 26.5-26.9 |  |
| hyper | B | template | 35.4-35.7 |  |
| tokio | B | template | 27.6-28.4 |  |
| xitca-web | B | template | 33.7-34.1 |  |
| dusty | B | template | 34.2-34.7 |  |
| goose-uring | C | serialize | 90.5-91.1 |  |
| goose-epoll | C | serialize | 90.3-90.5 |  |
| hyper | C | serialize | 143.1-149.3 |  |
| tokio | C | serialize | 136.8-138.4 |  |
| xitca-web | C | serialize | 127.1-129.7 |  |
| dusty | C | serialize | 181.0-182.8 |  |
| goose-uring | C | template | 45.5-45.6 |  |
| goose-epoll | C | template | 45.4-45.8 |  |
| hyper | C | template | 54.6-55.7 |  |
| tokio | C | template | 48.8-50.3 |  |
| xitca-web | C | template | 60.7-61.7 |  |
| dusty | C | template | 55.7-56.1 |  |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | C | alone | bookings | 1.1K of 1.1K | 0.69 | 0.86-1.07 | 0 |
| goose-uring | C | alone | client | 360 of 360 | 0.10-0.11 | 0.61-0.82 | 0 |
| goose-uring | C | alone | encounter | 1.4K of 1.4K | 0.12-0.13 | 0.68-0.82 | 0 |
| goose-uring | C | alone | history | 1.4K of 1.4K | 0.17 | 0.72-0.76 | 0 |
| goose-uring | C | alone | poll | 6.6K of 6.6K | 0.10 | 0.71-0.81 | 0 |
| goose-uring | C | alone | shifts | 1.1K of 1.1K | 0.11-0.12 | 0.49-0.80 | 0 |
| goose-epoll | C | alone | bookings | 1.1K of 1.1K | 0.68-0.69 | 0.87-1.03 | 0 |
| goose-epoll | C | alone | client | 360 of 360 | 0.10-0.11 | 0.58-0.75 | 0 |
| goose-epoll | C | alone | encounter | 1.4K of 1.4K | 0.12-0.14 | 0.66-0.74 | 0 |
| goose-epoll | C | alone | history | 1.4K of 1.4K | 0.17 | 0.73-0.75 | 0 |
| goose-epoll | C | alone | poll | 6.6K of 6.6K | 0.10 | 0.66-0.70 | 0 |
| goose-epoll | C | alone | shifts | 1.1K of 1.1K | 0.11-0.12 | 0.43-0.62 | 0 |
| hyper | C | alone | bookings | 1.1K of 1.1K | 1.16-1.17 | 1.41-1.42 | 0 |
| hyper | C | alone | client | 360 of 360 | 0.11 | 0.22-0.60 | 0 |
| hyper | C | alone | encounter | 1.4K of 1.4K | 0.13-0.16 | 0.35-0.61 | 0 |
| hyper | C | alone | history | 1.4K of 1.4K | 0.18-0.20 | 0.38-0.69 | 0 |
| hyper | C | alone | poll | 6.6K of 6.6K | 0.11 | 0.31-0.52 | 0 |
| hyper | C | alone | shifts | 1.1K of 1.1K | 0.14 | 0.25-0.79 | 0 |
| tokio | C | alone | bookings | 1.1K of 1.1K | 1.19-1.24 | 1.82-2.22 | 0 |
| tokio | C | alone | client | 360 of 360 | 0.11-0.12 | 1.24-1.55 | 0 |
| tokio | C | alone | encounter | 1.4K of 1.4K | 0.14 | 1.33-1.55 | 0 |
| tokio | C | alone | history | 1.4K of 1.4K | 0.19 | 1.43-1.59 | 0 |
| tokio | C | alone | poll | 6.6K of 6.6K | 0.11 | 1.43-1.56 | 0 |
| tokio | C | alone | shifts | 1.1K of 1.1K | 0.14-0.15 | 1.26-1.52 | 0 |
| xitca-web | C | alone | bookings | 1.1K of 1.1K | 1.01-1.02 | 1.34-1.44 | 0 |
| xitca-web | C | alone | client | 360 of 360 | 0.12 | 1.35-1.68 | 0 |
| xitca-web | C | alone | encounter | 1.4K of 1.4K | 0.14 | 1.68-1.78 | 0 |
| xitca-web | C | alone | history | 1.4K of 1.4K | 0.18-0.19 | 1.62-1.83 | 0 |
| xitca-web | C | alone | poll | 6.6K of 6.6K | 0.11-0.12 | 1.66-1.76 | 0 |
| xitca-web | C | alone | shifts | 1.1K of 1.1K | 0.14-0.16 | 1.25-1.46 | 0 |
| dusty | C | alone | bookings | 1.1K of 1.1K | 1.43 | 1.89-2.40 | 0 |
| dusty | C | alone | client | 360 of 360 | 0.13-0.23 | 1.30-1.72 | 0 |
| dusty | C | alone | encounter | 1.4K of 1.4K | 0.16-0.17 | 1.45-1.52 | 0 |
| dusty | C | alone | history | 1.4K of 1.4K | 0.25 | 1.51-1.60 | 0 |
| dusty | C | alone | poll | 6.6K of 6.6K | 0.10-0.11 | 0.86-1.40 | 0 |
| dusty | C | alone | shifts | 1.1K of 1.1K | 0.14 | 0.90-1.47 | 0 |
| goose-uring | C | uploads | bookings | 1.1K of 1.1K | 2.45-2.71 | 8.17-8.71 | 0 |
| goose-uring | C | uploads | client | 360 of 360 | 2.79-2.89 | 9.08-10.3 | 0 |
| goose-uring | C | uploads | encounter | 1.4K of 1.4K | 2.79-2.90 | 9.69-9.91 | 0 |
| goose-uring | C | uploads | history | 1.4K of 1.4K | 2.06-2.27 | 7.80-8.23 | 0 |
| goose-uring | C | uploads | poll | 6.6K of 6.6K | 2.86-2.92 | 9.63-10.6 | 0 |
| goose-uring | C | uploads | shifts | 1.1K of 1.1K | 2.70-3.04 | 9.57-9.92 | 0 |
| goose-epoll | C | uploads | bookings | 1.1K of 1.1K | 0.82-0.84 | 1.69-2.00 | 0 |
| goose-epoll | C | uploads | client | 360 of 360 | 0.25-0.34 | 1.27-1.66 | 0 |
| goose-epoll | C | uploads | encounter | 1.4K of 1.4K | 0.27-0.31 | 1.41-1.53 | 0 |
| goose-epoll | C | uploads | history | 1.4K of 1.4K | 0.28-0.32 | 1.34-1.58 | 0 |
| goose-epoll | C | uploads | poll | 6.6K of 6.6K | 0.24-0.26 | 1.32-1.54 | 0 |
| goose-epoll | C | uploads | shifts | 1.1K of 1.1K | 0.23-0.28 | 1.02-1.69 | 0 |
| hyper | C | uploads | bookings | 1.1K of 1.1K | 5.38-5.44 | 11.8-29.1 | 0 |
| hyper | C | uploads | client | 360 of 360 | 4.59-5.11 | 11.2-20.6 | 0 |
| hyper | C | uploads | encounter | 1.4K of 1.4K | 4.77-4.85 | 11.1-26.0 | 0 |
| hyper | C | uploads | history | 1.4K of 1.4K | 4.79-4.84 | 11.2-23.4 | 0 |
| hyper | C | uploads | poll | 6.6K of 6.6K | 4.80-4.87 | 11.5-24.9 | 0 |
| hyper | C | uploads | shifts | 1.1K of 1.1K | 4.45-4.54 | 10.9-22.8 | 0 |
| tokio | C | uploads | bookings | 872-1.0K of 1.1K | 61.5-358 | 1645-5609 | 0 |
| tokio | C | uploads | client | 305-350 of 360 | 21.2-47.9 | 1055-5216 | 0 |
| tokio | C | uploads | encounter | 1.2K-1.3K of 1.4K | 47.2-465 | 1890-5630 | 0 |
| tokio | C | uploads | history | 1.2K-1.3K of 1.4K | 17.4-322 | 1882-5769 | 0 |
| tokio | C | uploads | poll | 5.5K-6.2K of 6.6K | 28.1-219 | 1653-5573 | 0 |
| tokio | C | uploads | shifts | 863-1.0K of 1.1K | 16.4-703 | 1602-5540 | 0 |
| xitca-web | C | uploads | bookings | 1.1K of 1.1K | 1.10-1.17 | 3.49-4.62 | 0 |
| xitca-web | C | uploads | client | 360 of 360 | 0.19-0.23 | 2.64-3.73 | 0 |
| xitca-web | C | uploads | encounter | 1.4K of 1.4K | 0.21-0.27 | 2.40-3.52 | 0 |
| xitca-web | C | uploads | history | 1.4K of 1.4K | 0.26-0.32 | 2.84-4.15 | 0 |
| xitca-web | C | uploads | poll | 6.6K of 6.6K | 0.20-0.25 | 3.17-4.25 | 0 |
| xitca-web | C | uploads | shifts | 1.1K of 1.1K | 0.21-0.23 | 2.27-2.69 | 0 |
| dusty | C | uploads | bookings | 1.1K of 1.1K | 1.89-2.30 | 8.87-40.4 | 0 |
| dusty | C | uploads | client | 360 of 360 | 0.56-1.14 | 7.70-20.0 | 0 |
| dusty | C | uploads | encounter | 1.4K of 1.4K | 0.72-0.87 | 6.67-39.0 | 0 |
| dusty | C | uploads | history | 1.4K of 1.4K | 0.87-1.19 | 8.32-41.8 | 0 |
| dusty | C | uploads | poll | 6.6K of 6.6K | 0.80-1.01 | 8.19-36.9 | 0 |
| dusty | C | uploads | shifts | 1.1K of 1.1K | 0.52-0.70 | 7.04-37.4 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | C | alone | 90.3-91.9 |  |
| goose-epoll | C | alone | 89.7-92.5 |  |
| hyper | C | alone | 146.6-147.2 |  |
| tokio | C | alone | 138.1-139.9 |  |
| xitca-web | C | alone | 128.2-128.8 |  |
| dusty | C | alone | 179.6-181.5 |  |
| goose-uring | C | uploads | 333.5-334.8 | 852-877 |
| goose-epoll | C | uploads | 334.3-336.6 | 878-886 |
| hyper | C | uploads | 335.5-336.6 | 760-776 |
| tokio | C | uploads | 360.2-405.6 | 677-730 |
| xitca-web | C | uploads | 335.9-336.9 | 618-635 |
| dusty | C | uploads | 336.8-337.6 | 514-526 |

