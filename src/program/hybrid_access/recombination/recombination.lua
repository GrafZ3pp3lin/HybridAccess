module(..., package.seeall)

local link = require("core.link")
local engine = require("core.app")
local lib = require("core.lib")
local counter = require("core.counter")
local ha = require("program.hybrid_access.base.hybrid_access")

Recombination = {}
Recombination.config = {
    link_delays = { required = true },
}
Recombination.shm = {
    timeout_startet = { counter },
    timeout_reached = { counter },
    drop_seq_no = { counter },
}

function Recombination:new(conf)
    local o = {
        next_pkt_num = 0,
        link_delays = conf.link_delays,
        wait_until = nil
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Recombination:file_report(f)
    local in1_stats = link.stats(self.input[1])
    local in2_stats = link.stats(self.input[2])
    local output_stats = link.stats(self.output.output)

    f:write(
    string.format("%20s# / %20sb in 1", lib.comma_value(in1_stats.txpackets), lib.comma_value(in1_stats.txbytes)), "\n")
    f:write(
    string.format("%20s# / %20sb in 2", lib.comma_value(in2_stats.txpackets), lib.comma_value(in2_stats.txbytes)), "\n")
    f:write(
    string.format("%20s# / %20sb out", lib.comma_value(output_stats.txpackets), lib.comma_value(output_stats.txbytes)),
        "\n")
    f:write(string.format("%20s timeout started", lib.comma_value(counter.read(self.shm.timeout_startet))), "\n")
    f:write(string.format("%20s timeout reached", lib.comma_value(counter.read(self.shm.timeout_reached))), "\n")
    f:write(
    string.format("%20s dropped packages because of too low seq num", lib.comma_value(counter.read(self.shm.drop_seq_no))),
        "\n")
end

function Recombination:pull()
    local process, waited = true, false

    if self.wait_until ~= nil then
        process, waited = self:continue_processing()
    end

    if not process then
        return
    end

    local output = assert(self.output.output, "output port not found")

    if waited then
        self:process_waited(output)
    end

    if not link.empty(self.input[1]) and not link.empty(self.input[2]) then
        self.wait_until = nil
        self:process_non_empty_links(output)
    end
    if not link.empty(self.input[1]) then
        self:process_with_empty_link(self.input[1], output)
    end
    if not link.empty(self.input[2]) then
        self:process_with_empty_link(self.input[2], output)
    end
end

---Process packets with only non-empty links.
---Always choose the lower sequence number first.
---@param output link
function Recombination:process_non_empty_links(output)
    local buf_seq_no = math.huge
    local buf_ha_type = 0
    local buf_input_index
    local buf_eth_type = 0
    local found_pkt = false

    while not link.empty(self.input[1]) and not link.empty(self.input[2]) do
        buf_seq_no = math.huge
        found_pkt = false
        for i = 1, 2, 1 do
            local eth_type, seq_num, ha_type = self:read_next_hybrid_access_pkt(self.input[i], output)
            if eth_type == -1 then
                -- found no packet on that link - stop processing
                return
            elseif seq_num == self.next_pkt_num then
                -- found next packet
                self:process_packet(self.input[i], output, seq_num, eth_type, ha_type)
                found_pkt = true
                break
            elseif seq_num < self.next_pkt_num then
                counter.add(self.shm.drop_seq_no)
                local p_real = link.receive(self.input[i])
                packet.free(p_real)
                found_pkt = true
                break;
            elseif seq_num < buf_seq_no then
                -- packet has not the next expected sequence number - buffer the number and compare it with the other links
                buf_input_index = i
                buf_seq_no = seq_num
                buf_ha_type = ha_type
                buf_eth_type = eth_type
            end
        end
        if not found_pkt and buf_seq_no ~= math.huge then
            self:process_packet(self.input[buf_input_index], output, buf_seq_no, buf_eth_type, buf_ha_type)
        end
    end
end

---Process packets where the other link is empty.
---Process packets from this link as long as the sequence numbers are consecutive.
---@param input link
---@param output link
function Recombination:process_with_empty_link(input, output)
    while not link.empty(input) do
        local eth_type, seq_num, ha_type = self:read_next_hybrid_access_pkt(input, output)
        if eth_type == -1 then
            -- found no packet on that link - stop processing
            break
        elseif seq_num == self.next_pkt_num then
            -- found next packet
            self:process_packet(input, output, seq_num, eth_type, ha_type)
            self.wait_until = nil
        elseif seq_num < self.next_pkt_num then
            counter.add(self.shm.drop_seq_no)
            local p_real = link.receive(input)
            packet.free(p_real)
            break
        else
            local now = engine.now()
            counter.add(self.shm.timeout_startet)
            self.wait_until = now + self:estimate_wait_time()
            self.empty_links = self:get_empty_links()
            break
        end
    end
end

---Process packets after timeout.
---Choose the one with the lowest sequence number.
---@param output link
function Recombination:process_waited(output)
    local buf_seq_no = math.huge
    local buf_ha_type = 0
    local buf_input_index
    local buf_eth_type = 0

    for i = 1, 2, 1 do
        if not link.empty(self.input[i]) then
            local eth_type, seq_num, ha_type = self:read_next_hybrid_access_pkt(self.input[i], output)
            if eth_type ~= -1 and seq_num < buf_seq_no then
                buf_input_index = i
                buf_seq_no = seq_num
                buf_ha_type = ha_type
                buf_eth_type = eth_type
            end
        end
    end
    if buf_seq_no ~= math.huge then
        -- print("waited for ", buf_seq_no, self.next_pkt_num, buf_input_index)
        self:process_packet(self.input[buf_input_index], output, buf_seq_no, buf_eth_type, buf_ha_type)
    end
end

---Checks if processing packets should be continued or we still have to wait for the next packet.
---Checks if timeout is reached or new packets arrived.
---@return boolean continue continue processing
---@return boolean waited timeout reached
function Recombination:continue_processing()
    if engine.now() >= self.wait_until then
        self.wait_until = nil
        counter.add(self.shm.timeout_reached)
        return true, true
    else
        -- check if an empty link is no longer empty
        for _, k in ipairs(self.empty_links) do
            if not link.empty(self.input[k]) then
                return true, false
            end
        end
    end
    return false, false
end

function Recombination:estimate_wait_time()
    local times = {}
    local index = 1
    for i, v in ipairs(self.input) do
        if link.empty(v) then
            times[index] = self.link_delays["delay" .. i]
            index = index + 1
        end
    end
    if index == 2 then
        return times[1]
    elseif index == 1 then
        print(link.empty(self.input[1]), link.empty(self.input[2]))
        return 0
    else
        return math.max(unpack(times))
    end
end

function Recombination:get_empty_links()
    local links = {}
    local index = 1
    for i, v in ipairs(self.input) do
        if link.empty(v) then
            links[index] = i
            index = index + 1
        end
    end
    return links
end

---read next hybrid access packet from input link.
---@param input link
---@param output link
---@return integer eth_type ethernet type (-1 if no packet found)
---@return integer seq_num sequence number (-1 if no packet found)
---@return integer ha_type hybrid access type (-1 if no packet found)
function Recombination:read_next_hybrid_access_pkt(input, output)
    local p = link.front(input)
    local eth_type = ha.get_eth_type(p)
    while eth_type ~= ha.HYBRID_ACCESS_TYPE and eth_type ~= ha.HYBRID_ACCESS_DDC_TYPE do
        -- just forward non hybrid packets
        local p_real = link.receive(input)
        link.transmit(output, p_real)
        p = link.front(input)
        if p == nil then
            return -1, -1, -1
        end
        eth_type = ha.get_eth_type(p)
    end
    return eth_type, ha.read_hybrid_access_header(p)
end

---process the next packet from link input
---@param input link input link
---@param output link output link
---@param seq_no integer sequence number
---@param eth_type integer ethernet type
---@param ha_type integer hybrid access type
function Recombination:process_packet(input, output, seq_no, eth_type, ha_type)
    local p = link.receive(input)
    if eth_type == ha.HYBRID_ACCESS_TYPE then
        p = ha.remove_hybrid_access_header(p, ha_type)
        link.transmit(output, p)
    else
        packet.free(p)
    end
    self.next_pkt_num = seq_no + 1
end
