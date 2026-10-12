-- wrk's request mix for the REST benchmark's tier B (task 021), snowtime's k6
-- hot path: 25% GET /api/v1/session, 25% GET /api/v1/timer, 25% GET the
-- user's entries of the 14 days the timer page shows, 15% GET the
-- organization's projects with the archived ones, 6% PATCH the user's last
-- entry's description, and 4% timer start and stop, by turns for each user,
-- as k6's VUs alternate them. Each request is one of the dataset's 200 users,
-- with their session cookie and the fields k6's scenario sends.
--
--   wrk -t 4 -c 256 -d 15 -s bench/rest/tier-b.lua http://127.0.0.1:PORT -- DATADIR
--
-- DATADIR holds the generator's snow-load.txt, build/rest by default.

local users = {}
local started = {}
local thread_id = 0

function setup(thread)
    thread_id = thread_id + 1
    thread:set("seed", thread_id)
end

function init(args)
    math.randomseed(seed)
    local dir = args[1] or "build/rest"
    local f = assert(io.open(dir .. "/snow-load.txt"), "no " .. dir .. "/snow-load.txt; run bench/rest/gen.goose")
    for line in f:lines() do
        local cookie, user, org, entry, from, to = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)")
        users[#users + 1] = { cookie = cookie, user = user, org = org, entry = entry, from = from, to = to,
                              ip = string.format("10.%d.%d.%d", 0, math.floor(#users / 256), #users % 256) }
    end
    f:close()
end

-- A uuidv7 as the scenario makes one, from the time in ms.
local function uuid7()
    local t = string.format("%012x", os.time() * 1000 + math.random(0, 999))
    local function hex(n)
        local s = ""
        for i = 1, n do s = s .. string.format("%x", math.random(0, 15)) end
        return s
    end
    return t:sub(1, 8) .. "-" .. t:sub(9, 12) .. "-7" .. hex(3) .. "-" .. string.format("%x", math.random(8, 11))
        .. hex(3) .. "-" .. hex(12)
end

local function headers(u, kind, body)
    local h = { ["Cookie"] = u.cookie, ["Accept"] = "*/*", ["Origin"] = "https://time.bench.example.com",
                ["Sec-Fetch-Site"] = "same-origin", ["User-Agent"] = "snowtime-bench (k6)",
                ["CF-Connecting-IP"] = u.ip, ["X-Bench-Kind"] = kind .. " api", ["X-Bench-Step"] = "steady" }
    if body then h["Content-Type"] = "application/json" end
    return h
end

function request()
    local k = math.random(#users)
    local u = users[k]
    local r = math.random(100)
    if r <= 25 then
        return wrk.format("GET", "/api/v1/session", headers(u, "return"))
    elseif r <= 50 then
        return wrk.format("GET", "/api/v1/timer", headers(u, "return"))
    elseif r <= 75 then
        return wrk.format("GET", "/api/v1/organizations/" .. u.org .. "/entries?from=" .. u.from .. "&to=" .. u.to
            .. "&userId=" .. u.user, headers(u, "return"))
    elseif r <= 90 then
        return wrk.format("GET", "/api/v1/organizations/" .. u.org .. "/projects?includeArchived=true",
            headers(u, "sign-in"))
    elseif r <= 96 then
        local body = '{"description":"Benchmark edit ' .. (os.time() * 1000 + math.random(0, 999)) .. '"}'
        return wrk.format("PATCH", "/api/v1/organizations/" .. u.org .. "/entries/" .. u.entry,
            headers(u, "edit", true), body)
    end
    local id = started[k]
    if id then
        started[k] = nil
        return wrk.format("POST", "/api/v1/timer/stop", headers(u, "stop", true), '{"id":"' .. id .. '"}')
    end
    id = uuid7()
    started[k] = id
    return wrk.format("POST", "/api/v1/organizations/" .. u.org .. "/timer/start", headers(u, "start", true),
        '{"id":"' .. id .. '","description":"","ticket":null,"projectId":null}')
end

function done(summary, latency, requests)
    if summary.errors.status > 0 then
        io.write("tier-b: ", summary.errors.status, " responses not 2xx\n")
    end
end
