Requests per second, median (range of runs), and the server's CPU time per request.

### Tier F

| Server | root | id | json | Peak RSS |
|---|---:|---:|---:|---:|
| goose-uring-bare | 517.1K (516.1K-518.8K), 7.7 µs | 509.2K (507.1K-512.2K), 7.8 µs | 439.5K (432.6K-441.5K), 9.1 µs | 10 MB |
| goose-epoll-bare | 404.8K (402.9K-409.1K), 9.9 µs | 396.1K (392.8K-400.0K), 10.1 µs | 345.4K (342.3K-347.0K), 11.6 µs | 3 MB |
| goose-uring-rest | 513.6K (510.6K-514.0K), 7.8 µs | 503.6K (501.5K-512.4K), 7.9 µs | 433.5K (428.5K-439.1K), 9.2 µs | 10 MB |
| goose-epoll-rest | 400.8K (400.7K-406.2K), 10.0 µs | 389.2K (388.4K-399.8K), 10.3 µs | 341.2K (334.1K-342.7K), 11.7 µs | 3 MB |

### Tier R

| Server | routes | Peak RSS |
|---|---:|---:|
| goose-uring-rest | 324.9K (324.1K-325.5K), 12.3 µs | 10 MB |
| goose-epoll-rest | 259.3K (256.0K-261.9K), 15.5 µs | 4 MB |
| goose-uring-rest-gen | 457.9K (453.0K-463.0K), 8.7 µs | 10 MB |
| goose-epoll-rest-gen | 361.5K (361.5K-364.0K), 11.1 µs | 4 MB |

### Tier M, against tier A

| Server | a | m | Peak RSS |
|---|---:|---:|---:|
| goose-uring-rest | 578.1K (568.7K-578.5K), 6.9 µs | 489.4K (486.8K-494.2K), 8.2 µs | 33 MB |
| goose-epoll-rest | 431.7K (431.2K-434.5K), 9.3 µs | 353.7K (332.5K-360.7K), 11.3 µs | 27 MB |
