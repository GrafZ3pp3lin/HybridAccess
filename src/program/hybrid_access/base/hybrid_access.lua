---@diagnostic disable: undefined-field, inject-field
module(..., package.seeall)

local ffi = require("ffi")
local packet = require("core.packet")
local lib = require("core.lib")

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

function HybridAccess:new()
    local o = {}
    o.eth_buf_add = ETHER_HEADER_T()
    o.eth_buf_remove = ETHER_HEADER_T()
    o.ether_type_ha = htons(HYBRID_ACCESS_ETH_TYPE)
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

function HybridAccess:_move_eth_header(pkt, shift_length)
    if pkt.length + shift_length > 1514 then
        error("Can not add hybrid access header to paket. It would be to large: "..pkt.length.." + "..shift_length)
    end
    -- buffer current header
    local old_eth_header = cast(ETHER_HEADER_PTR_T, pkt.data)
    copy(self.eth_buf_add, old_eth_header, ETHER_HEADER_LEN)
    -- make new packet with room for new ha header
    local p_new = shiftright(pkt, shift_length)
    -- Move old eth header to front with new type
    self.eth_buf_add.ether_type = self.ether_type_ha
    copy(p_new.data, self.eth_buf_add, ETHER_HEADER_LEN)
    return p_new
end

function HybridAccess:_set_ha_header(pkt, offset, seq_no, buf_type, type)
    -- cast packet to hybrid access header (at correct index pointer)
    local ha_header = cast(HA_HEADER_PTR_T, pkt.data + offset)
    ha_header.seq_no = seq_no
    ha_header.buf_type = buf_type
    ha_header.type = type
    ha_header.unused = 0
end

function HybridAccess:add_header(pkt, seq_no, buf_type)
    -- resize packet and move eth header to front
    local p_new = self:_move_eth_header(pkt, HA_HEADER_LEN)
    -- set ha header in new packet
    self:_set_ha_header(p_new, ETHER_HEADER_LEN, seq_no, buf_type, HYBRID_ACCESS_TYPE)
    return p_new
end

function HybridAccess:_remove_header(pkt, shift_length, buf_type)
    -- buffer current header
    local old_eth_header = cast(ETHER_HEADER_PTR_T, pkt.data)
    copy(self.eth_buf_remove, old_eth_header, ETHER_HEADER_LEN)
    -- make new packet with removed hybrid access headers
    local p_new = shiftleft(pkt, shift_length)
    -- Move old eth header to front with new type
    self.eth_buf_remove.ether_type = htons(buf_type)
    copy(p_new.data, self.eth_buf_remove, ETHER_HEADER_LEN)
    return p_new
end

function HybridAccess:remove_header(pkt, buf_type)
    return self:_remove_header(pkt, HA_HEADER_LEN, buf_type)
end

function HybridAccess:make_ddc_packet(orig_pkt, seq_no)
    -- create new packet
    local pkt = allocate()
    pkt.length = ETHER_HEADER_LEN + HA_HEADER_LEN
    -- get original eth header
    local orig_eth_header = cast(ETHER_HEADER_PTR_T, orig_pkt.data)
    -- copy original eth header to ddc packet
    copy(pkt.data, orig_eth_header, ETHER_HEADER_LEN)
    -- change eth type in new packet
    local eth_header = cast(ETHER_HEADER_PTR_T, pkt.data)
    eth_header.ether_type = self.ether_type_ha
    -- set ha header in new packet
    self:_set_ha_header(pkt, ETHER_HEADER_LEN, seq_no, 0xFFFF, HYBRID_ACCESS_DDC_TYPE)
    return pkt
end
