---@diagnostic disable: inject-field, undefined-field
module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")

require("core.packet_h")
require("program.hybrid_access.base.ring_queue_h")
local C = ffi.C

Delayer5 = {
    config = {
        -- delay in ms
        delay = { default = 30 },
        -- correction in ns (actual link delay)
        correction = { default = 0 }
    }
}

function Delayer5:new(conf)
    local o = {}
    o.delay = ffi.new("uint64_t", conf.delay * 1e6 - conf.correction)
    o.queue = C.buffer_new()

    print(string.format("%20s ms delay", lib.comma_value(conf.delay)))
    print(string.format("%20s ns corrected", lib.comma_value(conf.correction)))
    print(string.format("%20s ns actual delay", lib.comma_value(o.delay)))

    setmetatable(o, self)
    self.__index = self
    return o
end

function Delayer5:stop()
    C.buffer_free(self.queue)
end

function Delayer5:push()
    local iface_in = assert(self.input.input, "<input> (Input) not found")
    local iface_out = assert(self.output.output, "<output> (Output) not found")

    local current_time = C.get_time_ns()
    while C.buffer_peek_time(self.queue) <= current_time do
        local pkt = C.buffer_dequeue(self.queue)
        link.transmit(iface_out, pkt)
    end

    local sending_time = current_time + self.delay
    while not link.empty(iface_in) do
        local p = link.receive(iface_in)
        if C.buffer_enqueue(self.queue, p, sending_time) == 0 then
            packet.free(p)
            break;
        end
    end

    while not link.empty(iface_in) do
        local p = link.receive(iface_in)
        packet.free(p)
    end
end

function Delayer5:report()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(string.format("%20s queue length", lib.comma_value(C.buffer_size(self.queue))))
    print(string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets),
        lib.comma_value(input_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets),
            lib.comma_value(output_stats.txbytes)))
end
