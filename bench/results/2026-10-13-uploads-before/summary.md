## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring | alone | 978-995 | 20.3-20.8 |  |  | 130 | 0 |
| goose-epoll | alone | 1.0K | 20.3-21.2 |  |  | 124 | 0 |
| hyper | alone | 1.1K | 14.9-15.3 |  |  | 74 | 0 |
| goose-uring | beside forms | 148-159 | 123-135 | 7.0K-7.1K | 72.9-79.7 | 207 | 0 |
| goose-epoll | beside forms | 116-118 | 164-181 | 7.3K-7.5K | 85.7-94.0 | 212 | 0 |
| hyper | beside forms | 51-57 | 126-195 | 5.0K | 133-143 | 199 | 0 |

