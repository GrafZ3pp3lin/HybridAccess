module(..., package.seeall)

local link = require("core.link")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")

local ethernet_header_size = 14

Relay = {}

function Relay:new (args)
    local o = {
        name = args.name
    }
    setmetatable(o, self)
    self.__index = self
   return o
end

function Relay:pull ()
    local input = self.input.input
    local output = self.output.output
    for _ = 1, link.nreadable(input) do
        local p = link.receive(input)
        local ether_hdr = ethernet:new_from_mem(p.data, ethernet_header_size)
        local ether_type = ether_hdr:type()
        print(self.name, macdump(ether_hdr:dst()), macdump(ether_hdr:src()), ether_type)
        if ether_type == 0x800 then
            local ip_header = ipv4:new_from_mem(p.data + ethernet_header_size, p.length - ethernet_header_size)
            print(ip_header:version(), ip_header:ihl(), ip_header:dscp(), ip_header:ecn(), ip_header:total_length(), ip_header:id(), ip_header:flags(), ip_header:frag_off(), ip_header:ttl(), ip_header:protocol(), ip_header:checksum(), ipdump(ip_header:src()), ipdump(ip_header:dst()))
        end
        link.transmit(output, p)
    end
end

function macdump(data)
    return string.format("%x:%x:%x:%x:%x:%x", data[0], data[1], data[2], data[3], data[4], data[5])
end

function ipdump(data)
    return string.format("%d.%d.%d.%d", data[0], data[1], data[2], data[3])
end
