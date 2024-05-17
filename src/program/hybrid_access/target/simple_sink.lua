module(..., package.seeall)

local lib = require("core.lib")
local link = require("core.link")

SimpleSink = {}

function SimpleSink:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function SimpleSink:push()
    local input = assert(self.input.input, "input port not found")
    for _ = 1, link.nreadable(input) do
        local p = receive(input)
        packet.free(p)
    end
end

function SimpleSink:report ()
    local input_stats = link.stats(self.input.input)
    print(string.format("%20s packets received", lib.comma_value(input_stats.txpackets)))
    print(string.format("%20s bytes received", lib.comma_value(input_stats.txbytes)))
end
