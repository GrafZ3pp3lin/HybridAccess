---@diagnostic disable: inject-field, undefined-field
module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")

require("core.packet_h")
require("program.hybrid_access.base.delay_buffer_h")

local C = ffi.C

local min = math.min
local transmit, receive, empty, nwritable = link.transmit, link.receive, link.empty, link.nwritable
local free = packet.free

DelayerWithCBuffer = {
    config = {
        -- delay in ns
        delay = { default = 30e6 },
        -- correction in ns (actual link delay)
        correction = { default = 0 }
    }
}

function DelayerWithCBuffer:new(conf)
    local o = {
        tx_drop = 0,
    }
    o.delay = ffi.new("uint64_t", conf.delay - conf.correction)
    o.queue = C.db_new()

    print(string.format("delay: %s - %s = %s", lib.comma_value(conf.delay), lib.comma_value(conf.correction),
        lib.comma_value(o.delay)))

    setmetatable(o, self)
    self.__index = self
    return o
end

function DelayerWithCBuffer:stop()
    C.db_free(self.queue)
end

function DelayerWithCBuffer:push()
    local iface_in = assert(self.input.input, "<input> (Input) not found")
    local iface_out = assert(self.output.output, "<output> (Output) not found")

    -- forward all packets where the delay is reached
    local current_time = C.get_time_ns()
    local max_packets_to_forward = min(C.db_size(self.queue), nwritable(iface_out))
    for _ = 1, max_packets_to_forward do
        if C.db_peek_time(self.queue) <= current_time then
            local pkt = C.db_dequeue(self.queue)
            transmit(iface_out, pkt)
        else
            break
        end
    end

    -- discard all packets that dont fit on the link
    while C.db_peek_time(self.queue) <= current_time do
        local pkt = C.db_dequeue(self.queue)
        free(pkt)
    end

    -- put new packets on the link as long as there is space
    local sending_time = current_time + self.delay
    while not empty(iface_in) do
        local p = receive(iface_in)
        if C.db_enqueue(self.queue, p, sending_time) == 0 then
            free(p)
            self.tx_drop = self.tx_drop + 1 -- COUNTER
            break;
        end
    end

    -- discard other incoming packets
    while not empty(iface_in) do
        local p = receive(iface_in)
        free(p)
        self.tx_drop = self.tx_drop + 1 -- COUNTER
    end
end

function DelayerWithCBuffer:report()
    print(string.format("%20s current buffer length", lib.comma_value(C.db_size(self.queue))))
    print(string.format("%20s dropped", lib.comma_value(self.tx_drop)))
end
