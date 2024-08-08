module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local lib = require("core.lib")

local co = require("program.hybrid_access.base.constants")

local HYBRID_ACCESS_TYPE = co.HYBRID_ACCESS_TYPE

local C = ffi.C

local transmit, receive, empty, front = link.transmit, link.receive, link.empty, link.front
local free = packet.free

Recombination = {}
Recombination.config = {
    link_delays = { required = true },
    mode = { required = false },
    pull_npackets = { default = 204 }
}

function Recombination:new(conf)
    local o = {
        ordered_input = {},
        next_pkt_num = ffi.new("uint64_t", 0),
        link_delays = conf.link_delays,
        wait_until = nil,
        pull_npackets = conf.pull_npackets,

        -- timeout_startet = 0,
        -- timeout_reached = 0,
        -- drop_seq_no = 0,
        -- missing = 0,
    }
    if conf.mode == "IP" then
        print("Recombination in ip mode")
        self.hybrid_access = require("program.hybrid_access.base.hybrid_access_ip").HybridAccessIp:new(conf)
    else
        print("Recombination in eth mode")
        self.hybrid_access = require("program.hybrid_access.base.hybrid_access").HybridAccess:new()
    end
    print(string.format("%fms link delay for link 1, %fms link delay for link 2", o.link_delays[1] / 1e6, o.link_delays[2] / 1e6))
    setmetatable(o, self)
    self.__index = self
    
    return o
end

function Recombination:report()
    local in1_stats = link.stats(self.ordered_input[1])
    local in2_stats = link.stats(self.ordered_input[2])
    local output_stats = link.stats(self.output.output)

    print(string.format("%20s # / %20s b in 1", lib.comma_value(in1_stats.txpackets), lib.comma_value(in1_stats.txbytes)))
    print(string.format("%20s # / %20s b in 2", lib.comma_value(in2_stats.txpackets), lib.comma_value(in2_stats.txbytes)))
    print(string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets),
        lib.comma_value(output_stats.txbytes)))

    print(string.format("%20s timeout started", lib.comma_value(self.timeout_startet)))
    print(string.format("%20s timeout reached", lib.comma_value(self.timeout_reached)))
    print(string.format("%20s dropped packages because of too low seq num",
        lib.comma_value(self.drop_seq_no)))
    print(string.format("%20s missing seq nums", lib.comma_value(self.missing)))
end

function Recombination:link(in_or_out, l_name)
    if in_or_out ~= 'input' then
        return
    end
    local index = tonumber(string.sub(l_name, 6))
    if index == nil then
        error("link name is not parsable: "..l_name)
        return
    end
    print(string.format("recombination: added link %s as index %i", l_name, index))
    self.ordered_input[index] = self.input[l_name]
end

function Recombination:push()
    local process, waited = true, false

    if self.wait_until ~= nil then
        process, waited = self:continue_processing()
    end

    if not process then
        return
    end

    local output_link = self.output.output

    if waited then
        self:process_waited(output_link)
    end

    self:process_links(output_link)
end

