module(..., package.seeall)

local lib = require("core.lib")
local link = require("core.link")
local packet = require("core.packet")
local counter = require("core.counter")
local expo = require("program.hybrid_access.base.exponential_dist")

PacketDropper = {
    config = {
        -- can be "nth", "prob"
        -- nth: every nth packet
        -- prob: probability of packet drop
        mode = {default="nth"},
        -- every value'th packet will be dropped (fix or probabilistic)
        value = {default=100}
    },
    shm = {
        dropped = {counter},
    }
}

function PacketDropper:new (conf)
    assert(conf.value > 1, "value has to be larger than 1")
    local o = {
        mode = 0,
        index = 0,
        next = 0,
    }
    if conf.mode == "nth" then
        o.mode = 1
        o.next = conf.value
    elseif conf.mode == "prob" then
        o.mode = 2
        o.dist = expo.Exponential:new(conf.value)
        o.next = o.dist:next()
    end
    setmetatable(o, self)
    self.__index = self
   return o
end

function PacketDropper:get_next()
    if self.mode == 1 then
        -- do nothing
    elseif self.mode == 2 then
        self.next = self.dist:next()
    else
        error("mode must be 'nth' or 'prob'")
    end
end

function PacketDropper:push ()
    local input = self.input.input
    local output = self.output.output

    for _ = 1, link.nreadable(input) do
        local p = link.receive(input)
        if self.index == self.next then
            counter.add(self.shm.dropped)
            packet.free(p)
            self:get_next()
            self.index = 0
        else
            link.transmit(output, p)
            self.index = self.index + 1
        end
    end
end

function PacketDropper:report ()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(string.format("%20s packets in", lib.comma_value(input_stats.rxpackets)))
    print(string.format("%20s packets out", lib.comma_value(output_stats.txpackets)))
    print(string.format("%20s packets dropped", lib.comma_value(counter.read(self.shm.dropped))))
end
