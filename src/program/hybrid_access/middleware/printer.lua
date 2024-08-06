module(..., package.seeall)

local link = require("core.link")
local base = require("program.hybrid_access.base.base")

Printer = {}
Printer.config = {
    -- name of printer
    name = { required = false },
    -- print packet bytes
    bytes = { default = true },
    -- write into file
    file = { required = false }
}

function Printer:new(conf)
    local o = {
        name = conf.name or "",
        bytes = conf.bytes,
        file = conf.file,
        buffer = {}
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Printer:push()
    local input = assert(self.input.input, "input port not found")
    local output = assert(self.output.output, "output port not found")

    while not link.empty(input) do
        local p = link.receive(input)
        if self.bytes then
            table.insert(self.buffer, base.data_to_str(p.data, p.length))
        else
            table.insert(self.buffer, base.pkt_to_str(p))
        end
        link.transmit(output, p)
    end
end

function Printer:flush_buffer()
    local f = io.open(self.file, "a")
    if f == nil then
        return
    end
    for i, value in ipairs(self.buffer) do
        f:write(value)
        f:write('\n')
        self.buffer[i] = nil
    end

    f:close()
end

function Printer:print()
    if #self.buffer == 0 then
        return
    end
    if self.file ~= nil then
        self:flush_buffer()
    else
        for i, value in ipairs(self.buffer) do
            print(value)
            self.buffer[i] = nil
        end
    end
end