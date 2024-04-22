-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local raw = require("apps.socket.raw")
local sprayer = require("program.example_spray.sprayer")

function run (parameters)
   if not (#parameters == 2) then
      print("Usage: example_spray <input> <output>")
      main.exit(1)
   end
   local input = parameters[1]
   local output = parameters[2]

   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, input)
   config.app(c, "spray_app", sprayer.Sprayer)
   config.app(c, "playback", raw.RawSocket, output)

   config.link(c, "capture.output -> spray_app.in1")
   config.link(c, "spray_app.out1 -> playback.rx")

   engine.configure(c)
   engine.main({duration=1, report = {showlinks=true}})
end
