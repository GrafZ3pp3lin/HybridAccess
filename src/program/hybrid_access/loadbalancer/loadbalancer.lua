module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local lib = require("core.lib")

local co = require("program.hybrid_access.base.constants")

local ETHER_HEADER_LEN, GET_ETHER_TYPE =
    co.ETHER_HEADER_LEN, co.GET_ETHER_TYPE

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
        print(string.format("Loadbalancer in ip mode from %s to %s", cfg.self_ip, cfg.target_ip))
        self.hybrid_access = require("program.hybrid_access.base.hybrid_access_ip").HybridAccessIp:new(cfg)
    else
        print("Loadbalancer in eth mode")
        self.hybrid_access = require("program.hybrid_access.base.hybrid_access").HybridAccess:new(cfg)
    end
end

function LoadBalancer:build_packet(p, sequence_number)
    if p.length >= ETHER_HEADER_LEN then
        -- get eth_type of packet
        local buf_type = GET_ETHER_TYPE(p)
        -- make new packet with room for hybrid access header
        return self.hybrid_access:add_header(p, sequence_number, buf_type)
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
    local p_delay = self.hybrid_access:make_ddc_packet(self.sequence_number)
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
        f:write("Loadbalancer type: " .. self.class_type, "\n")
    end

    f:write(
        string.format("%20s # / %20s b in", lib.comma_value(input_stats.txpackets), lib.comma_value(input_stats.txbytes)),
        "\n")
    f:write(
        string.format("%20s # / %20s b out 1", lib.comma_value(out1_stats.txpackets), lib.comma_value(out1_stats.txbytes)),
        "\n")
    f:write(
        string.format("%20s # / %20s b out 2", lib.comma_value(out2_stats.txpackets), lib.comma_value(out2_stats.txbytes)),
        "\n")
end
