-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")
local worker = require("core.worker")

local mellanox = require("apps.mellanox.connectx")

local recombination = require("program.hybrid_access.recombination.recombination")

local forwarder = require("program.hybrid_access.middleware.mac_forwarder")

local rate_limiter_ts = require("program.hybrid_access.middleware.rate_limiter_ts")
local rate_limiter = require("program.hybrid_access.middleware.rate_limiter")

local delayer = require("program.hybrid_access.middleware.delayer_c_buffer")
local delayer_ts = require("program.hybrid_access.middleware.delayer_ts")

-- local buffer = require("program.hybrid_access.middleware.buffer")

local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")

local function configure_middleware(m_type, c, cfg, source, suffix)
    local out_source = source
    if m_type == "r" or m_type == "rate_limiter" then
        if cfg.rate_limiter ~= nil then
            local name =  "rate_limiter_" .. suffix
            if cfg.rate_limiter.timestamp == true then
                config.app(c, name, rate_limiter_ts.RateLimiterTS, cfg.rate_limiter)
            else
                config.app(c, name, rate_limiter.TBRateLimiter, cfg.rate_limiter)
            end
            config.link(c, source.." -> "..name..".input")
            print(source.." -> "..name..".input")
            out_source = name..".output"
        end
    elseif m_type == "d" or m_type == "delayer" then
        if cfg.delayer ~= nil then
            local name =  "delayer_" .. suffix
            if cfg.delayer.timestamp == true then
                config.app(c, name, delayer_ts.DelayerTS, cfg.delayer)
            else
                config.app(c, name, delayer.DelayerWithCBuffer, cfg.delayer)
            end
            config.link(c, source.." -> "..name..".input")
            print(source.." -> "..name..".input")
            out_source = name..".output"
        end
    end
    
    return out_source
end

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

    -- recombination

    -- config.app(c, "buffer_1", buffer.Buffer)
    -- config.app(c, "buffer_2", buffer.Buffer)

    -- config.link(c, node_out1.." -> buffer_1.input")
    -- config.link(c, node_out2.." -> buffer_2.input")

    -- config.link(c, "buffer_1.output -> recombination.input1")
    -- config.link(c, "buffer_2.output -> recombination.input2")

    config.link(c, node_out1.." -> recombination.input1")
    config.link(c, node_out2.." -> recombination.input2")

    config.link(c, "recombination.output -> forwarder_in.input")
    config.link(c, "forwarder_in.output -> link_in.input")

    -- loadbalancer
    config.link(c, "link_in.output -> loadbalancer.input")

    node_out1 = "loadbalancer.output1"
    node_out2 = "loadbalancer.output2"

    if cfg.order ~= nil then
        for middleware in string.gmatch(cfg.order, "[^,]+") do
            node_out1 = configure_middleware(middleware, c, cfg.link1, node_out1)
            node_out2 = configure_middleware(middleware, c, cfg.link2, node_out2)
        end
    end

    config.app(c, "forwarder_out1", forwarder.MacForwarder, cfg.link1.forwarder)
    config.app(c, "forwarder_out2", forwarder.MacForwarder, cfg.link2.forwarder)

    config.link(c, node_out1.." -> forwarder_out1.input")
    config.link(c, "forwarder_out1.output -> link_out1.input")
    
    config.link(c, node_out2.." -> forwarder_out2.input")
    config.link(c, "forwarder_out2.output -> link_out2.input")

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
        if (key == "d1" or key == "delay1") and cfg.link1.delayer ~= nil then
            if value == "off" then
                cfg.link1.delayer = nil
            else
                cfg.link1.delayer.delay = base.resolve_time(value)
            end
        elseif (key == "d2" or key == "delay2") and cfg.link2.delayer ~= nil then
            if value == "off" then
                cfg.link2.delayer = nil
            else
                cfg.link2.delayer.delay = base.resolve_time(value)
            end
        elseif (key == "dc1" or key == "delay_corr1") and cfg.link1.delayer ~= nil then
            cfg.link1.delayer.correction = base.resolve_time(value)
        elseif (key == "dc2" or key == "delay_corr2") and cfg.link2.delayer ~= nil then
            cfg.link2.delayer.correction = base.resolve_time(value)
        elseif key == "r1" or key == "rate1" then
            if value == "off" then
                cfg.link1.rate_limiter = nil
            else
                cfg.link1.rate_limiter.rate = base.resolve_bandwidth(value)
            end
        elseif key == "r2" or key == "rate2" then
            if value == "off" then
                cfg.link2.rate_limiter = nil
            else
                cfg.link2.rate_limiter.rate = base.resolve_bandwidth(value)
            end
        elseif (key == "c1" or key == "capacity1") and cfg.link1.rate_limiter ~= nil then
            cfg.link1.rate_limiter.bucket_capacity = base.resolve_number(value)
        elseif (key == "c2" or key == "capacity2") and cfg.link2.rate_limiter ~= nil then
            cfg.link2.rate_limiter.bucket_capacity = base.resolve_number(value)
        elseif (key == "l1" or key == "latency1") and cfg.link1.rate_limiter ~= nil then
            cfg.link1.rate_limiter.buffer_latency = base.resolve_time(value)
        elseif (key == "l2" or key == "latency2") and cfg.link2.rate_limiter ~= nil then
            cfg.link2.rate_limiter.buffer_latency = base.resolve_time(value)
        elseif (key == "o1" or key == "overhead1") and cfg.link1.rate_limiter ~= nil then
            cfg.link1.rate_limiter.additional_overhead = base.resolve_number(value)
        elseif (key == "o2" or key == "overhead2") and cfg.link2.rate_limiter ~= nil then
            cfg.link2.rate_limiter.additional_overhead = base.resolve_number(value)
        elseif (key == "ol1_1" or key == "overhead_layer1_1") and cfg.link1.rate_limiter ~= nil then
            cfg.link1.rate_limiter.layer1_overhead = base.resolve_bool(value)
        elseif (key == "ol1_2" or key == "overhead_layer1_2") and cfg.link2.rate_limiter ~= nil then
            cfg.link2.rate_limiter.layer1_overhead = base.resolve_bool(value)
        elseif (key == "ts" or key == "timestamp") then
            if cfg.link1.rate_limiter ~= nil and cfg.link1.delayer ~= nil then
                cfg.link1.rate_limiter.timestamp = base.resolve_bool(value)
                cfg.link1.delayer.timestamp = base.resolve_bool(value)
            end
            if cfg.link2.rate_limiter ~= nil and cfg.link2.delayer ~= nil then
                cfg.link2.rate_limiter.timestamp = base.resolve_bool(value)
                cfg.link2.delayer.timestamp = base.resolve_bool(value)
            end
        elseif (key == "rd1" or key == "rec_delay1") then
            cfg.recombination.config.link_delays[1] = base.resolve_time(value)
        elseif key == "rd2" or key == "rec_delay2" then
            cfg.recombination.config.link_delays[2] = base.resolve_time(value)
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
    
    worker.start("io1_worker", ('require("program.hybrid_access.hybrid_access").run_worker(%q, %q)'):format(path, rest))
    
    local c = config.new()
    engine.configure(c)
    engine.main()
end
