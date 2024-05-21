---@diagnostic disable: inject-field, undefined-field, lowercase-global
module(..., package.seeall)

local lib = require("core.lib")
local packet = require("core.packet")
local ffi = require("ffi")
local ethernet = require("lib.protocol.ethernet")
local ipv4     = require("lib.protocol.ipv4")

local cast, copy = ffi.cast, ffi.copy
local shiftleft, shiftright, allocate = packet.shiftleft, packet.shiftright, packet.allocate
local ntohs = lib.ntohs

local hybrid_access_header_t = ffi.typeof([[
   struct {
      uint64_t seq_no;
      uint16_t buf_type;
      uint8_t type;
      uint8_t unused;
   } __attribute__((packed))
]])
local hybrid_access_header_ptr_t = ffi.typeof("$*", hybrid_access_header_t)

ETH_SIZE = ethernet:sizeof()
IP_SIZE = ipv4:sizeof()
local ETH_SIZE = ETH_SIZE
local IP_SIZE = IP_SIZE
local HYBRID_ACCESS_SIZE = ffi.sizeof(hybrid_access_header_t)

local uint16_ptr_t = ffi.typeof("uint16_t*")
local uint8_ptr_t = ffi.typeof("uint8_t*")

HYBRID_ACCESS_ETH_TYPE = 0x9444
HYBRID_ACCESS_IP_TYPE = 0x94

IPV4_ETH_TYPE = 0x0800

HYBRID_ACCESS_TYPE = 0x01
HYBRID_ACCESS_DDC_TYPE = 0x02

function get_eth_type(pkt)
    return ntohs(cast(uint16_ptr_t, pkt.data + ETH_SIZE - 2)[0])
end

function get_ip_protocol(pkt)
    return cast(uint8_ptr_t, pkt.data + ETH_SIZE + 9)[0]
end

function get_types(pkt)
    local eth = ntohs(cast(uint16_ptr_t, pkt.data + ETH_SIZE - 2)[0])
    local ip = 0
    if eth == IPV4_ETH_TYPE then
        ip = cast(uint8_ptr_t, pkt.data + ETH_SIZE + 9)[0]
    end
    return eth, ip
end

---Creates a new packet with an hybrid access header
---@param pkt any old packet
---@param eth_header any new eth header
---@param ip_header any new ip header or nil
---@param seq_no integer sequence number
---@param type integer hybrid access type
---@param buf_type integer buffered eth type
---@return unknown p new packet
function add_hybrid_access_header(pkt, eth_header, ip_header, seq_no, type, buf_type)
    local size = HYBRID_ACCESS_SIZE
    local ha_header_offset = ETH_SIZE
    if ip_header ~= nil then
        size = size + IP_SIZE
        ha_header_offset = ha_header_offset + IP_SIZE
    end
    -- make new packet with room for new headers
    local p_new = shiftright(pkt, size)
    -- Slap on new ethernet header
    copy(p_new.data, eth_header:header(), ETH_SIZE)
    if ip_header ~= nil then
        -- Slap on new ipv4 header
        copy(p_new.data + ETH_SIZE, ip_header:header(), IP_SIZE)
    end
    -- cast packet to hybrid access header (at correct index pointer)
    local ha_header = cast(hybrid_access_header_ptr_t, p_new.data + ha_header_offset)
    ha_header.seq_no = seq_no
    ha_header.buf_type = buf_type
    ha_header.type = type
    return p_new
end

---comment
---@param pkt any packet
---@param buf_type integer buffered eth_type 
---@param ip_protocol integer ip_protocol of packet
---@return unknown p new packet
function remove_hybrid_access_header(pkt, buf_type, ip_protocol)
    local size = HYBRID_ACCESS_SIZE
    if ip_protocol == HYBRID_ACCESS_IP_TYPE then
        size = size + IP_SIZE
    end
    -- make new packet with room for hybrid access header
    local p_new = shiftleft(pkt, size)
    local eth_header = ethernet:new{
        type = buf_type
    }
    -- Slap on new ethernet header
    copy(p_new.data, eth_header:header(), ETH_SIZE)
    return p_new
end

---read the hybrid access header from the packet
---@param pkt any packet
---@param eth_type integer eth_type of packet
---@param ip_protocol integer ip_protocol of packet
---@return integer seq_no sequence number
---@return integer type hybrid access type
---@return integer buf_type buffered type
function read_hybrid_access_header(pkt, eth_type, ip_protocol)
    if eth_type ~= HYBRID_ACCESS_ETH_TYPE and ip_protocol ~= HYBRID_ACCESS_IP_TYPE then
        error("packet is not a hybrid access packet")
    end
    local offset = ETH_SIZE
    if ip_protocol == HYBRID_ACCESS_IP_TYPE then
        offset = offset + IP_SIZE
    end
    -- cast packet to hybrid access header (at correct index pointer)
    local ha_header = cast(hybrid_access_header_ptr_t, pkt.data + offset)
    local seq_no = ha_header.seq_no
    local buf_type = ha_header.buf_type
    local type = ha_header.type
    return seq_no, type, buf_type
end

---creates a new hybrid access ddc (delay difference compensation) packet
---@param eth_header any eth header
---@param ip_header any ip header or nil
---@param seq_no integer sequence number
---@return unknown pkt ddc packet
function make_ddc_packet(eth_header, ip_header, seq_no)
    local pkt = allocate()
    local length = ETH_SIZE + HYBRID_ACCESS_SIZE
    local ha_header_offset = ETH_SIZE
    if ip_header ~= nil then
        length = length + IP_SIZE
        ha_header_offset = ha_header_offset + IP_SIZE
    end
    pkt.length = length

    copy(pkt.data, eth_header:header(), ETH_SIZE)

    if ip_header ~= nil then
        copy(pkt.data + ETH_SIZE, ip_header:header(), IP_SIZE)
    end

    local ha_header = cast(hybrid_access_header_ptr_t, pkt.data + ha_header_offset)
    ha_header.seq_no = seq_no
    ha_header.buf_type = 0xFFFF
    ha_header.type = HYBRID_ACCESS_DDC_TYPE

    return pkt
end