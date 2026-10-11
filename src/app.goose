// What both builds of the server share: the command line, the worker count,
// and the limits a worker holds its connections to. src/main.goose builds the
// epoll loop (src/server.goose) and src/main_uring.goose the io_uring loop
// (src/uring.goose); each loop defines thread_fn worker.
import os;
import http;
import echo;

// A worker's buffers, which the connection it's driving uses. The read
// buffer holds the longest request head whole. The write buffer takes the
// responses to a read's worth of pipelined requests: 16 TechEmpower
// responses are about 2 KB. When it fills, the server sends it and answers
// the rest of the read buffer after.
let RBUF = http::MAX_HEAD;
let WBUF = 8192;

// The most connections one worker holds. One worker must be able to take
// TechEmpower's largest run, 16,384 connections, alone.
let MAX_CONNS = 16384;
let BACKLOG = 4096;

// In milliseconds of the monotonic clock. A request has REQUEST_MS from its
// first byte to arrive whole, and a response as long to leave once it stops
// moving. An idle keep-alive connection closes after IDLE_MS. A refused
// connection has LINGER_MS for the client to read the refusal and close.
let REQUEST_MS = 10000;
let IDLE_MS = 60000;
let LINGER_MS = 2000;

fn usage() {
    write_stderr("usage: server http|echo-blocking|echo-epoll [port]\n");
    exit(2);
}

fn run() {
    let argv = args();
    guard argv.len >= 2 else { usage(); }
    var port: i32 = 8080;
    if argv.len > 2 {
        let p, ok = parse_int(argv[2]);
        guard ok && p > 0 && p < 65536 else { usage(); }
        port = p as i32;
    }
    let mode = argv[1];
    if mode == "http" { serve_http(port); }
    else if mode == "echo-blocking" { echo_blocking(port); }
    else if mode == "echo-epoll" { echo_epoll(port); }
    else { usage(); }
}

fn serve_http(port: i32) {
    let n = workers();
    print("http: ", n, if n == 1 { " worker" } else { " workers" }, " on port ", port);
    var ids: i64[>..] = [];
    for i in n { ids.push(thread_spawn(worker, port)); }
    for id in ids { thread_wait(id); }
}

// WORKERS, or one worker per hardware thread.
fn workers() -> i64 {
    var v: u8[>..] = [];
    guard env("WORKERS", v) else { return max(1, hardware_threads()); }
    let n, ok = parse_int(v);
    guard ok && n > 0 else {
        write_stderr("WORKERS must be a positive number\n");
        exit(2);
    }
    return n;
}
