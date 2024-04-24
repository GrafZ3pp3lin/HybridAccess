module(..., package.seeall)

local packet = require("core.packet")
local link = require("core.link")
local bit = require("bit")
local lshift, bor =
    bit.lshift, bit.bor

local HEADER_SIZE = 8

Recombination = {}

function Recombination:new ()
    local o = {
        next_pkt_num = 0
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Recombination:push()
    local input1 = assert(self.input.input1, "input port 1 not found")
    local input2 = assert(self.input.input2, "input port 2 not found")
    local output = assert(self.output.output, "output port not found")

    local last_pkt_num_i1, last_pkt_num_i2 = -1, -1
    local i1_pkts = not link.empty(input1)
    local i2_pkts = not link.empty(input2)
    local found_next = false

    while i1_pkts or i2_pkts do
        found_next = false

        if i1_pkts then
            local p = link.front(input1)
            local seq_num, _, _ = self:read_header(p)
            last_pkt_num_i1 = seq_num
            if seq_num == self.next_pkt_num then
                self:process_packet(input1, output, seq_num)
                found_next = true
            end
        end
        if not found_next and i2_pkts then
            local p = link.front(input2)
            local seq_num, _, _ = self:read_header(p)
            last_pkt_num_i2 = seq_num
            if seq_num == self.next_pkt_num then
                self:process_packet(input2, output, seq_num)
                found_next = true
            end
        end
        if not found_next and i1_pkts and i2_pkts then
            if last_pkt_num_i1 < last_pkt_num_i2 then
                self:process_packet(input1, output, last_pkt_num_i1)
            else
                self:process_packet(input2, output, last_pkt_num_i2)
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

function Recombination:process_packet(input, output, pkt_num)
    local p = link.receive(input)
    --print(p.data[0], p.data[1], p.data[2], p.data[3], p.data[4], p.data[5], p.data[6], p.data[7])
    p = packet.shiftleft(p, HEADER_SIZE)
    link.transmit(output, p)
    self.next_pkt_num = pkt_num + 1
end

---comment
---@param p any (packet)
---@return integer
---@return integer
---@return integer
function Recombination:read_header(p)
    if p.length < HEADER_SIZE then
        error("packet does not contain a header")
    end

    local header = p.data
    local sequence_number = lshift(header[0], 24);
    sequence_number = bor(sequence_number, lshift(header[1], 16));
    sequence_number = bor(sequence_number, lshift(header[2], 8));
    sequence_number = bor(sequence_number, header[3]);

    local length = lshift(header[4], 16)
    length = bor(length, lshift(header[5], 8))
    length = bor(length, header[6])

    local type = header[7]

    return sequence_number, length, type
end
