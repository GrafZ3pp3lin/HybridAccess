-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local raw = require("apps.socket.raw")
local basics = require("apps.basic.basic_apps")
local ini = require("program.hybrid_access.base.ini")
-- local target = require("program.hybrid_access.base.ordered_sink")
local recombination = require("program.hybrid_recombinator.recombination")

local function dump(o)
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

function run()
    local cfg = ini.Ini:parse("/home/student/snabb/src/program/hybrid_recombinator/config.ini")
    print(dump(cfg))

    local c = config.new()
    config.app(c, "in1", raw.RawSocket, cfg.link_in_1)
    config.app(c, "in2", raw.RawSocket, cfg.link_in_2)
    config.app(c, "recombination", recombination.Recombination)
    config.app(c, "target", basics.Sink)

    config.link(c, "in1.tx -> recombination.input1")
    config.link(c, "in2.tx -> recombination.input2")
    config.link(c, "recombination.output -> target.input")

    engine.configure(c)
    print("start recombinator")
    engine.busywait = true
    engine.main({ duration = cfg.duration, report = { showlinks = true, showapps = true } })
    print("stop recombinator")
end
