-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")
local lib = require("core.lib")

local mellanox = require("apps.mellanox.connectx")

local recombination = require("program.hybrid_access.recombination.recombination")
local forwarder = require("program.hybrid_access.middleware.mac_forwarder")
local rate_limiter = require("program.hybrid_access.middleware.rate_limiter")
local delayer = require("program.hybrid_access.middleware.delayer")

local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")

function run(args)
    local path = "/home/student/snabb/src/program/hybrid_access/config.ini"
    if #args == 1 then
        path = args[1]
    end

    local cfg = ini.Ini:parse(path)

    local c = config.new()

    config.app(c, "nic_in", mellanox.ConnectX, { pciaddress = cfg.input.pci, queues = {{ id = "q1" }}})
    config.app(c, "nic_out1", mellanox.ConnectX, { pciaddress = cfg.link1.pci, queues = {{ id = "q1" }}})
    config.app(c, "nic_out2", mellanox.ConnectX, { pciaddress = cfg.link2.pci, queues = {{ id = "q1" }}})

    config.app(c, "link_in", mellanox.IO, { pciaddress = cfg.input.pci, queue = "q1" })
    config.app(c, "link_out1", mellanox.IO, { pciaddress = cfg.link1.pci, queue = "q1" })
    config.app(c, "link_out2", mellanox.IO, { pciaddress = cfg.link2.pci, queue = "q1" })

    config.app(c, "loadbalancer", require(cfg.loadbalancer.path)[cfg.loadbalancer.type], cfg.loadbalancer.config)
    config.app(c, "recombination", recombination.Recombination, cfg.recombination.config)

    config.app(c, "forwarder_in", forwarder.MacForwarder, cfg.input.forwarder)

    -- recombination
    config.link(c, "link_out1.output -> recombination.input1")
    config.link(c, "link_out2.output -> recombination.input2")
    config.link(c, "recombination.output -> forwarder_in.input")
    config.link(c, "forwarder_in.output -> link_in.input")

    -- loadbalancer
    config.link(c, "link_in.output -> loadbalancer.input")

    local node_out1 = "loadbalancer.output1"
    local node_out2 = "loadbalancer.output2"

    local pipeline1 = "loadbalancer"
    local pipeline2 = "loadbalancer"

    if cfg.link1.enable.rate_limiter == true then
        config.app(c, "rate_limiter_1", rate_limiter.TBRateLimiter, cfg.link1.rate_limiter)
        config.link(c, node_out1.." -> rate_limiter_1.input")
        node_out1 = "rate_limiter_1.output"
        pipeline1 = pipeline1.." -> rate limiter"
    end
    if cfg.link2.enable.rate_limiter == true then
        config.app(c, "rate_limiter_2", rate_limiter.TBRateLimiter, cfg.link2.rate_limiter)
        config.link(c, node_out2.." -> rate_limiter_2.input")
        node_out2 = "rate_limiter_2.output"
        pipeline2 = pipeline2.." -> rate limiter"
    end

    if cfg.link1.enable.delayer == true then
        config.app(c, "delayer_1", delayer.Delayer, cfg.link1.delayer)
        config.link(c, node_out1.." -> delayer_1.input")
        node_out1 = "delayer_1.output"
        pipeline1 = pipeline1.." -> delayer"
    end
    if cfg.link2.enable.delayer == true then
        config.app(c, "delayer_2", delayer.Delayer, cfg.link2.delayer)
        config.link(c, node_out2.." -> delayer_2.input")
        node_out2 = "delayer_2.output"
        pipeline2 = pipeline2.." -> delayer"
    end

    if cfg.link1.enable.forwarder == true then
        config.app(c, "forwarder_out1", forwarder.MacForwarder, cfg.link1.forwarder)
        config.link(c, node_out1.." -> forwarder_out1.input")
        node_out1 = "forwarder_out1.output"
        pipeline1 = pipeline1.." -> forwarder"
    end
    if cfg.link2.enable.forwarder == true then
        config.app(c, "forwarder_out2", forwarder.MacForwarder, cfg.link2.forwarder)
        config.link(c, node_out2.." -> forwarder_out2.input")
        node_out2 = "forwarder_out2.output"
        pipeline2 = pipeline2.." -> forwarder"
    end
    
    config.link(c, node_out1.." -> link_out1.input")
    config.link(c, node_out2.." -> link_out2.input")

    pipeline1 = pipeline1.." -> out"
    pipeline2 = pipeline2.." -> out"

    print("pipeline link 1: ", pipeline1)
    print("pipeline link 2: ", pipeline2)

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
