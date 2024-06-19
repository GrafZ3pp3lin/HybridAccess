module(..., package.seeall)

local link = require("core.link")
local timer = require("core.timer")
local lib = require("core.lib")

Delayer2 = {
    config = {
        -- delay in ms
        delay = { default = 30 },
        -- correction in ns (actual link delay)
        correction = { default = 0 },
        debugging = { default = false }
    }
}

function Delayer2:new(conf)
    if conf.debugging then 
        print("[Delay1] Init...")
    end
    local o = {
        debugging = conf.debugging
    }
    o.delay = conf.delay * 1000000 - conf.correction
    setmetatable(o, self)
    self.__index = self
    return o
end

function Delayer2:push()
    local iface_in = assert(self.input.input, "[Delay1] <input> (Input) not found")

    while not link.empty(iface_in) do
        self:process_packet(iface_in)
    end
end

function Delayer2:process_packet(iface_in)
    local iface_out = assert(self.output.output, "[Delay1] <output> (Output) not found")
    local pkt = link.receive(iface_in)

    local fn = function () link.transmit(iface_out, pkt) end

    local t = timer.new("packet_delay", fn, self.delay)
    timer.activate(t)
end

function Delayer2:report()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(string.format("%20s ms delay", lib.comma_value(self.orig_delay)))
    print(string.format("%20s ns corrected", lib.comma_value(self.orig_correction)))
    print(string.format("%20s ns actual delay", lib.comma_value(self.delay)))
    print(string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets),
        lib.comma_value(input_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets),
            lib.comma_value(output_stats.txbytes)))
end