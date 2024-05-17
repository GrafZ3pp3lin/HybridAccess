module(..., package.seeall)

local ffi = require("ffi")
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

function OrderedSink:pull ()
    local input = assert(self.input.input, "input port not found")

    for _ = 1, link.nreadable(input) do
        local p = link.receive(input)
        local seq_num_ptr = ffi.cast("uint32_t*", p.data + p.length - 4)
        local seq_num = lib.ntohl(seq_num_ptr[0])
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
