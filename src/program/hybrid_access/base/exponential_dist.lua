module(..., package.seeall)

Exponential = {}

function Exponential:new (a)
    assert(a > 0, "a has to be larger than 0")
    local o = {
        lamda = 1 / a,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Exponential:next ()
    local u = math.random()
    while u == 0 do
        u = math.random()
    end
    local next = -math.log(u) / self.lambda
    return next
end