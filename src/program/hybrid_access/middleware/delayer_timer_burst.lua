---@diagnostic disable: inject-field, undefined-field
module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local timer = require("core.timer")

local BUFFER_LENGTH = 102

require("core.packet_h")

local pkt_buffer = ffi.typeof([[
    struct {
        struct packet   *packets[102];
        uint16_t        length;
    } __attribute__((packed))
]])

DelayerTimerBurst = {
    config = {
        -- delay in ms
        delay = { default = 30 },
        -- correction in ns (actual link delay)
        correction = { default = 0 }
    }
}

function DelayerTimerBurst:new(conf)
    local o = {}
    o.delay = conf.delay * 1e6 - conf.correction
    setmetatable(o, self)
    self.__index = self
    return o
end

function DelayerTimerBurst:push()
    local iface_in = assert(self.input.input, "[Delayer3] <input> (Input) not found")
    local iface_out = assert(self.output.output, "[Delayer3] <output> (Output) not found")

    local length = link.nreadable(iface_in)
    if length <= 0 then
        return
    elseif length > BUFFER_LENGTH then
        error("[Delayer3] amounts of packets exceed buffer length")
    end

    local buffer = ffi.new(pkt_buffer)
    buffer.length = length
    for i = 0, length - 1 do
        local p = link.receive(iface_in)
        buffer.packets[i] = p
    end

    local fn = function ()
        for i = 0, buffer.length - 1 do
            link.transmit(iface_out, buffer.packets[i])
        end
    end
    local t = timer.new("packet_delay", fn, self.delay)
    timer.activate(t)
end
