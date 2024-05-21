module(..., package.seeall)

local link = require("core.link")
local lib = require("core.lib")
local ha = require("program.hybrid_access.base.hybrid_access")

local ETH_SIZE = ha.ETH_SIZE

LoadBalancer = {}

function LoadBalancer:new()
    local o = {}
    setmetatable(o, self)
    self.sequence_number = 0
    self.__index = self
    return o
end

function LoadBalancer:build_packet(p, sequence_number)
    if p.length >= ETH_SIZE then
        -- get eth_type of packet
        local eth_type = ha.get_eth_type(p)
        -- make new packet with room for hybrid access header
        return ha.add_hybrid_access_header(p, sequence_number, eth_type)
    else
        return nil
    end
end

function LoadBalancer:send_pkt(pkt, l_out)
    local p_new = self:build_packet(pkt, self.sequence_number)
    if p_new == nil then
        return
    end
    self.sequence_number = self.sequence_number + 1
    link.transmit(l_out, p_new)
end

function LoadBalancer:send_pkt_with_ddc(pkt, l_out, l_delay)
    local p_delay = ha.make_ddc_packet(self.sequence_number)
    local p_new = self:build_packet(pkt, self.sequence_number + 1)
    if p_delay == nil or p_new == nil then
        return
    end
    self.sequence_number = self.sequence_number + 2
    link.transmit(l_delay, p_delay)
    link.transmit(l_out, p_new)
end

function LoadBalancer:file_report(f)
    local input_stats = link.stats(self.input.input)
    local out1_stats = link.stats(self.output.output1)
    local out2_stats = link.stats(self.output.output2)

    if self.class_type then
        f:write("Loadbalancer type: "..self.class_type, "\n")
    end

    f:write(
    string.format("%20s# / %20sb in", lib.comma_value(input_stats.txpackets), lib.comma_value(input_stats.txbytes)), "\n")
    f:write(
    string.format("%20s# / %20sb out 1", lib.comma_value(out1_stats.txpackets), lib.comma_value(out1_stats.txbytes)),
        "\n")
    f:write(
    string.format("%20s# / %20sb out 2", lib.comma_value(out2_stats.txpackets), lib.comma_value(out2_stats.txbytes)),
        "\n")
end
