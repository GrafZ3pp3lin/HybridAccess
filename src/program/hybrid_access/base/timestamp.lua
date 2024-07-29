---@diagnostic disable: inject-field, param-type-mismatch, undefined-field
local ffi = require("ffi")

local cast, copy = ffi.cast, ffi.copy

local pkt_timestamp = ffi.typeof([[
   struct {
      uint8_t  marker;
      uint64_t timestamp;
   } __attribute__((packed))
]])
local pkt_timestamp_p = ffi.typeof("$*", pkt_timestamp)
local pkt_timestamp_len = ffi.sizeof(pkt_timestamp)

local timestamp_marker = 0x55

function timestamp_to_pointer(timestamp)
    local obj = ffi.new(pkt_timestamp)
    obj.marker = timestamp_marker
    obj.timestamp = timestamp
    local obj_p = cast(pkt_timestamp_p, obj)
    return obj_p
end

function append_timestamp(pkt, tsp)
    copy(pkt.data + pkt.length, tsp, pkt_timestamp_len)
end

function get_timestamp(pkt)
    local obj_p = cast(pkt_timestamp_p, pkt.data + pkt.length)
    if obj_p.marker ~= timestamp_marker then
        return nil
    else
        return obj_p.timestamp
    end
end