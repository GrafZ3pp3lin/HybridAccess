module(..., package.seeall)

local link = require("core.link")
local base = require("program.hybrid_access.base.base")

Printer = {}
Printer.config = {
    -- name of printer
    name = { required = false },
    -- print packet bytes
    bytes = { default = false }
}

function Printer:new(conf)
    local o = {
        name = conf.name or "",
        bytes = conf.bytes
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
        if self.bytes then
            print(self.name, base.data_to_str(p.data, p.length))
        else
            print(self.name, base.pkt_to_str(p))
        end
        link.transmit(output, p)
    end
end