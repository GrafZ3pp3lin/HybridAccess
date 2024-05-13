module(..., package.seeall)

local link = require("core.link")
local ethernet = require("lib.protocol.ethernet")
local ha = require("program.hybrid_access.base.hybrid_access")

local ETH_SIZE = ha.ETH_SIZE

LoadBalancer = {}

function LoadBalancer:new()
    local o = {}
    setmetatable(o, self)
    self.sequence_number = 0
    self.eth = ethernet:new{
        type = ha.HYBRID_ACCESS_TYPE
    }
    self.__index = self
    return o
end

function LoadBalancer:build_packet(p, sequence_number, eth_header)
    if p.length >= ETH_SIZE then
        -- get eth_type of packet
        local eth_type = ha.get_eth_type(p)
        -- make new packet with room for hybrid access header
        return ha.add_hybrid_access_header(p, eth_header, sequence_number, eth_type)
    else
        return nil
    end
end

function LoadBalancer:send_pkt(pkt, l_out)
    local p_new = self:build_packet(pkt, self.sequence_number, self.eth)
    if p_new == nil then
        return
    end
    self.sequence_number = self.sequence_number + 1
    link.transmit(l_out, p_new)
end

