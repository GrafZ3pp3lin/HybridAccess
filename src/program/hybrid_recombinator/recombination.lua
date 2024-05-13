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
        link_delays = conf.link_delays
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Recombination:pull()
    local output = assert(self.output.output, "output port not found")

    local waited = false

    if self.wait_until ~= nil then
        local now = engine.now()
        if now >= self.wait_until then
            waited = true
            self.wait_until = nil
        else
            -- check if an empty link is no longer empty
            local check_pkts = false
            for _, k in ipairs(self.empty_links) do
                if not link.empty(self.input[k]) then
                    check_pkts = true
                    break
                end
            end
            if not check_pkts then
                return
            end
        end
    end

    local buf_seq_no = math.huge
    local buf_ha_type = 0
    local buf_input
    local found_pkt, empty_link_exists, packet_exists = true, false, false

    while found_pkt do
        found_pkt = false
        empty_link_exists = false
        packet_exists = false
        buf_seq_no = math.huge

        for _, i in ipairs(self.input) do
            if link.empty(i) then
                empty_link_exists = true
                goto continue
            end
            packet_exists = true
            local p = link.front(i)
            --local eth_type = ha.get_eth_type(p)
            --if eth_type ~= ha.HYBRID_ACCESS_TYPE then
            --    -- just forward non hybrid packets
            --    local p_real = link.receive(i)
            --    link.transmit(output, p_real)
            --    goto continue
            --end
            local seq_num, ha_type = ha.read_hybrid_access_header(p)
            if seq_num == self.next_pkt_num then
                -- found next packet
                self:process_packet(i, output, seq_num, ha_type)
                self.wait_until = nil
                found_pkt = true
                break
            elseif seq_num < buf_seq_no then
                buf_input = i
                buf_seq_no = seq_num
                buf_ha_type = ha_type
            end
            ::continue::
        end
        if not found_pkt then
            if ((not empty_link_exists) or waited) and buf_seq_no < math.huge then
                -- every link is full - take the one with the lowest seq_no
                self:process_packet(buf_input, output, buf_seq_no, buf_ha_type)
                found_pkt = true
            elseif empty_link_exists and packet_exists and self.wait_until == nil then
                -- at least one link is empty and the correct packet has not yet arrived - wait
                --print(link.empty(self.input.input1), link.empty(self.input.input2), empty_link_exists, packet_exists, self.next_pkt_num, buf_seq_no)
                local now = engine.now()
                self.wait_until = now + self:estimate_wait_time()
                self.empty_links = self:get_empty_links()
            end
        end
    end
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

function Recombination:process_packet(input, output, pkt_num, eth_type)
    local p = link.receive(input)
    p = ha.remove_hybrid_access_header(p, eth_type)
    link.transmit(output, p)
    self.next_pkt_num = pkt_num + 1
end
