module(..., package.seeall)

local engine = require("core.app")
local link = require("core.link")
local loadbalancer = require("program.hybrid_access.loadbalancer.loadbalancer")
local min = math.min

TokenBucketDDC = loadbalancer.LoadBalancer:new()
TokenBucketDDC.config = {
    rate     = { required = true },
    capacity = { required = true },
    setup    = { required = false }
}

function TokenBucketDDC:new(conf)
    local o = {
        byte_rate = math.floor(conf.rate / 8),
        capacity = conf.capacity,
        contingent = conf.capacity,
        class_type = "TokenBucket with delay difference compensation"
    }
    setmetatable(o, self)
    print(string.format("tokenbucket wrr: %20s byte/s, %20s capacity", o.byte_rate, o.capacity))
    self.__index = self
    o:setup(conf.setup)
    return o
end

function TokenBucketDDC:push()
    local i = assert(self.input.input, "input port not found")
    local o1 = assert(self.output.output1, "output port 1 not found")
    local o2 = assert(self.output.output2, "output port 2 not found")

    if link.empty(i) then
        return
    end

    local cur_now = tonumber(engine.now())
    local last_time = self.last_time or cur_now
    local interval = cur_now - last_time
    self.contingent = min(
        self.contingent + self.byte_rate * interval,
        self.capacity
    )
    self.last_time = cur_now

    for _ = 1, link.nreadable(i) do
        local p = link.receive(i)
        local length = p.length + self.additional_overhead

        if length <= self.contingent then
            self.contingent = self.contingent - length
            self:send_pkt_with_ddc(p, o1, o2)
        else
            self:send_pkt_with_ddc(p, o2, o1)
            break
        end
    end
    for _ = 1, link.nreadable(i) do
        -- send rest of packages to output 2
        local p = link.receive(i)
        self:send_pkt_with_ddc(p, o2, o1)
    end
end
