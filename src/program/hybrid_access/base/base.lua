module(..., package.seeall)

local engine = require("core.app")

function dump(o)
    if type(o) == 'table' then
        local s = '{'
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. k .. '=' .. dump(v) .. ','
        end
        return s .. '}'
    else
        return tostring(o)
    end
end

function report_to_file(file_path, start, stop)
    local f = io.open(file_path, "w")
    if f ~= nil then
        f:write("main report:", "\n")
        f:write(string.format("%20s ms", (stop - start) * 1000), "\n")

        for name, app in pairs(engine.app_table) do
            if app.file_report then
                f:write(name.." report:\n")
                app:file_report(f)
            end
        end

        f:close()
    end
end