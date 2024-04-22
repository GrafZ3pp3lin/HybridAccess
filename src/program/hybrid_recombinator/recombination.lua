module(..., package.seeall)

local packet = require("core.packet")
local link = require("core.link")
local ffi = require("ffi")
local bit = require("bit")
local lshift, band =
    bit.lshift, bit.band

local HEADER_SIZE = 8
local header_pointer_ctype = ffi.typeof("uint8_t*")

Recombination = {}

function Recombination:new ()
    local o = {
        last_pkt_num = 0
    }
    return setmetatable(o, {__index = Recombination})
end

function Recombination:push()
    local i1 = assert(self.input.input1, "input port 1 not found")
    local i2 = assert(self.input.input2, "input port 2 not found")
    local o = assert(self.output.output, "output port not found")

    local last_pkt_num_i1, last_pkt_num_i2 = -1, -1
    local i1_pkts = not link.empty(i1)
    local i2_pkts = not link.empty(i2)

    while i1_pkts or i2_pkts do
        local found_next = false
        local next_pkt_num = self.last_pkt_num + 1

        if i1_pkts then
            local p = link.front(i1)
            local seq_num, _, _ = self:read_header(p)
            last_pkt_num_i1 = seq_num
            if seq_num == next_pkt_num then
                self:process_packet(i1, o, seq_num)
                found_next = true
            end
        end
        if not found_next and i2_pkts then
            local p = link.front(i1)
            local seq_num, _, _ = self:read_header(p)
            last_pkt_num_i2 = seq_num
            if seq_num == next_pkt_num then
                self:process_packet(i1, o, seq_num)
                found_next = true
            end
        end
        if not found_next and i1_pkts and i2_pkts then
            if last_pkt_num_i1 < last_pkt_num_i2 then
                self:process_packet(i1, o, last_pkt_num_i1)
            else
                self:process_packet(i2, o, last_pkt_num_i2)
            end
            found_next = true
        end
        if not found_next then
            break
        end
    end
end

function Recombination:process_packet(input, output, pkt_num)
    local p = link.receive(input)
    p = packet.shiftleft(p, HEADER_SIZE)
    link.transmit(output, p)
    self.last_pkt_num = pkt_num
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

    local header_pointer = ffi.cast(header_pointer_ctype, p.data)
    local sequence_number = lshift(header_pointer[0], 24);
    sequence_number = band(sequence_number, lshift(header_pointer[1], 16));
    sequence_number = band(sequence_number, lshift(header_pointer[2], 8));
    sequence_number = band(sequence_number, header_pointer[3]);

    local length = lshift(header_pointer[4], 16)
    length = band(length, lshift(header_pointer[5], 8))
    length = band(length, header_pointer[6])

    local type = header_pointer[7]

    return sequence_number, length, type
end
