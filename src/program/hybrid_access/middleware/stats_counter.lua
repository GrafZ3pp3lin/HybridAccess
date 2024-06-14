module(..., package.seeall)

local lib = require("core.lib")
local link = require("core.link")
local counter = require("core.counter")

StatsCounter = {}
StatsCounter.config = {
    -- name of stats counter
    name = { required = false }
}
StatsCounter.shm = {
    txdrop_packets = { counter },
    txdrop = { counter }
}

function StatsCounter:new(conf)
    local o = {
        name = conf.name or ""
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function StatsCounter:report()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(
        string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets), lib.comma_value(input_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets),
            lib.comma_value(output_stats.txbytes)))
    print(string.format("%20s overflow packets", lib.comma_value(counter.read(self.shm.txdrop_packets))))
    print(string.format("%20s overflows", lib.comma_value(counter.read(self.shm.txdrop))))
end

function StatsCounter:push()
    local input = assert(self.input.input, "input port not found")
    local output = assert(self.output.output, "output port not found")

    local nRead = link.nreadable(input)
    local nWrite = link.nwritable(output)
    local overflow = nRead - nWrite

    if overflow then
        counter.add(self.shm.txdrop, 1)
        counter.add(self.shm.txdrop_packets, overflow)
    end

    for _ = 1, nRead do
        local p = link.receive(input)
        link.transmit(output, p)
    end
end