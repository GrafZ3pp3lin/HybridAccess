module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local lib = require("core.lib")

local co = require("program.hybrid_access.base.constants")
local buffer = require("program.hybrid_access.base.buffer_ts")

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
        next_seq_no = ffi.new("uint64_t", 0),
        link_delays = conf.link_delays,
        wait_until_time = nil,
        wait_until_seq_no = ffi.new("uint64_t", 0),
        empty_link = nil,
        pull_npackets = conf.pull_npackets,

        -- timeout_startet = 0,
        -- timeout_reached = 0,
        -- drop_seq_no = 0,
        -- missing = 0,
    }
    o.buffer = {}
    o.buffer[1] = buffer.PacketWithTimestampBuffer:new(65536)
    o.buffer[2] = buffer.PacketWithTimestampBuffer:new(65536)
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

function Recombination:fetch_links()
    local current_time = C.get_time_ns()
    for i = 1, 2, 1 do
        local iface_in = self.ordered_input[i]
        local buf = self.buffer[i]
        while not empty(iface_in) do
            local pkt = receive(iface_in)
            if buf.enqueue(pkt, current_time) == 0 then
                free(pkt)
                break
            end
        end
        while not empty(iface_in) do
            local pkt = receive(iface_in)
            free(pkt)
        end
    end
end

function Recombination:push()
    -- fetch and buffer packets from links
    self:fetch_links()

    local mode = 1
    if self.wait_until_time ~= nil then
        mode = self:get_processing_mode()
    end

    local output_link = self.output.output

    if mode == 1 then
        -- process links normally
        self:process_links(output_link)
    elseif mode == 2 then
        -- timeout occured & one link is empty
        self:process_timeout(output_link)
    end
end

---Process packets.
---Instantly process the next expected sequence number.
---Else if both links do have packets choose the lower sequence number first.
---If there is an empty link, start a timer to wait for the expected packet.
---@param output_link any output link
function Recombination:process_links(output_link)
    local buffered_input_index = 0
    local buffered_header = nil
    local any_link_empty = false

    local pulled = 0

    -- while at least one packet exists
    while (not self.buffer[1]:is_empty() or not self.buffer[2]:is_empty()) and pulled < self.pull_npackets do
        any_link_empty = false
        buffered_header = nil
        pulled = pulled + 1
        -- iterate over all links
        for i = 1, 2, 1 do
            local ha_header = self:read_next_hybrid_access_pkt(self.buffer[i], output_link)
            if ha_header == nil then
                -- found no hybrid access packet on that link
                any_link_empty = true
            elseif ha_header.seq_no == self.next_seq_no then
                -- found expected packet
                if ha_header.seq_no >= self.wait_until_seq_no then
                    -- reset timeout if preceding packet has arrived
                    self.wait_until_time = nil
                end
                self:process_packet(self.buffer[i], output_link, ha_header)
                buffered_header = nil
                break
            elseif ha_header.seq_no < self.next_seq_no then
                -- Discard packets with a smaller sequence number than expected
                -- self.drop_seq_no = self.drop_seq_no + 1 -- COUNTER
                local pkt_ts_real = self.buffer[i]:dequeue()
                free(pkt_ts_real.packet)
                buffered_header = nil
                break
            elseif buffered_header == nil or ha_header.seq_no < buffered_header.seq_no then
                -- packet has not the next expected sequence number - buffer the number and compare it with the other links
                buffered_header = ha_header
                buffered_input_index = i
            end
        end
        if buffered_header ~= nil then
            if not any_link_empty then
                -- forward packet with lower sequence number
                if buffered_header.seq_no >= self.wait_until_seq_no then
                    -- reset timeout if preceding packet has arrived
                    self.wait_until_time = nil
                end
                -- self.missing = self.missing + (buffered_header.seq_no - self.next_seq_no) -- COUNTER
                self:process_packet(self.buffer[buffered_input_index], output_link, buffered_header)
            elseif self.wait_until_time ~= nil then
                -- we wait already for another packet
                break
            else
                -- there is one empty link and a paket with an unexpected sequence number on the other link.
                -- wait till either:
                -- - preceding packet arrives
                -- - timeout
                local empty_link_index = 3 - buffered_input_index -- either 1 or 2
                local pkt_ts = self.buffer[buffered_input_index]:peek()
                -- self.timeout_startet = self.timeout_startet + 1 -- COUNTER
                self.wait_until_time = pkt_ts.timestamp + self.link_delays[empty_link_index]
                self.wait_until_seq_no = buffered_header.seq_no - 1
                self.empty_link = empty_link_index
                break
            end
        end
    end
end

---Process packets after timeout.
---Forward all packets with timeout reached 
---@param output_link any output link
function Recombination:process_timeout(output_link)
    local buf = self.buffer[3 - self.empty_link]
    local current_time = C.get_time_ns()

    -- forward all packets where the timeout is reached
    while not buf:is_empty() do
        local pkt_ts = buf:peek()
        if pkt_ts.timestamp > current_time then
            break
        end
        local ha_header = self.hybrid_access:get_header(pkt_ts.packet)
        if ha_header ~= nil and ha_header.seq_no >= self.next_seq_no then
            self:process_packet(buf, output_link, ha_header)
        elseif ha_header ~= nil and ha_header.seq_no >= self.next_seq_no then
            local pkt_ts_real = buf:dequeue()
            free(pkt_ts_real.packet)
        else
            local pkt_ts_real = buf:dequeue()
            transmit(output_link, pkt_ts_real.packet)
        end
    end
end

---Checks if processing packets should be continued or we still have to wait for the next packet.
---Checks if timeout is reached or new packets arrived.
---@return integer mode continue mode
function Recombination:get_processing_mode()
    -- check if packet on the empty link has arrived
    if not self.buffer[self.empty_link]:is_empty() then
        -- empty link is no longer empty
        return 1
    end
    -- check if timeout is reached
    local current_time = C.get_time_ns()
    if current_time >= self.wait_until_time then
        -- timeout reached
        self.wait_until_time = nil
        -- self.timeout_reached = self.timeout_reached + 1 -- COUNTER
        return 2
    end

    return 0
end

---read next hybrid access packet from input link.
---@param buf any
---@param output_link any
---@return unknown ha_header hybrid access header (nil if no packet available)
function Recombination:read_next_hybrid_access_pkt(buf, output_link)
    if buf:is_empty() then
        return nil
    end
    local pkt_ts = buf:peek()
    local ha_header = self.hybrid_access:get_header(pkt_ts.packet)
    if ha_header == nil then
        repeat
            -- just forward non hybrid packets
            local pkt_ts_real = buf:dequeue()
            transmit(output_link, pkt_ts_real.packet)
            if buf:is_empty() then
                break
            end
            pkt_ts = buf:peek()
            ha_header = self.hybrid_access:get_header(pkt_ts.packet)
        until ha_header ~= nil
    end
    return ha_header
end

---process the next packet from link input
---@param buf any input link
---@param output_link any output link
---@param ha_header any hybrid access header
function Recombination:process_packet(buf, output_link, ha_header)
    local pkt_ts = buf:dequeue()
    self.next_seq_no = ha_header.seq_no + 1
    if ha_header.type == HYBRID_ACCESS_TYPE then
        local pkt = self.hybrid_access:remove_header(pkt_ts.packet, ha_header.buf_type) -- DO NOT ACCESS ha_header after this, because memory gets overwritten here
        transmit(output_link, pkt)
    else
        free(pkt_ts.packet)
    end
end
