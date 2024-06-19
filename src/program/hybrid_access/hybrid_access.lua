-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")
local lib = require("core.lib")

local mellanox = require("apps.mellanox.connectx")

local recombination = require("program.hybrid_access.recombination.recombination")
local forwarder = require("program.hybrid_access.middleware.mac_forwarder")
local rate_limiter = require("program.hybrid_access.middleware.rate_limiter")
local delayer = require("program.hybrid_access.middleware.delayer")
local delayer2 = require("program.hybrid_access.middleware.delayer2")
local delayer3 = require("program.hybrid_access.middleware.delayer3")
local printer = require("program.hybrid_access.middleware.printer")

local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")

function run(args)
    if #args ~= 1 then
        error("please provide config path")
    end
    
    local path = args[1]
    local cfg = ini.Ini:parse(path)
    -- local middleware = "./program/hybrid_access/middleware.ini"
    -- local middleware = ini.Ini:parse(middleware)

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

    local node_out1 = "link_out1.output"
    local node_out2 = "link_out2.output"

    local pipeline1 = "in"
    local pipeline2 = "in"

    -- recombination
    if cfg.link1.enable.printer_in == true then
        config.app(c, "printer_in_1", printer.Printer, cfg.link1.printer_in)
        config.link(c, node_out1.." -> printer_in_1.input")
        node_out1 = "printer_in_1.output"
        pipeline1 = pipeline1.." -> printer"
    end
    if cfg.link2.enable.printer_in == true then
        config.app(c, "printer_in_2", printer.Printer, cfg.link2.printer_in)
        config.link(c, node_out2.." -> printer_in_2.input")
        node_out2 = "printer_in_2.output"
        pipeline2 = pipeline2.." -> printer"
    end

    if cfg.link1.enable.delayer == true then
        config.app(c, "delayer_1", delayer2.Delayer2, cfg.link1.delayer)
        config.link(c, node_out1.." -> delayer_1.input")
        node_out1 = "delayer_1.output"
        pipeline1 = pipeline1.." -> delayer"
    end
    if cfg.link2.enable.delayer == true then
        config.app(c, "delayer_2", delayer2.Delayer2, cfg.link2.delayer)
        config.link(c, node_out2.." -> delayer_2.input")
        node_out2 = "delayer_2.output"
        pipeline2 = pipeline2.." -> delayer"
    end

    config.link(c, node_out1.." -> recombination.input1")
    config.link(c, node_out2.." -> recombination.input2")

    config.link(c, "recombination.output -> forwarder_in.input")
    config.link(c, "forwarder_in.output -> link_in.input")
    
    pipeline1 = pipeline1.." -> recombination"
    pipeline2 = pipeline2.." -> recombination"
    print("pipeline link 1: ", pipeline1)
    print("pipeline link 2: ", pipeline2)

    -- loadbalancer
    config.link(c, "link_in.output -> loadbalancer.input")

    node_out1 = "loadbalancer.output1"
    node_out2 = "loadbalancer.output2"

    pipeline1 = "loadbalancer"
    pipeline2 = "loadbalancer"

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

    if cfg.link1.enable.printer_out == true then
        config.app(c, "printer_out_1", printer.Printer, cfg.link1.printer_out)
        config.link(c, node_out1.." -> printer_out_1.input")
        node_out1 = "printer_out_1.output"
        pipeline1 = pipeline1.." -> printer"
    end
    if cfg.link2.enable.printer_out == true then
        config.app(c, "printer_out_2", printer.Printer, cfg.link2.printer_out)
        config.link(c, node_out2.." -> printer_out_2.input")
        node_out2 = "printer_out_2.output"
        pipeline2 = pipeline2.." -> printer"
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
                if cfg.report_links then
                    base.report_links()
                end
                if cfg.report_apps then
                    base.report_apps()
                    -- base.report_nics()
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
