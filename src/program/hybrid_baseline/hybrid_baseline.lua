-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")

local mellanox = require("apps.mellanox.connectx")

local forwarder = require("program.hybrid_access.middleware.mac_forwarder")
local delayer = require("program.hybrid_access.middleware.delayer5")
local rate_limiter = require("program.hybrid_access.middleware.rate_limiter")

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

    local source = "link_in.output"

    if cfg.rate_limiter then
        config.app(c, "rate_limiter", rate_limiter.TBRateLimiter, cfg.rate_limiter)
        config.link(c, source.." -> rate_limiter.input")
        source = "rate_limiter.output"
    end
    
    if cfg.delayer then
        config.app(c, "delayer", delayer.Delayer5, cfg.delayer)
        config.link(c, source.." -> delayer.input")
        source = "delayer.output"
    end
    
    config.link(c, source.." -> forwarder_out.input")
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
    engine.busywait = true
    engine.main({ duration = cfg.duration })

    if report_timer ~= nil then
        timer.cancel(report_timer)
    end
end