---Process packets.
---Instantly process the next expected sequence number.
---Else if both links do have packets choose the lower sequence number first.
---If there is an empty link, start a timer to wait for the expected packet.
---@param output_link any output link
function Recombination:process_links(output_link)
    local buffered_input_index = 0
    local buffered_header = nil
    local empty_link = false

    local pulled = 0

    -- while at least one packet exists
    while (not empty(self.ordered_input[1]) or not empty(self.ordered_input[2])) and pulled < self.pull_npackets do
        empty_link = false
        buffered_header = nil
        pulled = pulled + 1
        -- iterate over all links
        for i = 1, 2, 1 do
            local ha_header = self:read_next_hybrid_access_pkt(self.ordered_input[i], output_link)
            if ha_header == nil then
                -- found no hybrid access packet on that link
                empty_link = true
            elseif ha_header.seq_no == self.next_pkt_num then
                -- found expected packet
                self:process_packet(self.ordered_input[i], output_link, ha_header)
                self.wait_until = nil
                buffered_header = nil
                break
            elseif ha_header.seq_no < self.next_pkt_num then
                -- Discard packets with a smaller sequence number than expected
                -- self.drop_seq_no = self.drop_seq_no + 1 -- COUNTER
                local p_real = receive(self.ordered_input[i])
                free(p_real)
                buffered_header = nil
                break;
            elseif buffered_header == nil or ha_header.seq_no < buffered_header.seq_no then
                -- packet has not the next expected sequence number - buffer the number and compare it with the other links
                buffered_header = ha_header
                buffered_input_index = i
            end
        end
        if buffered_header ~= nil then
            if not empty_link then
                -- self.missing = self.missing + (buffered_header.seq_no - self.next_pkt_num) -- COUNTER
                self:process_packet(self.ordered_input[buffered_input_index], output_link, buffered_header)
                self.wait_until = nil
            elseif self.wait_until ~= nil then
                -- we wait already for another packet
                break
            else
                -- there is one empty link and a paket with an unexpected sequence number on the other link.
                -- wait till either:
                -- - there is no empty link
                -- - timeout
                local current_time = C.get_time_ns()
                -- self.timeout_startet = self.timeout_startet + 1 -- COUNTER
                self.wait_until = current_time + self:get_wait_time(buffered_input_index)
                self.empty_links = self:get_empty_links()
                break
            end
        end
    end
end

---Process packets after timeout.
---Choose the one with the lowest sequence number.
---@param output_link any output link
function Recombination:process_waited(output_link)
    local buffered_input_index = 0
    local buffered_header = nil

    for i = 1, 2, 1 do
        local ha_header = self:read_next_hybrid_access_pkt(self.ordered_input[i], output_link)
        if ha_header ~= nil and (buffered_header == nil or ha_header.seq_no < buffered_header.seq_no) then
            buffered_input_index = i
            buffered_header = ha_header
        end
    end
    if buffered_header ~= nil then
        -- self.missing = self.missing + (buffered_header.seq_no - self.next_pkt_num) -- COUNTER
        self:process_packet(self.ordered_input[buffered_input_index], output_link, buffered_header)
    end
end

---Checks if processing packets should be continued or we still have to wait for the next packet.
---Checks if timeout is reached or new packets arrived.
---@return boolean continue continue processing
---@return boolean waited timeout reached
function Recombination:continue_processing()
    local current_time = C.get_time_ns()
    if current_time >= self.wait_until then
        self.wait_until = nil
        -- self.timeout_reached = self.timeout_reached + 1 -- COUNTER
        return true, true
    else
        -- check if an empty link is no longer empty
        for _, k in ipairs(self.empty_links) do
            if not empty(self.ordered_input[k]) then
                return true, false
            end
        end
    end
    return false, false
end

function Recombination:get_wait_time(not_empty_link_index)
    return self.link_delays[3 - not_empty_link_index]
end

function Recombination:get_empty_links()
    local links = {}
    local index = 1
    for i, v in ipairs(self.ordered_input) do
        if empty(v) then
            links[index] = i
            index = index + 1
        end
    end
    return links
end

---read next hybrid access packet from input link.
---@param input_link any
---@param output_link any
---@return unknown ha_header hybrid access header (nil if no packet available)
function Recombination:read_next_hybrid_access_pkt(input_link, output_link)
    if empty(input_link) then
        return nil
    end
    local p = front(input_link)
    local ha_header = self.hybrid_access:get_header(p)
    if ha_header == nil then
        repeat
            -- just forward non hybrid packets
            local p_real = receive(input_link)
            transmit(output_link, p_real)
            if empty(input_link) then
                break
            end
            p = front(input_link)
            ha_header = self.hybrid_access:get_header(p)
        until ha_header ~= nil
    end
    return ha_header
end

---process the next packet from link input
---@param input_link any input link
---@param output_link any output link
---@param ha_header any hybrid access header
function Recombination:process_packet(input_link, output_link, ha_header)
    local p = receive(input_link)
    self.next_pkt_num = ha_header.seq_no + 1
    if ha_header.type == HYBRID_ACCESS_TYPE then
        p = self.hybrid_access:remove_header(p, ha_header.buf_type) -- DO NOT ACCESS ha_header after this, because memory gets overwritten here
        transmit(output_link, p)
    else
        free(p)
    end
end
