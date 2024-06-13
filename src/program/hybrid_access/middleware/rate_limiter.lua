-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")
local link = require("core.link")
local packet = require("core.packet")
local counter = require("core.counter")
local lib = require("core.lib")

local min = math.min

TBRateLimiter = {
    config = {
        -- bits per second
        rate             = { required = true },
        -- bucket capacity in byte (default 5000)
        bucket_capacity  = { default = 5000 },
        -- initial capacity in bucket (eg 3000)
        initial_capacity = { required = false }
    },
    shm = {
        txdrop = { counter }
    }
}

function TBRateLimiter:new(conf)
    conf.initial_capacity = conf.initial_capacity or conf.bucket_capacity
    local o =
    {
        byte_rate = math.floor(conf.rate / 8),
        bucket_capacity = conf.bucket_capacity,
        contingent = conf.initial_capacity,
        last_link_empty = true,
        push_amount = 0,
        push_interval = 0
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function TBRateLimiter:report()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(
        string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets), lib.comma_value(input_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets),
            lib.comma_value(output_stats.txbytes)))
    print(string.format("%20s packets dropped", lib.comma_value(counter.read(self.shm.txdrop))))
    print(string.format("%20s delay between pushes (%s / %s)", lib.comma_value(self.push_interval / self.push_amount),
        lib.comma_value(self.push_interval), lib.comma_value(self.push_amount)))
end

function TBRateLimiter:push()
    local i = assert(self.input.input, "input port not found")
    local o = assert(self.output.output, "output port not found")

    local cur_now = tonumber(engine.now())
    local last_time = self.last_time or cur_now
    local interval = cur_now - last_time

    if link.empty(i) then
        if not self.last_link_empty then
            self.push_amount = self.push_amount + 1
            self.push_interval = self.push_interval + interval
        end
        self.last_link_empty = true
        return
    end

    self.contingent = min(
        self.contingent + self.byte_rate * interval,
        self.bucket_capacity
    )
    self.last_time = cur_now

    if not self.last_link_empty then
        self.push_amount = self.push_amount + 1
        self.push_interval = self.push_interval + interval
    end
    self.last_link_empty = false

    for _ = 1, link.nreadable(i) do
        local p = link.receive(i)
        local length = p.length

        if length <= self.contingent then
            self.contingent = self.contingent - length
            link.transmit(o, p)
        else
            -- discard packet
            counter.add(self.shm.txdrop)
            packet.free(p)
        end
    end
end
