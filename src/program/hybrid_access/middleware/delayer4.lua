---@diagnostic disable: inject-field, undefined-field
module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")

local queue = require("program.hybrid_access.base.ring_queue")
local C = ffi.C

Delayer4 = {
    config = {
        -- delay in ms
        delay = { default = 30 },
        -- correction in ns (actual link delay)
        correction = { default = 0 }
    }
}

function Delayer4:new(conf)
    local o = {}
    o.delay = ffi.new("uint64_t", conf.delay * 1e6 - conf.correction)
    o.queue = queue.RingQueue:new()

    print(string.format("%20s ms delay", lib.comma_value(conf.delay)))
    print(string.format("%20s ns corrected", lib.comma_value(conf.correction)))
    print(string.format("%20s ns actual delay", lib.comma_value(o.delay)))

    setmetatable(o, self)
    self.__index = self
    return o
end

function Delayer4:push()
    local iface_in = assert(self.input.input, "<input> (Input) not found")
    local iface_out = assert(self.output.output, "<output> (Output) not found")

    local current_time = C.get_time_ns()
    while not self.queue:empty() and self.queue:front_time() <= current_time do
        local pkt = self.queue:pop()
        link.transmit(iface_out, pkt)        
    end

    local sending_time = current_time + self.delay
    while not link.empty(iface_in) and not self.queue:full() do
        local p = link.receive(iface_in)
        self.queue:push(p, sending_time)
    end

    while not link.empty(iface_in) do
        local p = link.receive(iface_in)
        packet.free(p)
    end
end

function Delayer4:report()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(string.format("%20s queue length", lib.comma_value(self.queue:nreadable())))
    print(string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets),
        lib.comma_value(input_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets),
            lib.comma_value(output_stats.txbytes)))
end
