-- wrk -s scripts/pipeline.lua URL -- DEPTH sends DEPTH requests in each
-- write, as TechEmpower's plaintext test does with 16.
init = function(args)
  local depth = tonumber(args[1]) or 1
  local r = {}
  for i = 1, depth do
    r[i] = wrk.format()
  end
  req = table.concat(r)
end

request = function()
  return req
end
