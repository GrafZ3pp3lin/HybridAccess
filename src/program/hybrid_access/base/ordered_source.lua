module(..., package.seeall)

local ffi = require("ffi")
local bit = require("bit")
local engine = require("core.app")
local link = require("core.link")
local packet = require("core.packet")

OrderedSource = {}

function OrderedSource:new(size)
    size = tonumber(size) or 60
    local o = {
        index = 0,
        size = size
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function OrderedSource:pull ()
    local output = self.output.output
    for i = 1, engine.pull_npackets do
        local data = ffi.new("uint8_t[?]", self.size)
        data[self.size - 1] = bit.band(self.index, 0xff)
        data[self.size - 2] = bit.band(bit.rshift(self.index, 8), 0xff)
        data[self.size - 3] = bit.band(bit.rshift(self.index, 16), 0xff)
        data[self.size - 4] = bit.band(bit.rshift(self.index, 24), 0xff)
        local p = packet.from_pointer(data, self.size)
        link.transmit(output, p)
        self.index = self.index + 1
    end
end