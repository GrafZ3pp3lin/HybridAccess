module(..., package.seeall)

local link = require("core.link")
local loadbalancer = require("program.hybrid_access.loadbalancer.loadbalancer")

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
    local i = assert(self.input.input, "input port not found")
    local o1 = assert(self.output.output1, "output port 1 not found")

    for _ = 1, link.nreadable(i) do
        local p = link.receive(i)
        self:send_pkt(p, o1)
    end
end
