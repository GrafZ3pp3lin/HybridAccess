module(..., package.seeall)

local link = require("core.link")
local loadbalancer = require("program.hybrid_access.loadbalancer.loadbalancer")

RoundRobin = loadbalancer.LoadBalancer:new()

function RoundRobin:new()
    print("Use RoundRobin as Loadbalancer")
    local o = {
        flip = false
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function RoundRobin:push()
    local i = assert(self.input.input, "input port not found")
    local o1 = assert(self.output.output1, "output port 1 not found")
    local o2 = assert(self.output.output2, "output port 2 not found")

    while not link.empty(i) do
        self:process_packet(i, o1, o2)
    end
end

function RoundRobin:process_packet(i, o1, o2)
    local p = link.receive(i)
    if self.flip then
        self:send_pkt(p, o1)
    else
        self:send_pkt(p, o2)
    end
    self.flip = not self.flip
end