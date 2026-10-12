-- wrk's request mix for the REST benchmark's tier D (task 021), writes with
-- large bodies, in two roles that run as two wrk processes at once, so that
-- the uploads come from a fixed eighth of the connections:
--
--   uploads: an attachment of 100 KB to 1 MB two times in three, and a CSV
--            import of 2-8 MB, chunked, the third; about 20% and 10% of
--            tier D's requests
--   forms:   a batch of bookings of 200-500 KB four times in seven, and a
--            form of 2-8 KB the other three; about 40% and 30%
--
-- Each request carries one of tier C's bearer tokens.
--
--   wrk -t 1 -c 32 -d 15 -s bench/rest/tier-d.lua http://127.0.0.1:PORT -- DATADIR uploads &
--   wrk -t 6 -c 224 -d 15 -s bench/rest/tier-d.lua http://127.0.0.1:PORT -- DATADIR forms
--
-- DATADIR holds the generator's writes-load.txt and its bodies, and
-- heavy-load.txt for the tokens; build/rest by default. A quarter of the
-- batches have invalid bookings, which are answered 422, so wrk counts
-- about a seventh of the forms role's responses as errors.

local imports, attachments, batches, forms = {}, {}, {}, {}
local thread_id = 0

function setup(thread)
    thread_id = thread_id + 1
    thread:set("seed", thread_id)
end

local function slurp(path)
    local f = assert(io.open(path, "rb"), "no " .. path .. "; run bench/rest/gen.goose")
    local data = f:read("*a")
    f:close()
    return data
end

-- body in chunks of 64 KB, as an import tool streams a file.
local function chunked(body)
    local out = {}
    for k = 1, #body, 65536 do
        local piece = body:sub(k, k + 65535)
        out[#out + 1] = string.format("%x\r\n", #piece) .. piece .. "\r\n"
    end
    out[#out + 1] = "0\r\n\r\n"
    return table.concat(out)
end

function init(args)
    math.randomseed(seed)
    local dir = args[1] or "build/rest"
    role = args[2] or "forms"
    local token
    for line in io.lines(dir .. "/heavy-load.txt") do
        local kind, value = line:match("([^\t]+)\t([^\t]+)")
        if kind == "token" then
            token = "Bearer " .. value
            break
        end
    end
    local function headers(ctype)
        return {
            ["Authorization"] = token,
            ["Content-Type"] = ctype,
            ["User-Agent"] = "import-tool/2.4",
            ["Accept"] = "application/json",
        }
    end
    for line in io.lines(dir .. "/writes-load.txt") do
        local kind, name, boundary = line:match("([^\t]+)\t([^\t]+)\t?([^\t]*)")
        if role == "uploads" and kind == "import" then
            local h = headers("text/csv")
            h["Transfer-Encoding"] = "chunked"
            imports[#imports + 1] = wrk.format("POST", "/api/v3/imports", h) .. chunked(slurp(dir .. "/" .. name))
        elseif role == "uploads" and kind == "attachment" then
            attachments[#attachments + 1] = wrk.format("POST", "/api/v3/attachments",
                headers("multipart/form-data; boundary=" .. boundary), slurp(dir .. "/" .. name))
        elseif role == "forms" and kind == "batch" then
            batches[#batches + 1] = wrk.format("POST", "/api/v3/bookings/batch", headers("application/json"),
                slurp(dir .. "/" .. name))
        elseif role == "forms" and kind == "form" then
            forms[#forms + 1] = wrk.format("POST", "/api/v3/forms",
                headers("application/x-www-form-urlencoded"), slurp(dir .. "/" .. name))
        end
    end
    assert(role == "uploads" or role == "forms", "the role is uploads or forms")
end

function request()
    if role == "uploads" then
        if math.random(3) <= 2 then return attachments[math.random(#attachments)] end
        return imports[math.random(#imports)]
    end
    if math.random(7) <= 4 then return batches[math.random(#batches)] end
    return forms[math.random(#forms)]
end

function done(summary, latency, requests)
    if summary.errors.status > 0 then
        io.write("tier-d: ", summary.errors.status, " responses not 2xx, the invalid batches' 422s among them\n")
    end
end
