local link = require("core.link")

Forwarder = {}

-- constructor
function Forwarder:new()
    local o = {
        -- definition of fields
        pkt_count = 0
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- implementation of push method
function Forwarder:push()
    -- assert that input is defined
    local iface_in = assert(self.input.input, "input not found")
    -- assert that output is defined
    local iface_out = assert(self.output.output, "output not found")

    while not link.empty(iface_in) do
        -- get the next available paket from the input link
        local pkt = link.receive(iface_in)
        self.pkt_count = self.pkt_count + 1 -- total count of packets processed 
        -- transmit the packet to the output link
        link.transmit(iface_out, pkt)
    end
end
