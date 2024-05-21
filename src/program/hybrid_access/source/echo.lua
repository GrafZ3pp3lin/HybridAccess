module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local link = require("core.link")
local packet = require("core.packet")

local function build_packet(seq_no)
    local size = 60
    local data = ffi.new("uint8_t[?]", size)
    local seq_num_ptr = ffi.cast("uint32_t*", data + size - 4)
    seq_num_ptr[0] = lib.htonl(seq_no)
    local p = packet.from_pointer(data, size)
    return p
end

local function init_buffer(buffer)
    for i = 1, 50, 1 do
        buffer[i] = build_packet(i)
    end
end

local function read_seq_no(p)
    local size = 60
    local seq_num_ptr = ffi.cast("uint32_t*", p.data + size - 4)
    local seq_num = lib.ntohl(seq_num_ptr[0])
    return seq_num
end

Echo = {}

function Echo:new(cfg)
    local o = {
        buffer = {},
        name = cfg.name
    }
    if cfg.init then
        init_buffer(o.buffer)
    end
    setmetatable(o, self)
    self.__index = self
    return o
end

function Echo:pull()
    local count = #self.buffer
    if count ~= 50 then
        return
    end

    local output = assert(self.output.output, "output port not found")
    for i = 1, count do
        local p = self.buffer[i]
        link.transmit(output, p)
        self.buffer[i] = nil
    end
end

function Echo:push()
    local input = assert(self.input.input, "input port not found")

    if link.empty(input) then
        return
    end

    local count = #self.buffer
    for i = 1, link.nreadable(input) do
        local p = link.receive(input)
        local seq_no = read_seq_no(p)
        if seq_no ~= i + count then
            error(self.name .. ": packets durcheinander: " .. seq_no .. ", " .. (i + count))
        end
        self.buffer[i + count] = p
    end
end

function Echo:stop()
    local count = #self.buffer
    for i = 1, count do
        packet.free(self.buffer[i])
        self.buffer[i] = nil
    end
end

function Echo:file_report(f)
    local input_stats = link.stats(self.input.input)
    local output_stats = link.stats(self.output.output)

    f:write(
    string.format("%20s# / %20sb in", lib.comma_value(input_stats.txpackets), lib.comma_value(input_stats.txbytes)), "\n")
    f:write(
    string.format("%20s# / %20sb out", lib.comma_value(output_stats.txpackets), lib.comma_value(output_stats.txbytes)),
        "\n")
end
