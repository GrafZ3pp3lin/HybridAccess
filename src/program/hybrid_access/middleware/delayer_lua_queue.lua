---@diagnostic disable: inject-field, undefined-field
module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local link = require("core.link")

local queue = require("program.hybrid_access.base.queue")

local BUFFER_LENGTH = 102

local C = ffi.C

require("core.packet_h")

local buffered_pkts = ffi.typeof([[
    struct {
        struct packet   *packets[102];
        uint64_t        release_time;
        uint8_t         length;
    } __attribute__((packed))
]])

DelayerLuaQueue = {
    config = {
        -- delay in ms
        delay = { default = 30 },
        -- correction in ns (actual link delay)
        correction = { default = 0 }
    }
}

function DelayerLuaQueue:new(conf)
    assert(conf.delay >= 0, "delay has to be >= 0")
    local o = {
        queue = queue.Queue:new(),
        max_buffered = 0,
        max_buffer_length = 0,
        max_output_n = 0,
        orig_delay = conf.delay,
        orig_correction = conf.correction
    }
    o.delay = ffi.new("uint64_t", (conf.delay * 1000000) - conf.correction)
    setmetatable(o, self)
    self.__index = self
    return o
end

function DelayerLuaQueue:push()
    self:buffer_input()
    self:release_buffer()
end

function DelayerLuaQueue:buffer_input()
    local input = assert(self.input.input, "input port not found")
    local length = link.nreadable(input)
    if length <= 0 then
        return
    elseif length > BUFFER_LENGTH then
        error("amounts of packets exceed buffer length")
    end

    local release_time = C.get_time_ns() + self.delay

    local buffer = ffi.new(buffered_pkts)
    buffer.release_time = release_time
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
    if length > self.max_buffer_length then
        self.max_buffer_length = length
    end
end

function DelayerLuaQueue:release_buffer()
    local output = assert(self.output.output, "output port not found")
    if self.queue:size() <= 0 then
        return
    end

    local now = C.get_time_ns()
    local peek_buf = self.queue:peek()
    while peek_buf.release_time <= now do
        local buffer = self.queue:pop()
        self:send_buffer(buffer, output)
        if self.queue:size() > 0 then
            peek_buf = self.queue:peek()
        else
            break
        end
    end

    local out_n = link.nreadable(output)
    if out_n > self.max_output_n then
        self.max_output_n = out_n
    end
end

function DelayerLuaQueue:send_buffer(buffer, output)
    for i = 0, buffer.length - 1 do
        local p = buffer.packets[i]
        link.transmit(output, p)
        buffer.packets[i] = nil
    end
end

function DelayerLuaQueue:report()
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
    print(string.format("%20s max buffered", lib.comma_value(self.max_buffered)))
    print(string.format("%20s max buffer length", lib.comma_value(self.max_buffer_length)))
    print(string.format("%20s max output length", lib.comma_value(self.max_output_n)))

    self.max_buffered = 0
    self.max_buffer_length = 0
    self.max_output_n = 0
end
