module(..., package.seeall)

local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")

local buffer = require("program.hybrid_access.base.buffer")

local min = math.min
local receive, transmit = link.receive, link.transmit

Buffer2 = {}

function Buffer2:new(size)
    local buf = buffer:new(size)
    local o = {
        buffer = buf,
        buffered = 0,
        tx_drop = 0,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Buffer2:push()
    local iface_in = assert(self.input.input, "<input> (Input) not found")
    local iface_out = assert(self.output.output, "<output> (Output) not found")

    local i_len = link.nreadable(iface_in)
    local o_len = link.nwritable(iface_out)
    local q_len = self.buffer:size()

    -- forward queued packets
    local q_forward = min(q_len, o_len)
    if q_forward > 0 then
        for _ = 1, q_forward do
            local pkt = self.buffer:dequeue()
            transmit(iface_out, pkt)
        end
    end

    -- forward incoming packets
    local i_forward = min(o_len - q_forward, i_len)
    if i_forward > 0 then
        for _ = 1, i_forward do
            local pkt = receive(iface_in)
            transmit(iface_out, pkt)
        end
    end

    -- queue incoming packets
    if not link.empty(iface_in) then
        while not link.empty(iface_in) do
            local pkt = receive(iface_in)
            if self.buffer:enqueue(pkt) == 0 then
                packet.free(pkt)
                self.tx_drop = self.tx_drop + 1
                break
            end
            self.buffered = self.buffered + 1
        end
        while not link.empty(iface_in) do
            local pkt = receive(iface_in)
            self.tx_drop = self.tx_drop + 1
            packet.free(pkt)
        end
    end
end

function Buffer2:report()
    print(string.format("%20s current buffer length", lib.comma_value(self.buffer:size())))
    print(string.format("%20s total buffered", lib.comma_value(self.buffered)))
    print(string.format("%20s dropped", lib.comma_value(self.tx_drop)))
end