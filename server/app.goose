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
// default_loop without it. uring-epoll is the uring loop over the emulation
// it falls back to where io_uring is blocked.
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
    if mode == "http" {
        // A body may be as long as /upload's tests send. The timeouts are
        // the package's unless the environment names others, for the tests.
        var cfg = http::Config { port: port, workers: positive("WORKERS", 0), max_body: 1 << 30, .. };
        cfg.request_ms = positive("REQUEST_MS", cfg.request_ms);
        cfg.body_ms = positive("BODY_MS", cfg.body_ms);
        cfg.write_ms = positive("WRITE_MS", cfg.write_ms);
        serve_http(cfg, default_loop);
    }
    else if mode == "echo-blocking" { echo_blocking(port); }
    else if mode == "echo-epoll" { echo_epoll(port); }
    else { usage(); }
}

thread_fn worker(cfg: http::Config) { stopped(http::serve(cfg, Transfer { .. }, handle)); }

thread_fn worker_epoll(cfg: http::Config) { stopped(http::serve_epoll(cfg, Transfer { .. }, handle)); }

// Reports why a worker's loop failed, and ends the process. A loop that a
// stop ended returns, and the process ends once every worker has.
fn stopped(e: http::Error) {
    guard e.code != 0 else { return; }
    http::report(e);
    exit(1);
}

fn serve_http(given: http::Config, default_loop: const u8[:]) {
    // SIGTERM and SIGINT stop the workers gracefully.
    let s = http::stop_on_signals();
    guard s == 0 else { stopped(http::Error { call: "sigaction", code: -s }); }
    var cfg = given;
    var name: u8[>..] = [];
    if !env("LOOP", name) { name.append(default_loop); }
    let epoll = name == "epoll";
    cfg.emulate_ring = name == "uring-epoll";
    guard epoll || cfg.emulate_ring || name == "uring" || name == "iocp" else {
        write_stderr("LOOP must be epoll, uring, uring-epoll, or iocp\n");
        exit(2);
    }
    let n = http::worker_count(cfg);
    // Where io_uring is blocked, the uring loop runs over an emulation, and
    // says so.
    var ring: u8[>..] = [];
    let probe = if epoll { 0 } else { http::ring_probe() };
    if probe < 0 && !cfg.emulate_ring {
        var text: u8[128] = [0; 128];
        let k = http::net_strerror(-probe, text);
        format(ring, " on an emulated ring (io_uring_setup: ", text[..k], ")");
    }
    // SERVER_RUNS serves again after each stop, for testing a loop called
    // again. Not RUNS, which the benchmark scripts set for themselves.
    for run in positive("SERVER_RUNS", 1) {
        print("http: ", n, if n == 1 { " worker" } else { " workers" }, " on port ", cfg.port,
              ", ", name, " loop", ring);
        var ids: i64[>..] = [];
        for i in n {
            ids.push(if epoll { thread_spawn(worker_epoll, cfg) } else { thread_spawn(worker, cfg) });
        }
        for id in ids { thread_wait(id); }
    }
}

// The environment variable name, a positive number, or otherwise without it.
fn positive(name: const u8[:], otherwise: i64) -> i64 {
    var v: u8[>..] = [];
    guard env(name, v) else { return otherwise; }
    let n, ok = parse_int(v);
    guard ok && n > 0 else {
        write_stderr(str(name, " must be a positive number\n"));
        exit(2);
    }
    return n;
}
