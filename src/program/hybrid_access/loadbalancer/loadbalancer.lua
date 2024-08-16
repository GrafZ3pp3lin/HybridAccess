module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local lib = require("core.lib")

local co = require("program.hybrid_access.base.constants")

local GET_ETHER_TYPE = co.GET_ETHER_TYPE

local transmit = link.transmit

LoadBalancer = {}

function LoadBalancer:new()
    local o = {}
    setmetatable(o, self)
    self.sequence_number = ffi.new("uint64_t", 0)
    self.__index = self
    return o
end

function LoadBalancer:setup(cfg)
    if cfg.mode == "IP" then
        print(string.format("Loadbalancer %s in ip mode from %s to %s", self.class_type, cfg.source_ip, cfg.destination_ip))
        self.hybrid_access = require("program.hybrid_access.base.hybrid_access_ip").HybridAccessIp:new(cfg)
    else
        print(string.format("Loadbalancer %s in eth mode", self.class_type))
        self.hybrid_access = require("program.hybrid_access.base.hybrid_access").HybridAccess:new()
    end
end

function LoadBalancer:build_packet(p, sequence_number)
    -- assert(p.length >= ETHER_HEADER_LEN, "packet does not have a ethernet header, it is to short")
    -- get eth_type of packet
    local buf_type = GET_ETHER_TYPE(p)
    -- make new packet with room for hybrid access header
    return self.hybrid_access:add_header(p, sequence_number, buf_type)
end

function LoadBalancer:send_pkt(pkt, l_out)
    local p_new = self:build_packet(pkt, self.sequence_number)
    self.sequence_number = self.sequence_number + 1
    transmit(l_out, p_new)
end

function LoadBalancer:send_pkt_with_ddc(pkt, l_out, l_delay)
    local p_delay = self.hybrid_access:make_ddc_packet(pkt, self.sequence_number)
    local p_new = self:build_packet(pkt, self.sequence_number + 1)
    self.sequence_number = self.sequence_number + 2
    transmit(l_delay, p_delay)
    transmit(l_out, p_new)
end

function LoadBalancer:report()
    local input_stats = link.stats(self.input.input)
    local out1_stats = link.stats(self.output.output1)
    local out2_stats = link.stats(self.output.output2)

    if self.class_type then
        print("Loadbalancer type: " .. self.class_type)
    end

    print(
        string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets), lib.comma_value(input_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out 1", lib.comma_value(out1_stats.txpackets), lib.comma_value(out1_stats.txbytes)))
    print(
        string.format("%20s # / %20s b out 2", lib.comma_value(out2_stats.txpackets), lib.comma_value(out2_stats.txbytes)))
end
