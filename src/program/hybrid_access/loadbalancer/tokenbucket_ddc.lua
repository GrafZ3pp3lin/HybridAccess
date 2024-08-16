module(..., package.seeall)

local engine = require("core.app")
local link = require("core.link")
local lib = require("core.lib")

local loadbalancer = require("program.hybrid_access.loadbalancer.loadbalancer")
local co = require("program.hybrid_access.base.constants")

local min = math.min
local tonumber = tonumber
local empty, receive = link.empty, link.receive

TokenBucketDDC = loadbalancer.LoadBalancer:new()
TokenBucketDDC.config = {
    -- bit rate
    rate            = { required = true },
    -- amount of tokens
    capacity        = { required = true },
    -- multiply rate and capacity by this percentage
    percentage      = { default = 95 },
    -- use layer 1 overhead
    layer1_overhead = { default = true },
    -- loadbalancer setup
    setup    = { required = false }
}

function TokenBucketDDC:new(conf)
    local rp = conf.percentage / 100
    local o = {
        byte_rate = math.floor((conf.rate * rp) / 8),
        capacity = math.floor(conf.capacity * rp),
        contingent = conf.capacity,
        additional_overhead = co.HA_HEADER_LEN,
        class_type = "TokenBucket with delay difference compensation"
    }
    if conf.layer1_overhead == true then
        o.additional_overhead = o.additional_overhead + 7 + 1 + 4 + 12
    end

    print(string.format("tokenbucket ddc: %20s byte/s, %20s capacity", lib.comma_value(o.byte_rate), lib.comma_value(o.capacity)))

    setmetatable(o, self)
    self.__index = self
    o:setup(conf.setup)
    return o
end

function TokenBucketDDC:push()
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
        local length = min(p.length, 60) + self.additional_overhead

        if length <= self.contingent then
            self.contingent = self.contingent - length
            self:send_pkt_with_ddc(p, iface_out1, iface_out2)
        else
            self:send_pkt_with_ddc(p, iface_out2, iface_out1)
            break
        end
    end
    while not empty(iface_in) do
        -- send rest of packages to output 2
        local p = receive(iface_in)
        self:send_pkt_with_ddc(p, iface_out2, iface_out1)
    end
end
