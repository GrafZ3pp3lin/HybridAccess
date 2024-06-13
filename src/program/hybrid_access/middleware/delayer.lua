---@diagnostic disable: inject-field, undefined-field
module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local link = require("core.link")

local C = ffi.C

local queue = require("program.hybrid_access.base.queue")
local base = require("program.hybrid_access.base.base")

require("core.packet_h")

local link_buffer = ffi.typeof([[
    struct {
        struct packet   *packets[1024];
        uint64_t        release_time;
        uint32_t        length;
    } __attribute__((packed))
]])

Delayer = {
    config = {
        -- delay in ms
        delay = { default = 30 }
    }
}

function Delayer:new(conf)
    assert(conf.delay >= 0, "delay has to be >= 0")
    local o = {
        queue = queue.Queue:new(),
        max_buffered = 0
    }
    o.delay = ffi.new("uint64_t", conf.delay * 1000000)
    setmetatable(o, self)
    self.__index = self
    return o
end

function Delayer:pull()
    local input = assert(self.input.input, "input port not found")
    local length = link.nreadable(input)
    if length <= 0 then
        return
    end

    local buffer = ffi.new(link_buffer)
    local now = C.get_time_ns()
    buffer.release_time = now + self.delay
    buffer.length = length

    for i = 0, length - 1 do
        local p = link.receive(input)
        buffer.packets[i] = p
    end

    self.queue:push(buffer)
    local queue_size = self.queue:size()
    if queue_size > self.max_buffered then
        self.max_buffered = queue_size
    end
end

function Delayer:push()
    local output = assert(self.output.output, "output port not found")
    if self.queue:size() <= 0 then
        return
    end

    local now = C.get_time_ns()
    local capacity = link.nwritable(output)

    while self.queue:size() > 0 and capacity > 0 do
        local buffer = self.queue:look()
        if now >= buffer.release_time and buffer.length <= capacity then
            self:send_buffer(buffer, output)
            local _ = self.queue:pop()
            capacity = capacity - buffer.length
        else
            break
        end
    end
end

function Delayer:send_buffer(buffer, output)
    for i = 0, buffer.length - 1 do
        local p = buffer.packets[i]
        link.transmit(output, p)
    end
end

function Delayer:report()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(string.format("delayed with %ss", lib.comma_value(self.delay)))
    print(string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets),
        lib.comma_value(input_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets),
            lib.comma_value(output_stats.txbytes)))
    print(string.format("%20s max buffered breaths", lib.comma_value(self.max_buffered)))
end
