module(..., package.seeall)

local engine = require("core.app")
local link = require("core.link")
local lib = require("core.lib")

local loadbalancer = require("program.hybrid_access.loadbalancer.loadbalancer")
local co = require("program.hybrid_access.base.constants")

local min, max = math.min, math.max
local tonumber = tonumber
local empty, receive = link.empty, link.receive

TokenBucket = loadbalancer.LoadBalancer:new()
TokenBucket.config = {
    -- bit rate
    rate            = { required = true },
    -- amount of tokens
    capacity        = { required = true },
    -- multiply rate by this percentage
    rate_percentage      = { default = 99 },
    -- multiply capacity by this percentage
    capacity_percentage      = { default = 99 },
    -- use layer 1 overhead
    layer1_overhead = { default = true },
    -- loadbalancer setup
    setup           = { required = false }
}

function TokenBucket:new(conf)
    local rp = conf.rate_percentage / 100
    local cp = conf.capacity_percentage / 100
    local o = {
        byte_rate = math.floor((conf.rate * rp) / 8),
        capacity = math.floor(conf.capacity * cp),
        contingent = conf.capacity,
        additional_overhead = co.HA_HEADER_LEN,
        class_type = "TokenBucket"
    }
    if conf.layer1_overhead == true then
        o.additional_overhead = o.additional_overhead + 7 + 1 + 4 + 12
    end
    print(string.format("tokenbucket: %20s byte/s (%i%%), %20s capacity (%i%%)", lib.comma_value(o.byte_rate), conf.rate_percentage, lib.comma_value(o.capacity), conf.capacity_percentage))
    setmetatable(o, self)
    self.__index = self
    o:setup(conf.setup)
    return o
end

function TokenBucket:push()
    local iface_in = assert(self.input.input, "input port not found")
    local iface_out1 = assert(self.output.output1, "output port 1 not found")
    local iface_out2 = assert(self.output.output2, "output port 2 not found")

    if empty(iface_in) then
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

    while not empty(iface_in) do
        local p = receive(iface_in)
        local length = max(p.length, 60) + self.additional_overhead

        if length <= self.contingent then
            self.contingent = self.contingent - length
            self:send_pkt(p, iface_out1)
        else
            self:send_pkt(p, iface_out2)
            break
        end
    end
    while not empty(iface_in) do
        -- send rest of packages to output 2
        local p = receive(iface_in)
        self:send_pkt(p, iface_out2)
    end
end
