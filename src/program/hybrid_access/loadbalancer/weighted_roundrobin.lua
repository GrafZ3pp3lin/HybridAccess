module(..., package.seeall)

local link = require("core.link")
local loadbalancer = require("program.hybrid_access.loadbalancer.loadbalancer")

WeightedRoundRobin = loadbalancer.LoadBalancer:new()
WeightedRoundRobin.config = {
    -- link bandwidths
    bandwidths = {required=true},
}

function WeightedRoundRobin:new(conf)
    print("Use weighted RoundRobin as Loadbalancer")
    local b1 = conf.bandwidths.output1
    local b2 = conf.bandwidths.output2
    local w1, w2 = 0, 0
    if b1 % b2 == 0 then
        w1 = b1 / b2
        w2 = w1 + 1
    elseif b2 % b1 == 0 then
        w1 = 1
        w2 = w1 + (b2 / b1)
    else
        error("bandwidths must be divisible without remainder")
    end
    local o = {
        index = 0,
        w1 = w1,
        w2 = w2
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function WeightedRoundRobin:push()
    local i = assert(self.input.input, "input port not found")
    local o1 = assert(self.output.output1, "output port 1 not found")
    local o2 = assert(self.output.output2, "output port 2 not found")

    while not link.empty(i) do
        self:process_packet(i, o1, o2)
    end
end

function WeightedRoundRobin:process_packet(i, o1, o2)
    local p = link.receive(i)
    if self.index < self.w1 then
        self:send_pkt(p, o1)
    elseif self.index < self.w2 then
        self:send_pkt(p, o2)
    else
        self.index = 0
        self:send_pkt(p, o1)
    end
    self.index = self.index + 1
end