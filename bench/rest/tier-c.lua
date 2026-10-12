-- wrk's request mix for the REST benchmark's tier C (task 021), a clinic's
-- schedule view and records: 55% the schedule's version poll; 9% a week's
-- bookings of all 10 staff, one in ten of them a month of one staff member's
-- instead, and 9% the same range's shifts, the refetch after a change; 12% an
-- encounter with its case's notes and 12% a client's last 20 visits, as a
-- visit is opened; and 3% a client. Each request carries one of the 10
-- staff's bearer tokens and a browser's other fields, a head of about 1.2 KB.
--
--   wrk -t 4 -c 256 -d 15 -s bench/rest/tier-c.lua http://127.0.0.1:PORT -- DATADIR
--
-- DATADIR holds the generator's heavy-load.txt, build/rest by default.

local tokens, weeks = {}, {}
local month, ranges, epoch
local thread_id = 0

function setup(thread)
    thread_id = thread_id + 1
    thread:set("seed", thread_id)
end

function init(args)
    math.randomseed(seed)
    local dir = args[1] or "build/rest"
    local f = assert(io.open(dir .. "/heavy-load.txt"), "no " .. dir .. "/heavy-load.txt; run bench/rest/gen.goose")
    ranges = {}
    for line in f:lines() do
        local kind, a, b = line:match("([^\t]+)\t([^\t]+)\t?([^\t]*)")
        if kind == "token" then tokens[#tokens + 1] = "Bearer " .. a
        elseif kind == "week" then weeks[#weeks + 1] = { a, b }
        elseif kind == "month" then month = { a, b }
        elseif kind == "version0" then epoch = tonumber(a)
        else ranges[kind] = { tonumber(a), tonumber(b) } end
    end
    f:close()
end

local function headers(referer)
    return {
        ["Authorization"] = tokens[math.random(#tokens)],
        ["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
            .. "Chrome/141.0.0.0 Safari/537.36",
        ["Accept"] = "application/json, text/plain, */*",
        ["Accept-Language"] = "et-EE,et;q=0.9,en-US;q=0.8,en;q=0.7",
        ["Accept-Encoding"] = "gzip, deflate, br, zstd",
        ["Origin"] = "https://clinic.bench.example.com",
        ["Referer"] = "https://clinic.bench.example.com" .. referer,
        ["sec-ch-ua"] = '"Google Chrome";v="141", "Not?A_Brand";v="8", "Chromium";v="141"',
        ["sec-ch-ua-mobile"] = "?0",
        ["sec-ch-ua-platform"] = '"macOS"',
        ["sec-fetch-dest"] = "empty",
        ["sec-fetch-mode"] = "cors",
        ["sec-fetch-site"] = "same-site",
    }
end

local all = "1,2,3,4,5,6,7,8,9,10"

local function between(r) return math.random(r[1], r[2]) end

function request()
    local r = math.random(100)
    local week = weeks[math.random(#weeks)]
    local view = "/schedule/week/" .. week[1] .. "?staff=" .. all
    if r <= 55 then
        local since = math.floor((os.time() * 1000 - epoch) / 60000) - math.random(0, 2)
        return wrk.format("GET", "/api/v2/schedule/version?since=" .. since, headers(view))
    elseif r <= 73 then
        local what = r <= 64 and "bookings" or "shifts"
        local q = "start=" .. week[1] .. "&end=" .. week[2] .. "&staff=" .. all
        if math.random(10) == 1 then
            local staff = math.random(10)
            q = "start=" .. month[1] .. "&end=" .. month[2] .. "&staff=" .. staff
            view = "/schedule/month/" .. month[1] .. "?staff=" .. staff
        end
        return wrk.format("GET", "/api/v2/schedule/" .. what .. "?" .. q, headers(view))
    elseif r <= 85 then
        local id = between(ranges.encounters)
        return wrk.format("GET", "/api/v2/encounters/" .. id, headers("/encounters/" .. id))
    elseif r <= 97 then
        local id = between(ranges.history)
        return wrk.format("GET", "/api/v2/clients/" .. id .. "/encounters?limit=20", headers("/clients/" .. id))
    end
    local id = between(ranges.clients)
    return wrk.format("GET", "/api/v2/clients/" .. id, headers("/clients/" .. id))
end

function done(summary, latency, requests)
    if summary.errors.status > 0 then
        io.write("tier-c: ", summary.errors.status, " responses not 2xx\n")
    end
end
