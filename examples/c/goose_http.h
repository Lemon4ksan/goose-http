/* What the C handler of app.goose implements, and what it's given.
 *
 * app.goose runs the package's server, one event loop per core, and calls
 * gh_handle for each request on the worker thread that read it: several at
 * once, one per worker. Everything it gets is borrowed for the call only.
 */
#ifndef GOOSE_HTTP_H
#define GOOSE_HTTP_H

#include <stdint.h>
#include <string.h>

/* Goose packs what it shares with C, a slice included: a slice is 12 bytes on a
 * 32-bit target and 16 on a 64-bit one. */
#pragma pack(push, 1)

/* A Goose u8[:]: data isn't NUL-terminated. */
typedef struct {
    const uint8_t *data;
    int64_t len;
} gh_bytes;

typedef struct {
    uint8_t *data;
    int64_t len;
} gh_buffer;

/* app.goose's CResponse, field for field. */
typedef struct {
    int32_t status;             /* 200 unless the handler sets another */
    int32_t content_type_len;   /* 0 for no Content-Type */
    uint8_t content_type[64];
} gh_response;

#pragma pack(pop)

_Static_assert(sizeof(gh_bytes) == sizeof(void *) + 8 && sizeof(gh_buffer) == sizeof(void *) + 8,
               "a slice must be packed as Goose packs it");
_Static_assert(sizeof(gh_response) == 72, "gh_response must match CResponse");

/* Answers one request. method and target are as sent; fields are the header
 * field lines, each ending in CRLF, which gh_field searches. body is the whole
 * body when it fits in the read buffer with the head (8 KB by default), and
 * empty otherwise; content_length is its Content-Length either way.
 *
 * Writes the body into out and returns its length, or -1 for a 500. A length
 * past out.len is a 500 too. The response's head, and a HEAD request's empty
 * body, are the server's. */
int64_t gh_handle(gh_bytes method, gh_bytes target, gh_bytes fields, gh_bytes body,
                  int64_t content_length, gh_response *res, gh_buffer out);

static inline int gh_eq(gh_bytes b, const char *s) {
    size_t n = strlen(s);
    return b.len == (int64_t)n && memcmp(b.data, s, n) == 0;
}

static inline int gh_lower(uint8_t c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }

/* The value of header field name, matched without regard to case, with the
 * spaces around it trimmed; found is 0 without one. */
static inline gh_bytes gh_field(gh_bytes fields, const char *name, int *found) {
    size_t n = strlen(name);
    int64_t i = 0;
    while (i < fields.len) {
        int64_t end = i;
        while (end + 1 < fields.len && !(fields.data[end] == '\r' && fields.data[end + 1] == '\n')) end++;
        if (end - i > (int64_t)n && fields.data[i + n] == ':') {
            size_t k = 0;
            while (k < n && gh_lower(fields.data[i + k]) == gh_lower((uint8_t)name[k])) k++;
            if (k == n) {
                int64_t v = i + n + 1, w = end;
                while (v < w && (fields.data[v] == ' ' || fields.data[v] == '\t')) v++;
                while (w > v && (fields.data[w - 1] == ' ' || fields.data[w - 1] == '\t')) w--;
                *found = 1;
                return (gh_bytes){ fields.data + v, w - v };
            }
        }
        i = end + 2;
    }
    *found = 0;
    return (gh_bytes){ fields.data, 0 };
}

static inline void gh_content_type(gh_response *res, const char *type) {
    size_t n = strlen(type);
    if (n > sizeof res->content_type) n = sizeof res->content_type;
    memcpy(res->content_type, type, n);
    res->content_type_len = (int32_t)n;
}

#endif
