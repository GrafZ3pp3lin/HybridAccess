module(..., package.seeall)

local engine = require("core.app")
local link = require("core.link")
local lib = require("core.lib")

local loadbalancer = require("program.hybrid_access.loadbalancer.loadbalancer")
local co = require("program.hybrid_access.base.constants")

local min, max = math.min, math.max
local tonumber = tonumber
local empty, receive = link.empty, link.receive

TokenBucketDDCSeries = loadbalancer.LoadBalancer:new()
TokenBucketDDCSeries.config = {
    -- bit rate
    rate            = { required = true },
    -- amount of tokens
    capacity        = { required = true },
    -- multiply rate by this percentage
    rate_percentage      = { default = 95 },
    -- multiply capacity by this percentage
    capacity_percentage      = { default = 99 },
    -- use layer 1 overhead
    layer1_overhead = { default = true },
    -- link where ddc packets should be send (link with higher one-way delay)
    ddc_link = { required = true },
    -- how long is one ddc packet valid
    ddc_cache = { required = false },
    -- loadbalancer setup
    setup    = { required = false }
}

function TokenBucketDDCSeries:new(conf)
    local rp = conf.rate_percentage / 100
    local cp = conf.capacity_percentage / 100
    -- local corrected_ddc_cache = {}
    -- for i, value in ipairs(conf.ddc_cache) do
    --     corrected_ddc_cache[i] = value / 1e9
    -- end
    local o = {
        byte_rate = math.floor((conf.rate * rp) / 8),
        capacity = math.floor(conf.capacity * cp),
        contingent = conf.capacity,
        additional_overhead = co.HA_HEADER_LEN,
        min_pkt_size = 64,
        ddc_link = conf.ddc_link,
        last_ddc_send = 0,
        -- ddc_cache = corrected_ddc_cache,
        -- last_ddc_time = {},
        class_type = "TokenBucket with minimal delay difference compensation"
    }
    if conf.layer1_overhead == true then
        o.additional_overhead = o.additional_overhead + 7 + 1 + 4 + 12
        o.min_pkt_size = 84
    end

    print(string.format("tokenbucket ddc: %20s byte/s (%f%%), %20s capacity (%f%%)", lib.comma_value(o.byte_rate), conf.rate_percentage, lib.comma_value(o.capacity), conf.capacity_percentage))

    setmetatable(o, self)
    self.__index = self
    o:setup(conf.setup)
    return o
end

function TokenBucketDDCSeries:push()
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

    -- local send_ddc_1 = (self.ddc_link == 1 or self.ddc_link == 0) and (self.last_ddc_time[1] or cur_now) + self.ddc_cache[1] <= cur_now
    -- local send_ddc_2 = (self.ddc_link == 2 or self.ddc_link == 0) and (self.last_ddc_time[2] or cur_now) + self.ddc_cache[2] <= cur_now
    local send_ddc_1 = self.ddc_link == 1 or self.ddc_link == 0
    local send_ddc_2 = self.ddc_link == 2 or self.ddc_link == 0

    while not empty(iface_in) do
        local p = receive(iface_in)
        local length = max(p.length + self.additional_overhead, self.min_pkt_size)

        if length <= self.contingent then
            self.contingent = self.contingent - length
            if self.last_ddc_send == 2 or send_ddc_2 == false then
                self:send_pkt(p, iface_out1)
            else
                self:send_pkt_with_ddc(p, iface_out1, iface_out2)
                self.last_ddc_send = 2
                -- send_ddc_2 = false
                -- self.last_ddc_time[2] = cur_now
            end
        elseif self.last_ddc_send == 1 or send_ddc_1 == false then
            self:send_pkt(p, iface_out2)
            break
        else
            self:send_pkt_with_ddc(p, iface_out2, iface_out1)
            self.last_ddc_send = 1
            -- send_ddc_1 = false
            -- self.last_ddc_time[1] = cur_now
            break
        end
    end
    while not empty(iface_in) do
        -- send rest of packages to output 2 - ddc packet was already send
        local p = receive(iface_in)
        self:send_pkt(p, iface_out2)
    end
end
