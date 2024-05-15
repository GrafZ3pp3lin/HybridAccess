module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
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
        local seq_num = ffi.cast("uint32_t*", data + self.size - 4)
        seq_num[0] = lib.htonl(self.index)
        local p = packet.from_pointer(data, self.size)
        link.transmit(output, p)
        self.index = self.index + 1
    end
end

function OrderedSource:report ()
    local output_stats = link.stats(self.output.output)

    print(string.format("%20s packets generated", lib.comma_value(output_stats.txpackets)))
    print(string.format("%20s bytes generated", lib.comma_value(output_stats.txbytes)))
end