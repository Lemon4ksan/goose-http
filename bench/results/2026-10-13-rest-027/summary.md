## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| hyper | A | serialize | 283.5K | 279.2K-286.7K | 0.87 | 1.95 | 14.1 | 13 | 0 |
| dusty | A | serialize | 351.6K | 346.0K-357.1K | 0.70 | 1.15 | 11.4 | 16 | 0 |
| goose-uring-base | A | serialize | 598.6K | 590.2K-602.1K | 0.37 | 0.64 | 6.6 | 33 | 0 |
| goose-uring-p2 | A | serialize | 592.7K | 592.0K-593.2K | 0.37 | 0.66 | 6.7 | 33 | 0 |
| goose-uring-p3 | A | serialize | 591.3K | 582.9K-597.4K | 0.38 | 0.66 | 6.7 | 33 | 0 |
| goose-uring-p4 | A | serialize | 590.2K | 588.6K-593.9K | 0.38 | 0.66 | 6.7 | 33 | 0 |
| hyper | A | template | 311.9K | 303.9K-313.0K | 0.79 | 1.79 | 12.8 | 16 | 0 |
| dusty | A | template | 392.3K | 386.5K-418.4K | 0.60 | 0.96 | 10.2 | 18 | 0 |
| goose-uring-base | A | template | 609.8K | 599.3K-610.8K | 0.36 | 0.60 | 6.5 | 49 | 0 |
| goose-uring-p2 | A | template | 602.9K | 596.3K-609.9K | 0.36 | 0.66 | 6.6 | 49 | 0 |
| goose-uring-p3 | A | template | 608.0K | 604.9K-609.6K | 0.36 | 0.62 | 6.5 | 49 | 0 |
| goose-uring-p4 | A | template | 603.4K | 602.6K-603.8K | 0.36 | 0.64 | 6.6 | 49 | 0 |
| hyper | B | serialize | 152.7K | 151.6K-155.3K | 1.64 | 3.61 | 26.2 | 29 | 0 |
| dusty | B | serialize | 163.8K | 163.0K-166.2K | 1.46 | 2.95 | 24.5 | 42 | 0 |
| goose-uring-base | B | serialize | 272.2K | 269.4K-273.8K | 0.91 | 1.43 | 14.7 | 95 | 0 |
| goose-uring-p2 | B | serialize | 276.7K | 276.6K-278.5K | 0.90 | 1.39 | 14.4 | 95 | 0 |
| goose-uring-p3 | B | serialize | 272.0K | 271.8K-273.2K | 0.90 | 1.46 | 14.7 | 95 | 0 |
| goose-uring-p4 | B | serialize | 278.8K | 278.6K-278.9K | 0.89 | 1.41 | 14.3 | 95 | 0 |
| hyper | B | template | 200.1K | 196.0K-201.1K | 1.25 | 2.73 | 20.0 | 45 | 0 |
| dusty | B | template | 287.0K | 284.2K-291.1K | 0.80 | 1.51 | 14.0 | 54 | 0 |
| goose-uring-base | B | template | 386.8K | 381.9K-390.3K | 0.64 | 0.95 | 10.3 | 221 | 0 |
| goose-uring-p2 | B | template | 385.8K | 383.7K-387.1K | 0.64 | 0.96 | 10.3 | 221 | 0 |
| goose-uring-p3 | B | template | 380.9K | 380.4K-386.3K | 0.64 | 0.98 | 10.5 | 221 | 0 |
| goose-uring-p4 | B | template | 385.4K | 384.9K-386.7K | 0.64 | 0.95 | 10.4 | 221 | 0 |
| hyper | C | serialize | 32.5K | 32.1K-32.6K | 7.70 | 18.6 | 123.5 | 36 | 0 |
| dusty | C | serialize | 25.1K | 24.3K-25.1K | 11.2 | 33.1 | 160.2 | 216 | 0 |
| goose-uring-base | C | serialize | 53.1K | 52.9K-53.4K | 4.66 | 10.5 | 75.4 | 140 | 0 |
| goose-uring-p2 | C | serialize | 54.1K | 53.7K-54.3K | 4.59 | 10.1 | 73.9 | 140 | 0 |
| goose-uring-p3 | C | serialize | 51.7K | 51.7K-51.8K | 4.79 | 10.8 | 77.3 | 140 | 0 |
| goose-uring-p4 | C | serialize | 54.2K | 53.5K-54.3K | 4.57 | 10.2 | 73.7 | 140 | 0 |
| hyper | C | template | 122.1K | 120.5K-122.5K | 2.04 | 4.38 | 32.6 | 75 | 0 |
| dusty | C | template | 126.2K | 124.4K-126.8K | 1.95 | 3.81 | 31.6 | 241 | 0 |
| goose-uring-base | C | template | 149.2K | 148.7K-149.8K | 1.64 | 3.08 | 26.7 | 387 | 0 |
| goose-uring-p2 | C | template | 149.9K | 149.8K-150.2K | 1.63 | 3.09 | 26.6 | 387 | 0 |
| goose-uring-p3 | C | template | 147.4K | 144.8K-148.3K | 1.66 | 3.18 | 27.0 | 387 | 0 |
| goose-uring-p4 | C | template | 149.0K | 147.8K-149.9K | 1.64 | 3.10 | 26.7 | 387 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| hyper | alone | 1.1K-1.2K | 14.5-15.3 |  |  | 75 | 0 |
| dusty | alone | 1.1K-1.2K | 14.9-16.0 |  |  | 31 | 0 |
| goose-uring-base | alone | 1.1K-1.2K | 15.8-16.6 |  |  | 130 | 0 |
| goose-uring-p2 | alone | 1.1K | 16.3-16.9 |  |  | 130 | 0 |
| goose-uring-p3 | alone | 1.1K | 16.5-17.8 |  |  | 130 | 0 |
| goose-uring-p4 | alone | 1.1K | 16.4-17.3 |  |  | 130 | 0 |
| hyper | beside forms | 51-69 | 129-228 | 4.9K-5.0K | 164-172 | 219 | 0 |
| dusty | beside forms | 14-41 | 347-824 | 2.9K | 621-677 | 814 | 5 |
| goose-uring-base | beside forms | 162-164 | 124-132 | 7.2K | 73.3-75.5 | 205 | 0 |
| goose-uring-p2 | beside forms | 155-159 | 126-132 | 7.2K | 73.8-73.9 | 207 | 0 |
| goose-uring-p3 | beside forms | 154-160 | 128-147 | 7.2K-7.3K | 75.1-76.3 | 205 | 0 |
| goose-uring-p4 | beside forms | 161-163 | 120-127 | 7.1K-7.2K | 72.6-78.3 | 206 | 0 |

