---@diagnostic disable: undefined-field, inject-field
module(..., package.seeall)

local ts = require("program.hybrid_access.base.timestamp")

local ffi = require('ffi')
local C = ffi.C

local test_struct = ffi.typeof([[
   struct {
      uint8_t  marker;
      uint64_t timestamp;
   } __attribute__((packed))
]])
local test_struct_p = ffi.typeof("$*", test_struct)

function run ()
    local time_now = C.get_time_ns()
    print(time_now)
    local obj_p = ts.timestamp_to_pointer(time_now)
    -- local time_now_p = ts.timestamp_to_pointer(time_now)
    print(obj_p.timestamp)
    -- print(ctp[0])
    -- print(time_now == ctp[0])
    local strct2 = ffi.new(test_struct)
    local lp2 = ffi.cast(test_struct_p, strct2)
    print(lp2.timestamp)
    ffi.copy(lp2, obj_p, 9)
    print(lp2.timestamp)
end
