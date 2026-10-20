# 056: tier C's byte loops, and h2c's cost to HTTP/1.1 on epoll

Status: done (found 2026-10-20; the byte loops and h2c's cost fixed 2026-10-20)

goose-rest's task 054 profiled its tier C templated and found most of a request's
cycles in loops that take a header line a byte at a time: its benchmark server's JWT
check, `http::bearer`'s `is_token68`, and `http::field_at`, over tier C's ~1.2 KB heads
with 560-byte bearer tokens. goose-rest replaced its JWT check with std's `find_any`,
which the runtime runs 16 bytes at a time (goose-rest `809d36f`). This task does the
same here: goose-http's REST server checks the same JWT shape, so both Goose servers do
the same work outside the framework again, and the two library loops are on every
goose-rest request that reads a bearer token or a field.

## The changes

- `bench/rest/goose/rest.goose`: `has_bearer` checks the token with `find_any`, as
  goose-rest's `jwt_shaped` does: one scan for a byte that is neither base64url nor
  `.`, and three for the dots.
- `auth.goose`: `is_token68` finds the first byte that isn't a token68 character with
  `find_any`, then takes the `=`s after it, as before.
- `message.goose`: `field_at` finds the colon, the name's first byte that isn't a
  token character, and the line's CR with `find_any`, where it took `position`, a
  byte loop.

`test/api/auth.goose` checks `is_token68` and `field_at` at every length up to 48 and
every position of a bad byte or an `=`: 9,408 cases, which the earlier code passes too.

## Measured

User instructions and cycles per request, counted as goose-rest's task 054 counts:
one worker on CPU 0, `TIER=c JSON=template`, 200,000 GETs of `/api/v2/clients/7` from
h2load on CPUs 4-15 (8 threads, 256 connections, one request in flight on each) with a
tier C bearer token and `tier-c.lua`'s browser fields, and `perf stat -e
instructions:u,cycles:u` on the server's process; two runs each, Goose `f114b5a`, each
change added in turn. goose-rest is its `main` at `a817ee6` built against this
repository's working tree.

| Build | epoll | io_uring |
|---|---:|---:|
| goose-http alone, `5cc789f7` | 21,180; 7,643-7,841 | 21,236; 6,411-6,450 |
| and the JWT check | 15,083; 5,475-5,528 | 15,139; 4,287-4,303 |
| and `field_at` | 12,004; 4,746-4,777 | 12,050; 3,497-3,640 |
| goose-rest on `5cc789f7` | 20,534; 8,996-9,076 | 20,610; 7,717-7,867 |
| and `is_token68` | 16,049; 6,657-6,857 | 16,125; 5,332-5,379 |
| and `field_at` | 12,975; 5,111-5,120 | 13,051; 3,960-3,977 |

goose-http alone doesn't call `is_token68`. Every request answered 200; goose-http's
`check.py` passes tiers A and B on goose-http alone, and C and D, D's server checked
with C too, on both servers and both loops.

Tier C templated at saturation, 4 workers on CPUs 0-3, wrk with 8 threads and 256
connections and `tier-c.lua` on CPUs 4-15, three 8 s runs after 3 s, two rounds
interleaved; the 1-minute load average was 2.5 when they began:

| Server | Loop | Before | After | Median |
|---|---|---:|---:|---:|
| goose-http alone | io_uring | 141.8-148.7 K | 154.0-157.8 K | +6.7% |
| goose-http alone | epoll | 138.0-139.7 K | 144.4-147.2 K | +5.4% |
| goose-rest | io_uring | 140.3-144.5 K | 151.3-155.1 K | +6.9% |
| goose-rest | epoll | 133.0-134.6 K | 143.9-145.7 K | +8.0% |

goose-rest is 1.5% behind goose-http alone on io_uring and 0.8% on epoll.

Plaintext doesn't move: `bench/instructions.sh` (3 runs, interleaved) counts
1,592-1,624 user instructions per request on epoll against 1,610-1,621 before, and
1,642-1,679 on io_uring against 1,643-1,651.

## h2c's cost to HTTP/1.1 on epoll

goose-http alone's REST server counted 376 more user instructions per tier C request
on epoll at `v0.4.0` than at `v0.3.7` (20,803 → 21,180, counted as above, one run per
build). A bisect of `main`'s first parents on that count (bad above 20,990) finds
`2ad56de8`, which serves h2c in the epoll loop: 20,842 → 21,158. Later commits add the
other 20 or so. An HTTP/1.1 request's own path gains only an `if c.h2 >= 0` branch,
but the loop now also calls the handler from `h2_answer`, which takes it as a block:
the shape task 055 found to change how Goose inlines the loop's call to the handler.

### The cause

At `v0.4.2`, dropping the call to `h2_answer` from the epoll loop saves 79 user
instructions per request, on tier A as on tier C (table below), not the bisect's 316,
which were counted at `2ad56de8`; the commits since, task 055's fixes among them,
weren't split to see which took the rest. The handler isn't inlined differently: Goose's optimized specializations (`goose -O2
--specs`) of the epoll loop's `answer` are the same with and without the call to
`h2_answer`, and gcc gives `answer` the same 0x4840 bytes. The cost is in `advance`,
the nested function that runs the loop's answer, send, and receive turns. A nested
function takes each variable it captures as a pointer, and `advance` captured, for
`h2_answer`, the h2 driver's pools, buffers, and counters: its C function took 49
arguments, against 22 without the call, passed at every call from `drive`, most on the
stack, and gcc kept it a function of its own (0xc31 bytes). The io_uring loop calls
`h2_answer` from `pump_h2`, a function apart from HTTP/1.1's `pump`, and was never
affected. Moving the call into a nested function of `advance`'s didn't help: Goose
asked gcc to inline the copy (a function with two results that Goose can't inline is
marked `GS_INLINE`), and the count didn't move.

### The fix

`advance` takes its answering turn as a block, which returns an `EpollTurn`, and
`drive` calls it with `answer`'s block on an HTTP/1.1 connection and `h2_answer`'s on an
h2c one (`epoll.goose`). Goose specializes `advance` for each block, so the HTTP/1.1
copy captures only what `answer` uses, and both copies are now inlined into
`epoll_loop`. What a turn does is unchanged.

### What it measured

Counted as above, on the desktop (Ryzen 7 5800X3D, WSL2 kernel
6.18.54.1-microsoft-standard-WSL2), Goose `f114b5a`, h2load nghttp2 1.68.0: one worker
on CPU 0, `JSON=template`, h2load on CPUs 4-15 (8 threads, 256 connections, one request
in flight on each); tier C with 200,000 GETs of `/api/v2/clients/7` and its bearer
token and browser fields, tier A with 400,000 GETs of `/api/items/1` and its bearer
token and `Accept-Encoding`. User instructions and cycles per request, two runs each
on epoll. "Before" is `v0.4.2` (`6dd2a857`); goose-rest is its `main` at `88677f8`,
built against each.

| Build | Tier A | Tier C |
|---|---:|---:|
| goose-http alone, before | 4,357.1; 2,798-2,827 | 12,003.8; 4,748-4,751 |
| without the call to `h2_answer`, for the trace | 4,278.0; 2,741 | 11,924.6; 4,612-4,726 |
| after | 4,187.0; 2,611-2,646 | 11,833.6; 4,549-4,558 |
| goose-rest, before | 4,501.4; 3,011-3,106 | 12,975.2; 5,175-5,195 |
| goose-rest, after | 4,291.2; 2,833-2,913 | 12,764.9; 4,961-5,120 |

The fix saves 170 instructions per request on goose-http alone and 210 on goose-rest,
more than dropping the call to `h2_answer` did (79), as `advance` is now inlined too.
The io_uring loop counts the same before and after: 4,281.8 and 12,050.1 on goose-http
alone, 4,441.8 and 13,051.3 on goose-rest. goose-rest's `bench/rest.sh count`
(pipelined 16 deep, `N=1000000`, one run each) counts 11-13 fewer user instructions per
request on every route, and 51 fewer on tier F's bare server's `/`.

Plaintext doesn't regress: `bench/instructions.sh` (3 runs, interleaved) counts
1,577-1,599 user instructions per request on epoll after, against 1,589-1,618 before,
and 1,637-1,651 on io_uring, against 1,627-1,656.

Rates on epoll, 4 workers on CPUs 0-3, wrk with 8 threads and 256 connections and the
tier's script on CPUs 4-15, `JSON=template`, three 8 s runs after 3 s, two rounds with
the four builds interleaved; the 1-minute load average was 1.5 when they began:

| Server | Tier | Before | After | Median |
|---|---|---:|---:|---:|
| goose-http alone | A | 424.4-438.5 K | 438.6-454.3 K | +3.7% |
| goose-rest | A | 429.5-434.8 K | 431.3-444.7 K | +1.9% |
| goose-http alone | C | 144.9-147.1 K | 145.0-146.7 K | +0.5% |
| goose-rest | C | 141.8-145.1 K | 144.0-146.4 K | +0.7% |

Tier A gains beyond the runs' spread; tier C, whose requests cost 1.4% fewer
instructions, within it.

## Acceptance criteria

- [x] goose-http's REST server checks the JWT as goose-rest's does, with the same
      answers (`check.py` on tiers A to D)
- [x] `is_token68` and `field_at` scan 16 bytes at a time, tested at every length and
      position, with no plaintext cost
- [x] h2c's cost to an HTTP/1.1 request on epoll traced in the generated C, and fixed
      or recorded with its reason: `advance`'s captured h2 state, fixed with a block
