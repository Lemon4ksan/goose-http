// The REST benchmark's tiers (task 021) on xitca-web's HTTP/1 stack, configured
// as bench/xitca-web is, after TechEmpower's entry: xitca-server workers, each
// a thread with its own tokio-uring runtime accepting on one shared listener,
// the h1 dispatcher in io_uring mode, and mimalloc. The routes are
// bench/rest/rust's, answering as bench/rest/hyper does, behind one service
// in place of the entry's router; they write JSON with serde_json, as the
// other Rust servers' routes do, where the entry's /json uses sonic-rs.
//
// The dispatcher hands the handler the body as a stream of the pieces it
// reads, so tier D reads the CSV and the multipart body as they arrive. It
// closes a connection whose request body wasn't read to its end, so a body
// is read to its end after an answer that comes before it, as multer's at
// the close delimiter, unless the answer is a 413.
//
//     REST_DATA=DIR TIER=a|b|c|d WORKERS=n [JSON=template] rest-xitca-web [port]

#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

use std::future::poll_fn;
use std::pin::Pin;

use futures_core::Stream;
use rest_app::writes::{self, Start};
use rest_app::{Head, Resp};
use xitca_http::{
    HttpServiceBuilder,
    body::Once,
    bytes::Bytes,
    h1::RequestBody,
    http::{
        self, HeaderValue, RequestExt, StatusCode,
        const_header_value::JSON,
        header::{CONNECTION, CONTENT_TYPE, SERVER},
    },
};
use xitca_service::{ServiceExt, fn_service};

type Request = http::Request<RequestExt<RequestBody>>;

type Response = http::Response<Once<Bytes>>;

type Error = Box<dyn std::error::Error + Send + Sync + 'static>;

fn response(r: Resp) -> Response {
    let mut res = http::Response::new(Once::new(Bytes::from(r.body)));
    *res.status_mut() = StatusCode::from_u16(r.status).unwrap();
    let headers = res.headers_mut();
    headers.insert(SERVER, HeaderValue::from_static("xitca-web"));
    if r.json {
        headers.insert(CONTENT_TYPE, JSON);
    }
    if r.close {
        headers.insert(CONNECTION, HeaderValue::from_static("close"));
    }
    res
}

async fn next(body: &mut RequestBody) -> Option<std::io::Result<Bytes>> {
    poll_fn(|cx| Pin::new(&mut *body).poll_next(cx)).await
}

async fn drain(body: &mut RequestBody) {
    while let Some(Ok(_)) = next(body).await {}
}

async fn route(req: Request) -> Result<Response, Error> {
    let (parts, ext) = req.into_parts();
    let (_, mut body) = ext.replace_body(());
    let target = parts.uri.path_and_query().map_or("/", |p| p.as_str());
    let mut head = Head::new(parts.method.as_str().as_bytes(), target);
    for (name, value) in &parts.headers {
        head.field(name.as_str().as_bytes(), value.as_bytes());
    }
    if !writes::is_writes(head.path) {
        let mut whole = Vec::new();
        while let Some(piece) = next(&mut body).await {
            whole.extend_from_slice(&piece?);
        }
        return Ok(response(rest_app::handle(&head, &whole)));
    }
    let r = match writes::start(&head) {
        Start::Answer(r) => {
            if !r.close {
                drain(&mut body).await;
            }
            r
        }
        Start::Read(mut w) => {
            let mut early = None;
            while let Some(piece) = next(&mut body).await {
                early = w.push_bytes(piece?);
                if early.is_some() {
                    break;
                }
            }
            match early {
                Some(r) => {
                    if !r.close {
                        drain(&mut body).await;
                    }
                    r
                }
                None => w.finish(),
            }
        }
    };
    Ok(response(r))
}

fn main() -> std::io::Result<()> {
    let config = rest_app::init("rest-xitca-web");
    let service = fn_service(route).enclosed(HttpServiceBuilder::h1().io_uring());
    xitca_server::Builder::new()
        .worker_threads(config.workers)
        .bind("rest-xitca-web", ("0.0.0.0", config.port), service)?
        .build()
        .wait()
}
