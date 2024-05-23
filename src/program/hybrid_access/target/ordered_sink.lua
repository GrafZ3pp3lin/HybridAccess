module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local link = require("core.link")
local packet = require("core.packet")
local engine = require("core.app")

OrderedSink = {}

function OrderedSink:new()
    local o = {
        index = 0,
        start = engine.now()
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function OrderedSink:pull()
    local input = assert(self.input.input, "input port not found")

    for _ = 1, link.nreadable(input) do
        local p = link.receive(input)
        local seq_num_ptr = ffi.cast("uint32_t*", p.data + p.length - 4)
        local seq_num = lib.ntohl(seq_num_ptr[0])
        if seq_num > self.index then
            -- print("received packet "..seq_num.." - expected: "..self.index)
            self.index = seq_num
        elseif seq_num < self.index then
            error("paket out of order: " .. seq_num .. " - expected: " .. self.index)
        end
        packet.free(p)
        self.index = self.index + 1
    end
end

function OrderedSink:file_report(f)
    local input_stats = link.stats(self.input.input)

    f:write(
    string.format("%20s # / %20s b received", lib.comma_value(input_stats.txpackets), lib.comma_value(input_stats.txbytes)),
        "\n")

    local now = engine.now()
    local runned_seconds = now - self.start
    local bytes_per_seconds = input_stats.txbytes / runned_seconds
    local bits_per_seconds = bytes_per_seconds * 8
    local mbits_per_seconds = bits_per_seconds / 1000000

    f:write(string.format("%20s s active\n", lib.comma_value(runned_seconds)))
    f:write(string.format("%20s B/s\n", lib.comma_value(bytes_per_seconds)))
    f:write(string.format("%20s bit/s\n", lib.comma_value(bits_per_seconds)))
    f:write(string.format("%20s Mbit/s\n", lib.comma_value(mbits_per_seconds)))
end
