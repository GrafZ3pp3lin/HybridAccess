local ffi = require("ffi")

local longp = ffi.typeof("uint64_t *")
local cast, copy = ffi.cast, ffi.copy

local timestamp_marker = 0x55

function timestamp_to_pointer(timestamp)
    local ctp = cast(longp, timestamp)
    return ctp
end

function append_timestamp(pkt, tsp)
    pkt.data[pkt.length] = timestamp_marker
    copy(pkt.data + pkt.length + 1, tsp, 8)
end

function get_timestamp(pkt)
    if pkt.data[pkt.length] ~= timestamp_marker then
        return nil
    end
    return cast(longp, pkt.data + pkt.length + 1)
end