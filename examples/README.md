# Examples

Each example imports the package from this checkout (`"../../"`), not from GitHub. A
program of your own imports it as the [Quick start](../README.md#quick-start) does.

| Example | What it shows |
|---|---|
| [`hello/`](hello/hello.goose) | One route, one worker per core: the Quick start |
| [`routes/`](routes/routes.goose) | The router: parameters, 404 and 405, a JSON response, a request body, and a stop on Ctrl+C |

Build and run one from the repository's root:

```sh
goose build -o build/examples/routes examples/routes/routes.goose
./build/examples/routes
curl localhost:8080/users/42
```

Each one listens on port 8080. `scripts/test.sh` typechecks them.

## A handler in C, on a branch

The `examples-c` branch has `examples/c/`, an experiment (2026-10-12): the package's
server with a handler written in C, which `goose build` compiles from the example's
sidecar. It's off `main` until Goose leaves examples out of a package: Goose links the
C function of every `extern fn` under the package's root into the package's library
for in-process runs, so the example's `gh_handle`, which only its own C defines, broke
every `goose file.goose` that imported the package
([findings](../docs/goose-findings.md#a-packages-jit-library-links-the-externs-of-every-file-under-its-root)).

