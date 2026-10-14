## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-epoll-cm | A | serialize | 427.5K | 425.2K-432.8K | 0.59 | 0.88 | 9.4 | 7 | 0 |
| goose-epoll-cs | A | serialize | 427.4K | 402.8K-427.6K | 0.59 | 0.89 | 9.4 | 7 | 0 |
| goose-epoll-cm | A | template | 444.6K | 422.7K-452.5K | 0.56 | 0.87 | 9.0 | 8 | 0 |
| goose-epoll-cs | A | template | 439.5K | 409.1K-445.4K | 0.57 | 0.86 | 9.1 | 8 | 0 |
| goose-epoll-cm | B | serialize | 214.1K | 199.3K-215.0K | 1.19 | 1.80 | 18.7 | 29 | 0 |
| goose-epoll-cs | B | serialize | 237.8K | 231.8K-237.9K | 1.10 | 1.52 | 16.9 | 29 | 0 |
| goose-epoll-cm | B | template | 284.4K | 264.7K-285.8K | 0.91 | 1.35 | 14.1 | 50 | 0 |
| goose-epoll-cs | B | template | 285.3K | 283.0K-290.6K | 0.89 | 1.25 | 14.1 | 50 | 0 |
| goose-epoll-cm | C | serialize | 48.3K | 44.6K-48.6K | 5.11 | 10.5 | 83.0 | 69 | 0 |
| goose-epoll-cs | C | serialize | 58.9K | 58.7K-59.3K | 4.19 | 8.57 | 68.1 | 69 | 0 |
| goose-epoll-cm | C | template | 133.9K | 127.3K-135.3K | 1.85 | 3.10 | 29.9 | 58 | 0 |
| goose-epoll-cs | C | template | 135.0K | 134.9K-135.6K | 1.84 | 2.97 | 29.6 | 58 | 0 |

