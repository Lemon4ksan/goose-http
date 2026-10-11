// /plaintext and /json on xitca-web's HTTP/1 stack, configured as TechEmpower's
// xitca-web entry runs its default test (TechEmpower/FrameworkBenchmarks
// frameworks/Rust/xitca-web/src/main.rs at 57d92fb): xitca-server workers,
// each a thread with its own tokio-uring runtime accepting on one shared
// listener, the h1 dispatcher in io_uring mode, the xitca-http router,
// sonic-rs for JSON, and mimalloc. The routes, the Server middleware, and the
// 404 and 405 handling are the entry's; its database routes are left out.
// xitca-http writes the Date field.
//
// What this repository's benchmark needs on top: WORKERS for the worker count
// (the entry takes the CPU count), the port as the first argument, an Allow
// field on 405, and `xitca-web` for the entry's Server value, `x`.
//
//     WORKERS=n bench-xitca-web [port]

#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

use serde_core::{Serialize, Serializer, ser::SerializeStruct};
use xitca_http::{
    HttpServiceBuilder,
    body::Once,
    bytes::Bytes,
    h1::RequestBody,
    http::{
        self, HeaderValue, IntoResponse as _, RequestExt, StatusCode,
        const_header_value::{JSON, TEXT_UTF8},
        header::{ALLOW, CONTENT_TYPE, SERVER},
    },
    util::service::{
        route::get,
        router::{Router, RouterError},
    },
};
use xitca_service::{Service, ServiceExt, fn_service};

type Request = http::Request<RequestExt<RequestBody>>;

type Response = http::Response<Once<Bytes>>;

type Error = Box<dyn std::error::Error + Send + Sync + 'static>;

const HELLO: &str = "Hello, World!";

struct Message {
    message: &'static str,
}

// The entry's hand-expanded derive.
impl Serialize for Message {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut res = serializer.serialize_struct("Message", 1)?;
        res.serialize_field("message", self.message)?;
        res.end()
    }
}

fn main() -> std::io::Result<()> {
    let workers = std::env::var("WORKERS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or_else(|| std::thread::available_parallelism().map_or(1, |n| n.get()));
    let port: u16 = std::env::args().nth(1).and_then(|p| p.parse().ok()).unwrap_or(8080);
    println!("xitca-web: {workers} workers on port {port}");

    let service = Router::new()
        .insert(
            "/plaintext",
            get(fn_service(async |req: Request| {
                let mut res = req.into_response(const { Bytes::from_static(HELLO.as_bytes()) });
                res.headers_mut().insert(CONTENT_TYPE, TEXT_UTF8);
                Ok::<_, Error>(res)
            })),
        )
        .insert(
            "/json",
            get(fn_service(async |req: Request| {
                let buf = sonic_rs::to_vec(&Message { message: HELLO })?;
                let mut res = req.into_response(Bytes::from(buf));
                res.headers_mut().insert(CONTENT_TYPE, JSON);
                Ok::<_, Error>(res)
            })),
        )
        .enclosed_fn(async |service, req| {
            let mut res = service.call(req).await.unwrap_or_else(error_handler);
            res.headers_mut().insert(SERVER, HeaderValue::from_static("xitca-web"));
            Ok::<_, core::convert::Infallible>(res)
        })
        .enclosed(HttpServiceBuilder::h1().io_uring());
    xitca_server::Builder::new()
        .worker_threads(workers)
        .bind("xitca-web", ("0.0.0.0", port), service)?
        .build()
        .wait()
}

#[cold]
#[inline(never)]
fn error_handler(e: RouterError<Error>) -> Response {
    let mut res = http::Response::new(Once::new(Bytes::new()));
    *res.status_mut() = match e {
        RouterError::Match(_) => StatusCode::NOT_FOUND,
        RouterError::NotAllowed(_) => {
            res.headers_mut().insert(ALLOW, HeaderValue::from_static("GET"));
            StatusCode::METHOD_NOT_ALLOWED
        }
        RouterError::Service(e) => {
            eprintln!("Internal Error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        }
    };
    res
}
