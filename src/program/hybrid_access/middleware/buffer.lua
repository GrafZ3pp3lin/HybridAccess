module(..., package.seeall)

local link = require("core.link")
local lib = require("core.lib")

local queue = require("program.hybrid_access.base.queue")

Buffer = {}

function Buffer:new()
    local o = {
        queue = queue.Queue:new(),
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
    local q_len = self.queue:size()

    local q_forward = math.min(q_len, o_len)
    for _ = 1, q_forward do
        local pkt = self.queue:pop()
        link.transmit(iface_out, pkt)
    end

    local i_forward = math.min(o_len - q_forward, i_len)
    for _ = 1, i_forward do
        local pkt = link.receive(iface_in)
        link.transmit(iface_out, pkt)
    end

    local remaining = i_len - i_forward
    for _ = 1, remaining do
        local pkt = link.receive(iface_in)
        self.queue:push(pkt)
    end
end

function Buffer:report()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets),
        lib.comma_value(input_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets),
            lib.comma_value(output_stats.txbytes)))
end