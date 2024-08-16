module(..., package.seeall)

local link = require("core.link")
local loadbalancer = require("program.hybrid_access.loadbalancer.loadbalancer")

local empty, receive = link.empty, link.receive

WeightedRoundRobin = loadbalancer.LoadBalancer:new()
WeightedRoundRobin.config = {
    -- link bandwidths
    bandwidths = { required = true },
    setup = { required = false }
}

function WeightedRoundRobin:new(conf)
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
    print(string.format("weighted roundrobin: %i link1 / %i link2", w1, w2 - w1))
    local o = {
        index = 0,
        w1 = w1,
        w2 = w2,
        class_type = "WeightedRoundRobin"
    }
    setmetatable(o, self)
    self.__index = self
    o:setup(conf.setup)
    return o
end

function WeightedRoundRobin:push()
    local iface_in = assert(self.input.input, "input port not found")
    local iface_out1 = assert(self.output.output1, "output port 1 not found")
    local iface_out2 = assert(self.output.output2, "output port 2 not found")

    while not empty(iface_in) do
        local p = receive(iface_in)
        if self.index < self.w1 then
            self:send_pkt(p, iface_out1)
        elseif self.index < self.w2 then
            self:send_pkt(p, iface_out2)
        else
            self.index = 0
            self:send_pkt(p, iface_out1)
        end
        self.index = self.index + 1
    end
end
