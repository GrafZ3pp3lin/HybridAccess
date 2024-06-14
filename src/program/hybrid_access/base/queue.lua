module(..., package.seeall)

Queue = {}

function Queue:new()
    local o = {
        read = 0,
        write = 0
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Queue:size()
    return self.write - self.read
end

function Queue:peek()
    local read = self.read
    if read >= self.write then
        error("queue is empty")
    end
    return self[read]
end

function Queue:push(value)
    self[self.write] = value
    self.write = self.write + 1
end

function Queue:pop()
    local read = self.read
    if read >= self.write then
        error("queue is empty")
    end
    local value = self[read]
    self[read] = nil -- to allow garbage collection
    self.read = read + 1
    return value
end
