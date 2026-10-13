-- HttpArena json-comp's requests, for wrk: GET /json/{count}?m={m} at its
-- seven counts in turn, each connection starting at another, with its
-- "Accept-Encoding: gzip, br", or none with the argument identity
-- (HttpArena 0720ee5, requests/json-gzip-*.raw).
--
--   wrk -t 8 -c 512 -d 15 -s bench/json-comp.lua http://127.0.0.1:8080 [-- identity]
local paths = {
    "/json/1?m=3", "/json/5?m=7", "/json/10?m=2", "/json/15?m=5",
    "/json/25?m=4", "/json/40?m=8", "/json/50?m=6",
}
local requests = {}
local identity = false
local next_one = 1
local counter = 0

function setup(thread)
    counter = counter + 1
    thread:set("first", counter)
end

function init(args)
    identity = args[1] == "identity"
    local headers = identity and {} or { ["Accept-Encoding"] = "gzip, br" }
    for i, p in ipairs(paths) do
        requests[i] = wrk.format("GET", p, headers)
    end
    next_one = (first or 1) % #requests + 1
end

function request()
    local r = requests[next_one]
    next_one = next_one % #requests + 1
    return r
end
