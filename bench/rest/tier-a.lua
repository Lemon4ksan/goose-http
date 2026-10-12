-- wrk's request mix for the REST benchmark's tier A (task 021), HttpArena's
-- production-stack application layer: 78% GET /api/items/{1..10000}, 16% GET
-- /api/me as one of 1,000 users, and 6% POST /api/items/{1..20} with a
-- 51-byte JSON body, about the share of production-stack's write connections.
-- Every request carries a 147-byte bearer token and HttpArena's
-- Accept-Encoding, unpipelined, as an API's clients send them.
--
--   wrk -t 4 -c 256 -d 15 -s bench/rest/tier-a.lua http://127.0.0.1:PORT

local token = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    .. "eyJzdWIiOiI0MiIsImV4cCI6MTc5MDAwMDAwMH0." .. string.rep("x", 70)
local body = '{"name":"bench-updated","price":250,"quantity":10}'
local thread_id = 0

function setup(thread)
    thread_id = thread_id + 1
    thread:set("seed", thread_id)
end

function init(args)
    math.randomseed(seed)
end

function request()
    local r = math.random(100)
    if r <= 78 then
        return wrk.format("GET", "/api/items/" .. math.random(10000),
            { ["Authorization"] = token, ["Accept-Encoding"] = "br;q=1, gzip;q=0.8" })
    elseif r <= 94 then
        return wrk.format("GET", "/api/me",
            { ["Authorization"] = token, ["Accept-Encoding"] = "br;q=1, gzip;q=0.8",
              ["X-User-Id"] = tostring(math.random(1000)) })
    end
    return wrk.format("POST", "/api/items/" .. math.random(20),
        { ["Authorization"] = token, ["Accept-Encoding"] = "br;q=1, gzip;q=0.8",
          ["Content-Type"] = "application/json" }, body)
end

local codes = {}

function response(status, headers, body)
    codes[status] = (codes[status] or 0) + 1
end

function done(summary, latency, requests)
    -- wrk counts only non-2xx; 204 is a 2xx, so any status but 200 and 204 is
    -- an error the run must not have.
    if summary.errors.status > 0 then
        io.write("tier-a: ", summary.errors.status, " responses not 2xx\n")
    end
end
