-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")

--local pci = require("lib.hardware.pci")

local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")

function run()
    local cfg = ini.Ini:parse("/home/student/snabb/src/program/hybrid_loadbalancer/config.ini")
    print(base.dump(cfg))

    --pci.scan_devices()
    --print(base.dump(pci.devices))

    local c = config.new()
    for _, app in ipairs(cfg.apps) do
        if not lib.have_module(app.path) then
            error("app %s does not exists", app.path)
        end
        config.app(c, app.name, require(app.path)[app.type], app.config)
    end

    for _, l in ipairs(cfg.links) do
        config.link(c, l)
    end

    engine.configure(c)
    print("start loadbalancer")
    engine.busywait = true
    engine.main({ duration = cfg.duration, report = { showlinks = true, showapps = true } })
    engine.stop()
    print("stop loadbalancer")
end
