---@diagnostic disable: inject-field, undefined-field
module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")

require("core.packet_h")
require("program.hybrid_access.base.delay_buffer_h")
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
    local o = {
        tx_drop = 0,
    }
    o.delay = ffi.new("uint64_t", conf.delay * 1e6 - conf.correction)
    o.queue = C.db_new()

    print(string.format("delay: %se6 - %s = %s", lib.comma_value(conf.delay), lib.comma_value(conf.correction), lib.comma_value(o.delay)))

    setmetatable(o, self)
    self.__index = self
    return o
end

function Delayer5:stop()
    C.db_free(self.queue)
end

function Delayer5:push()
    local iface_in = assert(self.input.input, "<input> (Input) not found")
    local iface_out = assert(self.output.output, "<output> (Output) not found")

    local current_time = C.get_time_ns()
    while C.db_peek_time(self.queue) <= current_time do
        local pkt = C.db_dequeue(self.queue)
        link.transmit(iface_out, pkt)
    end

    local sending_time = current_time + self.delay
    while not link.empty(iface_in) do
        local p = link.receive(iface_in)
        if C.db_enqueue(self.queue, p, sending_time) == 0 then
            packet.free(p)
            self.tx_drop = self.tx_drop + 1
            break;
        end
    end

    while not link.empty(iface_in) do
        local p = link.receive(iface_in)
        packet.free(p)
        self.tx_drop = self.tx_drop + 1
    end
end

function Delayer5:report()
    print(string.format("%20s current buffer length", lib.comma_value(C.db_size(self.queue))))
    print(string.format("%20s dropped", lib.comma_value(self.tx_drop)))
end
