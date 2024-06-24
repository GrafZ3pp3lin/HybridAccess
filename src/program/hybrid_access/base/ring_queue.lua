---@diagnostic disable: inject-field
module(..., package.seeall)

local ffi = require("ffi")

require("core.packet_h")
require("program.hybrid_access.base.ring_queue_h")

local timed_pkt_t = ffi.typeof("struct timed_packet")
local delayer_buffer_t = ffi.typeof("struct delay_buffer")

local BUFFER_LENGTH = 128 * 1024

RingQueue = {}

local function init_queue(buffer)
    for i = 0, BUFFER_LENGTH - 1 do
        local timed_pkt = ffi.new(timed_pkt_t)
        buffer.packets[i] = timed_pkt
    end
end

function RingQueue:new()
    local o = {}
    o.buffer = ffi.new(delayer_buffer_t)
    init_queue(o.buffer)
    o.default_sending_time = ffi.new("uint64_t", -1)
    setmetatable(o, self)
    self.__index = self
    return o
end

function RingQueue:pop()
    -- assert(not self:empty())
    local buffer = self.buffer
    local timed_pkt = buffer.packets[buffer.read]
    buffer.read = (buffer.read + 1) % BUFFER_LENGTH

    return timed_pkt.packet
end

function RingQueue:push(pkt, sending_time)
    -- assert(not self:full())
    local buffer = self.buffer
    local timed_pkt = buffer.packets[buffer.write]
    timed_pkt.packet = pkt
    timed_pkt.sending_time = sending_time

    buffer.write = (buffer.write + 1) % BUFFER_LENGTH
end

function RingQueue:empty()
    return self.buffer.read == self.buffer.write
end

function RingQueue:full()
    return self.buffer.read == (self.buffer.write + 1) % BUFFER_LENGTH
end

function RingQueue:nreadable()
    local buffer = self.buffer
    if buffer.read > buffer.write then
       return buffer.write + BUFFER_LENGTH - buffer.read
    else
       return buffer.write - buffer.read
    end
end

function RingQueue:front_time()
    if self:empty() then
        return self.default_sending_time
    else
        return self.buffer.packets[self.buffer.read].sending_time
    end
end
