-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")
local lib = require("core.lib")

local mellanox = require("apps.mellanox.connectx")

local recombination = require("program.hybrid_access.recombination.recombination")
local forwarder = require("program.hybrid_access.middleware.mac_forwarder")
local rate_limiter = require("program.hybrid_access.middleware.rate_limiter")

local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")

function run(args)
    local path = "/home/student/snabb/src/program/hybrid_access/config.ini"
    if #args == 1 then
        path = args[1]
    end

    local cfg = ini.Ini:parse(path)

    local c = config.new()

    config.app(c, "nic_in", mellanox.ConnectX, { pciaddress = cfg.pci_in, queues = {{ id = "q1" }}})
    config.app(c, "nic_out1", mellanox.ConnectX, { pciaddress = cfg.pci_out1, queues = {{ id = "q1" }}})
    config.app(c, "nic_out2", mellanox.ConnectX, { pciaddress = cfg.pci_out2, queues = {{ id = "q1" }}})

    config.app(c, "link_in", mellanox.IO, { pciaddress = cfg.pci_in, queue = "q1" })
    config.app(c, "link_out1", mellanox.IO, { pciaddress = cfg.pci_out1, queue = "q1" })
    config.app(c, "link_out2", mellanox.IO, { pciaddress = cfg.pci_out2, queue = "q1" })

    config.app(c, "loadbalancer", require(cfg.loadbalancer.path)[cfg.loadbalancer.type], cfg.loadbalancer.config)
    config.app(c, "recombination", recombination.Recombination, cfg.recombination.config)

    config.app(c, "forwarder_in", forwarder.MacForwarder, { source_mac = cfg.forwarder_in.src, destination_mac = cfg.forwarder_in.dst })
    config.app(c, "forwarder_out1", forwarder.MacForwarder, { source_mac = cfg.forwarder_out1.src, destination_mac = cfg.forwarder_out1.dst })
    config.app(c, "forwarder_out2", forwarder.MacForwarder, { source_mac = cfg.forwarder_out2.src, destination_mac = cfg.forwarder_out2.dst })

    config.app(c, "rate_limiter_1", rate_limiter.TBRateLimiter, { rate = cfg.link_1_rate })
    config.app(c, "rate_limiter_2", rate_limiter.TBRateLimiter, { rate = cfg.link_2_rate })

    -- loadbalancer
    config.link(c, "link_in.output -> loadbalancer.input")
    config.link(c, "loadbalancer.output1 -> rate_limiter_1.input")
    config.link(c, "loadbalancer.output2 -> rate_limiter_2.input")
    config.link(c, "rate_limiter_1.output -> forwarder_out1.input")
    config.link(c, "rate_limiter_2.output -> forwarder_out2.input")
    config.link(c, "forwarder_out1.output -> link_out1.input")
    config.link(c, "forwarder_out2.output -> link_out2.input")
    -- recombination
    config.link(c, "link_out1.output -> recombination.input1")
    config.link(c, "link_out2.output -> recombination.input2")
    config.link(c, "recombination.output -> forwarder_in.input")
    config.link(c, "forwarder_in.output -> link_in.input")

    local report_timer = nil
    if cfg.report_interval ~= nil then
        report_timer = timer.new(
            "report",
            function ()
                engine.report({ showload = cfg.report_load, showlinks = cfg.report_links, showapps = cfg.report_apps })
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
