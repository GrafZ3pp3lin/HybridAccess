module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local ethernet = require("lib.protocol.ethernet")

local copy = ffi.copy
local receive, transmit, empty = link.receive, link.transmit, link.empty

MacForwarder = {}
MacForwarder.config = {
    source_mac = { required = true },
    destination_mac = { required = true }
}

function MacForwarder:new(conf)
    local source_mac = ethernet:pton(conf.source_mac)
    local destination_mac = ethernet:pton(conf.destination_mac)
    local eth_header_addr = ffi.new("uint8_t[12]")
    copy(eth_header_addr, destination_mac, 6)
    copy(eth_header_addr + 6, source_mac, 6)

    local o = {
        header_addr = eth_header_addr
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function MacForwarder:push()
    local input = assert(self.input.input, "input port not found")
    local output = assert(self.output.output, "output port not found")

    while not empty(input) do
        local p = receive(input)
        copy(p.data, self.header_addr, 12)
        transmit(output, p)
    end
end