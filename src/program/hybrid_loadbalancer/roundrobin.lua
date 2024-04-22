module(..., package.seeall)

local link = require("core.link")

RoundRobin = LoadBalancer:new()

function RoundRobin:new()
    local o = {
        flip = false
    }
    return setmetatable(o, {__index = RoundRobin})
 end

function RoundRobin:push()
    local i = assert(self.input.input, "input port not found")
    local o1 = assert(self.output.output1, "output port 1 not found")
    local o2 = assert(self.output.output2, "output port 2 not found")

    while not link.empty(i) do
        self:process_packet(i, o1, o2)
        self.sequence_number = self.sequence_number + 1
    end
end

function RoundRobin:process_packet(i, o1, o2)
    local p = link.receive(i)

    local header = {}

    if self.flip then
        link.transmit(o1, p)
    else
        link.transmit(o2, p)
    end
    self.flip = not self.flip
end