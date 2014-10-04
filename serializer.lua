Serializer = {}
function Serializer:new(s)
    s = s or {}
    s.spaces = s.spaces or 2
    s.idlevel = 0
    s.prefix = ''
    s.strs = {}
    s.buf = ''
    setmetatable(s, self)
    self.__index = self
    return s
end

function Serializer:write(fmt, ...)
    local line = string.format(fmt, ...)
    if self.buf ~= '' then
        line = self.buf .. line
        self.buf = ''
    end
    if line:match('},?$') and not line:match('{') then
        self:dedent()
    end
    line = self.prefix .. line
    if line:match('{$') then
        self:indent()
    end
    table.insert(self.strs, line)
end

function Serializer:partial(fmt, ...)
    self.buf = self.buf .. string.format(fmt, ...)
end

function Serializer:indent()
    self.idlevel = self.idlevel + 1
    self.prefix = string.rep(' ', self.idlevel * self.spaces)
end

function Serializer:dedent()
    self.idlevel = self.idlevel - 1
    if self.idlevel < 0 then self.idlevel = 0 end
    self.prefix = string.rep(' ', self.idlevel * self.spaces)
end

function Serializer:__tostring()
    if self.buf then self:write('') end
    return table.concat(self.strs, '\n')
end
