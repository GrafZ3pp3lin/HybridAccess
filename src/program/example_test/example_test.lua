module(..., package.seeall)

local ts = require("program.hybrid_access.base.timestamp")

local ffi = require('ffi')
local C = ffi.C

function run ()
    local time_now = C.get_time_ns()
    print(time_now)
    local long = ffi.new("uint64_t", 0)
    print(long)
    local lp = ffi.cast("uint64_t*", long)
    local ctp = ffi.cast("uint64_t*", time_now)
    -- local time_now_p = ts.timestamp_to_pointer(time_now)
    print(ctp)
    -- print(ctp[0])
    -- print(time_now == ctp[0])
    ffi.copy(lp, ctp, 8)
    print(long)
end
