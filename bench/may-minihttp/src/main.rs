// /plaintext and /json on may-minihttp, as TechEmpower's may-minihttp entry
// serves them: mimalloc, yarte's JSON serializer, and the crate's own
// Server and Date headers.
//
//     WORKERS=n bench-may-minihttp [port]

#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

use std::io;

use may_minihttp::{HttpService, HttpServiceFactory, Request, Response};
use yarte::Serialize;

#[derive(Serialize)]
struct HelloMessage {
    message: &'static str,
}

#[derive(PartialEq)]
enum Route {
    Plaintext,
    Json,
    NotFound,
}

struct Techempower;

impl HttpService for Techempower {
    fn call(&mut self, req: Request, rsp: &mut Response) -> io::Result<()> {
        let path = req.path();
        let path = path.split_once('?').map_or(path, |(p, _)| p);
        let route = match path {
            "/plaintext" => Route::Plaintext,
            "/json" => Route::Json,
            _ => Route::NotFound,
        };
        let allowed = req.method() == "GET" || req.method() == "HEAD";
        // The crate leaves an unread body in its buffer, where it would be
        // parsed as the next request, so every body is read and dropped.
        io::copy(&mut req.body(), &mut io::sink())?;
        if route != Route::NotFound && !allowed {
            rsp.status_code(405, "Method Not Allowed");
            rsp.header("Allow: GET, HEAD");
            return Ok(());
        }
        match route {
            Route::Json => {
                rsp.header("Content-Type: application/json");
                let msg = HelloMessage { message: "Hello, World!" };
                msg.to_bytes_mut(rsp.body_mut());
            }
            Route::Plaintext => {
                rsp.header("Content-Type: text/plain").body("Hello, World!");
            }
            Route::NotFound => {
                rsp.status_code(404, "Not Found");
            }
        }
        Ok(())
    }
}

struct Server;

impl HttpServiceFactory for Server {
    type Service = Techempower;

    fn new_service(&self, _: usize) -> Techempower {
        Techempower
    }
}

fn main() {
    let workers = std::env::var("WORKERS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or_else(|| std::thread::available_parallelism().map_or(1, |n| n.get()));
    let port: u16 = std::env::args().nth(1).and_then(|p| p.parse().ok()).unwrap_or(8080);
    may::config()
        .set_workers(workers)
        .set_pool_capacity(1000)
        .set_stack_size(0x1000);
    println!("may-minihttp: {workers} workers on port {port}");
    Server.start(("0.0.0.0", port)).unwrap().join().unwrap();
}
