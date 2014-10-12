kNone = 'None'

function printf(fmt, ...)
    print(string.format(fmt, ...))
end

DEBUG = false
function dprintf(fmt, ...)
    if DEBUG then printf(fmt, ...) end
end

