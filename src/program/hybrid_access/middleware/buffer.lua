module(..., package.seeall)

local ffi = require("ffi")

local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")

require("core.packet_h")
require("program.hybrid_access.base.delay_buffer_h")

local C = ffi.C
local min = math.min
local receive, transmit = link.receive, link.transmit

Buffer = {}

function Buffer:new()
    local o = {
        buffer = C.buffer_new(),
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Buffer:push()
    local iface_in = assert(self.input.input, "<input> (Input) not found")
    local iface_out = assert(self.output.output, "<output> (Output) not found")

    local i_len = link.nreadable(iface_in)
    local o_len = link.nwritable(iface_out)
    local q_len = C.buffer_size(self.buffer)

    local q_forward = min(q_len, o_len)
    if q_forward > 0 then
        for _ = 1, q_forward do
            local pkt = C.buffer_dequeue(self.buffer)
            transmit(iface_out, pkt)
        end
    end

    local i_forward = min(o_len - q_forward, i_len)
    if i_forward > 0 then
        for _ = 1, i_forward do
            local pkt = receive(iface_in)
            transmit(iface_out, pkt)
        end
    end

    if not link.empty(iface_in) then
        while not link.empty(iface_in) do
            local pkt = receive(iface_in)
            if C.buffer_enqueue(self.buffer, pkt) == 0 then
                packet.free(pkt)
                break
            end
        end
        while not link.empty(iface_in) do
            local pkt = receive(iface_in)
            packet.free(pkt)
        end
    end
end

function Buffer:report()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(string.format("%20s buffer length", lib.comma_value(C.buffer_size(self.buffer))))
    print(string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets),
        lib.comma_value(input_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets),
            lib.comma_value(output_stats.txbytes)))
end