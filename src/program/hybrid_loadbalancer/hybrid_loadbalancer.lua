-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local raw = require("apps.socket.raw")
local roundrobin = require("program.hybrid_access.roundrobin")

function run (parameters)
   if not (#parameters == 3) then
      print("Usage: example_spray <input> <output1> <output2>")
      main.exit(1)
   end
   local input = parameters[1]
   local output1 = parameters[2]
   local output2 = parameters[3]

   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, input)
   config.app(c, "roundrobin", roundrobin.RoundRobin)
   config.app(c, "out1", raw.RawSocket, output1)
   config.app(c, "out2", raw.RawSocket, output2)

   config.link(c, "capture.output -> roundrobin.input")
   config.link(c, "roundrobin.output1 -> out1.rx")
   config.link(c, "roundrobin.output2 -> out2.rx")

   engine.configure(c)
   engine.main({duration=1, report = {showlinks=true}})
end
