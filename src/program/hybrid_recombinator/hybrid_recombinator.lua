-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local raw = require("apps.socket.raw")
--local basics = require("apps.basic.basic_apps")
local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")
local target = require("program.hybrid_access.target.ordered_sink")
local recombination = require("program.hybrid_access.recombination.recombination")

function run()
    local cfg = ini.Ini:parse("/home/student/snabb/src/program/hybrid_recombinator/config.ini")
    print(base.dump(cfg))

    local c = config.new()
    config.app(c, "in1", raw.RawSocket, cfg.link_in_1)
    config.app(c, "in2", raw.RawSocket, cfg.link_in_2)
    config.app(c, "recombination", recombination.Recombination, cfg.recombination.config)
    config.app(c, "target", target.OrderedSink)

    config.link(c, "in1.tx -> recombination.input1")
    config.link(c, "in2.tx -> recombination.input2")
    config.link(c, "recombination.output -> target.input")

    engine.configure(c)
    print("start recombinator")
    engine.busywait = true
    engine.main({ duration = cfg.duration, report = { showlinks = true, showapps = true } })
    engine.stop()
    print("stop recombinator")
end
