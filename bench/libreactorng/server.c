/* /plaintext and /json on libreactorng, configured as HttpArena's libreactorng
 * entry runs it (MDA2AV/HttpArena frameworks/libreactorng/src/server.c at
 * 0720ee5): one reactor per worker, each with its own SO_REUSEPORT listener
 * and io_uring loop, libreactor's HTTP server and parser, and the entry's
 * patch for Connection: close. libreactor writes the Server field, as `*`,
 * and the Date field.
 *
 * What this repository's benchmark needs on top:
 *
 * - A thread per worker where the entry forks a process per worker, so
 *   bench/run.sh's CPU time and peak RSS, read from one process, cover every
 *   worker, and stopping that process stops them all. libreactor keeps its
 *   reactor, network, and server state in thread-local storage.
 * - WORKERS for the worker count (the entry takes the CPUs in its mask) and
 *   the port as the first argument.
 * - TechEmpower's /plaintext and /json in place of the entry's routes, and 405
 *   for other methods on them. /json builds its object and encodes it with
 *   libreactor's JSON encoder per request.
 *
 *     WORKERS=n bench-libreactorng [port]
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdbool.h>
#include <stdint.h>
#include <signal.h>
#include <pthread.h>
#include <sched.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>

#include <reactor.h>

/* Encoder output, reused per worker. */
static __thread buffer_t json_buffer;

/* True if the request carried Connection: close (the entry's). */
static bool wants_close(server_session_t *s)
{
    for (size_t i = 0; i < s->request.fields_count; i++) {
        string_t name = s->request.fields[i].name;
        if (data_size(name) == 10 && strncasecmp((const char *) data_base(name), "connection", 10) == 0) {
            string_t val = s->request.fields[i].value;
            const char *v = (const char *) data_base(val);
            size_t vl = data_size(val);
            for (size_t j = 0; j + 5 <= vl; j++)
                if (strncasecmp(v + j, "close", 5) == 0)
                    return true;
            return false;
        }
    }
    return false;
}

static void json(server_session_t *s)
{
    value_t *message = value_object();

    value_object_set_release(message, string("message"), value_string_constant(string("Hello, World!")));
    buffer_clear(&json_buffer);
    (void) value_buffer_encode(&json_buffer, message, 0);
    value_release(message);
    server_respond(s, string("200 OK"), string("application/json"), buffer_data(&json_buffer), NULL, 0);
}

static void on_request(reactor_event_t *event)
{
    server_session_t *s = (server_session_t *) event->data;
    string_t method = s->request.method;
    const char *t = (const char *) data_base(s->request.target);
    size_t t_len = data_size(s->request.target);
    const char *q = memchr(t, '?', t_len);
    size_t path_len = q ? (size_t) (q - t) : t_len;
    bool plaintext = path_len == 10 && memcmp(t, "/plaintext", 10) == 0;

    if (!plaintext && !(path_len == 5 && memcmp(t, "/json", 5) == 0)) {
        server_respond(s, string("404 Not Found"), string("text/plain"), data_string("Not Found"), NULL, 0);
    } else if (!string_equal(method, string("GET"))) {
        http_field_t allow = http_field_define(string("Allow"), string("GET"));
        server_respond(s, string("405 Method Not Allowed"), string("text/plain"), data_string(""), &allow, 1);
    } else if (plaintext) {
        server_plain(s, data_string("Hello, World!"), NULL, 0);
    } else {
        json(s);
    }

    /* Close gracefully after the response drains to the socket when the client asked for it. */
    if (wants_close(s))
        stream_close_on_drain(&s->stream);
}

static int make_reuseport_socket(int port)
{
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) { perror("socket"); exit(1); }
    int on = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
    setsockopt(s, SOL_SOCKET, SO_REUSEPORT, &on, sizeof(on));
    setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on));
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(port),
        .sin_addr.s_addr = htonl(INADDR_ANY),
    };
    if (bind(s, (struct sockaddr *) &addr, sizeof(addr)) < 0) {
        perror("bind"); exit(1);
    }
    if (listen(s, 4096) < 0) { perror("listen"); exit(1); }
    return s;
}

static void *worker(void *arg)
{
    int fd = make_reuseport_socket((int) (intptr_t) arg);
    server_t server;

    buffer_construct(&json_buffer);
    reactor_construct();
    server_construct(&server, on_request, NULL);
    server_open_socket(&server, fd);
    reactor_loop();
    server_destruct(&server);
    reactor_destruct();
    return NULL;
}

int main(int argc, char **argv)
{
    signal(SIGPIPE, SIG_IGN);

    int port = argc > 1 ? atoi(argv[1]) : 8080;
    int workers = 0;
    const char *w = getenv("WORKERS");
    if (w)
        workers = atoi(w);
    if (workers < 1) {
        cpu_set_t cs;
        workers = sched_getaffinity(0, sizeof(cs), &cs) == 0 ? CPU_COUNT(&cs) : 1;
    }
    printf("libreactorng: %d workers on port %d\n", workers, port);
    fflush(stdout);

    /* The main thread becomes the last worker. */
    for (int i = 1; i < workers; i++) {
        pthread_t t;
        if (pthread_create(&t, NULL, worker, (void *) (intptr_t) port) != 0) {
            perror("pthread_create");
            exit(1);
        }
        pthread_detach(t);
    }
    worker((void *) (intptr_t) port);
    return 0;
}
