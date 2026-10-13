## Fixed rate

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | A | serialize | item | 108.9K-109.0K of 109.2K | 0.10 | 0.18-0.21 | 0 |
| goose-uring | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.17-0.19 | 0 |
| goose-uring | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.17-0.19 | 0 |
| goose-epoll | A | serialize | item | 108.9K-109.0K of 109.2K | 0.10 | 0.18-0.22 | 0 |
| goose-epoll | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.17-0.20 | 0 |
| goose-epoll | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.17-0.21 | 0 |
| hyper | A | serialize | item | 108.8K-109.0K of 109.2K | 0.11 | 0.29-0.57 | 0 |
| hyper | A | serialize | me | 22.4K of 22.4K | 0.10 | 0.26-0.46 | 0 |
| hyper | A | serialize | write | 8.4K of 8.4K | 0.12 | 0.27-0.47 | 0 |
| tokio | A | serialize | item | 108.9K of 109.2K | 0.10 | 0.24-16.3 | 0 |
| tokio | A | serialize | me | 22.4K of 22.4K | 0.09-0.10 | 0.23-34.8 | 0 |
| tokio | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.24-28.8 | 0 |
| may-minihttp | A | serialize | item | 108.8K-108.9K of 109.2K | 0.10 | 0.18-0.21 | 0 |
| may-minihttp | A | serialize | me | 22.4K of 22.4K | 0.09 | 0.16-0.19 | 0 |
| may-minihttp | A | serialize | write | 8.4K of 8.4K | 0.11 | 0.17-0.19 | 0 |
| xitca-web | A | serialize | item | 108.8K-109.0K of 109.2K | 0.13 | 0.32-2.11 | 0 |
| xitca-web | A | serialize | me | 22.4K of 22.4K | 0.12 | 0.30-0.92 | 0 |
| xitca-web | A | serialize | write | 8.4K of 8.4K | 0.13-0.14 | 0.29-1.15 | 0 |
| odin-http | A | serialize | item | 108.9K of 109.2K | 0.23-0.24 | 1.69-82.6 | 0 |
| odin-http | A | serialize | me | 22.4K of 22.4K | 0.23-0.24 | 1.60-80.7 | 1 |
| odin-http | A | serialize | write | 8.4K of 8.4K | 0.23-0.25 | 1.23-52.0 | 0 |
| tina | A | serialize | item | 108.9K-109.0K of 109.2K | 0.12-0.13 | 0.34-0.85 | 0 |
| tina | A | serialize | me | 22.4K of 22.4K | 0.10-0.11 | 0.27-0.78 | 0 |
| tina | A | serialize | write | 8.4K of 8.4K | 0.12 | 0.29-0.53 | 0 |
| goose-uring | A | template | item | 108.9K-109.0K of 109.2K | 0.10 | 0.18-4.71 | 0 |
| goose-uring | A | template | me | 22.4K of 22.4K | 0.09 | 0.17-3.80 | 0 |
| goose-uring | A | template | write | 8.4K of 8.4K | 0.11 | 0.17-1.88 | 0 |
| goose-epoll | A | template | item | 108.8K-108.9K of 109.2K | 0.10 | 0.18-10.3 | 0 |
| goose-epoll | A | template | me | 22.4K of 22.4K | 0.09 | 0.17-9.15 | 0 |
| goose-epoll | A | template | write | 8.4K of 8.4K | 0.11 | 0.17-12.0 | 0 |
| hyper | A | template | item | 108.9K-109.0K of 109.2K | 0.11 | 0.30-0.55 | 0 |
| hyper | A | template | me | 22.4K of 22.4K | 0.10 | 0.27-0.47 | 0 |
| hyper | A | template | write | 8.4K of 8.4K | 0.12 | 0.28-0.49 | 0 |
| tokio | A | template | item | 108.7K-108.9K of 109.2K | 0.10 | 0.19-0.24 | 0 |
| tokio | A | template | me | 22.3K-22.4K of 22.4K | 0.09 | 0.18-0.21 | 0 |
| tokio | A | template | write | 8.4K of 8.4K | 0.11 | 0.18-0.23 | 0 |
| may-minihttp | A | template | item | 108.8K-108.9K of 109.2K | 0.10 | 0.19-0.82 | 0 |
| may-minihttp | A | template | me | 22.4K of 22.4K | 0.09 | 0.18-0.65 | 0 |
| may-minihttp | A | template | write | 8.4K of 8.4K | 0.11 | 0.18-0.63 | 0 |
| xitca-web | A | template | item | 108.9K-109.0K of 109.2K | 0.12-0.13 | 0.29-0.31 | 0 |
| xitca-web | A | template | me | 22.4K of 22.4K | 0.11-0.12 | 0.26-0.28 | 0 |
| xitca-web | A | template | write | 8.4K of 8.4K | 0.13-0.14 | 0.28-0.30 | 0 |
| odin-http | A | template | item | 108.8K-108.9K of 109.2K | 0.14-0.15 | 0.62-2.71 | 1 |
| odin-http | A | template | me | 22.4K of 22.4K | 0.13-0.14 | 0.66-2.43 | 0 |
| odin-http | A | template | write | 8.4K of 8.4K | 0.15 | 0.50-1.70 | 0 |
| tina | A | template | item | 108.9K-109.0K of 109.2K | 0.09-0.10 | 0.22-0.30 | 0 |
| tina | A | template | me | 22.4K of 22.4K | 0.08 | 0.18-0.24 | 0 |
| tina | A | template | write | 8.4K of 8.4K | 0.10 | 0.18-0.24 | 0 |
| goose-uring | B | serialize | entries | 18.5K of 18.5K | 0.12 | 0.21-2.78 | 0 |
| goose-uring | B | serialize | patch | 7.4K of 7.4K | 0.11 | 0.19-0.80 | 0 |
| goose-uring | B | serialize | projects | 11.1K of 11.1K | 0.11 | 0.20-0.70 | 0 |
| goose-uring | B | serialize | session | 18.5K of 18.5K | 0.10-0.11 | 0.20-1.27 | 0 |
| goose-uring | B | serialize | timer | 18.5K of 18.5K | 0.10 | 0.20-1.80 | 0 |
| goose-epoll | B | serialize | entries | 18.5K of 18.5K | 0.12 | 0.19-0.21 | 0 |
| goose-epoll | B | serialize | patch | 7.4K of 7.4K | 0.11 | 0.18-0.19 | 0 |
| goose-epoll | B | serialize | projects | 11.1K of 11.1K | 0.11 | 0.18-0.20 | 0 |
| goose-epoll | B | serialize | session | 18.5K of 18.5K | 0.10-0.11 | 0.19-0.20 | 0 |
| goose-epoll | B | serialize | timer | 18.5K of 18.5K | 0.10 | 0.19 | 0 |
| hyper | B | serialize | entries | 18.5K of 18.5K | 0.14 | 0.27-0.30 | 0 |
| hyper | B | serialize | patch | 7.4K of 7.4K | 0.13 | 0.24-0.27 | 0 |
| hyper | B | serialize | projects | 11.1K of 11.1K | 0.12 | 0.24-0.27 | 0 |
| hyper | B | serialize | session | 18.5K of 18.5K | 0.12 | 0.25-0.28 | 0 |
| hyper | B | serialize | timer | 18.5K of 18.5K | 0.12 | 0.24-0.27 | 0 |
| tokio | B | serialize | entries | 18.5K of 18.5K | 0.13 | 0.24-0.28 | 0 |
| tokio | B | serialize | patch | 7.4K of 7.4K | 0.12 | 0.21-0.26 | 0 |
| tokio | B | serialize | projects | 11.1K of 11.1K | 0.12 | 0.22-0.25 | 0 |
| tokio | B | serialize | session | 18.5K of 18.5K | 0.11-0.12 | 0.21-0.26 | 0 |
| tokio | B | serialize | timer | 18.5K of 18.5K | 0.11 | 0.20-0.28 | 0 |
| may-minihttp | B | serialize | entries | 18.5K of 18.5K | 0.12-0.13 | 0.23-0.33 | 0 |
| may-minihttp | B | serialize | patch | 7.4K of 7.4K | 0.12 | 0.21-0.29 | 0 |
| may-minihttp | B | serialize | projects | 11.1K of 11.1K | 0.11-0.12 | 0.22-0.30 | 0 |
| may-minihttp | B | serialize | session | 18.5K of 18.5K | 0.11 | 0.20-0.30 | 0 |
| may-minihttp | B | serialize | timer | 18.5K of 18.5K | 0.11 | 0.21-0.33 | 0 |
| xitca-web | B | serialize | entries | 18.5K of 18.5K | 0.14-0.15 | 0.29-4.29 | 0 |
| xitca-web | B | serialize | patch | 7.4K of 7.4K | 0.13-0.14 | 0.28-3.79 | 0 |
| xitca-web | B | serialize | projects | 11.1K of 11.1K | 0.13 | 0.27-3.67 | 0 |
| xitca-web | B | serialize | session | 18.5K of 18.5K | 0.13-0.14 | 0.27-4.97 | 0 |
| xitca-web | B | serialize | timer | 18.5K of 18.5K | 0.13 | 0.26-3.59 | 0 |
| odin-http | B | serialize | entries | 12.5K-12.7K of 18.5K | 1821-2338 | 5327-6330 | 0 |
| odin-http | B | serialize | patch | 5.1K-5.4K of 7.4K | 1581-2268 | 5462-5962 | 0 |
| odin-http | B | serialize | projects | 7.5K-7.9K of 11.1K | 1637-2326 | 5405-6285 | 0 |
| odin-http | B | serialize | session | 12.6K-12.8K of 18.5K | 1799-2213 | 5335-6322 | 0 |
| odin-http | B | serialize | timer | 12.2K-12.7K of 18.5K | 1981-2473 | 5728-6531 | 0 |
| tina | B | serialize | entries | 13.0K-13.2K of 18.5K | 1725-2158 | 4950-5724 | 0 |
| tina | B | serialize | patch | 5.1K-5.2K of 7.4K | 2007-2166 | 5220-5929 | 0 |
| tina | B | serialize | projects | 7.9K-8.1K of 11.1K | 1697-2081 | 5007-5700 | 0 |
| tina | B | serialize | session | 13.1K-13.7K of 18.5K | 1534-2089 | 4995-5650 | 0 |
| tina | B | serialize | timer | 12.9K-13.3K of 18.5K | 1870-2089 | 4946-5765 | 0 |
| goose-uring | B | template | entries | 18.5K of 18.5K | 0.11 | 0.17-0.19 | 0 |
| goose-uring | B | template | patch | 7.4K of 7.4K | 0.11 | 0.17-0.18 | 0 |
| goose-uring | B | template | projects | 11.1K of 11.1K | 0.10-0.11 | 0.16-0.18 | 0 |
| goose-uring | B | template | session | 18.5K of 18.5K | 0.10 | 0.17-0.18 | 0 |
| goose-uring | B | template | timer | 18.5K of 18.5K | 0.10 | 0.16-0.18 | 0 |
| goose-epoll | B | template | entries | 18.5K of 18.5K | 0.11 | 0.18-10.2 | 0 |
| goose-epoll | B | template | patch | 7.4K of 7.4K | 0.11 | 0.17-16.9 | 0 |
| goose-epoll | B | template | projects | 11.1K of 11.1K | 0.10 | 0.17-3.67 | 0 |
| goose-epoll | B | template | session | 18.5K of 18.5K | 0.10 | 0.18-14.1 | 0 |
| goose-epoll | B | template | timer | 18.5K of 18.5K | 0.10 | 0.17-9.39 | 0 |
| hyper | B | template | entries | 18.5K of 18.5K | 0.12 | 0.21-0.24 | 0 |
| hyper | B | template | patch | 7.4K of 7.4K | 0.12 | 0.20-0.23 | 0 |
| hyper | B | template | projects | 11.1K of 11.1K | 0.12 | 0.21-0.23 | 0 |
| hyper | B | template | session | 18.5K of 18.5K | 0.11-0.12 | 0.21-0.23 | 0 |
| hyper | B | template | timer | 18.5K of 18.5K | 0.11-0.12 | 0.21-0.23 | 0 |
| tokio | B | template | entries | 18.5K of 18.5K | 0.11 | 0.18-0.20 | 0 |
| tokio | B | template | patch | 7.4K of 7.4K | 0.11 | 0.17-0.19 | 0 |
| tokio | B | template | projects | 11.1K of 11.1K | 0.10-0.11 | 0.17-0.19 | 0 |
| tokio | B | template | session | 18.5K of 18.5K | 0.10 | 0.17-0.19 | 0 |
| tokio | B | template | timer | 18.5K of 18.5K | 0.10 | 0.17-0.19 | 0 |
| may-minihttp | B | template | entries | 18.5K of 18.5K | 0.11 | 0.18-4.58 | 0 |
| may-minihttp | B | template | patch | 7.4K of 7.4K | 0.11 | 0.17-7.09 | 0 |
| may-minihttp | B | template | projects | 11.1K of 11.1K | 0.10-0.11 | 0.17-3.38 | 0 |
| may-minihttp | B | template | session | 18.5K of 18.5K | 0.10-0.11 | 0.18-7.89 | 0 |
| may-minihttp | B | template | timer | 18.5K of 18.5K | 0.10 | 0.18-5.51 | 0 |
| xitca-web | B | template | entries | 18.5K of 18.5K | 0.13 | 0.24-3.80 | 0 |
| xitca-web | B | template | patch | 7.4K of 7.4K | 0.12-0.13 | 0.22-3.64 | 0 |
| xitca-web | B | template | projects | 11.1K of 11.1K | 0.12 | 0.23-2.94 | 0 |
| xitca-web | B | template | session | 18.5K of 18.5K | 0.12 | 0.23-3.67 | 0 |
| xitca-web | B | template | timer | 18.5K of 18.5K | 0.12 | 0.24-4.50 | 0 |
| odin-http | B | template | entries | 18.5K of 18.5K | 0.13 | 0.36-15.5 | 0 |
| odin-http | B | template | patch | 7.4K of 7.4K | 0.13 | 0.33-11.6 | 0 |
| odin-http | B | template | projects | 11.1K of 11.1K | 0.12 | 0.33-8.17 | 0 |
| odin-http | B | template | session | 18.5K of 18.5K | 0.12 | 0.36-15.9 | 0 |
| odin-http | B | template | timer | 18.5K of 18.5K | 0.12 | 0.37-12.0 | 0 |
| tina | B | template | entries | 18.5K of 18.5K | 0.09-0.10 | 0.19-0.20 | 0 |
| tina | B | template | patch | 7.4K of 7.4K | 0.09-0.10 | 0.17 | 0 |
| tina | B | template | projects | 11.1K of 11.1K | 0.09 | 0.16-0.18 | 0 |
| tina | B | template | session | 18.5K of 18.5K | 0.08-0.09 | 0.18-0.19 | 0 |
| tina | B | template | timer | 18.5K of 18.5K | 0.08 | 0.18-0.20 | 0 |
| goose-uring | C | serialize | bookings | 1.4K of 1.4K | 0.67 | 0.85-1.00 | 0 |
| goose-uring | C | serialize | client | 480 of 480 | 0.11 | 0.71-0.82 | 0 |
| goose-uring | C | serialize | encounter | 1.9K of 1.9K | 0.13 | 0.72-0.87 | 0 |
| goose-uring | C | serialize | history | 1.9K of 1.9K | 0.17 | 0.71-0.75 | 0 |
| goose-uring | C | serialize | poll | 8.8K of 8.8K | 0.10 | 0.74-0.93 | 0 |
| goose-uring | C | serialize | shifts | 1.4K of 1.4K | 0.12 | 0.40-0.71 | 0 |
| goose-epoll | C | serialize | bookings | 1.4K of 1.4K | 0.67 | 0.85-0.89 | 0 |
| goose-epoll | C | serialize | client | 480 of 480 | 0.11 | 0.61-0.68 | 0 |
| goose-epoll | C | serialize | encounter | 1.9K of 1.9K | 0.13 | 0.67-0.68 | 0 |
| goose-epoll | C | serialize | history | 1.9K of 1.9K | 0.17 | 0.72-0.73 | 0 |
| goose-epoll | C | serialize | poll | 8.8K of 8.8K | 0.10 | 0.66-0.68 | 0 |
| goose-epoll | C | serialize | shifts | 1.4K of 1.4K | 0.12 | 0.65-0.75 | 0 |
| hyper | C | serialize | bookings | 1.4K of 1.4K | 1.16-1.17 | 1.45-1.49 | 0 |
| hyper | C | serialize | client | 480 of 480 | 0.12-0.18 | 0.35-0.57 | 0 |
| hyper | C | serialize | encounter | 1.9K of 1.9K | 0.14-0.15 | 0.55-0.62 | 0 |
| hyper | C | serialize | history | 1.9K of 1.9K | 0.20 | 0.62-0.65 | 0 |
| hyper | C | serialize | poll | 8.8K of 8.8K | 0.12 | 0.56-0.59 | 0 |
| hyper | C | serialize | shifts | 1.4K of 1.4K | 0.14-0.15 | 0.31-0.40 | 0 |
| tokio | C | serialize | bookings | 1.4K of 1.4K | 1.18-1.23 | 1.96-2.74 | 0 |
| tokio | C | serialize | client | 480 of 480 | 0.12-0.16 | 1.31-2.02 | 0 |
| tokio | C | serialize | encounter | 1.9K of 1.9K | 0.15-0.17 | 1.49-2.27 | 0 |
| tokio | C | serialize | history | 1.9K of 1.9K | 0.20-0.21 | 1.38-1.97 | 0 |
| tokio | C | serialize | poll | 8.8K of 8.8K | 0.12-0.13 | 1.53-2.35 | 0 |
| tokio | C | serialize | shifts | 1.4K of 1.4K | 0.15-0.48 | 1.12-2.36 | 0 |
| may-minihttp | C | serialize | bookings | 1.4K of 1.4K | 1.08-1.09 | 1.56-21.9 | 0 |
| may-minihttp | C | serialize | client | 480 of 480 | 0.12-0.14 | 1.22-12.1 | 0 |
| may-minihttp | C | serialize | encounter | 1.9K of 1.9K | 0.15 | 1.16-15.7 | 0 |
| may-minihttp | C | serialize | history | 1.9K of 1.9K | 0.20-0.21 | 1.23-14.6 | 0 |
| may-minihttp | C | serialize | poll | 8.8K of 8.8K | 0.12 | 1.20-14.6 | 0 |
| may-minihttp | C | serialize | shifts | 1.4K of 1.4K | 0.13-0.14 | 0.27-13.4 | 0 |
| xitca-web | C | serialize | bookings | 1.4K of 1.4K | 1.04-1.11 | 1.81-2.80 | 0 |
| xitca-web | C | serialize | client | 480 of 480 | 0.12-0.13 | 1.77-2.62 | 0 |
| xitca-web | C | serialize | encounter | 1.9K of 1.9K | 0.15 | 1.80-2.38 | 0 |
| xitca-web | C | serialize | history | 1.9K of 1.9K | 0.19-0.20 | 1.79-1.88 | 0 |
| xitca-web | C | serialize | poll | 8.8K of 8.8K | 0.12 | 1.83-2.59 | 0 |
| xitca-web | C | serialize | shifts | 1.4K of 1.4K | 0.14-0.29 | 1.55-2.19 | 0 |
| odin-http | C | serialize | bookings | 124-261 of 1.4K | 5200-6212 | 12726-13881 | 0 |
| odin-http | C | serialize | client | 124-227 of 480 | 3716-5507 | 7870-11686 | 0 |
| odin-http | C | serialize | encounter | 494-1.1K of 1.9K | 2074-5360 | 6097-11702 | 0 |
| odin-http | C | serialize | history | 601-1.4K of 1.9K | 859-5138 | 6101-10965 | 0 |
| odin-http | C | serialize | poll | 2.2K-7.1K of 8.8K | 2.24-5728 | 6003-11907 | 0 |
| odin-http | C | serialize | shifts | 256-838 of 1.4K | 2833-6117 | 6126-12636 | 0 |
| tina | C | serialize | bookings | 160-167 of 1.4K | 6621-6679 | 13119-13251 | 0 |
| tina | C | serialize | client | 371-392 of 480 | 1127-1207 | 3677-5523 | 0 |
| tina | C | serialize | encounter | 1.4K of 1.9K | 1693-2024 | 4663-6101 | 0 |
| tina | C | serialize | history | 921-956 of 1.9K | 3626-3919 | 7899-8794 | 0 |
| tina | C | serialize | poll | 6.4K-6.6K of 8.8K | 1613-2073 | 4659-6081 | 0 |
| tina | C | serialize | shifts | 1.1K-1.2K of 1.4K | 1355-1660 | 4295-5171 | 0 |
| goose-uring | C | template | bookings | 1.4K of 1.4K | 0.25 | 0.36-0.40 | 0 |
| goose-uring | C | template | client | 480 of 480 | 0.10-0.11 | 0.15-0.27 | 0 |
| goose-uring | C | template | encounter | 1.9K of 1.9K | 0.11 | 0.20-0.24 | 0 |
| goose-uring | C | template | history | 1.9K of 1.9K | 0.12 | 0.23-0.25 | 0 |
| goose-uring | C | template | poll | 8.8K of 8.8K | 0.10 | 0.23-0.24 | 0 |
| goose-uring | C | template | shifts | 1.4K of 1.4K | 0.10-0.11 | 0.15-0.24 | 0 |
| goose-epoll | C | template | bookings | 1.4K of 1.4K | 0.25-0.26 | 0.34-0.40 | 0 |
| goose-epoll | C | template | client | 480 of 480 | 0.10 | 0.15-0.27 | 0 |
| goose-epoll | C | template | encounter | 1.9K of 1.9K | 0.11 | 0.22-0.24 | 0 |
| goose-epoll | C | template | history | 1.9K of 1.9K | 0.12-0.13 | 0.23-0.26 | 0 |
| goose-epoll | C | template | poll | 8.8K of 8.8K | 0.10 | 0.23 | 0 |
| goose-epoll | C | template | shifts | 1.4K of 1.4K | 0.10 | 0.15-0.25 | 0 |
| hyper | C | template | bookings | 1.4K of 1.4K | 0.25-0.27 | 0.38-0.42 | 0 |
| hyper | C | template | client | 480 of 480 | 0.11-0.12 | 0.18-0.27 | 0 |
| hyper | C | template | encounter | 1.9K of 1.9K | 0.12 | 0.26-0.29 | 0 |
| hyper | C | template | history | 1.9K of 1.9K | 0.13-0.14 | 0.29-0.31 | 0 |
| hyper | C | template | poll | 8.8K of 8.8K | 0.11 | 0.27-0.29 | 0 |
| hyper | C | template | shifts | 1.4K of 1.4K | 0.12-0.16 | 0.20-0.30 | 0 |
| tokio | C | template | bookings | 1.4K of 1.4K | 0.27 | 0.39-0.43 | 0 |
| tokio | C | template | client | 480 of 480 | 0.10-0.11 | 0.16-0.29 | 0 |
| tokio | C | template | encounter | 1.9K of 1.9K | 0.11 | 0.24-0.26 | 0 |
| tokio | C | template | history | 1.9K of 1.9K | 0.13 | 0.26-0.27 | 0 |
| tokio | C | template | poll | 8.8K of 8.8K | 0.10 | 0.24-0.25 | 0 |
| tokio | C | template | shifts | 1.4K of 1.4K | 0.11 | 0.15-0.18 | 0 |
| may-minihttp | C | template | bookings | 1.4K of 1.4K | 0.29 | 0.48-0.49 | 0 |
| may-minihttp | C | template | client | 480 of 480 | 0.10 | 0.21-0.31 | 0 |
| may-minihttp | C | template | encounter | 1.9K of 1.9K | 0.11-0.12 | 0.27-0.30 | 0 |
| may-minihttp | C | template | history | 1.9K of 1.9K | 0.13 | 0.30 | 0 |
| may-minihttp | C | template | poll | 8.8K of 8.8K | 0.10 | 0.27-0.28 | 0 |
| may-minihttp | C | template | shifts | 1.4K of 1.4K | 0.11-0.14 | 0.26-0.37 | 0 |
| xitca-web | C | template | bookings | 1.4K of 1.4K | 0.29 | 0.46 | 0 |
| xitca-web | C | template | client | 480 of 480 | 0.12 | 0.28-0.31 | 0 |
| xitca-web | C | template | encounter | 1.9K of 1.9K | 0.12 | 0.27-0.28 | 0 |
| xitca-web | C | template | history | 1.9K of 1.9K | 0.14 | 0.29-0.31 | 0 |
| xitca-web | C | template | poll | 8.8K of 8.8K | 0.11 | 0.27-0.28 | 0 |
| xitca-web | C | template | shifts | 1.4K of 1.4K | 0.12 | 0.18-0.26 | 0 |
| odin-http | C | template | bookings | 1.4K of 1.4K | 0.89-0.91 | 1.55-21.0 | 0 |
| odin-http | C | template | client | 480 of 480 | 0.13-0.14 | 2.27-14.9 | 0 |
| odin-http | C | template | encounter | 1.9K of 1.9K | 0.13 | 1.77-7.02 | 0 |
| odin-http | C | template | history | 1.9K of 1.9K | 0.15 | 1.89-15.1 | 0 |
| odin-http | C | template | poll | 8.8K of 8.8K | 0.12-0.13 | 2.01-16.3 | 0 |
| odin-http | C | template | shifts | 1.4K of 1.4K | 0.12-0.13 | 1.32-11.3 | 0 |
| tina | C | template | bookings | 1.4K of 1.4K | 0.30-0.34 | 0.57-1.19 | 0 |
| tina | C | template | client | 480 of 480 | 0.08-0.09 | 0.14-0.27 | 0 |
| tina | C | template | encounter | 1.9K of 1.9K | 0.09 | 0.17-0.34 | 0 |
| tina | C | template | history | 1.9K of 1.9K | 0.11-0.12 | 0.22-0.38 | 0 |
| tina | C | template | poll | 8.8K of 8.8K | 0.07-0.08 | 0.17-0.34 | 0 |
| tina | C | template | shifts | 1.4K of 1.4K | 0.09 | 0.15-0.26 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | A | serialize | 17.9-18.2 |  |
| goose-epoll | A | serialize | 17.8-18.0 |  |
| hyper | A | serialize | 22.9-23.0 |  |
| tokio | A | serialize | 18.9-19.4 |  |
| may-minihttp | A | serialize | 18.7-19.1 |  |
| xitca-web | A | serialize | 22.9-23.1 |  |
| odin-http | A | serialize | 27.2-27.7 |  |
| tina | A | serialize | 28.7-28.8 |  |
| goose-uring | A | template | 17.7-18.2 |  |
| goose-epoll | A | template | 17.5-18.0 |  |
| hyper | A | template | 22.3-22.4 |  |
| tokio | A | template | 18.0-18.8 |  |
| may-minihttp | A | template | 18.5-18.8 |  |
| xitca-web | A | template | 23.0 |  |
| odin-http | A | template | 24.8-25.0 |  |
| tina | A | template | 28.7-28.8 |  |
| goose-uring | B | serialize | 28.7-29.5 |  |
| goose-epoll | B | serialize | 28.3-29.2 |  |
| hyper | B | serialize | 38.8-39.5 |  |
| tokio | B | serialize | 31.7-32.2 |  |
| may-minihttp | B | serialize | 31.1-31.7 |  |
| xitca-web | B | serialize | 36.8-37.2 |  |
| odin-http | B | serialize | 77.5-79.7 |  |
| tina | B | serialize | 75.8-77.0 |  |
| goose-uring | B | template | 26.8-27.2 |  |
| goose-epoll | B | template | 26.2-26.6 |  |
| hyper | B | template | 35.0-35.7 |  |
| tokio | B | template | 27.8-28.6 |  |
| may-minihttp | B | template | 26.9-27.3 |  |
| xitca-web | B | template | 33.3-34.7 |  |
| odin-http | B | template | 35.3-36.1 |  |
| tina | B | template | 54.3 |  |
| goose-uring | C | serialize | 87.0-88.5 |  |
| goose-epoll | C | serialize | 86.7-87.3 |  |
| hyper | C | serialize | 142.9-143.6 |  |
| tokio | C | serialize | 134.4-135.0 |  |
| may-minihttp | C | serialize | 128.3-133.1 |  |
| xitca-web | C | serialize | 124.1-126.2 |  |
| odin-http | C | serialize | 354.9-998.4 |  |
| tina | C | serialize | 381.3-387.1 |  |
| goose-uring | C | template | 43.5-44.3 |  |
| goose-epoll | C | template | 42.0-43.9 |  |
| hyper | C | template | 53.2-55.2 |  |
| tokio | C | template | 47.1-48.3 |  |
| may-minihttp | C | template | 47.9-49.2 |  |
| xitca-web | C | template | 58.9-59.3 |  |
| odin-http | C | template | 112.9-116.3 |  |
| tina | C | template | 251.2-251.4 |  |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | C | alone | bookings | 1.4K of 1.4K | 0.67-0.68 | 0.88-2.98 | 0 |
| goose-uring | C | alone | client | 480 of 480 | 0.10-0.11 | 0.58-1.90 | 0 |
| goose-uring | C | alone | encounter | 1.9K of 1.9K | 0.13-0.14 | 0.77-2.31 | 0 |
| goose-uring | C | alone | history | 1.9K of 1.9K | 0.17 | 0.72-2.21 | 0 |
| goose-uring | C | alone | poll | 8.8K of 8.8K | 0.10 | 0.78-3.10 | 0 |
| goose-uring | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.48-2.37 | 0 |
| goose-epoll | C | alone | bookings | 1.4K of 1.4K | 0.67-0.68 | 0.87-19.8 | 0 |
| goose-epoll | C | alone | client | 480 of 480 | 0.10-0.11 | 0.51-0.67 | 0 |
| goose-epoll | C | alone | encounter | 1.9K of 1.9K | 0.13 | 0.69-5.74 | 0 |
| goose-epoll | C | alone | history | 1.9K of 1.9K | 0.17-0.18 | 0.70-5.46 | 0 |
| goose-epoll | C | alone | poll | 8.8K of 8.8K | 0.10-0.11 | 0.67-5.03 | 0 |
| goose-epoll | C | alone | shifts | 1.4K of 1.4K | 0.12 | 0.66-1.71 | 0 |
| hyper | C | alone | bookings | 1.4K of 1.4K | 1.16-1.19 | 1.45-6.48 | 0 |
| hyper | C | alone | client | 480 of 480 | 0.14-0.15 | 0.52-5.62 | 0 |
| hyper | C | alone | encounter | 1.9K of 1.9K | 0.14-0.16 | 0.61-5.06 | 0 |
| hyper | C | alone | history | 1.9K of 1.9K | 0.20 | 0.66-5.07 | 0 |
| hyper | C | alone | poll | 8.8K of 8.8K | 0.12 | 0.59-7.14 | 0 |
| hyper | C | alone | shifts | 1.4K of 1.4K | 0.15-0.18 | 0.52-5.23 | 0 |
| tokio | C | alone | bookings | 1.4K of 1.4K | 1.19-1.27 | 1.97-9.55 | 0 |
| tokio | C | alone | client | 480 of 480 | 0.12-0.18 | 1.56-6.49 | 0 |
| tokio | C | alone | encounter | 1.9K of 1.9K | 0.15-0.16 | 1.61-5.67 | 0 |
| tokio | C | alone | history | 1.9K of 1.9K | 0.20-0.22 | 1.63-10.5 | 0 |
| tokio | C | alone | poll | 8.8K of 8.8K | 0.12-0.13 | 1.61-9.74 | 0 |
| tokio | C | alone | shifts | 1.4K of 1.4K | 0.18-0.22 | 1.44-6.97 | 0 |
| xitca-web | C | alone | bookings | 1.4K of 1.4K | 1.03-1.29 | 1.60-29.3 | 0 |
| xitca-web | C | alone | client | 480 of 480 | 0.13-0.14 | 1.79-18.3 | 0 |
| xitca-web | C | alone | encounter | 1.9K of 1.9K | 0.14-0.17 | 1.81-12.1 | 0 |
| xitca-web | C | alone | history | 1.9K of 1.9K | 0.19-0.20 | 1.82-15.1 | 0 |
| xitca-web | C | alone | poll | 8.8K of 8.8K | 0.12-0.13 | 1.78-24.4 | 0 |
| xitca-web | C | alone | shifts | 1.4K of 1.4K | 0.15-0.16 | 1.13-23.4 | 0 |
| odin-http | C | alone | bookings | 166-283 of 1.4K | 4034-5896 | 12358-13767 | 0 |
| odin-http | C | alone | client | 51-226 of 480 | 3892-6953 | 7875-13308 | 0 |
| odin-http | C | alone | encounter | 421-1.1K of 1.9K | 2807-5925 | 6142-11809 | 0 |
| odin-http | C | alone | history | 433-1.1K of 1.9K | 2930-6097 | 6191-11727 | 0 |
| odin-http | C | alone | poll | 1.8K-5.3K of 8.8K | 3057-6412 | 6228-12030 | 0 |
| odin-http | C | alone | shifts | 189-850 of 1.4K | 2954-7387 | 6113-12931 | 0 |
| goose-uring | C | uploads | bookings | 1.4K of 1.4K | 2.70-2.99 | 7.88-8.65 | 0 |
| goose-uring | C | uploads | client | 480 of 480 | 2.92-3.31 | 8.81-10.3 | 0 |
| goose-uring | C | uploads | encounter | 1.9K of 1.9K | 3.04-3.19 | 10.4 | 0 |
| goose-uring | C | uploads | history | 1.9K of 1.9K | 2.34-2.48 | 7.82-8.25 | 0 |
| goose-uring | C | uploads | poll | 8.8K of 8.8K | 2.89-3.31 | 9.92-10.6 | 0 |
| goose-uring | C | uploads | shifts | 1.4K of 1.4K | 2.90-3.05 | 9.81-10.5 | 0 |
| goose-epoll | C | uploads | bookings | 1.4K of 1.4K | 0.85-0.90 | 2.27-2.49 | 0 |
| goose-epoll | C | uploads | client | 480 of 480 | 0.27-0.33 | 1.36-2.03 | 0 |
| goose-epoll | C | uploads | encounter | 1.9K of 1.9K | 0.30-0.34 | 1.62-2.06 | 0 |
| goose-epoll | C | uploads | history | 1.9K of 1.9K | 0.35-0.36 | 1.40-1.80 | 0 |
| goose-epoll | C | uploads | poll | 8.8K of 8.8K | 0.32-0.34 | 1.66-2.08 | 0 |
| goose-epoll | C | uploads | shifts | 1.4K of 1.4K | 0.29-0.33 | 1.49-2.06 | 0 |
| hyper | C | uploads | bookings | 1.4K of 1.4K | 6.69-6.84 | 18.6-19.4 | 0 |
| hyper | C | uploads | client | 480 of 480 | 5.95-6.36 | 17.8-18.7 | 0 |
| hyper | C | uploads | encounter | 1.9K of 1.9K | 6.12-6.21 | 18.0-18.9 | 0 |
| hyper | C | uploads | history | 1.9K of 1.9K | 6.14-6.29 | 18.1-18.9 | 0 |
| hyper | C | uploads | poll | 8.8K of 8.8K | 6.17-6.38 | 18.3-19.0 | 0 |
| hyper | C | uploads | shifts | 1.4K of 1.4K | 6.03-6.56 | 18.0-19.0 | 0 |
| tokio | C | uploads | bookings | 988-1.1K of 1.4K | 1089-1780 | 5446-7354 | 0 |
| tokio | C | uploads | client | 281-382 of 480 | 155-2246 | 5032-7219 | 0 |
| tokio | C | uploads | encounter | 1.3K-1.4K of 1.9K | 1628-2047 | 5622-7379 | 0 |
| tokio | C | uploads | history | 1.3K-1.4K of 1.9K | 1482-2233 | 5638-7420 | 0 |
| tokio | C | uploads | poll | 6.1K-6.5K of 8.8K | 1192-2020 | 5458-7277 | 0 |
| tokio | C | uploads | shifts | 1.0K-1.1K of 1.4K | 764-2035 | 5417-7014 | 0 |
| xitca-web | C | uploads | bookings | 1.4K of 1.4K | 1.25-1.33 | 3.96-12.5 | 0 |
| xitca-web | C | uploads | client | 480 of 480 | 0.18-0.56 | 3.17-13.2 | 0 |
| xitca-web | C | uploads | encounter | 1.9K of 1.9K | 0.33-0.47 | 3.33-13.0 | 0 |
| xitca-web | C | uploads | history | 1.9K of 1.9K | 0.38-0.71 | 3.16-4.52 | 0 |
| xitca-web | C | uploads | poll | 8.8K of 8.8K | 0.33-0.41 | 3.51-4.29 | 0 |
| xitca-web | C | uploads | shifts | 1.4K of 1.4K | 0.26-0.32 | 1.73-4.20 | 0 |
| odin-http | C | uploads | bookings | 161-184 of 1.4K | 6011-6433 | 12956-13234 | 0 |
| odin-http | C | uploads | client | 49-56 of 480 | 6130-6670 | 13193-13382 | 0 |
| odin-http | C | uploads | encounter | 241-306 of 1.9K | 5560-6359 | 12448-13013 | 0 |
| odin-http | C | uploads | history | 234-269 of 1.9K | 5519-6687 | 12734-13054 | 0 |
| odin-http | C | uploads | poll | 991-1.1K of 8.8K | 6629-7219 | 12931-13136 | 0 |
| odin-http | C | uploads | shifts | 172-249 of 1.4K | 6191-7305 | 12325-13103 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | C | alone | 87.2-89.9 |  |
| goose-epoll | C | alone | 86.3-88.9 |  |
| hyper | C | alone | 142.9-146.9 |  |
| tokio | C | alone | 135.3-138.2 |  |
| xitca-web | C | alone | 124.3-127.9 |  |
| odin-http | C | alone | 453.0-1209.6 |  |
| goose-uring | C | uploads | 250.9-251.5 | 754-773 |
| goose-epoll | C | uploads | 251.3-252.7 | 769-781 |
| hyper | C | uploads | 252.9-253.2 | 553-567 |
| tokio | C | uploads | 343.2-362.5 | 647-653 |
| xitca-web | C | uploads | 232.5-252.2 | 402-482 |
| odin-http | C | uploads | 1873.2-2150.1 | 260-293 |

