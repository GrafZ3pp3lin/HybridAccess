-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")
local link = require("core.link")
local packet = require("core.packet")
local lib = require("core.lib")

local buffer = require("program.hybrid_access.base.buffer")

local min, ceil = math.min, math.ceil
local tonumber = tonumber
local receive, transmit, nreadable, nwritable = link.receive, link.transmit, link.nreadable, link.nwritable
local free = packet.free

TBRateLimiter = {
    config = {
        -- bits per second
        rate             = { required = true },
        -- bucket capacity in byte (default 5000)
        bucket_capacity  = { default = 5000 },
        -- initial capacity in bucket (eg 3000)
        initial_capacity = { required = false },
        -- take preamble, start frame delimiter and ipg into account
        respect_layer1_overhead = { default = true },
        -- optional packet buffer
        buffer_capacity = { default = 0 },
    }
}

function TBRateLimiter:new(conf)
    conf.initial_capacity = conf.initial_capacity or conf.bucket_capacity
    local o =
    {
        byte_rate = math.floor(conf.rate / 8),
        bucket_capacity = conf.bucket_capacity,
        bucket_contingent = conf.initial_capacity,
        buffer_capacity = conf.buffer_capacity,
        buffer_contingent = conf.buffer_capacity,
        additional_overhead = 0,
        txdrop = 0,
        txbuffer = 0
    }
    if conf.respect_layer1_overhead == true then
        o.additional_overhead = 7 + 1 + 4 + 12
    end
    if conf.buffer_capacity > 0 then
        o.buffer = buffer.PacketBuffer:new(65536)
    end
    print(string.format("rate limiter: %20s byte/s, %20s capacity, %20s buffer", lib.comma_value(o.byte_rate), lib.comma_value(o.bucket_capacity), lib.comma_value(o.buffer_capacity)))
    setmetatable(o, self)
    self.__index = self
    return o
end

function TBRateLimiter:report()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets), lib.comma_value(input_stats.txbytes)))
    print(string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets), lib.comma_value(output_stats.txbytes)))
    print(string.format("%20s dropped", lib.comma_value(self.txdrop)))
    print(string.format("%20s buffered total", lib.comma_value(self.txbuffer)))
    print(string.format("%20s buffered current", lib.comma_value(self.buffer:size())))
    print(string.format("%20s buffer contingent", lib.comma_value(self.buffer_contingent)))
    print(string.format("%20s bucket contingent", lib.comma_value(self.bucket_contingent)))
end

function TBRateLimiter:push()
    local iface_in = assert(self.input.input, "input port not found")
    local iface_out = assert(self.output.output, "output port not found")

    -- check if packets exists - otherwise return here
    local buffer_size = 0
    if self.buffer ~= nil then
        buffer_size = self.buffer:size()
    end
    local incoming = link.nreadable(iface_in)
    if incoming == 0 and buffer_size == 0 then
        return
    end

    -- fill up bucket
    local cur_now = tonumber(engine.now())
    local last_time = self.last_time or cur_now
    local interval = cur_now - last_time
    self.bucket_contingent = min(
        self.bucket_contingent + ceil(self.byte_rate * interval),
        self.bucket_capacity
    )
    self.last_time = cur_now

    -- send packets from buffer
    if buffer_size > 0 then
        self:send_from_buffer(buffer_size, iface_out)
    end

    -- receive packets from link
    if incoming > 0 then
        local p = self:send_from_link(incoming, iface_in, iface_out) -- returns optional packet from link that can not be forwarded
        if p then
            local length = p.length + self.additional_overhead
            if length <= self.buffer_contingent then
                self.buffer_contingent = self.buffer_contingent - length
                self.buffer:enqueue(p)
                self.txbuffer = self.txbuffer + 1
            else
                -- discard packet
                self.txdrop = self.txdrop + 1
                free(p)
            end
        end

        -- store incoming packets in buffer
        if self.buffer_contingent > 0 then
            self:store_in_buffer(iface_in)
        end

        -- discard all remaining/out of band packets
        self:drop_incoming_packets(iface_in)
    end
end

function TBRateLimiter:send_from_buffer(buffer_size, iface_out)
    -- send from buffer
    local send_from_buffer = min(buffer_size, nwritable(iface_out))
    for _ = 1, send_from_buffer do
        local pkt = self.buffer:dequeue()
        local length = pkt.length + self.additional_overhead
        self.buffer_contingent = self.buffer_contingent + length
        transmit(iface_out, pkt)
    end
end

function TBRateLimiter:send_from_link(incoming, iface_in, iface_out)
    -- send from buffer
    local send_from_link = min(incoming, nwritable(iface_out))
    for _ = 1, send_from_link do
        local p = receive(iface_in)
        local length = p.length + self.additional_overhead
        if length <= self.bucket_contingent then
            self.bucket_contingent = self.bucket_contingent - length
            transmit(iface_out, p)
        else
            return p
        end
    end
end

function TBRateLimiter:store_in_buffer(iface_in)
    local incoming = nreadable(iface_in)
    for _ = 1, incoming do
        local p = receive(iface_in)
        local length = p.length + self.additional_overhead
        if length <= self.buffer_contingent then
            self.buffer_contingent = self.buffer_contingent - length
            self.buffer:enqueue(p)
            self.txbuffer = self.txbuffer + 1
        else
            -- discard packet
            self.txdrop = self.txdrop + 1
            free(p)
        end
    end
end

function TBRateLimiter:drop_incoming_packets(iface_in)
    local incoming = nreadable(iface_in)
    for _ = 1, incoming do
        local p = receive(iface_in)
        self.txdrop = self.txdrop + 1
        free(p)
    end
end
