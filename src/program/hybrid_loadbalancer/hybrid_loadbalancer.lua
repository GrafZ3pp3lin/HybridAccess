-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local raw = require("apps.socket.raw")
local ini = require("program.hybrid_access.base.ini")
local source = require("program.hybrid_access.base.ordered_source")
local dropper = require("program.hybrid_access.base.packet_dropper")
local w_roundrobin = require("program.hybrid_loadbalancer.weighted_roundrobin")

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function run()
    local cfg = ini.Ini:parse("/home/student/snabb/src/program/hybrid_loadbalancer/config.ini")
    print(dump(cfg))

    local c = config.new()
    config.app(c, "source", source.OrderedSource)
    config.app(c, "loadbalancer", w_roundrobin.WeightedRoundRobin, { bandwidths = { output1 = 100, output2 = 10 } })
    config.app(c, "dropper1", dropper.PacketDropper, { mode = "nth", value = 100 })
    config.app(c, "out1", raw.RawSocket, cfg.link_out_1)
    config.app(c, "out2", raw.RawSocket, cfg.link_out_2)

    config.link(c, "source.output -> loadbalancer.input")
    config.link(c, "loadbalancer.output1 -> dropper1.input")
    config.link(c, "dropper1.output -> out1.rx")
    config.link(c, "loadbalancer.output2 -> out2.rx")

    engine.configure(c)
    print("start loadbalancer")
    engine.main({ duration = cfg.duration, report = { showlinks = true, showapps = true } })
    print("stop loadbalancer")
end
