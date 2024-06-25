---@diagnostic disable: inject-field
module(..., package.seeall)

local ffi = require("ffi")

require("core.packet_h")
require("program.hybrid_access.base.ring_queue_h")

local delayer_buffer_t = ffi.typeof("struct delay_buffer")

local BUFFER_LENGTH = ffi.C.QUEUE_SIZE

RingQueue = {}

function RingQueue:new()
    local o = {}
    o.buffer = ffi.new(delayer_buffer_t)
    o.default_sending_time = ffi.new("uint64_t", -1)

    setmetatable(o, self)
    self.__index = self
    return o
end

function RingQueue:dequeue()
    -- assert(not self:empty())
    local buffer = self.buffer
    local timed_pkt = buffer.packets[buffer.read]
    
    local pkt_pointer = timed_pkt.packet
    
    timed_pkt.packet = nil
    buffer.read = (buffer.read + 1) % BUFFER_LENGTH

    return pkt_pointer
end

function RingQueue:enqueue(pkt, sending_time)
    -- assert(not self:full())
    local buffer = self.buffer
    local timed_pkt = buffer.packets[buffer.write]
    timed_pkt.packet = pkt
    timed_pkt.sending_time = sending_time

    buffer.write = (buffer.write + 1) % BUFFER_LENGTH
end

function RingQueue:is_empty()
    return self.buffer.read == self.buffer.write
end

function RingQueue:is_full()
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

function RingQueue:peek_time()
    if self:is_empty() then
        return self.default_sending_time
    else
        return self.buffer.packets[self.buffer.read].sending_time
    end
end
