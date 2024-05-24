module(..., package.seeall)

local lib = require("core.lib")
local link = require("core.link")
local engine = require("core.app")

local base = require("program.hybrid_access.base.base")

SimpleSink = {}

function SimpleSink:new()
    local o = {
        start = engine.now()
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function SimpleSink:push()
    local input = assert(self.input.input, "input port not found")
    for _ = 1, link.nreadable(input) do
        local p = link.receive(input)
        print(base.data_to_str(p.data, p.length))
        packet.free(p)
    end
end

function SimpleSink:file_report(f)
    local input_stats = link.stats(self.input.input)
    f:write(string.format("%20s # / %20s b received", lib.comma_value(input_stats.txpackets), lib.comma_value(input_stats.txbytes)), "\n")

    local now = engine.now()
    local runned_seconds = now - self.start
    local bytes_per_seconds = input_stats.txbytes / runned_seconds
    local bits_per_seconds = bytes_per_seconds * 8
    local mbits_per_seconds = bits_per_seconds / 1000000

    f:write(string.format("%20s s active\n", lib.comma_value(runned_seconds)))
    f:write(string.format("%20s B/s\n", lib.comma_value(bytes_per_seconds)))
    f:write(string.format("%20s bit/s\n", lib.comma_value(bits_per_seconds)))
    f:write(string.format("%20s Mbit/s\n", lib.comma_value(mbits_per_seconds)))
end
