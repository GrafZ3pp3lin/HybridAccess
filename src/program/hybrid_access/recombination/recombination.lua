module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local engine = require("core.app")
local lib = require("core.lib")
local counter = require("core.counter")

local co = require("program.hybrid_access.base.constants")

local HYBRID_ACCESS_TYPE = co.HYBRID_ACCESS_TYPE

Recombination = {}
Recombination.config = {
    link_delays = { required = true },
    mode = { required = false }
}
Recombination.shm = {
    timeout_startet = { counter },
    timeout_reached = { counter },
    drop_seq_no = { counter },
}

function Recombination:new(conf)
    local o = {
        next_pkt_num = ffi.new("uint64_t", 0),
        link_delays = conf.link_delays,
        wait_until = nil
    }
    if conf.mode == "IP" then
        print("Recombination in ip mode")
        self.hybrid_access = require("program.hybrid_access.base.hybrid_access_ip").HybridAccessIp:new(conf)
    else
        print("Recombination in eth mode")
        self.hybrid_access = require("program.hybrid_access.base.hybrid_access").HybridAccess:new()
    end
    setmetatable(o, self)
    self.__index = self
    return o
end

function Recombination:report()
    local in1_stats = link.stats(self.input[1])
    local in2_stats = link.stats(self.input[2])
    local output_stats = link.stats(self.output.output)

    print(string.format("%20s # / %20s b in 1", lib.comma_value(in1_stats.txpackets), lib.comma_value(in1_stats.txbytes)))
    print(string.format("%20s # / %20s b in 2", lib.comma_value(in2_stats.txpackets), lib.comma_value(in2_stats.txbytes)))
    print(string.format("%20s # / %20s b out", lib.comma_value(output_stats.txpackets), lib.comma_value(output_stats.txbytes)))
    print(string.format("%20s timeout started", lib.comma_value(counter.read(self.shm.timeout_startet))))
    print(string.format("%20s timeout reached", lib.comma_value(counter.read(self.shm.timeout_reached))))
    print(
        string.format("%20s dropped packages because of too low seq num",
            lib.comma_value(counter.read(self.shm.drop_seq_no))))
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

    self:process_links(output)
end

---Process packets.
---Instantly process the next expected sequence number.
---Else if both links do have packets choose the lower sequence number first.
---If there is an empty link, start a timer to wait for the expected packet.
---@param output any output link
function Recombination:process_links(output)
    local buffered_input_index
    local buffered_header = nil
    local empty_link = false

    while not link.empty(self.input[1]) or not link.empty(self.input[2]) do
        empty_link = false
        buffered_header = nil
        for i = 1, 2, 1 do
            local ha_header = self:read_next_hybrid_access_pkt(self.input[i], output)
            if ha_header == nil then
                -- found no packet on that link
                empty_link = true
            elseif ha_header.seq_no == self.next_pkt_num then
                -- found next packet
                self:process_packet(self.input[i], output, ha_header)
                self.wait_until = nil
                break
            elseif ha_header.seq_no < self.next_pkt_num then
                counter.add(self.shm.drop_seq_no)
                local p_real = link.receive(self.input[i])
                packet.free(p_real)
                break;
            elseif buffered_header == nil or ha_header.seq_no < buffered_header.seq_no then
                -- packet has not the next expected sequence number - buffer the number and compare it with the other links
                buffered_header = ha_header
                buffered_input_index = i
            end
        end
        if buffered_header ~= nil then
            if not empty_link then
                self:process_packet(self.input[buffered_input_index], output, buffered_header)
                self.wait_until = nil
            elseif self.wait_until == nil then
                local now = engine.now()
                counter.add(self.shm.timeout_startet)
                self.wait_until = now + self:estimate_wait_time()
                self.empty_links = self:get_empty_links()
                break
            end
        end
    end
end

---Process packets after timeout.
---Choose the one with the lowest sequence number.
---@param output any output link
function Recombination:process_waited(output)
    local buffered_input_index
    local buffered_header = nil

    for i = 1, 2, 1 do
        if not link.empty(self.input[i]) then
            local ha_header = self:read_next_hybrid_access_pkt(self.input[i], output)
            if ha_header ~= nil and (buffered_header == nil or ha_header.seq_no < buffered_header.seq_no) then
                buffered_input_index = i
                buffered_header = ha_header
            end
        end
    end
    if buffered_header ~= nil then
        --print("waited for ", buffered_header.seq_no, self.next_pkt_num, buffered_input_index)
        self:process_packet(self.input[buffered_input_index], output, buffered_header)
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
            times[index] = self.link_delays[i]
            index = index + 1
        end
    end
    if index == 2 then
        return times[1]
    elseif index == 1 then
        error("could not estimate wait time due to no empty links")
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
---@param input any
---@param output any
---@return unknown ha_header hybrid access header (nil if no packet available)
function Recombination:read_next_hybrid_access_pkt(input, output)
    if link.empty(input) then
        return nil
    end
    local p = link.front(input)
    local ha_header = self.hybrid_access:get_header(p)
    while ha_header == nil do
        -- just forward non hybrid packets
        local p_real = link.receive(input)
        link.transmit(output, p_real)
        if link.empty(input) then
            break
        end
        p = link.front(input)
        ha_header = self.hybrid_access:get_header(p)
    end
    return ha_header
end

---process the next packet from link input
---@param input any input link
---@param output any output link
---@param ha_header any hybrid access header
function Recombination:process_packet(input, output, ha_header)
    local p = link.receive(input)
    self.next_pkt_num = ha_header.seq_no + 1
    if ha_header.type == HYBRID_ACCESS_TYPE then
        p = self.hybrid_access:remove_header(p, ha_header.buf_type) -- DO NOT ACCESS ha_header after this, because memory gets overwritten here
        link.transmit(output, p)
    else
        packet.free(p)
    end
end
