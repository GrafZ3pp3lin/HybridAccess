module(..., package.seeall)

Ini = {}

function Ini:parse(file_name)
    assert(type(file_name) == 'string', 'Parameter "file_name" must be a string.');
	local file = assert(io.open(file_name, 'r'), 'Error loading file : ' .. file_name);

    local content = {}
    local currentContent = content
    for line in file:lines() do
        local temp_section = string.match(line, "^%[([%w_%.]+)%]$")
        if temp_section then
            currentContent = content
            for str in string.gmatch(temp_section, "[^%.]+") do
                currentContent[str] = currentContent[str] or {}
                currentContent = currentContent[str]
            end
        else
            local key, value = line:match('^([%w_]+)%s*=%s*(.+)$');
            if key and value ~= nil then
                local value_number = tonumber(value)
                if value_number then
                    value = value_number
                elseif string.lower(value) == 'true' then
                    value = true
                elseif string.lower(value) == 'false' then
                    value = false
                elseif string.lower(value) == 'nil' then
                    value = nil
                end

                currentContent[key] = value
            end
        end
    end
    file:close();
    return content
end
