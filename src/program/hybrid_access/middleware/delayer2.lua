module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local timer = require("core.timer")

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
    o.delay = ffi.new("uint64_t", (conf.delay * 1000000) - conf.correction)
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