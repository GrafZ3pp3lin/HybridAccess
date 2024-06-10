-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local basic = require("apps.basic.basic_apps")
local connectx = require("apps.mellanox.connectx")

local pci = require("lib.hardware.pci")


function run(args)
    local pciaddr = "0000:02:0d.0"

    local info = pci.device_info(pciaddr)
    print(info.pciaddress, info.vendor, info.device, info.model)
    assert(info.driver == 'apps.mellanox.connectx',
       "Driver should be apps.mellanox.connectx (is "..info.driver..")")

    local c = config.new()
    config.app(c, "nic", connectx.ConnectX, { pciaddress = pciaddr, queues={{id="q1"}} })
    config.app(c, "link", connectx.IO, { pciaddress = pciaddr, queue = "q1" })
    config.app(c, "sink", basic.Sink)

    config.link(c, "link.output -> sink.input")

    engine.configure(c)
    engine.main({ duration = 10, report = { showlinks = true, showapps = true } })
end
