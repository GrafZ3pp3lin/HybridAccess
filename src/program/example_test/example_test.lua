module(..., package.seeall)

local ts = require("program.hybrid_access.base.timestamp")

local ffi = require('ffi')
local C = ffi.C

function run ()
    local time_now = C.get_time_ns()
    print(time_now)
    local ctp = tonumber(ffi.cast("uint64_t*", time_now))
    -- local time_now_p = ts.timestamp_to_pointer(time_now)
    print(ctp)
    print(ctp[0])
    print(time_now == ctp[0])
end
