// The benchmark server: TechEmpower's and HttpArena's routes (routes.goose),
// served by either of the package's loops, and task 002's echo servers.
// server.goose and server_epoll.goose are its root files, which differ in the
// loop they serve with when LOOP doesn't name one.
import std;
import os;
import http;
import routes;
import echo;

fn usage() {
    write_stderr("usage: server http|echo-blocking|echo-epoll [port]\n");
    exit(2);
}

// Runs the mode the command line names. The http mode serves with the loop
// LOOP names, epoll or uring (iocp on Windows, the same loop), or with
// default_loop without it.
fn run(default_loop: const u8[:]) {
    let argv = args();
    guard argv.len >= 2 else { usage(); }
    var port: i32 = 8080;
    if argv.len > 2 {
        let p, ok = parse_int(argv[2]);
        guard ok && p > 0 && p < 65536 else { usage(); }
        port = p as i32;
    }
    let mode = argv[1];
    if mode == "http" { serve_http(http::Config { port: port, workers: workers(), .. }, default_loop); }
    else if mode == "echo-blocking" { echo_blocking(port); }
    else if mode == "echo-epoll" { echo_epoll(port); }
    else { usage(); }
}

thread_fn worker(cfg: http::Config) { stopped(http::serve(cfg, route)); }

thread_fn worker_epoll(cfg: http::Config) { stopped(http::serve_epoll(cfg, route)); }

// Reports why a worker's loop stopped, and ends the process.
fn stopped(e: http::Error) {
    http::report(e);
    exit(1);
}

fn serve_http(cfg: http::Config, default_loop: const u8[:]) {
    var name: u8[>..] = [];
    if !env("LOOP", name) { name.append(default_loop); }
    let epoll = name == "epoll";
    guard epoll || name == "uring" || name == "iocp" else {
        write_stderr("LOOP must be epoll, uring, or iocp\n");
        exit(2);
    }
    let n = http::worker_count(cfg);
    print("http: ", n, if n == 1 { " worker" } else { " workers" }, " on port ", cfg.port,
          ", ", if epoll { "epoll" } else { "uring" }, " loop");
    var ids: i64[>..] = [];
    for i in n {
        ids.push(if epoll { thread_spawn(worker_epoll, cfg) } else { thread_spawn(worker, cfg) });
    }
    for id in ids { thread_wait(id); }
}

// WORKERS, or 0 without it.
fn workers() -> i64 {
    var v: u8[>..] = [];
    guard env("WORKERS", v) else { return 0; }
    let n, ok = parse_int(v);
    guard ok && n > 0 else {
        write_stderr("WORKERS must be a positive number\n");
        exit(2);
    }
    return n;
}
