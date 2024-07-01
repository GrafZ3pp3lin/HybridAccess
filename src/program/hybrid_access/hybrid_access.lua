-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")
local worker = require("core.worker")

local mellanox = require("apps.mellanox.connectx")

local recombination = require("program.hybrid_access.recombination.recombination")
local forwarder = require("program.hybrid_access.middleware.mac_forwarder")
local rate_limiter = require("program.hybrid_access.middleware.rate_limiter")
-- local delayer = require("program.hybrid_access.middleware.delayer")
-- local delayer2 = require("program.hybrid_access.middleware.delayer2")
-- local delayer3 = require("program.hybrid_access.middleware.delayer3")
-- local delayer4 = require("program.hybrid_access.middleware.delayer4")
local delayer5 = require("program.hybrid_access.middleware.delayer5")
local buffer = require("program.hybrid_access.middleware.buffer")

local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")

local function generate_config(cfg)
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

    config.app(c, "buffer_1", buffer.Buffer)
    config.app(c, "buffer_2", buffer.Buffer)

    config.link(c, node_out1.." -> buffer_1.input")
    config.link(c, node_out2.." -> buffer_2.input")

    config.link(c, "buffer_1.output -> recombination.input1")
    config.link(c, "buffer_2.output -> recombination.input2")

    -- config.link(c, node_out1.." -> recombination.input1")
    -- config.link(c, node_out2.." -> recombination.input2")

    config.link(c, "recombination.output -> forwarder_in.input")
    config.link(c, "forwarder_in.output -> link_in.input")
    
    pipeline1 = pipeline1.." -> buffer -> recombination"
    pipeline2 = pipeline2.." -> buffer -> recombination"
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

    config.app(c, "forwarder_out1", forwarder.MacForwarder, cfg.link1.forwarder)
    config.app(c, "forwarder_out2", forwarder.MacForwarder, cfg.link2.forwarder)

    config.link(c, node_out1.." -> forwarder_out1.input")
    config.link(c, node_out2.." -> forwarder_out2.input")

    pipeline1 = pipeline1.." -> forwarder"
    pipeline2 = pipeline2.." -> forwarder"

    node_out1 = "forwarder_out1.output"
    node_out2 = "forwarder_out2.output"

    if cfg.link1.enable.delayer == true then
        config.app(c, "delayer_1", delayer5.Delayer5, cfg.link1.delayer)
        config.link(c, node_out1.." -> delayer_1.input")
        node_out1 = "delayer_1.output"
        pipeline1 = pipeline1.." -> delayer"
    end
    if cfg.link2.enable.delayer == true then
        config.app(c, "delayer_2", delayer5.Delayer5, cfg.link2.delayer)
        config.link(c, node_out2.." -> delayer_2.input")
        node_out2 = "delayer_2.output"
        pipeline2 = pipeline2.." -> delayer"
    end
    
    config.link(c, node_out1.." -> link_out1.input")
    config.link(c, node_out2.." -> link_out2.input")

    pipeline1 = pipeline1.." -> out"
    pipeline2 = pipeline2.." -> out"

    print("pipeline link 1: ", pipeline1)
    print("pipeline link 2: ", pipeline2)

    return c
end

