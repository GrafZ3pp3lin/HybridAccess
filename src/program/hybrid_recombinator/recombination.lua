module(..., package.seeall)

local link = require("core.link")
local engine = require("core.app")
local ha = require("program.hybrid_access.base.hybrid_access")

Recombination = {}
Recombination.config = {
    link_delays = {required=true},
}

function Recombination:new (conf)
    local o = {
        next_pkt_num = 0,
        link_delays = conf.link_delays,
        wait_until = nil
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Recombination:pull()
    local process, waited = true, false

    if self.wait_until ~= nil then
        process, waited = self:wait_for_next_packet()
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
            local p = link.front(self.input[i])
            local eth_type = ha.get_eth_type(p)
            if eth_type ~= ha.HYBRID_ACCESS_TYPE and eth_type ~= ha.HYBRID_ACCESS_DDC_TYPE then
                -- just forward non hybrid packets
                print("non hybrid package!")
                local p_real = link.receive(self.input[i])
                link.transmit(output, p_real)
                found_pkt = true
                break
            end
            local seq_num, ha_type = ha.read_hybrid_access_header(p)
            if seq_num == self.next_pkt_num then
                -- found next packet
                self:process_packet(self.input[i], output, seq_num, eth_type, ha_type)
                found_pkt = true
                break
            elseif seq_num < self.next_pkt_num then
                print("dismiss packet with lower seq num as expected", seq_num, self.next_pkt_num, i)
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

function Recombination:process_with_empty_link(input, output)
    while not link.empty(input) do
        local p = link.front(input)
        local eth_type = ha.get_eth_type(p)
        if eth_type ~= ha.HYBRID_ACCESS_TYPE and eth_type ~= ha.HYBRID_ACCESS_DDC_TYPE then
            -- just forward non hybrid packets
            local p_real = link.receive(input)
            link.transmit(output, p_real)
        else
            local seq_num, ha_type = ha.read_hybrid_access_header(p)
            if seq_num == self.next_pkt_num then
                -- found next packet
                self:process_packet(input, output, seq_num, eth_type, ha_type)
                self.wait_until = nil
            elseif seq_num < self.next_pkt_num then
                print("dismiss packet with lower seq num as expected", seq_num, self.next_pkt_num)
                local p_real = link.receive(input)
                packet.free(p_real)
                break
            else
                local now = engine.now()
                self.wait_until = now + self:estimate_wait_time()
                self.empty_links = self:get_empty_links()
                break
            end
        end
    end
end

function Recombination:process_waited(output)
    local buf_seq_no = math.huge
    local buf_ha_type = 0
    local buf_input_index
    local buf_eth_type = 0

    for i = 1, 2, 1 do
        if not link.empty(self.input[i]) then
            local p = link.front(self.input[i])
            local eth_type = ha.get_eth_type(p)
            if eth_type ~= ha.HYBRID_ACCESS_TYPE and eth_type ~= ha.HYBRID_ACCESS_DDC_TYPE then
                error("non hybrid packet when waited")
            end
            local seq_num, ha_type = ha.read_hybrid_access_header(p)
            if seq_num < buf_seq_no then
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

function Recombination:wait_for_next_packet()
    if engine.now() >= self.wait_until then
        self.wait_until = nil
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
            times[index] = self.link_delays["delay"..i]
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
