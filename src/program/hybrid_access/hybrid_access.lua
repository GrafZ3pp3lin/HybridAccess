-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")

local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")

function run(args)
    local path = "/home/student/snabb/src/program/hybrid_access/config.ini"
    if #args == 1 then
        path = args[1]
    end

    local cfg = ini.Ini:parse(path)
    print(base.dump(cfg))

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
    local start = engine.now()
    engine.busywait = true
    engine.main({ duration = cfg.duration, report = { showlinks = true, showapps = true } })
    engine.stop()
    local stop = engine.now()
    print("main report:")
    print(string.format("%20s ms", (stop - start) * 1000))
end