## Fixed rate

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| hyper | A | serialize | item | 108.8K-109.0K of 109.2K | 0.11 | 0.25-0.77 | 0 |
| hyper | A | serialize | me | 22.4K of 22.4K | 0.10 | 0.23-0.56 | 0 |
| hyper | A | serialize | write | 8.4K of 8.4K | 0.12 | 0.24-0.53 | 0 |
| dusty | A | serialize | item | 108.9K-109.0K of 109.2K | 0.11 | 0.19-0.20 | 0 |
| dusty | A | serialize | me | 22.4K of 22.4K | 0.10 | 0.18 | 0 |
| dusty | A | serialize | write | 8.4K of 8.4K | 0.12 | 0.19 | 0 |
| goose-uring-base | A | serialize | item | 108.8K-108.9K of 109.2K | 0.10 | 0.17-4.02 | 0 |
| goose-uring-base | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.16-2.80 | 0 |
| goose-uring-base | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.16-1.91 | 0 |
| goose-uring-p2 | A | serialize | item | 108.9K-109.0K of 109.2K | 0.09-0.10 | 0.17 | 0 |
| goose-uring-p2 | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.16-0.17 | 0 |
| goose-uring-p2 | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.16-0.17 | 0 |
| goose-uring-p3 | A | serialize | item | 108.9K-109.0K of 109.2K | 0.10 | 0.17-3.79 | 0 |
| goose-uring-p3 | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.16-2.58 | 0 |
| goose-uring-p3 | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.16-1.34 | 0 |
| goose-uring-p4 | A | serialize | item | 109.0K of 109.2K | 0.10 | 0.17 | 0 |
| goose-uring-p4 | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.16 | 0 |
| goose-uring-p4 | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.16-0.17 | 0 |
| hyper | A | template | item | 108.9K-109.0K of 109.2K | 0.11 | 0.29-0.39 | 0 |
| hyper | A | template | me | 22.4K of 22.4K | 0.10 | 0.25-0.33 | 0 |
| hyper | A | template | write | 8.4K of 8.4K | 0.12 | 0.27-0.33 | 0 |
| dusty | A | template | item | 108.9K-109.0K of 109.2K | 0.10-0.11 | 0.19-0.21 | 0 |
| dusty | A | template | me | 22.4K of 22.4K | 0.10 | 0.18-0.20 | 0 |
| dusty | A | template | write | 8.4K of 8.4K | 0.12 | 0.18-0.21 | 0 |
| goose-uring-base | A | template | item | 108.9K-109.0K of 109.2K | 0.09-0.10 | 0.17 | 0 |
| goose-uring-base | A | template | me | 22.4K of 22.4K | 0.08-0.09 | 0.15-0.16 | 0 |
| goose-uring-base | A | template | write | 8.4K of 8.4K | 0.11 | 0.16 | 0 |
| goose-uring-p2 | A | template | item | 108.9K-109.0K of 109.2K | 0.09-0.10 | 0.17 | 0 |
| goose-uring-p2 | A | template | me | 22.4K of 22.4K | 0.09 | 0.16 | 0 |
| goose-uring-p2 | A | template | write | 8.4K of 8.4K | 0.11 | 0.16 | 0 |
| goose-uring-p3 | A | template | item | 108.9K-109.0K of 109.2K | 0.09-0.10 | 0.17 | 0 |
| goose-uring-p3 | A | template | me | 22.4K of 22.4K | 0.09 | 0.16 | 0 |
| goose-uring-p3 | A | template | write | 8.4K of 8.4K | 0.11 | 0.16 | 0 |
| goose-uring-p4 | A | template | item | 108.9K-109.0K of 109.2K | 0.10 | 0.17 | 0 |
| goose-uring-p4 | A | template | me | 22.4K of 22.4K | 0.08-0.09 | 0.16 | 0 |
| goose-uring-p4 | A | template | write | 8.4K of 8.4K | 0.10-0.11 | 0.16 | 0 |
| hyper | B | serialize | entries | 18.5K of 18.5K | 0.14 | 0.25-0.49 | 0 |
| hyper | B | serialize | patch | 7.4K of 7.4K | 0.12-0.13 | 0.23-0.36 | 0 |
| hyper | B | serialize | projects | 11.1K of 11.1K | 0.12 | 0.23-0.38 | 0 |
| hyper | B | serialize | session | 18.5K of 18.5K | 0.12 | 0.23-0.59 | 0 |
| hyper | B | serialize | timer | 18.5K of 18.5K | 0.11-0.12 | 0.22-0.46 | 0 |
| dusty | B | serialize | entries | 18.5K of 18.5K | 0.14 | 0.23-0.28 | 0 |
| dusty | B | serialize | patch | 7.4K of 7.4K | 0.13 | 0.22-0.26 | 0 |
| dusty | B | serialize | projects | 11.1K of 11.1K | 0.12 | 0.22-0.25 | 0 |
| dusty | B | serialize | session | 18.5K of 18.5K | 0.12 | 0.22-0.27 | 0 |
| dusty | B | serialize | timer | 18.5K of 18.5K | 0.11-0.12 | 0.21-0.26 | 0 |
| goose-uring-base | B | serialize | entries | 18.5K of 18.5K | 0.12 | 0.18-1.05 | 0 |
| goose-uring-base | B | serialize | patch | 7.4K of 7.4K | 0.11 | 0.17-1.61 | 0 |
| goose-uring-base | B | serialize | projects | 11.1K of 11.1K | 0.11 | 0.18-1.17 | 0 |
| goose-uring-base | B | serialize | session | 18.5K of 18.5K | 0.10-0.11 | 0.18-2.16 | 0 |
| goose-uring-base | B | serialize | timer | 18.5K of 18.5K | 0.10 | 0.18-1.27 | 0 |
| goose-uring-p2 | B | serialize | entries | 18.5K of 18.5K | 0.12 | 0.19 | 0 |
| goose-uring-p2 | B | serialize | patch | 7.4K of 7.4K | 0.11 | 0.18 | 0 |
| goose-uring-p2 | B | serialize | projects | 11.1K of 11.1K | 0.11 | 0.18 | 0 |
| goose-uring-p2 | B | serialize | session | 18.5K of 18.5K | 0.10 | 0.18-0.19 | 0 |
| goose-uring-p2 | B | serialize | timer | 18.5K of 18.5K | 0.10 | 0.17-0.18 | 0 |
| goose-uring-p3 | B | serialize | entries | 18.5K of 18.5K | 0.12 | 0.20-0.22 | 0 |
| goose-uring-p3 | B | serialize | patch | 7.4K of 7.4K | 0.11 | 0.18-0.20 | 0 |
| goose-uring-p3 | B | serialize | projects | 11.1K of 11.1K | 0.11 | 0.19-0.21 | 0 |
| goose-uring-p3 | B | serialize | session | 18.5K of 18.5K | 0.10 | 0.18-0.22 | 0 |
| goose-uring-p3 | B | serialize | timer | 18.5K of 18.5K | 0.10 | 0.19-0.22 | 0 |
| goose-uring-p4 | B | serialize | entries | 18.5K of 18.5K | 0.12 | 0.19-0.21 | 0 |
| goose-uring-p4 | B | serialize | patch | 7.4K of 7.4K | 0.11 | 0.17-0.19 | 0 |
| goose-uring-p4 | B | serialize | projects | 11.1K of 11.1K | 0.11 | 0.17-0.20 | 0 |
| goose-uring-p4 | B | serialize | session | 18.5K of 18.5K | 0.10-0.11 | 0.17-0.21 | 0 |
| goose-uring-p4 | B | serialize | timer | 18.5K of 18.5K | 0.10-0.11 | 0.17-0.19 | 0 |
| hyper | B | template | entries | 18.5K of 18.5K | 0.12 | 0.21 | 0 |
| hyper | B | template | patch | 7.4K of 7.4K | 0.12 | 0.20 | 0 |
| hyper | B | template | projects | 11.1K of 11.1K | 0.12 | 0.21 | 0 |
| hyper | B | template | session | 18.5K of 18.5K | 0.11-0.12 | 0.20-0.21 | 0 |
| hyper | B | template | timer | 18.5K of 18.5K | 0.11 | 0.20-0.21 | 0 |
| dusty | B | template | entries | 18.5K of 18.5K | 0.11-0.12 | 0.18-0.22 | 0 |
| dusty | B | template | patch | 7.4K of 7.4K | 0.12 | 0.18-0.22 | 0 |
| dusty | B | template | projects | 11.1K of 11.1K | 0.11 | 0.18-0.21 | 0 |
| dusty | B | template | session | 18.5K of 18.5K | 0.11 | 0.18-0.24 | 0 |
| dusty | B | template | timer | 18.5K of 18.5K | 0.11 | 0.18-0.23 | 0 |
| goose-uring-base | B | template | entries | 18.5K of 18.5K | 0.11 | 0.17-0.18 | 0 |
| goose-uring-base | B | template | patch | 7.4K of 7.4K | 0.11 | 0.17 | 0 |
| goose-uring-base | B | template | projects | 11.1K of 11.1K | 0.10-0.11 | 0.16-0.17 | 0 |
| goose-uring-base | B | template | session | 18.5K of 18.5K | 0.10 | 0.17 | 0 |
| goose-uring-base | B | template | timer | 18.5K of 18.5K | 0.10 | 0.16-0.17 | 0 |
| goose-uring-p2 | B | template | entries | 18.5K of 18.5K | 0.11 | 0.17 | 0 |
| goose-uring-p2 | B | template | patch | 7.4K of 7.4K | 0.11 | 0.17 | 0 |
| goose-uring-p2 | B | template | projects | 11.1K of 11.1K | 0.11 | 0.17 | 0 |
| goose-uring-p2 | B | template | session | 18.5K of 18.5K | 0.10 | 0.17 | 0 |
| goose-uring-p2 | B | template | timer | 18.5K of 18.5K | 0.10 | 0.16-0.17 | 0 |
| goose-uring-p3 | B | template | entries | 18.5K of 18.5K | 0.11 | 0.17-0.18 | 0 |
| goose-uring-p3 | B | template | patch | 7.4K of 7.4K | 0.11 | 0.17 | 0 |
| goose-uring-p3 | B | template | projects | 11.1K of 11.1K | 0.10-0.11 | 0.16-0.17 | 0 |
| goose-uring-p3 | B | template | session | 18.5K of 18.5K | 0.10 | 0.16-0.18 | 0 |
| goose-uring-p3 | B | template | timer | 18.5K of 18.5K | 0.10 | 0.17-0.18 | 0 |
| goose-uring-p4 | B | template | entries | 18.5K of 18.5K | 0.11 | 0.17-0.19 | 0 |
| goose-uring-p4 | B | template | patch | 7.4K of 7.4K | 0.11 | 0.17-0.18 | 0 |
| goose-uring-p4 | B | template | projects | 11.1K of 11.1K | 0.11 | 0.17-0.18 | 0 |
| goose-uring-p4 | B | template | session | 18.5K of 18.5K | 0.10 | 0.17-0.19 | 0 |
| goose-uring-p4 | B | template | timer | 18.5K of 18.5K | 0.10 | 0.17-0.19 | 0 |
| hyper | C | serialize | bookings | 1.4K of 1.4K | 1.13-1.16 | 1.37-52.0 | 0 |
| hyper | C | serialize | client | 480 of 480 | 0.11-0.17 | 0.34-56.3 | 0 |
| hyper | C | serialize | encounter | 1.9K of 1.9K | 0.14-0.16 | 0.53-22.0 | 0 |
| hyper | C | serialize | history | 1.9K of 1.9K | 0.19-0.20 | 0.59-38.0 | 0 |
| hyper | C | serialize | poll | 8.8K of 8.8K | 0.11-0.12 | 0.53-21.7 | 0 |
| hyper | C | serialize | shifts | 1.4K of 1.4K | 0.15-0.24 | 0.58-19.3 | 0 |
| dusty | C | serialize | bookings | 1.4K of 1.4K | 1.45-1.46 | 2.54-2.68 | 0 |
| dusty | C | serialize | client | 480 of 480 | 0.16-0.34 | 2.12-2.60 | 0 |
| dusty | C | serialize | encounter | 1.9K of 1.9K | 0.17-0.20 | 1.61-1.78 | 0 |
| dusty | C | serialize | history | 1.9K of 1.9K | 0.26-0.28 | 1.66-1.77 | 0 |
| dusty | C | serialize | poll | 8.8K of 8.8K | 0.12 | 1.71-2.11 | 0 |
| dusty | C | serialize | shifts | 1.4K of 1.4K | 0.15 | 1.68-1.80 | 0 |
| goose-uring-base | C | serialize | bookings | 1.4K of 1.4K | 0.67 | 0.85-0.95 | 0 |
| goose-uring-base | C | serialize | client | 480 of 480 | 0.11 | 0.43-1.04 | 0 |
| goose-uring-base | C | serialize | encounter | 1.9K of 1.9K | 0.13 | 0.73-0.87 | 0 |
| goose-uring-base | C | serialize | history | 1.9K of 1.9K | 0.17 | 0.70-0.73 | 0 |
| goose-uring-base | C | serialize | poll | 8.8K of 8.8K | 0.10 | 0.72-0.89 | 0 |
| goose-uring-base | C | serialize | shifts | 1.4K of 1.4K | 0.11-0.12 | 0.58-0.67 | 0 |
| goose-uring-p2 | C | serialize | bookings | 1.4K of 1.4K | 0.67 | 0.85-1.08 | 0 |
| goose-uring-p2 | C | serialize | client | 480 of 480 | 0.11 | 0.65-1.09 | 0 |
| goose-uring-p2 | C | serialize | encounter | 1.9K of 1.9K | 0.13 | 0.72-0.91 | 0 |
| goose-uring-p2 | C | serialize | history | 1.9K of 1.9K | 0.17 | 0.70-0.77 | 0 |
| goose-uring-p2 | C | serialize | poll | 8.8K of 8.8K | 0.10 | 0.73-1.22 | 0 |
| goose-uring-p2 | C | serialize | shifts | 1.4K of 1.4K | 0.12-0.13 | 0.49-0.68 | 0 |
| goose-uring-p3 | C | serialize | bookings | 1.4K of 1.4K | 0.68 | 0.87-0.94 | 0 |
| goose-uring-p3 | C | serialize | client | 480 of 480 | 0.10-0.11 | 0.93-1.26 | 0 |
| goose-uring-p3 | C | serialize | encounter | 1.9K of 1.9K | 0.13-0.14 | 0.83-0.90 | 0 |
| goose-uring-p3 | C | serialize | history | 1.9K of 1.9K | 0.17-0.18 | 0.73-0.75 | 0 |
| goose-uring-p3 | C | serialize | poll | 8.8K of 8.8K | 0.10 | 0.83-0.99 | 0 |
| goose-uring-p3 | C | serialize | shifts | 1.4K of 1.4K | 0.12 | 0.81-1.02 | 0 |
| goose-uring-p4 | C | serialize | bookings | 1.4K of 1.4K | 0.66-0.67 | 0.90-0.97 | 0 |
| goose-uring-p4 | C | serialize | client | 480 of 480 | 0.10-0.11 | 0.95-1.07 | 0 |
| goose-uring-p4 | C | serialize | encounter | 1.9K of 1.9K | 0.13 | 0.91-1.08 | 0 |
| goose-uring-p4 | C | serialize | history | 1.9K of 1.9K | 0.17 | 0.71-0.73 | 0 |
| goose-uring-p4 | C | serialize | poll | 8.8K of 8.8K | 0.10 | 0.96-1.12 | 0 |
| goose-uring-p4 | C | serialize | shifts | 1.4K of 1.4K | 0.12 | 0.43-0.79 | 0 |
| hyper | C | template | bookings | 1.4K of 1.4K | 0.26 | 0.37-0.45 | 0 |
| hyper | C | template | client | 480 of 480 | 0.11-0.12 | 0.20-0.30 | 0 |
| hyper | C | template | encounter | 1.9K of 1.9K | 0.12 | 0.25-0.29 | 0 |
| hyper | C | template | history | 1.9K of 1.9K | 0.13-0.14 | 0.28-0.31 | 0 |
| hyper | C | template | poll | 8.8K of 8.8K | 0.11 | 0.25-0.29 | 0 |
| hyper | C | template | shifts | 1.4K of 1.4K | 0.12 | 0.25-0.28 | 0 |
| dusty | C | template | bookings | 1.4K of 1.4K | 0.24 | 0.33-0.36 | 0 |
| dusty | C | template | client | 480 of 480 | 0.11 | 0.15-0.26 | 0 |
| dusty | C | template | encounter | 1.9K of 1.9K | 0.11-0.12 | 0.23-0.24 | 0 |
| dusty | C | template | history | 1.9K of 1.9K | 0.13 | 0.25 | 0 |
| dusty | C | template | poll | 8.8K of 8.8K | 0.10 | 0.23 | 0 |
| dusty | C | template | shifts | 1.4K of 1.4K | 0.11 | 0.17-0.18 | 0 |
| goose-uring-base | C | template | bookings | 1.4K of 1.4K | 0.25 | 0.33-0.40 | 0 |
| goose-uring-base | C | template | client | 480 of 480 | 0.10 | 0.13-0.28 | 0 |
| goose-uring-base | C | template | encounter | 1.9K of 1.9K | 0.11 | 0.23-0.24 | 0 |
| goose-uring-base | C | template | history | 1.9K of 1.9K | 0.12 | 0.24-0.25 | 0 |
| goose-uring-base | C | template | poll | 8.8K of 8.8K | 0.10 | 0.23-0.24 | 0 |
| goose-uring-base | C | template | shifts | 1.4K of 1.4K | 0.11 | 0.15-0.24 | 0 |
| goose-uring-p2 | C | template | bookings | 1.4K of 1.4K | 0.25 | 0.32-0.38 | 0 |
| goose-uring-p2 | C | template | client | 480 of 480 | 0.10 | 0.14-0.27 | 0 |
| goose-uring-p2 | C | template | encounter | 1.9K of 1.9K | 0.11 | 0.22-0.24 | 0 |
| goose-uring-p2 | C | template | history | 1.9K of 1.9K | 0.12 | 0.24-0.26 | 0 |
| goose-uring-p2 | C | template | poll | 8.8K of 8.8K | 0.10 | 0.22-0.24 | 0 |
| goose-uring-p2 | C | template | shifts | 1.4K of 1.4K | 0.10-0.11 | 0.15-0.23 | 0 |
| goose-uring-p3 | C | template | bookings | 1.4K of 1.4K | 0.25 | 0.33-0.36 | 0 |
| goose-uring-p3 | C | template | client | 480 of 480 | 0.10 | 0.14-0.26 | 0 |
| goose-uring-p3 | C | template | encounter | 1.9K of 1.9K | 0.11 | 0.23-0.25 | 0 |
| goose-uring-p3 | C | template | history | 1.9K of 1.9K | 0.12 | 0.24-0.25 | 0 |
| goose-uring-p3 | C | template | poll | 8.8K of 8.8K | 0.10 | 0.22-0.23 | 0 |
| goose-uring-p3 | C | template | shifts | 1.4K of 1.4K | 0.10-0.11 | 0.15-0.26 | 0 |
| goose-uring-p4 | C | template | bookings | 1.4K of 1.4K | 0.25-0.26 | 0.33-0.40 | 0 |
| goose-uring-p4 | C | template | client | 480 of 480 | 0.10 | 0.14-0.26 | 0 |
| goose-uring-p4 | C | template | encounter | 1.9K of 1.9K | 0.11 | 0.23-0.25 | 0 |
| goose-uring-p4 | C | template | history | 1.9K of 1.9K | 0.12 | 0.23-0.25 | 0 |
| goose-uring-p4 | C | template | poll | 8.8K of 8.8K | 0.10 | 0.22-0.25 | 0 |
| goose-uring-p4 | C | template | shifts | 1.4K of 1.4K | 0.10 | 0.14-0.22 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| hyper | A | serialize | 22.5-22.8 |  |
| dusty | A | serialize | 23.3-23.6 |  |
| goose-uring-base | A | serialize | 17.9-18.2 |  |
| goose-uring-p2 | A | serialize | 17.5-17.8 |  |
| goose-uring-p3 | A | serialize | 17.6-18.1 |  |
| goose-uring-p4 | A | serialize | 17.4-18.0 |  |
| hyper | A | template | 21.9-22.2 |  |
| dusty | A | template | 22.9-23.3 |  |
| goose-uring-base | A | template | 17.5-18.0 |  |
| goose-uring-p2 | A | template | 17.5-18.0 |  |
| goose-uring-p3 | A | template | 17.7-18.0 |  |
| goose-uring-p4 | A | template | 17.3-17.8 |  |
| hyper | B | serialize | 38.5-39.6 |  |
| dusty | B | serialize | 40.0-40.6 |  |
| goose-uring-base | B | serialize | 28.6-29.1 |  |
| goose-uring-p2 | B | serialize | 28.7-28.9 |  |
| goose-uring-p3 | B | serialize | 28.4-29.6 |  |
| goose-uring-p4 | B | serialize | 28.6-28.7 |  |
| hyper | B | template | 35.0-35.7 |  |
| dusty | B | template | 34.4-35.0 |  |
| goose-uring-base | B | template | 26.4-26.8 |  |
| goose-uring-p2 | B | template | 26.8-27.2 |  |
| goose-uring-p3 | B | template | 26.5-27.2 |  |
| goose-uring-p4 | B | template | 26.7-27.0 |  |
| hyper | C | serialize | 138.5-145.1 |  |
| dusty | C | serialize | 174.8-175.5 |  |
| goose-uring-base | C | serialize | 86.2-87.2 |  |
| goose-uring-p2 | C | serialize | 86.3-88.0 |  |
| goose-uring-p3 | C | serialize | 88.7-89.4 |  |
| goose-uring-p4 | C | serialize | 85.8-86.6 |  |
| hyper | C | template | 53.3-54.4 |  |
| dusty | C | template | 52.9-53.7 |  |
| goose-uring-base | C | template | 42.8-43.4 |  |
| goose-uring-p2 | C | template | 42.8-43.1 |  |
| goose-uring-p3 | C | template | 42.7-43.5 |  |
| goose-uring-p4 | C | template | 43.4-43.9 |  |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| hyper | C | alone | bookings | 1.4K of 1.4K | 1.16-1.18 | 1.43-1.48 | 0 |
| hyper | C | alone | client | 480 of 480 | 0.12-0.14 | 0.30-0.42 | 0 |
| hyper | C | alone | encounter | 1.9K of 1.9K | 0.15-0.16 | 0.51-0.60 | 0 |
| hyper | C | alone | history | 1.9K of 1.9K | 0.20 | 0.60-0.64 | 0 |
| hyper | C | alone | poll | 8.8K of 8.8K | 0.11-0.12 | 0.52-0.58 | 0 |
| hyper | C | alone | shifts | 1.4K of 1.4K | 0.14-0.15 | 0.28-0.60 | 0 |
| dusty | C | alone | bookings | 1.4K of 1.4K | 1.45-1.46 | 2.62-2.73 | 0 |
| dusty | C | alone | client | 480 of 480 | 0.21-0.35 | 2.37-2.57 | 0 |
| dusty | C | alone | encounter | 1.9K of 1.9K | 0.17-0.21 | 1.70-1.77 | 0 |
| dusty | C | alone | history | 1.9K of 1.9K | 0.26-0.27 | 1.76-1.79 | 0 |
| dusty | C | alone | poll | 8.8K of 8.8K | 0.11-0.12 | 2.03-2.26 | 0 |
| dusty | C | alone | shifts | 1.4K of 1.4K | 0.15 | 1.63-2.08 | 0 |
| goose-uring-base | C | alone | bookings | 1.4K of 1.4K | 0.67 | 0.87-3.07 | 0 |
| goose-uring-base | C | alone | client | 480 of 480 | 0.10-0.11 | 0.52-0.82 | 0 |
| goose-uring-base | C | alone | encounter | 1.9K of 1.9K | 0.13 | 0.94-1.45 | 0 |
| goose-uring-base | C | alone | history | 1.9K of 1.9K | 0.17 | 0.72-1.01 | 0 |
| goose-uring-base | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.96-2.42 | 0 |
| goose-uring-base | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.80-1.24 | 0 |
| goose-uring-p2 | C | alone | bookings | 1.4K of 1.4K | 0.67 | 0.84-0.86 | 0 |
| goose-uring-p2 | C | alone | client | 480 of 480 | 0.11 | 0.64-0.75 | 0 |
| goose-uring-p2 | C | alone | encounter | 1.9K of 1.9K | 0.13 | 0.73-0.77 | 0 |
| goose-uring-p2 | C | alone | history | 1.9K of 1.9K | 0.17 | 0.70-0.71 | 0 |
| goose-uring-p2 | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.73-0.75 | 0 |
| goose-uring-p2 | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.29-0.78 | 0 |
| goose-uring-p3 | C | alone | bookings | 1.4K of 1.4K | 0.68-0.69 | 0.87-0.96 | 0 |
| goose-uring-p3 | C | alone | client | 480 of 480 | 0.10-0.11 | 0.81-1.09 | 0 |
| goose-uring-p3 | C | alone | encounter | 1.9K of 1.9K | 0.13 | 0.79-0.85 | 0 |
| goose-uring-p3 | C | alone | history | 1.9K of 1.9K | 0.18 | 0.74 | 0 |
| goose-uring-p3 | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.81-0.93 | 0 |
| goose-uring-p3 | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.45-0.65 | 0 |
| goose-uring-p4 | C | alone | bookings | 1.4K of 1.4K | 0.66-0.67 | 0.84-0.90 | 0 |
| goose-uring-p4 | C | alone | client | 480 of 480 | 0.11 | 0.46-0.72 | 0 |
| goose-uring-p4 | C | alone | encounter | 1.9K of 1.9K | 0.13 | 0.69-0.83 | 0 |
| goose-uring-p4 | C | alone | history | 1.9K of 1.9K | 0.17 | 0.69-0.71 | 0 |
| goose-uring-p4 | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.73-0.82 | 0 |
| goose-uring-p4 | C | alone | shifts | 1.4K of 1.4K | 0.11-0.12 | 0.48-0.58 | 0 |
| hyper | C | uploads | bookings | 1.4K of 1.4K | 6.61-6.84 | 17.9-21.5 | 0 |
| hyper | C | uploads | client | 480 of 480 | 5.71-6.21 | 16.8-20.0 | 0 |
| hyper | C | uploads | encounter | 1.9K of 1.9K | 5.98-6.18 | 17.2-20.3 | 0 |
| hyper | C | uploads | history | 1.9K of 1.9K | 6.02-6.22 | 17.3-20.6 | 0 |
| hyper | C | uploads | poll | 8.8K of 8.8K | 6.11-6.22 | 17.4-20.3 | 0 |
| hyper | C | uploads | shifts | 1.4K of 1.4K | 5.65-5.94 | 16.9-19.9 | 0 |
| dusty | C | uploads | bookings | 1.4K of 1.4K | 2.06-3.23 | 21.7-1613 | 0 |
| dusty | C | uploads | client | 471-480 of 480 | 0.97-1.44 | 17.1-1024 | 0 |
| dusty | C | uploads | encounter | 1.8K-1.9K of 1.9K | 1.40-1.74 | 20.0-1863 | 0 |
| dusty | C | uploads | history | 1.9K of 1.9K | 1.09-1.85 | 25.2-1843 | 0 |
| dusty | C | uploads | poll | 8.5K-8.8K of 8.8K | 1.46-1.66 | 20.8-1622 | 0 |
| dusty | C | uploads | shifts | 1.4K of 1.4K | 0.88-105 | 20.3-1622 | 0 |
| goose-uring-base | C | uploads | bookings | 1.4K of 1.4K | 2.75-2.86 | 8.17-10.3 | 0 |
| goose-uring-base | C | uploads | client | 480 of 480 | 2.65-3.21 | 8.49-10.1 | 0 |
| goose-uring-base | C | uploads | encounter | 1.9K of 1.9K | 2.83-3.19 | 9.82-10.2 | 0 |
| goose-uring-base | C | uploads | history | 1.9K of 1.9K | 2.11-2.41 | 7.79-8.95 | 0 |
| goose-uring-base | C | uploads | poll | 8.8K of 8.8K | 2.96-3.12 | 9.91-11.8 | 0 |
| goose-uring-base | C | uploads | shifts | 1.4K of 1.4K | 2.85-3.22 | 9.79-11.1 | 0 |
| goose-uring-p2 | C | uploads | bookings | 1.4K of 1.4K | 2.77-3.06 | 9.89-10.6 | 0 |
| goose-uring-p2 | C | uploads | client | 480 of 480 | 2.86-3.26 | 11.7-12.4 | 0 |
| goose-uring-p2 | C | uploads | encounter | 1.9K of 1.9K | 3.05-3.36 | 11.1-12.6 | 0 |
| goose-uring-p2 | C | uploads | history | 1.9K of 1.9K | 2.17-2.62 | 9.06-9.89 | 0 |
| goose-uring-p2 | C | uploads | poll | 8.8K of 8.8K | 3.10-3.45 | 11.7-12.8 | 0 |
| goose-uring-p2 | C | uploads | shifts | 1.4K of 1.4K | 3.11-3.45 | 11.7-13.0 | 0 |
| goose-uring-p3 | C | uploads | bookings | 1.4K of 1.4K | 2.75-3.07 | 9.18-51.7 | 0 |
| goose-uring-p3 | C | uploads | client | 480 of 480 | 3.00-3.06 | 11.3-39.2 | 0 |
| goose-uring-p3 | C | uploads | encounter | 1.9K of 1.9K | 2.96-3.43 | 10.5-71.4 | 0 |
| goose-uring-p3 | C | uploads | history | 1.9K of 1.9K | 2.36-2.48 | 9.06-32.5 | 0 |
| goose-uring-p3 | C | uploads | poll | 8.8K of 8.8K | 3.02-3.31 | 11.2-75.6 | 0 |
| goose-uring-p3 | C | uploads | shifts | 1.4K of 1.4K | 3.02-3.27 | 10.4-75.9 | 0 |
| goose-uring-p4 | C | uploads | bookings | 1.4K of 1.4K | 2.73-3.14 | 9.64-13.6 | 0 |
| goose-uring-p4 | C | uploads | client | 480 of 480 | 3.03-3.46 | 11.5-14.5 | 0 |
| goose-uring-p4 | C | uploads | encounter | 1.9K of 1.9K | 2.95-3.31 | 11.6-13.6 | 0 |
| goose-uring-p4 | C | uploads | history | 1.9K of 1.9K | 2.33-2.50 | 9.17-11.6 | 0 |
| goose-uring-p4 | C | uploads | poll | 8.8K of 8.8K | 3.08-3.34 | 11.5-14.4 | 0 |
| goose-uring-p4 | C | uploads | shifts | 1.4K of 1.4K | 3.10-3.42 | 11.8-13.4 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| hyper | C | alone | 143.0-143.4 |  |
| dusty | C | alone | 175.0-175.4 |  |
| goose-uring-base | C | alone | 86.8-88.2 |  |
| goose-uring-p2 | C | alone | 86.6-87.3 |  |
| goose-uring-p3 | C | alone | 89.6-89.7 |  |
| goose-uring-p4 | C | alone | 85.9-86.7 |  |
| hyper | C | uploads | 253.0-253.2 | 557-583 |
| dusty | C | uploads | 253.2-262.6 | 327-363 |
| goose-uring-base | C | uploads | 250.5-251.2 | 781-786 |
| goose-uring-p2 | C | uploads | 250.5-252.3 | 733-750 |
| goose-uring-p3 | C | uploads | 251.0-252.2 | 670-737 |
| goose-uring-p4 | C | uploads | 251.0-252.1 | 722-748 |

