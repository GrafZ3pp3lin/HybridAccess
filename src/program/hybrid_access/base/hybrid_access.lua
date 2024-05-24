---@diagnostic disable: undefined-field, inject-field
module(..., package.seeall)

local ffi = require("ffi")
local packet = require("core.packet")
local lib = require("core.lib")
local ethernet = require("lib.protocol.ethernet")

local co = require("program.hybrid_access.base.constants")

local cast, copy = ffi.cast, ffi.copy
local shiftleft, shiftright, allocate = packet.shiftleft, packet.shiftright, packet.allocate
local htons = lib.htons

local GET_ETHER_TYPE, HA_HEADER_PTR_T, ETHER_HEADER_PTR_T,
ETHER_HEADER_LEN, HA_HEADER_LEN,
ETHER_HEADER_T,
HYBRID_ACCESS_TYPE, HYBRID_ACCESS_DDC_TYPE, HYBRID_ACCESS_ETH_TYPE =
    co.GET_ETHER_TYPE, co.HA_HEADER_PTR_T, co.ETHER_HEADER_PTR_T,
    co.ETHER_HEADER_LEN, co.HA_HEADER_LEN,
    co.ETHER_HEADER_T,
    co.HYBRID_ACCESS_TYPE, co.HYBRID_ACCESS_DDC_TYPE, co.HYBRID_ACCESS_ETH_TYPE

HybridAccess = {}

function HybridAccess:new(conf)
    local o = {}
    o.ether_h = ETHER_HEADER_T()
    o.ether_h.ether_type = htons(HYBRID_ACCESS_ETH_TYPE)
    if conf.destination_mac and conf.source_mac then
        o.ether_h.ether_dhost = ethernet:pton(conf.destination_mac)
        o.ether_h.ether_shost = ethernet:pton(conf.source_mac)
    end
    setmetatable(o, self)
    self.__index = self
    return o
end

function HybridAccess:get_header(pkt)
    local ether_type = GET_ETHER_TYPE(pkt)
    if ether_type == HYBRID_ACCESS_ETH_TYPE then
        return cast(HA_HEADER_PTR_T, pkt.data + ETHER_HEADER_LEN)
    end
    return nil
end

function HybridAccess:add_header(pkt, seq_no, buf_type)
    -- make new packet with room for new ha header
    local p_new = shiftright(pkt, HA_HEADER_LEN)
    -- Slap on new ethernet header
    copy(p_new.data, self.ether_h, ETHER_HEADER_LEN)
    -- cast packet to hybrid access header (at correct index pointer)
    local ha_header = cast(HA_HEADER_PTR_T, p_new.data + ETHER_HEADER_LEN)
    ha_header.seq_no = seq_no
    ha_header.buf_type = buf_type
    ha_header.type = HYBRID_ACCESS_TYPE
    ha_header.unused = 0
    return p_new
end

function HybridAccess:_remove_header(pkt, shift_length, buf_type)
    -- make new packet with removed hybrid access headers
    local p_new = shiftleft(pkt, shift_length)
    -- Slap on new ethernet header
    copy(p_new.data, self.ether_h, ETHER_HEADER_LEN)
    -- set ether_type - cast header therefore
    local eth_header = cast(ETHER_HEADER_PTR_T, p_new.data)
    eth_header.ether_type = htons(buf_type)
    return p_new
end

function HybridAccess:remove_header(pkt, buf_type)
    return self:_remove_header(pkt, HA_HEADER_LEN, buf_type)
end

function HybridAccess:make_ddc_packet(seq_no)
    local pkt = allocate()
    pkt.length = ETHER_HEADER_LEN + HA_HEADER_LEN

    copy(pkt.data, self.ether_h, ETHER_HEADER_LEN)

    local ha_header = cast(HA_HEADER_PTR_T, pkt.data + ETHER_HEADER_LEN)
    ha_header.seq_no = seq_no
    ha_header.buf_type = 0xFFFF
    ha_header.type = HYBRID_ACCESS_DDC_TYPE
    ha_header.unused = 0

    return pkt
end
