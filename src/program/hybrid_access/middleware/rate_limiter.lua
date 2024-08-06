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

local QUEUE_LENGTH = 65536 -- 65536 * 1500 = 100M -- 100M / 625MByte = 160ms

TBRateLimiter = {
    config = {
        -- bits per second
        rate             = { required = true },
        -- bucket capacity in byte (default 5000)
        bucket_capacity  = { default = 5000 },
        -- additional overhead per packet
        additional_overhead = { required = false },
        -- use layer 1 overhead
        layer1_overhead = { default = true },
        -- optional packet buffer
        buffer_capacity = { required = false },
        -- optional how much latency the buffer can cause in ns
        buffer_latency = { required = false }
    }
}

function TBRateLimiter:new(conf)
    assert(conf.buffer_capacity == nil or conf.buffer_latency == nil, "Buffer capacity and latency are exclusive")
    local byte_rate = math.floor(conf.rate / 8)
    if conf.buffer_latency ~= nil then
        conf.buffer_capacity = math.floor(byte_rate * (conf.buffer_latency / 1e9))
    end
    assert(conf.buffer_capacity < QUEUE_LENGTH * 1500, "buffer length is too high")
    local o =
    {
        byte_rate = byte_rate,
        bucket_capacity = conf.bucket_capacity,
        bucket_contingent = conf.bucket_capacity,
        buffer_capacity = conf.buffer_capacity,
        buffer_contingent = conf.buffer_capacity,
        additional_overhead = 0,
        -- txdrop = 0
    }
    if conf.additional_overhead ~= nil then
        o.additional_overhead = conf.additional_overhead
    elseif conf.layer1_overhead == true then
        o.additional_overhead = 7 + 1 + 4 + 12
    end
    if conf.buffer_capacity > 0 then
        o.buffer = buffer.PacketBuffer:new(QUEUE_LENGTH)
    end
    print(string.format("rate limiter: %20s byte/s, %20s capacity, %20s buffer, additional overhead %i", lib.comma_value(o.byte_rate), lib.comma_value(o.bucket_capacity), lib.comma_value(o.buffer_capacity), lib.comma_value(o.additional_overhead)))
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

    -- refill bucket by time since last call
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
        self:send_from_link(incoming, iface_in, iface_out)

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
        local p = self.buffer:peek()
        local length = p.length + self.additional_overhead
        if length <= self.bucket_contingent then
            self.buffer:dequeue()
            -- move packets from buffer to bucket
            self.bucket_contingent = self.bucket_contingent - length -- decrease bucket contigent
            self.buffer_contingent = self.buffer_contingent + length -- increase buffer continget
            transmit(iface_out, p)
        end
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
        elseif length <= self.buffer_contingent then
            -- check if packet can be buffered
            self.buffer_contingent = self.buffer_contingent - length
            self.buffer:enqueue(p)
        else
            -- discard packet
            -- self.txdrop = self.txdrop + 1
            free(p)
        end
    end
end

function TBRateLimiter:store_in_buffer(iface_in)
    local incoming = nreadable(iface_in)
    for _ = 1, incoming do
        local p = receive(iface_in)
        local length = p.length + self.additional_overhead
        if length <= self.buffer_contingent then
            -- check if packet can be buffered
            self.buffer_contingent = self.buffer_contingent - length
            self.buffer:enqueue(p)
        else
            -- discard packet
            -- self.txdrop = self.txdrop + 1
            free(p)
        end
    end
end

function TBRateLimiter:drop_incoming_packets(iface_in)
    local incoming = nreadable(iface_in)
    for _ = 1, incoming do
        local p = receive(iface_in)
        -- self.txdrop = self.txdrop + 1
        free(p)
    end
end
