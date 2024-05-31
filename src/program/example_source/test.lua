module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local link = require("core.link")
local packet = require("core.packet")
local ethernet = require("lib.protocol.ethernet")

local hybrid_access_header_t = ffi.typeof([[
   struct {
      uint32_t seq_no;
      uint16_t type;
   } __attribute__((packed))
]])
local hybrid_access_header_ptr_t = ffi.typeof("$ *", hybrid_access_header_t)
local HYBRID_ACCESS_SIZE = ffi.sizeof(hybrid_access_header_t)

local uint16_ptr_t = ffi.typeof("uint16_t*")

Test = {}

function Test:new ()
    local o = {
        index = 0,
        seq_no = 0xfffffffc
    }
    setmetatable(o, self)
    self.eth = ethernet:new{
        type = 0x9444 -- HybridAccess
    }
    self.__index = self
    print(ethernet:sizeof(), HYBRID_ACCESS_SIZE)
    return o
end

function Test:push ()
    local input = self.input.input
    local output = self.output.output
    for _ = 1, link.nreadable(input) do
        local p = link.receive(input)
        local eth_type = ffi.cast(uint16_ptr_t, p.data + 12)[0]
        print_packet(p)
        local p2 = packet.shiftright(p, 6)
        ffi.copy(p2.data, self.eth:header(), 14)
        -- Strip Ethernet header
        --local p2 = packet.shiftleft(p, 14)
        -- Add Hybrid Access Header
        --local p3 = packet.shiftright(p2, 6)
        local ha_header = ffi.cast(hybrid_access_header_ptr_t, p2.data + 14)
        ha_header.seq_no = lib.htonl(self.seq_no)
        ha_header.type = eth_type
        -- Slap on Ethernet header
        --local p4 = packet.prepend(p3, self.eth:header(), 14)
        print_packet(p2)
        --print_packet(p3)
        --print_packet(p4)
        link.transmit(output, p2)
        self.seq_no = self.seq_no + 1
    end
end

function print_packet(p)
    local msg = string.format("%d: ", p.length)
    for i = 0, p.length, 1 do
        msg = string.format("%s%x ", msg, p.data[i])
    end
    print(msg)
end
