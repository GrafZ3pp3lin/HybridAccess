module(..., package.seeall)

local link = require("core.link")
local packet = require("core.packet")

Printer = {}

function Printer:new ()
    local o = {}
    setmetatable(o, self)
    self.__index = self
   return o
end

function Printer:push ()
    local input = self.input.input
    for _ = 1, link.nreadable(input) do
        local p = link.receive(input)
        -- print_packet(p)
        packet.free(p)
    end
end

function print_packet(p)
    local msg = string.format("%d: ", p.length)
    for i = 0, p.length, 1 do
        msg = string.format("%s%x ", msg, p.data[i])
    end
    print(msg)
end
