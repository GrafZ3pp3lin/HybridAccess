-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")
local lib = require("core.lib")

local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")

function run(args)
    local path = "/home/student/snabb/src/program/hybrid_access/config.ini"
    if #args == 1 then
        path = args[1]
    end

    local cfg = ini.Ini:parse(path)

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

    if cfg.report_interval ~= nil then
        local report_timer = timer.new(
            "report",
            function ()
                engine.report({ showload = true, showlinks = true, showapps = true })
            end,
            cfg.report_interval, -- every 5 seconds
            'repeating'
        )
        -- print packets statistics
        timer.activate(report_timer)
    end

    engine.configure(c)
    local start = engine.now()
    engine.busywait = true
    engine.main({ duration = cfg.duration })

    local stop = engine.now()
    if cfg.report_interval ~= nil then
        timer.cancel(report_timer)
    end

    if cfg.report_file ~= nil then
        base.report_to_file(cfg.report_file, start, stop)
    end
end
