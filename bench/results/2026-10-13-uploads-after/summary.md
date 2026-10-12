## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring | alone | 1.1K | 16.4-16.9 |  |  | 130 | 0 |
| goose-epoll | alone | 1.1K-1.2K | 14.8-15.2 |  |  | 124 | 0 |
| hyper | alone | 1.1K | 15.0-15.4 |  |  | 75 | 0 |
| goose-uring | beside forms | 157-163 | 124-135 | 7.1K-7.2K | 73.2-79.9 | 205 | 0 |
| goose-epoll | beside forms | 114-119 | 159-178 | 7.5K | 85.5-86.7 | 213 | 0 |
| hyper | beside forms | 46-57 | 125-150 | 4.8K-5.0K | 131-149 | 200 | 0 |