local function setup_report(cfg)
    local report_timer = timer.new(
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

    return report_timer
end

local function parse_cli(str, cfg)
    local overwrites = {};
    
    for i in string.gmatch(str, "([^;]+)") do
        local k, v = string.match(i, "^-(%w+)=\"?(%w+)\"?$")
        if k and v then
            overwrites[k] = v
        end
    end
    
    for key, value in pairs(overwrites) do
        if key == "d1" or key == "delay1" then
            cfg.link1.delayer.delay = tonumber(value)
        elseif key == "d2" or key == "delay2" then
            cfg.link2.delayer.delay = tonumber(value)
        elseif key == "d" or key == "delay" then
            local d = tonumber(value)
            if d then
                cfg.link1.delayer.delay = d
                cfg.link2.delayer.delay = d
            elseif value == "off" then
                cfg.link1.enable.delayer = false
                cfg.link2.enable.delayer = false
            end
        elseif key == "r1" or key == "rate1" then
            cfg.link1.rate_limiter.rate = tonumber(value)
        elseif key == "r2" or key == "rate2" then
            cfg.link2.rate_limiter.rate = tonumber(value)
        elseif key == "r" or key == "rate" then
            local d = tonumber(value)
            if d then
                cfg.link1.rate_limiter.rate = d
                cfg.link2.rate_limiter.rate = d
            elseif value == "off" then
                cfg.link1.enable.rate_limiter = false
                cfg.link2.enable.rate_limiter = false
            end
        elseif key == "c1" or key == "capacity1" then
            cfg.link1.rate_limiter.bucket_capacity = tonumber(value)
        elseif key == "c2" or key == "capacity2" then
            cfg.link2.rate_limiter.bucket_capacity = tonumber(value)
        elseif key == "c" or key == "capacity" then
            cfg.link1.rate_limiter.bucket_capacity = tonumber(value)
            cfg.link2.rate_limiter.bucket_capacity = tonumber(value)
        elseif key == "rd1" or key == "rec_delay1" then
            cfg.recombination.config.link_delays[1] = tonumber(value)
        elseif key == "rd2" or key == "rec_delay2" then
            cfg.recombination.config.link_delays[2] = tonumber(value)
        elseif key == "rd" or key == "rec_delay" then
            cfg.recombination.config.link_delays[1] = tonumber(value)
            cfg.recombination.config.link_delays[2] = tonumber(value)
        elseif key == "l" or key == "loadbalancer" then
            if value == "sl" or value == "singlelink" then
                cfg.loadbalancer.path = "program.hybrid_access.loadbalancer.single_link"
                cfg.loadbalancer.type = "SingleLink"
            elseif value == "rr" or value == "roundrobin" then
                cfg.loadbalancer.path = "program.hybrid_access.loadbalancer.roundrobin"
                cfg.loadbalancer.type = "RoundRobin"
            elseif value == "wrr" or value == "weighted_roundrobin" then
                cfg.loadbalancer.path = "program.hybrid_access.loadbalancer.weighted_roundrobin"
                cfg.loadbalancer.type = "WeightedRoundRobin"
            elseif value == "tb" or value == "tokenbucket" then
                cfg.loadbalancer.path = "program.hybrid_access.loadbalancer.tokenbucket"
                cfg.loadbalancer.type = "TokenBucket"
            elseif value == "tbddc" or value == "tokenbucket_ddc" then
                cfg.loadbalancer.path = "program.hybrid_access.loadbalancer.tokenbucket_ddc"
                cfg.loadbalancer.type = "TokenBucketDDC"
            end
        elseif key == "wrrb1" or value == "wrr_bandwidth1" then
            if not cfg.loadbalancer.config.bandwidths then
                cfg.loadbalancer.config.bandwidths = {}
            end
            cfg.loadbalancer.config.bandwidths.output1 = tonumber(value)
        elseif key == "wrrb2" or value == "wrr_bandwidth2" then
            if not cfg.loadbalancer.config.bandwidths then
                cfg.loadbalancer.config.bandwidths = {}
            end
            cfg.loadbalancer.config.bandwidths.output2 = tonumber(value)
        elseif key == "tbr" or value == "tb_rate" then
            cfg.loadbalancer.config.rate = tonumber(value)
        elseif key == "tbc" or value == "tb_capacity" then
            cfg.loadbalancer.config.capacity = tonumber(value)
        end
    end
end

function run_worker(path, args_str)
    local cfg = ini.Ini:parse(path)
    parse_cli(args_str, cfg)

    local c = generate_config(cfg)

    engine.configure(c)
    engine.busywait = true

    local report_timer = nil
    if cfg.report_interval ~= nil then
        report_timer = setup_report(cfg)
    end

    engine.main({ duration = cfg.duration })

    if report_timer ~= nil then
        timer.cancel(report_timer)
    end
end

function run(args)
    if #args == 0 then
        error("please provide config path")
    end
    
    local path = args[1]
    local rest = table.concat(args, ";", 2)

    -- local cfg = ini.Ini:parse(path)
    -- local middleware = ini.Ini:parse(middleware)
    
    worker.start("io1_worker", ('require("program.hybrid_access.hybrid_access").run_worker(%q, %q)'):format(path, rest))
    
    local c = config.new()
    engine.configure(c)
    engine.main()

    -- local c = generate_config(cfg)
    -- engine.configure(c)
    -- engine.busywait = true
    -- if cfg.report_interval ~= nil then
    --     setup_report(cfg)
    -- end

end
