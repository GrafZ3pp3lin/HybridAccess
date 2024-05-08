---@diagnostic disable: inject-field, undefined-field, lowercase-global
module(..., package.seeall)

local lib = require("core.lib")
local packet = require("core.packet")
local ffi = require("ffi")
local ethernet = require("lib.protocol.ethernet")

local cast, copy = ffi.cast, ffi.copy
local htonl, htons, ntohl, ntohs = lib.htonl, lib.htons, lib.ntohl, lib.ntohs

local hybrid_access_header_t = ffi.typeof([[
   struct {
      uint32_t seq_no;
      uint16_t type;
   } __attribute__((packed))
]])
local hybrid_access_header_ptr_t = ffi.typeof("$ *", hybrid_access_header_t)

ETH_SIZE = ethernet:sizeof()
local HYBRID_ACCESS_SIZE = ffi.sizeof(hybrid_access_header_t)
local ETH_SIZE = ETH_SIZE

local uint16_ptr_t = ffi.typeof("uint16_t*")

function get_eth_type(pkt)
    return cast(uint16_ptr_t, pkt.data + ETH_SIZE - 2)[0]
end

function add_hybrid_access_header(pkt, eth_header, sequence_number, eth_type)
    -- make new packet with room for hybrid access header
    local p_new = packet.shiftright(pkt, HYBRID_ACCESS_SIZE)
    -- Slap on new ethernet header
    copy(p_new.data, eth_header:header(), ETH_SIZE)
    -- cast packet to hybrid access header (at correct index pointer)
    local ha_header = cast(hybrid_access_header_ptr_t, p_new.data + ETH_SIZE)
    ha_header.seq_no = htonl(sequence_number)
    ha_header.type = htons(eth_type)
    return p_new
end

function remove_hybrid_access_header(pkt, eth_type)
    -- make new packet with room for hybrid access header
    local p_new = packet.shiftleft(pkt, HYBRID_ACCESS_SIZE)
    local eth_header = ethernet:new{
        type = eth_type
    }
    -- Slap on new ethernet header
    copy(p_new.data, eth_header:header(), ETH_SIZE)
    return p_new
end

function read_hybrid_access_header(pkt)
    if pkt.length < ETH_SIZE + HYBRID_ACCESS_SIZE then
        error("packet does not contain a header")
    end
    -- cast packet to hybrid access header (at correct index pointer)
    local ha_header = cast(hybrid_access_header_ptr_t, pkt.data + ETH_SIZE)
    local seq_no = ntohl(ha_header.seq_no)
    local type = ntohs(ha_header.type)
    return seq_no, type
end