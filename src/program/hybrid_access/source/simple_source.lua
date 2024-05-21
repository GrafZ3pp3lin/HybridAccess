module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local engine = require("core.app")
local link = require("core.link")

SimpleSource = {}

function SimpleSource:new(size)
    size = tonumber(size) or 60
    local data = ffi.new("uint8_t[?]", size)
    local p = packet.from_pointer(data, size)
    local o = {
        packet = p
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function SimpleSource:pull()
    local output = assert(self.output.output, "output port not found")

    for _ = 1, engine.pull_npackets do
        link.transmit(output, packet.clone(self.packet))
    end
end

function SimpleSource:stop()
    packet.free(self.packet)
end

function SimpleSource:file_report(f)
    local output_stats = link.stats(self.output.output)
    f:write(string.format("%20s packets generated", lib.comma_value(output_stats.txpackets)), "\n")
    f:write(string.format("%20s bytes generated", lib.comma_value(output_stats.txbytes)), "\n")
end
