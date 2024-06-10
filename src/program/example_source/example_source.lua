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
    config.app(c, "source", synth.Synth, {
        sizes = {1024},
        src="00:50:ba:85:85:ca",
        dst="ff:ff:ff:ff:ff:ff",
        random_payload = true
    })
    config.app(c, "nic", intel_nic.Intel_avf, { pciaddr = pciaddr, nqueues=1, macs = { "00:50:ba:85:85:ca"}})
    config.app(c, "link", intel_nic.IO, { pciaddr = pciaddr, queue=0 })

    config.app(c, "nic_in", intel_nic.Intel_avf, { pciaddr = "00:1c.0", macs = {"00:50:ba:85:85:ca"}})
    --config.app(c, "link_in", intel_nic.IO, { pciaddr = "00:1c.0", queue = 0 })




    config.link(c, "source.output -> nic_in.input")
    --config.link(c, "link_in.output -> link.input")
    --config.link(c, "source.output -> link.input")
    --config.link(c, "link.input -> link.output")

    engine.configure(c)
    engine.busywait = true
    engine.main({ duration = 5, report = { showlinks = true, showapps = true } })
end
