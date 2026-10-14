/* The example's handler, in C. It runs on every worker thread at once, so it
 * keeps no state of its own; the counter is atomic.
 *
 *   curl localhost:8080/
 *   curl -H 'User-Agent: me' localhost:8080/agent
 *   curl -d 'hi' localhost:8080/echo
 */
#include "goose_http.h"

#include <stdatomic.h>
#include <stdio.h>

static _Atomic int64_t requests;

static int64_t text(gh_response *res, gh_buffer out, int32_t status, const char *s) {
    size_t n = strlen(s);
    if ((int64_t)n > out.len) return -1;
    res->status = status;
    gh_content_type(res, "text/plain");
    memcpy(out.data, s, n);
    return (int64_t)n;
}

int64_t gh_handle(gh_bytes method, gh_bytes target, gh_bytes fields, gh_bytes body,
                  int64_t content_length, gh_response *res, gh_buffer out) {
    int64_t n = atomic_fetch_add(&requests, 1) + 1;
    int get = gh_eq(method, "GET") || gh_eq(method, "HEAD");

    if (gh_eq(target, "/") && get) return text(res, out, 200, "Hello from C!");

    if (gh_eq(target, "/count") && get) {
        res->status = 200;
        gh_content_type(res, "application/json");
        int k = snprintf((char *)out.data, (size_t)out.len, "{\"requests\":%lld}", (long long)n);
        return k < 0 ? -1 : k;
    }

    if (gh_eq(target, "/agent") && get) {
        int found;
        gh_bytes agent = gh_field(fields, "User-Agent", &found);
        if (!found) return text(res, out, 400, "no User-Agent");
        if (agent.len > out.len) return -1;
        res->status = 200;
        gh_content_type(res, "text/plain");
        memcpy(out.data, agent.data, (size_t)agent.len);
        return agent.len;
    }

    if (gh_eq(target, "/echo") && gh_eq(method, "POST")) {
        if (body.len < content_length) return text(res, out, 413, "body too long for this example");
        if (body.len > out.len) return -1;
        res->status = 200;
        gh_content_type(res, "application/octet-stream");
        memcpy(out.data, body.data, (size_t)body.len);
        return body.len;
    }

    return text(res, out, 404, "not found");
}
