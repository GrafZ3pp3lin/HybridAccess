module(..., package.seeall)

local link = require("core.link")
local loadbalancer = require("program.hybrid_access.loadbalancer.loadbalancer")

local empty, receive = link.empty, link.receive

SingleLink = loadbalancer.LoadBalancer:new()
SingleLink.config = {
    setup = { required = false }
}

function SingleLink:new(conf)
    local o = {
        class_type = "SingleLink"
    }
    setmetatable(o, self)
    self.__index = self
    o:setup(conf.setup)
    return o
end

function SingleLink:push()
    local iface_in = assert(self.input.input, "input port not found")
    local iface_out1 = assert(self.output.output1, "output port 1 not found")

    while not empty(iface_in) do
        local p = receive(iface_in)
        self:send_pkt(p, iface_out1)
    end
end
