module(..., package.seeall)

local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")

local buffer = require("program.hybrid_access.base.buffer")

local min = math.min
local receive, transmit, empty, nreadable, nwritable = link.receive, link.transmit, link.empty, link.nreadable, link.nwritable
local free = packet.free

Buffer = {}

function Buffer:new(size)
    local o = {
        -- buffered = 0,
        -- tx_drop = 0,
    }
    o.buffer = buffer.PacketBuffer:new(size)
    setmetatable(o, self)
    self.__index = self
    return o
end

function Buffer:push()
    local iface_in = assert(self.input.input, "<input> (Input) not found")
    local iface_out = assert(self.output.output, "<output> (Output) not found")

    local link_len = nreadable(iface_in)
    local out_len = nwritable(iface_out)
    local queue_len = self.buffer:size()

    -- forward queued packets
    local queue_forward = min(queue_len, out_len)
    if queue_forward > 0 then
        for _ = 1, queue_forward do
            local pkt = self.buffer:dequeue()
            transmit(iface_out, pkt)
        end
    end

    -- forward incoming packets
    local link_forward = min(out_len - queue_forward, link_len)
    if link_forward > 0 then
        for _ = 1, link_forward do
            local pkt = receive(iface_in)
            transmit(iface_out, pkt)
        end
    end

    -- queue incoming packets
    if not empty(iface_in) then
        while not empty(iface_in) do
            local pkt = receive(iface_in)
            if self.buffer:enqueue(pkt) == 0 then
                free(pkt)
                -- self.tx_drop = self.tx_drop + 1 -- COUNTER
                break
            end
            -- self.buffered = self.buffered + 1 -- COUNTER
        end
        while not empty(iface_in) do
            local pkt = receive(iface_in)
            -- self.tx_drop = self.tx_drop + 1 -- COUNTER
            free(pkt)
        end
    end
end

function Buffer:report()
    local iface_in = assert(self.input.input, "<input> (Input) not found")
    local iface_out = assert(self.output.output, "<output> (Output) not found")

    print(string.format("%20s current buffer length", lib.comma_value(self.buffer:size())))
    print(string.format("%20s total buffered", lib.comma_value(self.buffered)))
    print(string.format("%20s dropped", lib.comma_value(self.tx_drop)))
    print(string.format("%20s output readable", lib.comma_value(nreadable(iface_out))))
    print(string.format("%20s input readable", lib.comma_value(nreadable(iface_in))))
end