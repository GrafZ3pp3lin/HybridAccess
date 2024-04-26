module(..., package.seeall)

local bit = require("bit")
local lib = require("core.lib")
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
        if seq_num > self.index then
            -- print("received packet "..seq_num.." - expected: "..self.index)
            self.index = seq_num
        elseif seq_num < self.index then
            error("paket out of order: "..seq_num.." - expected: "..self.index)
        end
        packet.free(p)
        self.index = self.index + 1
    end
end

function OrderedSink:report ()
    local input_stats = link.stats(self.input.input)

    print(string.format("%20s packets received", lib.comma_value(input_stats.txpackets)))
    print(string.format("%20s bytes received", lib.comma_value(input_stats.txbytes)))
end
