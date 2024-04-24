module(..., package.seeall)

local bit = require("bit")
local link = require("core.link")
local packet = require("core.packet")

OrderedSink = {}

function OrderedSink:new ()
    local o = {
        index = 0,
    }
    setmetatable(o, self)
    self.__index = self
   return o
end

function OrderedSink:push ()
    local input = self.input.input
    for _ = 1, link.nreadable(input) do
        local p = link.receive(input)
        local seq_num = p.data[p.length - 1]
        seq_num = bit.bor(seq_num, bit.lshift(p.data[p.length - 2], 8))
        seq_num = bit.bor(seq_num, bit.lshift(p.data[p.length - 3], 16))
        seq_num = bit.bor(seq_num, bit.lshift(p.data[p.length - 4], 24))
        if (seq_num ~= self.index) then
            error("paket out of order: "..seq_num.." - expected: "..self.index)
        end
        packet.free(p)
        self.index = self.index + 1
    end
end
