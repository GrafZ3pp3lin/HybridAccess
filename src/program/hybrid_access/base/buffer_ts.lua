module(..., package.seeall)

local ffi = require("ffi")
local bit = require("bit")

require("core.packet_h")

ffi.cdef[[
struct ts_packet
{
    struct packet *packet;
    uint64_t timestamp;
};
]]

local band = bit.band

PacketWithTimestampBuffer = {}

function PacketWithTimestampBuffer:new(size)
    assert(band(size, (size - 1)) == 0, "size must be a power of two")
    local buf = ffi.new("struct ts_packet *[?]", size)
    local o = {
        buffer = buf,
        read = 0,
        write = 0,
        max = size,
        max_pkt = size - 1,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function PacketWithTimestampBuffer:size()
    if self.write >= self.read then
        return self.write - self.read
    end
    return self.write + self.max - self.read
end

function PacketWithTimestampBuffer:space()
    return self.max_pkt - self:size()
end

function PacketWithTimestampBuffer:is_empty()
    return self.write == self.read;
end

function PacketWithTimestampBuffer:is_full()
    return band(self.write + 1, self.max_pkt) == self.read;
end

function PacketWithTimestampBuffer:dequeue()
    -- assert not empty
    local ts_pkt = self.buffer[self.read]
    self.read = band(self.read + 1, self.max_pkt)
    return ts_pkt;
end

function PacketWithTimestampBuffer:peek()
    -- assert not empty
    local ts_pkt = self.buffer[self.read]
    return ts_pkt;
end

function PacketWithTimestampBuffer:enqueue(pkt, timestamp)
    if self:is_full() then
        return 0
    end
    self.buffer[self.write].packet = pkt;
    self.buffer[self.write].timestamp = timestamp;
    self.write = band(self.write + 1, self.max_pkt)

    return 1;
end