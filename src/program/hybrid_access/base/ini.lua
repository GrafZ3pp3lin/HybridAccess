module(..., package.seeall)

Ini = {}

function Ini:parse(file_name)
    assert(type(file_name) == 'string', 'Parameter "file_name" must be a string.');
	local file = assert(io.open(file_name, 'r'), 'Error loading file : ' .. file_name);

    local content = {}
    local section
    for line in file:lines() do
        local temp_section = string.match(line, "^%[[%w_]+%]$")
        if temp_section then
            section = temp_section
            content[section] = content[section] or {}
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
                end
                if section then
                    content[section][key] = value
                else
                    content[key] = value
                end
            end
        end
    end
    file:close();
    return content
end
