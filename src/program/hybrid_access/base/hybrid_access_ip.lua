---@diagnostic disable: inject-field, undefined-field, lowercase-global
module(..., package.seeall)

local ffi = require("ffi")
local packet = require("core.packet")
local lib = require("core.lib")
local ipv4 = require("lib.protocol.ipv4")

local hybrid_access = require("program.hybrid_access.base.hybrid_access")
local co = require("program.hybrid_access.base.constants")

local ipsum = require("lib.checksum").ipsum

local cast, copy = ffi.cast, ffi.copy
local allocate = packet.shiftleft
local htons = lib.htons

local GET_ETHER_TYPE, ETHER_HEADER_PTR_T, IPV4_HEADER_PTR_T, HA_HEADER_PTR_T,
ETHER_HEADER_LEN, IPV4_HEADER_LEN, HA_HEADER_LEN,
IPV4_HEADER_T, IPV4_ETH_TYPE, HYBRID_ACCESS_IP_TYPE,
HYBRID_ACCESS_TYPE, HYBRID_ACCESS_DDC_TYPE, UINT8_PTR_T =
    co.GET_ETHER_TYPE, co.ETHER_HEADER_PTR_T, co.IPV4_HEADER_PTR_T, co.HA_HEADER_PTR_T,
    co.ETHER_HEADER_LEN, co.IPV4_HEADER_LEN, co.HA_HEADER_LEN,
    co.IPV4_HEADER_T, co.IPV4_ETH_TYPE, co.HYBRID_ACCESS_IP_TYPE,
    co.HYBRID_ACCESS_TYPE, co.HYBRID_ACCESS_DDC_TYPE, co.UINT8_PTR_T

HybridAccessIp = hybrid_access.HybridAccess:new()

function HybridAccessIp:new(conf)
    local o = {}
    o.ether_type_ha = htons(IPV4_ETH_TYPE)
    o.ipv4_h = IPV4_HEADER_T()
    lib.bitfield(16, o.ipv4_h, 'ihl_v_tos', 0, 4, 4) -- v4
    lib.bitfield(16, o.ipv4_h, 'ihl_v_tos', 4, 4, IPV4_HEADER_LEN / 4) -- header length
    -- o.ipv4_h.total_length = htons(IPV4_HEADER_LEN)
    o.ipv4_h.ttl = 64
    o.ipv4_h.protocol = HYBRID_ACCESS_IP_TYPE
    if conf.source_ip and conf.destination_ip then
        o.ipv4_h.src_ip = ipv4:pton(conf.source_ip)
        o.ipv4_h.dst_ip = ipv4:pton(conf.destination_ip)
    end
    -- o.ipv4_h.checksum = htons(ipsum(ffi.cast(UINT8_PTR_T, o.ipv4_h), IPV4_HEADER_LEN, 0))
    setmetatable(o, self)
    self.__index = self
    return o
end

function HybridAccessIp:get_header(pkt)
    local ether_type = GET_ETHER_TYPE(pkt)
    if ether_type ~= IPV4_ETH_TYPE then
        return nil
    end
    local ipv4_h = cast(IPV4_HEADER_PTR_T, pkt.data + ETHER_HEADER_LEN)
    if ipv4_h.protocol ~= HYBRID_ACCESS_IP_TYPE then
        return nil
    end
    return cast(HA_HEADER_PTR_T, pkt.data + ETHER_HEADER_LEN + IPV4_HEADER_LEN)
end

function HybridAccessIp:add_header(pkt, seq_no, buf_type)
    -- resize packet and move eth header to front
    local p_new = self:_move_eth_header(pkt, HA_HEADER_LEN + IPV4_HEADER_LEN)
    -- Slap on new ip header
    copy(p_new.data + ETHER_HEADER_LEN, self.ipv4_h, IPV4_HEADER_LEN)
    -- set ha header in new packet
    self:_set_ha_header(p_new, ETHER_HEADER_LEN + IPV4_HEADER_LEN, seq_no, buf_type, HYBRID_ACCESS_TYPE)
    return p_new
end

function HybridAccessIp:remove_header(pkt, buf_type)
    return self:_remove_header(pkt, HA_HEADER_LEN + IPV4_HEADER_LEN, buf_type)
end

function HybridAccessIp:make_ddc_packet(orig_pkt, seq_no)
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
    -- copy ip header to new packet
    copy(pkt.data + ETHER_HEADER_LEN, self.ipv4_h, IPV4_HEADER_LEN)
    -- set ha header in new packet
    self:_set_ha_header(pkt, ETHER_HEADER_LEN + IPV4_HEADER_LEN, seq_no, 0xFFFF, HYBRID_ACCESS_DDC_TYPE)
    return pkt
end
