-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local basic = require("apps.basic.basic_apps")
local intel_nic = require("apps.intel_avf.intel_avf")

function run(args)
    local c = config.new()
    config.app(c, "source", basic.Source)
    config.app(c, "nic", intel_nic.Intel_avf, { pciaddr = "0000:00:10:0", nqueues = 1 })
    config.app(c, "link", intel_nic.IO, { pciaddr = "0000:00:10:0", queue = 0 })

    config.link(c, "source.output -> link.input")

    engine.configure(c)
    engine.main({ duration = 10, report = { showlinks = true, showapps = true } })
end
