-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")
local lib = require("core.lib")

local mellanox = require("apps.mellanox.connectx")

local recombination = require("program.hybrid_access.recombination.recombination")
local forwarder = require("program.hybrid_access.middleware.mac_forwarder")
local rate_limiter = require("program.hybrid_access.middleware.rate_limiter")
local delayer = require("program.hybrid_access.middleware.delayer")
local printer = require("program.hybrid_access.middleware.printer")
local stats_counter = require("program.hybrid_access.middleware.stats_counter")

local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")

function run(args)
    if #args ~= 1 then
        error("please provide config path")
    end
    
    local path = args[1]
    local cfg = ini.Ini:parse(path)

    local c = config.new()

    config.app(c, "nic_in", mellanox.ConnectX, { pciaddress = cfg.input.pci, queues = {{ id = "q1" }}})
    config.app(c, "nic_out", mellanox.ConnectX, { pciaddress = cfg.output.pci, queues = {{ id = "q1" }}})

    config.app(c, "link_in", mellanox.IO, { pciaddress = cfg.input.pci, queue = "q1" })
    config.app(c, "link_out", mellanox.IO, { pciaddress = cfg.output.pci, queue = "q1" })

    config.app(c, "forwarder_in", forwarder.MacForwarder, cfg.input.forwarder)
    config.app(c, "forwarder_out", forwarder.MacForwarder, cfg.output.forwarder)

    config.link(c, "link_in.output -> forwarder_out.input")
    config.link(c, "forwarder_out.output -> link_out.input")
    config.link(c, "link_out.output -> forwarder_in.input")
    config.link(c, "forwarder_in.output -> link_in.input")
    

    local report_timer = nil
    if cfg.report_interval ~= nil then
        report_timer = timer.new(
            "report",
            function ()
                if cfg.report_links then
                    base.report_links()
                end
                if cfg.report_apps then
                    base.report_apps()
                    base.report_nics()
                end
            end,
            cfg.report_interval,
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
    if report_timer ~= nil then
        timer.cancel(report_timer)
    end

    if cfg.report_file ~= nil then
        base.report_to_file(cfg.report_file, start, stop)
    end
end
