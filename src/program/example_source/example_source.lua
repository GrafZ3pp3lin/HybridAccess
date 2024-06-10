-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local synth = require("apps.test.synth")
local connectx = require("apps.mellanox.connectx")
local mac_forwarder = require("program.hybrid_access.middleware.mac_forwarder")

function run()
    local pciaddr = "0000:02:0f.0" -- enp2s15

    local c = config.new()
    config.app(c, "source", synth.Synth, {
        sizes = {64,67,128,133,192,256,384,512,777,1024},
        src="02:00:00:00:00:01",
        dst="ff:ff:ff:ff:ff:ff",
        random_payload = true
    })
    config.app(c, "nic", connectx.ConnectX, { pciaddress = pciaddr, queues={{id="q1"}} })
    config.app(c, "link", connectx.IO, { pciaddress = pciaddr, queue = "q1" })
    config.app(c, "forwarder", mac_forwarder.MacForwarder, { source_mac = "22:6a:af:6f:58:d2", destination_mac = "f6:fa:ed:3a:f4:d4" })

    config.link(c, "source.output -> forwarder.input")
    config.link(c, "forwarder.output -> link.input")

    engine.configure(c)
    engine.main({ duration = 10, report = { showlinks = true, showapps = true } })
end
