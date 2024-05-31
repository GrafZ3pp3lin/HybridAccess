-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local synth = require("apps.test.synth")
local intel_nic = require("apps.intel_avf.intel_avf")

local pci = require("lib.hardware.pci")

function run()
    local pciaddr = "0000:00:10.0"

    local info = pci.device_info(pciaddr)
    print(info.pciaddress, info.vendor, info.device, info.model)
    assert(info.driver == 'apps.intel_avf.intel_avf',
       "Driver should be apps.intel_avf.intel_avf (is "..info.driver..")")

    local c = config.new()
    config.app(c, "source", synth.Synth)
    config.app(c, "nic", intel_nic.Intel_avf, { pciaddr = pciaddr, nqueues = 1 })
    config.app(c, "link", intel_nic.IO, { pciaddr = pciaddr, queue = 0 })

    config.link(c, "source.output -> link.input")

    engine.configure(c)
    engine.main({ duration = 1, report = { showlinks = true, showapps = true } })
end
