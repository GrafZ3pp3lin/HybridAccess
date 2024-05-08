module(..., package.seeall)

local link = require("core.link")
local ha = require("program.hybrid_access.base.hybrid_access")

Recombination = {}

function Recombination:new ()
    local o = {
        next_pkt_num = 0
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Recombination:pull()
    local input1 = assert(self.input.input1, "input port 1 not found")
    local input2 = assert(self.input.input2, "input port 2 not found")
    local output = assert(self.output.output, "output port not found")

    local last_pkt_num_i1, last_pkt_num_i2 = -1, -1
    local last_eth_type_i1, last_eth_type_i2 = 0, 0
    local i1_pkts = not link.empty(input1)
    local i2_pkts = not link.empty(input2)
    local found_next = false

    while i1_pkts or i2_pkts do
        found_next = false

        if i1_pkts then
            local p = link.front(input1)
            local seq_num, eth_type = ha.read_hybrid_access_header(p)
            last_pkt_num_i1 = seq_num
            last_eth_type_i1 = eth_type
            if seq_num == self.next_pkt_num then
                self:process_packet(input1, output, seq_num, eth_type)
                found_next = true
            end
        end
        if not found_next and i2_pkts then
            local p = link.front(input2)
            local seq_num, eth_type = ha.read_hybrid_access_header(p)
            last_pkt_num_i2 = seq_num
            last_eth_type_i2 = eth_type
            if seq_num == self.next_pkt_num then
                self:process_packet(input2, output, seq_num, eth_type)
                found_next = true
            end
        end
        if not found_next and i1_pkts and i2_pkts then
            if last_pkt_num_i1 < last_pkt_num_i2 then
                self:process_packet(input1, output, last_pkt_num_i1, last_eth_type_i1)
            else
                self:process_packet(input2, output, last_pkt_num_i2, last_eth_type_i2)
            end
            found_next = true
        end
        if not found_next then
            break
        end

        i1_pkts = not link.empty(input1)
        i2_pkts = not link.empty(input2)
    end
end

function Recombination:process_packet(input, output, pkt_num, eth_type)
    local p = link.receive(input)
    p = ha.remove_hybrid_access_header(p, eth_type)
    link.transmit(output, p)
    self.next_pkt_num = pkt_num + 1
end
