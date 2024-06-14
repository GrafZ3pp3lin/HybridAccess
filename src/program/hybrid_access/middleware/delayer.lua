---@diagnostic disable: inject-field, undefined-field
module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local link = require("core.link")

local queue = require("program.hybrid_access.base.queue")

local C = ffi.C
-- local BUFFER_LENGTH = 64

require("core.packet_h")

local buffered_pkts = ffi.typeof([[
    struct {
        struct packet   *packets[1024];
        uint64_t        release_time;
        uint16_t        length;
    } __attribute__((packed))
]])

Delayer = {
    config = {
        -- delay in ms
        delay = { default = 30 },
        -- correction in ns (actual link delay)
        correction = { default = 0 }
    }
}

function Delayer:new(conf)
    assert(conf.delay >= 0, "delay has to be >= 0")
    local o = {
        queue = queue.Queue:new(),
        max_buffered = 0,
        orig_delay = conf.delay,
        orig_correction = conf.correction
    }
    o.delay = ffi.new("uint64_t", (conf.delay * 1000000) - conf.correction)
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

    local release_time = C.get_time_ns() + self.delay

    local buffer = ffi.new(buffered_pkts)
    buffer.release_time = release_time
    buffer.length = length
    for i = 0, length - 1 do
        local p = link.receive(input)
        buffer.packets[i] = p
    end
    self.queue:push(buffer)

    -- local buffered = 0
    -- while buffered < length do
    --     local buffer = ffi.new(buffered_pkts)
    --     local buffer_length = math.min(length - buffered, BUFFER_LENGTH)
    --     buffer.release_time = release_time
    --     buffer.length = buffer_length
    --     for i = 0, buffer_length - 1 do
    --         local p = link.receive(input)
    --         buffer.packets[i] = p
    --     end
    --     self.queue:push(buffer)
    --     buffered = buffered + buffer_length
    -- end

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
    local peek_buf = self.queue:peek()

    while peek_buf.release_time <= now and peek_buf.length < link.nwritable(output) do
        local buffer = self.queue:pop()
        self:send_buffer(buffer, output)
        if self.queue:size() <= 0 then
            break
        end
        peek_buf = self.queue:peek()
    end
end

function Delayer:send_buffer(buffer, output)
    for i = 0, buffer.length - 1 do
        local p = buffer.packets[i]
        link.transmit(output, p)
        buffer.packets[i] = nil
    end
end

function Delayer:report()
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    print(string.format("delayed by %sms", lib.comma_value(self.orig_delay)))
    print(string.format("corrected by %sns", lib.comma_value(self.orig_correction)))
    print(string.format("results in delay by %sns", lib.comma_value(self.delay)))
    print(string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets),
        lib.comma_value(input_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets),
            lib.comma_value(output_stats.txbytes)))
    print(string.format("%20s max buffered", lib.comma_value(self.max_buffered)))
end
