module(..., package.seeall)

local ffi = require("ffi")
local link = require("core.link")
local ethernet = require("lib.protocol.ethernet")

Layer2Forwarder = {}
Layer2Forwarder.config = {
    source_mac = { required = true },
    destination_mac = { required = true }
}

function Layer2Forwarder:new(conf)
    local o = {
        source_mac = ethernet:pton(conf.source_mac),
        destination_mac = ethernet:pton(conf.destination_mac)
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Layer2Forwarder:push()
    local input = assert(self.input.input, "input port not found")
    local output = assert(self.output.output, "output port not found")

    for _ = 1, link.nreadable(input) do
        local p = link.receive(input)
        ffi.copy(p.data, self.destination_mac, 6)
        ffi.copy(p.data + 6, self.source_mac, 6)
        link.transmit(output, p)
    end
end