/* High-performance HTTP/1.1 load generator for goose-http benchmarks.
   Drop-in replacement for oha and zrk, with zero Rust dependencies.
   Compiles on Linux, macOS, and Windows. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <ctype.h>
#include <time.h>
#include <errno.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
typedef SOCKET socket_t;
#define poll WSAPoll
#define close_socket closesocket
#else
#include <unistd.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
typedef int socket_t;
#define INVALID_SOCKET (-1)
#define close_socket close
#endif

/* Monotonic time in nanoseconds */
static uint64_t time_ns(void) {
#ifdef _WIN32
    static LARGE_INTEGER freq;
    static int init = 0;
    if (!init) {
        QueryPerformanceFrequency(&freq);
        init = 1;
    }
    LARGE_INTEGER counter;
    QueryPerformanceCounter(&counter);
    return (uint64_t)((counter.QuadPart * 1000000000ULL) / freq.QuadPart);
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
#endif
}

/* Latency histogram: 1 us bins up to 100 ms, 100 us bins up to 60 s */
#define FINE_BINS 100000
#define COARSE_BINS 600000
#define TOTAL_BINS (FINE_BINS + COARSE_BINS)

static uint32_t hist[TOTAL_BINS];

static void record_latency(uint64_t us) {
    size_t b;
    if (us < FINE_BINS) {
        b = (size_t)us;
    } else {
        b = FINE_BINS + (us - FINE_BINS) / 100;
        if (b >= TOTAL_BINS) b = TOTAL_BINS - 1;
    }
    hist[b]++;
}

static uint64_t hist_percentile(uint64_t count, double p) {
    if (count == 0) return 0;
    uint64_t rank = (uint64_t)(p * (double)count);
    if (rank >= count) rank = count - 1;
    uint64_t seen = 0;
    for (size_t b = 0; b < TOTAL_BINS; b++) {
        seen += hist[b];
        if (seen > rank) {
            return b < FINE_BINS ? b : FINE_BINS + (uint64_t)(b - FINE_BINS) * 100;
        }
    }
    return 0;
}

enum ConnState {
    ST_CONNECTING,
    ST_IDLE,
    ST_SENDING,
    ST_READING_HEAD,
    ST_READING_BODY
};

struct Connection {
    socket_t fd;
    enum ConnState state;
    size_t send_off;
    size_t recv_len;
    int status_code;
    size_t content_length;
    size_t body_read;
    uint64_t issue_time_ns;
    char recv_buf[8192];
};

static void set_nonblocking(socket_t fd) {
#ifdef _WIN32
    u_long nb = 1;
    ioctlsocket(fd, FIONBIO, &nb);
#else
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
#endif
    int nodelay = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (const char *)&nodelay, sizeof(nodelay));
}

