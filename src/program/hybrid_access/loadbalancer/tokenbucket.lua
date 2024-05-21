module(..., package.seeall)

local engine = require("core.app")
local link = require("core.link")
local loadbalancer = require("program.hybrid_access.loadbalancer.loadbalancer")
local min = math.min

TokenBucket = loadbalancer.LoadBalancer:new()
TokenBucket.config = {
    rate     = { required = true },
    capacity = { required = true },
    setup    = { required = false }
}

function TokenBucket:new(conf)
    local o = {
        rate = conf.rate,
        capacity = conf.capacity,
        contingent = conf.capacity,
        class_type = "TokenBucket"
    }
    setmetatable(o, self)
    self.__index = self
    o:setup_headers(conf.setup)
    return o
end

function TokenBucket:push()
    local i = assert(self.input.input, "input port not found")
    local o1 = assert(self.output.output1, "output port 1 not found")
    local o2 = assert(self.output.output2, "output port 2 not found")

    do
        local cur_now = tonumber(engine.now())
        local last_time = self.last_time or cur_now
        self.contingent = min(
            self.contingent + self.rate * (cur_now - last_time),
            self.capacity
        )
        self.last_time = cur_now
    end

    while not link.empty(i) do
        self:process_packet(i, o1, o2)
    end
end

function TokenBucket:process_packet(i, o1, o2)
    local p = link.receive(i)
    local length = p.length

    if length <= self.contingent then
        self.contingent = self.contingent - length
        self:send_pkt(p, o1)
    else
        self:send_pkt(p, o2)
    end
end
