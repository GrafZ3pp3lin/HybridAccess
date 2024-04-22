module(..., package.seeall)

local link = require("core.link")
local packet = require("core.packet")
local ffi = require("ffi")
local bit = require("bit")
local tobit, rshift, band =
   bit.tobit, bit.rshift, bit.band

local HEADER_SIZE = 8
local header_array_ctype = ffi.typeof("uint8_t[?]")

LoadBalancer = {}

function LoadBalancer:new()
    local o = {}
    setmetatable(o, self)
    self.sequence_number = 0
    self.__index = self
    return o
end

---comment
---@param sequence_number integer
---@param length integer
---@param type integer
function LoadBalancer:create_header(sequence_number, length, type)
    local header = header_array_ctype(HEADER_SIZE)
    local sn_bits = tobit(sequence_number);
    header[0] = band(rshift(sn_bits, 24), 0xff)
    header[1] = band(rshift(sn_bits, 16), 0xff)
    header[2] = band(rshift(sn_bits, 8), 0xff)
    header[3] = band(sn_bits, 0xff)
    local length_bits = tobit(length)
    header[4] = band(rshift(length_bits, 16), 0xff)
    header[5] = band(rshift(length_bits, 8), 0xff)
    header[6] = band(length_bits, 0xff)
    local type_bits = tobit(type)
    header[7] = band(type_bits, 0xff)
    --print(header[0], header[1], header[2], header[3], header[4], header[5], header[6], header[7])
    return header
end

function LoadBalancer:send_pkt(pkt, l_out, type)
    local length = pkt.length
    local header = self:create_header(self.sequence_number, length, type)
    self.sequence_number = self.sequence_number + 1
    local p = packet.prepend(pkt, header, HEADER_SIZE)
    link.transmit(l_out, p)
end

