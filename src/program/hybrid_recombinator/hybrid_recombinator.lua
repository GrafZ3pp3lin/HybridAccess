-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local raw = require("apps.socket.raw")
local recombination = require("program.hybrid_recombinator.recombination")

function run (parameters)
    if not (#parameters == 3) then
        print("Usage: hybrid_recombination <input1> <output2> <output>")
        main.exit(1)
    end
    local input1 = parameters[1]
    local input2 = parameters[2]
    local output = parameters[3]

    local c = config.new()
    config.app(c, "in1", raw.RawSocket, input1)
    config.app(c, "in2", raw.RawSocket, input2)
    config.app(c, "recombination", recombination.Recombination)
    config.app(c, "capture", pcap.PcapWriter, output)

    config.link(c, "in1.tx -> recombination.input1")
    config.link(c, "in2.tx -> recombination.input2")
    config.link(c, "recombination.output -> capture.input")

    engine.configure(c)
    engine.main({report = {showlinks=true}})
end
