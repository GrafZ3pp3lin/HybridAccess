module(..., package.seeall)

local link = require("core.link")
local base = require("program.hybrid_access.base.base")

Printer = {}
Printer.config = {
    name = { required = false },
}

function Printer:new(conf)
    local o = {
        name = conf.name or "",
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Printer:push()
    local input = assert(self.input.input, "input port not found")
    local output = assert(self.output.output, "output port not found")

    for _ = 1, link.nreadable(input) do
        local p = link.receive(input)
        print(self.name, base.pkt_to_str(p))
        link.transmit(output, p)
    end
end