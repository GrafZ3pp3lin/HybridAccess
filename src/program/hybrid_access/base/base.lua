module(..., package.seeall)

local engine = require("core.app")
local counter = require("core.counter")
local lib = require("core.lib")

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

function data_to_str(d, len)
    local text = ""
    for i = 0, len - 1, 1 do
        text = string.format("%s %02X", text, d[i])
    end
    return text
end

function number_to_hex(i)
    return string.format("%x", i)
end

local function link_loss_rate(drop, sent)
    sent = tonumber(sent)
    if not sent or sent == 0 then return 0 end
    return tonumber(drop) * 100 / (tonumber(drop)+sent)
 end

local function report_links_to_file(f)
    f:write("\nlink report:\n")
    for name, l in pairs(engine.link_table) do
       local txpackets = counter.read(l.stats.txpackets)
       local txdrop = counter.read(l.stats.txdrop)
       f:write(string.format("%20s sent on %s (loss rate: %d%%)\n", lib.comma_value(txpackets), name, link_loss_rate(txdrop, txpackets)))
    end
 end

function report_to_file(file_path, start, stop)
    local f = io.open(file_path, "w")
    if f ~= nil then
        f:write("main report:", "\n")
        f:write(string.format("%20s ms", (stop - start) * 1000), "\n")

        for name, app in pairs(engine.app_table) do
            if app.file_report then
                f:write(name .. " report:\n")
                app:file_report(f)
            end
        end

        report_links_to_file(f)

        f:close()
    end
end
