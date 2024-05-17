-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local test = require("program.example_test.test")
local target = require("program.example_test.printer")
local base = require("program.hybrid_access.base.base")

function run(args)
    local pcap_file = "src/program/example_replay/input.pcap"
    if #args == 1 then
        pcap_file = args[1]
    end

    print(base.dump(target))

    local c = config.new()
    config.app(c, "source", pcap.PcapReader, pcap_file)
    config.app(c, "test", test.Test)
    config.app(c, "target", target.Printer)

    config.link(c, "source.output -> test.input")
    config.link(c, "test.output -> target.input")

    engine.configure(c)
    engine.main({ duration = 1, report = { showlinks = true, showapps = true } })
end
