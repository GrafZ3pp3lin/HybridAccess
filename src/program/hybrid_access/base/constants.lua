module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")

local cast, typeof, sizeof = ffi.cast, ffi.typeof, ffi.sizeof
local ntohs = lib.ntohs

ETHER_HEADER_T = typeof([[
    struct {
       uint8_t  ether_dhost[6];
       uint8_t  ether_shost[6];
       uint16_t ether_type;
    } __attribute__((packed))
]])
ETHER_HEADER_PTR_T = typeof('$*', ETHER_HEADER_T)
ETHER_HEADER_LEN = sizeof(ETHER_HEADER_T)

IPV4_HEADER_T = typeof([[
    struct {
       uint16_t ihl_v_tos; // ihl:4, version:4, tos(dscp:6 + ecn:2)
       uint16_t total_length;
       uint16_t id;
       uint16_t frag_off; // flags:3, fragmen_offset:13
       uint8_t  ttl;
       uint8_t  protocol;
       uint16_t checksum;
       uint8_t  src_ip[4];
       uint8_t  dst_ip[4];
    } __attribute__((packed))
]])
IPV4_HEADER_PTR_T = typeof('$*', IPV4_HEADER_T)
IPV4_HEADER_LEN = sizeof(IPV4_HEADER_T)

HA_HEADER_T = typeof([[
   struct {
      uint64_t seq_no;
      uint16_t buf_type;
      uint8_t  type;
      uint8_t  unused;
   } __attribute__((packed))
]])
HA_HEADER_PTR_T = typeof("$*", HA_HEADER_T)
HA_HEADER_LEN = sizeof(HA_HEADER_T)

--local ether_ip_ha_header_t = ffi.typeof(
--    'struct { $ ether; $ ipv4; $ hybrid } __attribute__((packed))',
--    ether_header_t, ipv4_header_t, ha_header_t)
--local ether_ip_ha_header_ptr_t = ffi.typeof('$*', ether_ip_ha_header_t)
--local ether_ip_ha_header_len = ffi.sizeof(ether_ip_ha_header_t)

UINT16_PTR_T = ffi.typeof("uint16_t*")

HYBRID_ACCESS_ETH_TYPE = 0x9444
HYBRID_ACCESS_IP_TYPE = 0x94

IPV4_ETH_TYPE = 0x0800

HYBRID_ACCESS_TYPE = 0x01
HYBRID_ACCESS_DDC_TYPE = 0x02

function GET_ETHER_TYPE(pkt)
   return ntohs(cast(UINT16_PTR_T, pkt.data + ETHER_HEADER_LEN - 2)[0])
end
