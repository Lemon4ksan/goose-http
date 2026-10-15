Requests per second, median (range of runs), and the server's CPU time per request.

### Tier F

| Server | root | id | json | Peak RSS |
|---|---:|---:|---:|---:|
| goose-uring-bare | 515.4K (513.6K-520.8K), 7.7 µs | 512.0K (503.1K-512.0K), 7.8 µs | 438.9K (428.4K-440.5K), 9.1 µs | 10 MB |
| goose-epoll-bare | 407.0K (403.5K-410.3K), 9.8 µs | 398.4K (397.2K-398.7K), 10.1 µs | 346.5K (343.6K-349.5K), 11.6 µs | 3 MB |
| goose-uring-rest | 517.2K (510.2K-519.1K), 7.7 µs | 505.9K (502.5K-509.3K), 7.9 µs | 434.9K (427.1K-436.7K), 9.2 µs | 10 MB |
| goose-epoll-rest | 401.7K (400.5K-403.2K), 10.0 µs | 378.2K (374.2K-392.7K), 10.6 µs | 340.4K (339.7K-341.4K), 11.8 µs | 3 MB |
| axum | 277.8K (272.1K-281.6K), 14.4 µs | 249.8K (247.0K-250.7K), 16.1 µs | 190.2K (184.9K-190.5K), 21.1 µs | 22 MB |
| actix-web | 315.9K (304.9K-317.0K), 12.7 µs | 269.0K (263.6K-269.0K), 14.9 µs | 217.2K (204.1K-219.9K), 18.5 µs | 14 MB |
| dusty-routes | 376.8K (372.4K-385.5K), 10.6 µs | 361.2K (359.5K-374.7K), 11.1 µs | 249.3K (246.0K-249.7K), 16.1 µs | 10 MB |

### Tier R

| Server | routes | Peak RSS |
|---|---:|---:|
| goose-uring-rest | 322.8K (321.6K-324.9K), 12.4 µs | 10 MB |
| goose-epoll-rest | 257.8K (255.8K-259.7K), 15.5 µs | 4 MB |
| goose-uring-rest-gen | 461.6K (455.7K-466.7K), 8.6 µs | 10 MB |
| goose-epoll-rest-gen | 358.2K (357.1K-364.1K), 11.2 µs | 4 MB |
| axum | 245.1K (244.0K-248.4K), 16.4 µs | 26 MB |
| actix-web | 142.7K (142.5K-144.0K), 28.1 µs | 30 MB |
| dusty-routes | 354.9K (351.7K-358.3K), 11.3 µs | 9 MB |

### Tier M, against tier A

| Server | a | m | Peak RSS |
|---|---:|---:|---:|
| goose-uring-rest | 578.3K (574.9K-585.6K), 6.9 µs | 494.3K (490.3K-496.7K), 8.1 µs | 33 MB |
| goose-epoll-rest | 431.4K (393.1K-432.6K), 9.3 µs | 354.0K (326.1K-354.7K), 11.3 µs | 27 MB |
| axum | 237.5K (230.2K-239.8K), 16.9 µs | 179.9K (178.6K-181.0K), 22.3 µs | 28 MB |
| actix-web | 259.6K (259.1K-261.0K), 15.4 µs | 217.7K (217.0K-221.3K), 18.4 µs | 20 MB |
| dusty-routes | 344.4K (342.0K-350.5K), 11.6 µs | 321.3K (314.7K-323.9K), 12.5 µs | 15 MB |
