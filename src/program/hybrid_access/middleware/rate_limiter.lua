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
        txdrop = { counter },
    }
}

function TBRateLimiter:new(conf)
    conf.initial_capacity = conf.initial_capacity or conf.bucket_capacity
    local o =
    {
        byte_rate = math.floor(conf.rate / 8),
        bucket_capacity = conf.bucket_capacity,
        contingent = conf.initial_capacity
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
end

function TBRateLimiter:push()
    local i = assert(self.input.input, "input port not found")
    local o = assert(self.output.output, "output port not found")

    do
        local cur_now = tonumber(engine.now())
        local last_time = self.last_time or cur_now
        self.contingent = min(
            self.contingent + self.byte_rate * (cur_now - last_time),
            self.bucket_capacity
        )
        self.last_time = cur_now
    end


    while not link.empty(i) do
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
