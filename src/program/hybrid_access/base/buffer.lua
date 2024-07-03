module(..., package.seeall)

local ffi = require("ffi")
local bit = require("bit")

require("core.packet_h")

local band = bit.band

PacketBuffer = {}

function PacketBuffer:new(size)
    assert(band(size, (size - 1)) == 0, "size must be a power of two")
    local buf = ffi.new("struct packet *[?]", size)
    local o = {
        buffer = buf,
        read = 0,
        write = 0,
        max = size
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function PacketBuffer:size()
    if self.write >= self.read then
        return self.write - self.read
    end
    return self.write + self.max - self.read
end

function PacketBuffer:is_full()
    return band(self.write + 1, self.max - 1) == self.read;
end

function PacketBuffer:dequeue()
    -- assert not empty
    local pkt = self.buf[self.read]
    self.read = band(self.read + 1, self.max - 1)
    return pkt;
end

function PacketBuffer:enqueue(pkt)
    if self:is_full() then
        return 0
    end
    self.buffer[self.write] = pkt;
    self.write = band(self.write, self.max - 1)

    return 1;
end