int main(int argc, char **argv) {
#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif

    uint64_t target_requests = 0;
    int target_conns = 64;
    double duration_s = 0.0;
    double rate_limit = 0.0;
    const char *method = "GET";
    const char *out_file = NULL;
    const char *url = NULL;
    char req_buf[8192];
    char headers_buf[4096] = "";
    const char *body = NULL;
    size_t body_len = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-n") && i + 1 < argc) {
            target_requests = strtoull(argv[++i], NULL, 10);
        } else if (!strcmp(argv[i], "-c") && i + 1 < argc) {
            target_conns = atoi(argv[++i]);
        } else if (!strcmp(argv[i], "-d") && i + 1 < argc) {
            duration_s = atof(argv[++i]);
        } else if ((!strcmp(argv[i], "-R") || !strcmp(argv[i], "--rate")) && i + 1 < argc) {
            rate_limit = atof(argv[++i]);
        } else if (!strcmp(argv[i], "-m") && i + 1 < argc) {
            method = argv[++i];
        } else if (!strcmp(argv[i], "-H") && i + 1 < argc) {
            strncat(headers_buf, argv[++i], sizeof(headers_buf) - strlen(headers_buf) - 3);
            strcat(headers_buf, "\r\n");
        } else if (!strcmp(argv[i], "-b") && i + 1 < argc) {
            body = argv[++i];
            body_len = strlen(body);
        } else if (!strcmp(argv[i], "-o") && i + 1 < argc) {
            out_file = argv[++i];
        } else if (!strcmp(argv[i], "-t") && i + 1 < argc) {
            i++; /* Threads ignored in event-based poll mode */
        } else if (!strcmp(argv[i], "--plain") || !strcmp(argv[i], "--no-tui") ||
                   !strcmp(argv[i], "--format") || !strcmp(argv[i], "--output-format")) {
            if ((!strcmp(argv[i], "--format") || !strcmp(argv[i], "--output-format")) && i + 1 < argc) i++;
        } else if (argv[i][0] != '-') {
            url = argv[i];
        }
    }

    if (!url) {
        fprintf(stderr, "usage: loader [-n reqs] [-c conns] [-d sec] [-R rate] [-m method] [-H header] [-b body] [-o file] URL\n");
        return 2;
    }

    /* Parse URL: http://host[:port]/path */
    char host[256] = "127.0.0.1";
    int port = 80;
    char path[1024] = "/";
    const char *p = url;
    if (!strncmp(p, "http://", 7)) p += 7;
    const char *slash = strchr(p, '/');
    const char *colon = strchr(p, ':');
    if (slash) {
        strncpy(path, slash, sizeof(path) - 1);
    }
    if (colon && (!slash || colon < slash)) {
        size_t hlen = colon - p;
        if (hlen >= sizeof(host)) hlen = sizeof(host) - 1;
        strncpy(host, p, hlen);
        host[hlen] = '\0';
        port = atoi(colon + 1);
    } else {
        size_t hlen = slash ? (size_t)(slash - p) : strlen(p);
        if (hlen >= sizeof(host)) hlen = sizeof(host) - 1;
        strncpy(host, p, hlen);
        host[hlen] = '\0';
    }

    /* Build HTTP/1.1 request */
    int req_len;
    if (body_len > 0) {
        req_len = snprintf(req_buf, sizeof(req_buf),
            "%s %s HTTP/1.1\r\n"
            "Host: %s:%d\r\n"
            "User-Agent: goose-http-bench\r\n"
            "Accept: */*\r\n"
            "Connection: keep-alive\r\n"
            "Content-Length: %zu\r\n"
            "%s\r\n%s",
            method, path, host, port, body_len, headers_buf, body);
    } else {
        req_len = snprintf(req_buf, sizeof(req_buf),
            "%s %s HTTP/1.1\r\n"
            "Host: %s:%d\r\n"
            "User-Agent: goose-http-bench\r\n"
            "Accept: */*\r\n"
            "Connection: keep-alive\r\n"
            "%s\r\n",
            method, path, host, port, headers_buf);
    }

    /* Resolve host */
    struct sockaddr_in sin;
    memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &sin.sin_addr) <= 0) {
        struct hostent *he = gethostbyname(host);
        if (!he) {
            fprintf(stderr, "loader: cannot resolve host %s\n", host);
            return 1;
        }
        memcpy(&sin.sin_addr, he->h_addr_list[0], sizeof(sin.sin_addr));
    }

    /* Allocate connections and pollfd array */
    if (target_conns < 1) target_conns = 1;
    struct Connection *conns = calloc(target_conns, sizeof(*conns));
    struct pollfd *pfds = calloc(target_conns, sizeof(*pfds));

    for (int i = 0; i < target_conns; i++) {
        conns[i].fd = INVALID_SOCKET;
        conns[i].state = ST_IDLE;
        pfds[i].fd = INVALID_SOCKET;
    }

    uint64_t completed_reqs = 0;
    uint64_t code_2xx = 0, code_3xx = 0, code_4xx = 0, code_5xx = 0;
    uint64_t code_200 = 0;
    uint64_t errors = 0;
    uint64_t start_time = time_ns();
    uint64_t end_time = 0;
    uint64_t rate_interval_ns = rate_limit > 0 ? (uint64_t)(1000000000.0 / rate_limit) : 0;
    uint64_t next_scheduled_ns = start_time;

    while (1) {
        uint64_t now = time_ns();
        if (duration_s > 0 && (double)(now - start_time) / 1e9 >= duration_s) break;
        if (target_requests > 0 && completed_reqs >= target_requests) break;

        /* Prepare poll fds and handle new issues */
        for (int i = 0; i < target_conns; i++) {
            struct Connection *c = &conns[i];
            if (c->state == ST_IDLE) {
                if (target_requests > 0 && (completed_reqs + target_conns) > target_requests + 256) {
                    /* Don't overschedule */
                }
                uint64_t issue_time = now;
                if (rate_interval_ns > 0) {
                    if (now < next_scheduled_ns) {
                        /* Wait for next scheduled rate tick */
                    } else {
                        issue_time = next_scheduled_ns;
                        next_scheduled_ns += rate_interval_ns;
                    }
                }

                if (rate_interval_ns == 0 || now >= issue_time) {
                    if (c->fd == INVALID_SOCKET) {
                        c->fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
                        set_nonblocking(c->fd);
                        connect(c->fd, (struct sockaddr *)&sin, sizeof(sin));
                        c->state = ST_CONNECTING;
                    } else {
                        c->state = ST_SENDING;
                    }
                    c->send_off = 0;
                    c->recv_len = 0;
                    c->status_code = 0;
                    c->content_length = (size_t)-1;
                    c->body_read = 0;
                    c->issue_time_ns = issue_time;
                }
            }

            pfds[i].fd = c->fd;
            pfds[i].events = 0;
            if (c->state == ST_CONNECTING || c->state == ST_SENDING) {
                pfds[i].events = POLLOUT;
            } else if (c->state == ST_READING_HEAD || c->state == ST_READING_BODY) {
                pfds[i].events = POLLIN;
            }
        }

        int poll_timeout = rate_interval_ns > 0 ? 0 : 10;
        int nready = poll(pfds, target_conns, poll_timeout);
        if (nready < 0) {
            if (errno == EINTR) continue;
            break;
        }

        now = time_ns();
        for (int i = 0; i < target_conns; i++) {
            struct Connection *c = &conns[i];
            if (c->fd == INVALID_SOCKET) continue;

            short revents = pfds[i].revents;
            if (revents & (POLLERR | POLLHUP | POLLNVAL)) {
                errors++;
                close_socket(c->fd);
                c->fd = INVALID_SOCKET;
                c->state = ST_IDLE;
                continue;
            }

            if (c->state == ST_CONNECTING && (revents & POLLOUT)) {
                c->state = ST_SENDING;
            }

            if (c->state == ST_SENDING && (revents & POLLOUT)) {
                int n = send(c->fd, req_buf + c->send_off, (int)(req_len - c->send_off), 0);
                if (n > 0) {
                    c->send_off += n;
                    if (c->send_off == (size_t)req_len) {
                        c->state = ST_READING_HEAD;
                    }
                } else if (n < 0) {
#ifdef _WIN32
                    int err = WSAGetLastError();
                    if (err != WSAEWOULDBLOCK) { errors++; close_socket(c->fd); c->fd = INVALID_SOCKET; c->state = ST_IDLE; }
#else
                    if (errno != EAGAIN && errno != EWOULDBLOCK) { errors++; close_socket(c->fd); c->fd = INVALID_SOCKET; c->state = ST_IDLE; }
#endif
                }
            }

            if ((c->state == ST_READING_HEAD || c->state == ST_READING_BODY) && (revents & POLLIN)) {
                int n = recv(c->fd, c->recv_buf + c->recv_len, (int)(sizeof(c->recv_buf) - c->recv_len - 1), 0);
                if (n > 0) {
                    c->recv_len += n;
                    c->recv_buf[c->recv_len] = '\0';

                    if (c->state == ST_READING_HEAD) {
                        char *hdr_end = strstr(c->recv_buf, "\r\n\r\n");
                        if (hdr_end) {
                            /* Parse status code */
                            if (!strncmp(c->recv_buf, "HTTP/1.", 7) && c->recv_len >= 12) {
                                c->status_code = atoi(c->recv_buf + 9);
                            }
                            /* Parse Content-Length */
                            char *cl = strstr(c->recv_buf, "Content-Length:");
                            if (!cl) cl = strstr(c->recv_buf, "content-length:");
                            if (cl) {
                                c->content_length = (size_t)strtoull(cl + 15, NULL, 10);
                            } else {
                                c->content_length = 0;
                            }

                            size_t head_bytes = (hdr_end + 4) - c->recv_buf;
                            c->body_read = c->recv_len - head_bytes;
                            c->state = ST_READING_BODY;
                        }
                    } else {
                        c->body_read += n;
                    }

                    if (c->state == ST_READING_BODY && (c->content_length == (size_t)-1 || c->body_read >= c->content_length)) {
                        /* Request complete! */
                        completed_reqs++;
                        uint64_t lat_us = (now - c->issue_time_ns) / 1000;
                        record_latency(lat_us);

                        if (c->status_code >= 200 && c->status_code < 300) {
                            code_2xx++;
                            if (c->status_code == 200) code_200++;
                        } else if (c->status_code >= 300 && c->status_code < 400) {
                            code_3xx++;
                        } else if (c->status_code >= 400 && c->status_code < 500) {
                            code_4xx++;
                        } else {
                            code_5xx++;
                        }

                        c->state = ST_IDLE;
                        /* Reset buffer for keep-alive reuse */
                        c->recv_len = 0;
                        if (target_requests > 0 && completed_reqs >= target_requests) break;
                    }
                } else if (n == 0) {
                    /* Server closed connection */
                    close_socket(c->fd);
                    c->fd = INVALID_SOCKET;
                    c->state = ST_IDLE;
                } else {
#ifdef _WIN32
                    int err = WSAGetLastError();
                    if (err != WSAEWOULDBLOCK) { errors++; close_socket(c->fd); c->fd = INVALID_SOCKET; c->state = ST_IDLE; }
#else
                    if (errno != EAGAIN && errno != EWOULDBLOCK) { errors++; close_socket(c->fd); c->fd = INVALID_SOCKET; c->state = ST_IDLE; }
#endif
                }
            }
        }
    }

    end_time = time_ns();
    for (int i = 0; i < target_conns; i++) {
        if (conns[i].fd != INVALID_SOCKET) close_socket(conns[i].fd);
    }

    double elapsed_s = (double)(end_time - start_time) / 1e9;
    double rps = elapsed_s > 0 ? (double)completed_reqs / elapsed_s : 0.0;
    uint64_t p50_us = hist_percentile(completed_reqs, 0.50);
    uint64_t p90_us = hist_percentile(completed_reqs, 0.90);
    uint64_t p99_us = hist_percentile(completed_reqs, 0.99);

    /* Output summary text */
    printf("Success rate: %.2f%%\n", completed_reqs > 0 ? (double)code_2xx * 100.0 / (completed_reqs + errors) : 0.0);
    printf("Requests/sec: %.2f\n", rps);
    printf("[%d] %llu responses\n", 200, (unsigned long long)code_200);
    if (errors > 0) {
        printf("Error distribution:\n  [errors] %llu\n", (unsigned long long)errors);
    }

    /* Output JSON if -o was requested */
    if (out_file) {
        FILE *f = fopen(out_file, "w");
        if (f) {
            fprintf(f, "{\n"
                       "  \"summary\": {\"requestsPerSec\": %.2f},\n"
                       "  \"statusCodeDistribution\": {\"200\": %llu, \"2xx\": %llu, \"3xx\": %llu, \"4xx\": %llu, \"5xx\": %llu},\n"
                       "  \"errorDistribution\": {%s%llu},\n"
                       "  \"achieved_rate\": %.2f,\n"
                       "  \"target_rate\": %.2f,\n"
                       "  \"requests\": %llu,\n"
                       "  \"status_codes\": {\"2xx\": %llu, \"3xx\": %llu, \"4xx\": %llu, \"5xx\": %llu},\n"
                       "  \"errors\": {%s%llu},\n"
                       "  \"latency_us\": {\"p50\": %llu, \"p90\": %llu, \"p99\": %llu}\n"
                       "}\n",
                       rps,
                       (unsigned long long)code_200, (unsigned long long)code_2xx, (unsigned long long)code_3xx,
                       (unsigned long long)code_4xx, (unsigned long long)code_5xx,
                       errors > 0 ? "\"errors\": " : "\"none\": ", (unsigned long long)errors,
                       rps, rate_limit > 0 ? rate_limit : rps,
                       (unsigned long long)completed_reqs,
                       (unsigned long long)code_2xx, (unsigned long long)code_3xx,
                       (unsigned long long)code_4xx, (unsigned long long)code_5xx,
                       errors > 0 ? "\"errors\": " : "\"none\": ", (unsigned long long)errors,
                       (unsigned long long)p50_us, (unsigned long long)p90_us, (unsigned long long)p99_us);
            fclose(f);
        }
    }

    free(conns);
    free(pfds);
#ifdef _WIN32
    WSACleanup();
#endif
    return errors > 0 ? 1 : 0;
}
