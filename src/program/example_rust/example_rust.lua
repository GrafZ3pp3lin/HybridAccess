module(..., package.seeall)

local ffi = require('ffi')

ffi.cdef[[
    int32_t double_input(int32_t input);
]]

local lib = ffi.load('src/obj/program/example_rust/libdouble_input.so')
local double_input = lib.double_input

function run ()
   print(double_input(4))
end
