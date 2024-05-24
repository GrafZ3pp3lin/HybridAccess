---@diagnostic disable: inject-field, undefined-field, lowercase-global
module(..., package.seeall)

local ffi = require("ffi")
local packet = require("core.packet")
local lib = require("core.lib")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")

local hybrid_access = require("program.hybrid_access.base.hybrid_access")
local co = require("program.hybrid_access.base.constants")

local cast, copy = ffi.cast, ffi.copy
local shiftleft, shiftright, allocate = packet.shiftleft, packet.shiftright, packet.allocate
local htons = lib.htons

local GET_ETHER_TYPE, ETHER_HEADER_PTR_T, IPV4_HEADER_PTR_T, HA_HEADER_PTR_T,
ETHER_HEADER_LEN, IPV4_HEADER_LEN, HA_HEADER_LEN,
ETHER_HEADER_T, IPV4_HEADER_T, HYBRID_ACCESS_IP_TYPE,
HYBRID_ACCESS_TYPE, HYBRID_ACCESS_DDC_TYPE, IPV4_ETH_TYPE =
    co.GET_ETHER_TYPE, co.ETHER_HEADER_PTR_T, co.IPV4_HEADER_PTR_T, co.HA_HEADER_PTR_T,
    co.ETHER_HEADER_LEN, co.IPV4_HEADER_LEN, co.HA_HEADER_LEN,
    co.ETHER_HEADER_T, co.IPV4_HEADER_T, co.HYBRID_ACCESS_IP_TYPE,
    co.HYBRID_ACCESS_TYPE, co.HYBRID_ACCESS_DDC_TYPE, co.IPV4_ETH_TYPE

HybridAccessIp = hybrid_access.HybridAccess:new()

function HybridAccessIp:new(conf)
    local o = {}
    o.ether_h = ETHER_HEADER_T()
    o.ether_h.ether_type = htons(IPV4_ETH_TYPE)
    o.ipv4_h = IPV4_HEADER_T()
    o.ipv4_h.ttl = 64
    o.ipv4_h.protocol = HYBRID_ACCESS_IP_TYPE
    if conf.destination_mac and conf.source_mac then
        o.ether_h.ether_dhost = ethernet:pton(conf.destination_mac)
        o.ether_h.ether_shost = ethernet:pton(conf.source_mac)
    end
    if conf.source_ip and conf.destination_ip then
        o.ipv4_h.src_ip = ipv4:pton(conf.source_ip)
        o.ipv4_h.dst_ip = ipv4:pton(conf.destination_ip)
    end
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
    -- make new packet with room for new ip + ha header
    local p_new = shiftright(pkt, HA_HEADER_LEN + IPV4_HEADER_LEN)
    -- Slap on new ethernet header
    copy(p_new.data, self.ether_h, ETHER_HEADER_LEN)
    -- Slap on new ip header
    copy(p_new.data + ETHER_HEADER_LEN, self.ipv4_h, IPV4_HEADER_LEN)
    -- cast packet to hybrid access header (at correct index pointer)
    local ha_header = cast(HA_HEADER_PTR_T, p_new.data + ETHER_HEADER_LEN + IPV4_HEADER_LEN)
    ha_header.seq_no = seq_no
    ha_header.buf_type = buf_type
    ha_header.type = HYBRID_ACCESS_TYPE
    ha_header.unused = 0
    return p_new
end

function HybridAccessIp:remove_header(pkt, buf_type)
    return self:_remove_header(pkt, HA_HEADER_LEN + IPV4_HEADER_LEN, buf_type)
end

function HybridAccessIp:make_ddc_packet(seq_no)
    local pkt = allocate()
    pkt.length = ETHER_HEADER_LEN + IPV4_HEADER_LEN + HA_HEADER_LEN

    copy(pkt.data, self.ether_h, ETHER_HEADER_LEN)
    copy(pkt.data + ETHER_HEADER_LEN, self.ipv4_h, IPV4_HEADER_LEN)

    local ha_header = cast(HA_HEADER_PTR_T, pkt.data + ETHER_HEADER_LEN + IPV4_HEADER_LEN)
    ha_header.seq_no = seq_no
    ha_header.buf_type = 0xFFFF
    ha_header.type = HYBRID_ACCESS_DDC_TYPE
    ha_header.unused = 0

    return pkt
end
