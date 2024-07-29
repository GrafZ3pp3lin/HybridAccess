-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine = require("core.app")

local mellanox = require("apps.mellanox.connectx")

local forwarder = require("program.hybrid_access.middleware.mac_forwarder")
local delayer = require("program.hybrid_access.middleware.delayer_ts")
local rate_limiter = require("program.hybrid_access.middleware.rate_limiter_ts")

local ini = require("program.hybrid_access.base.ini")
local base = require("program.hybrid_access.base.base")

local function parse_cli(str, cfg)
    local overwrites = {};
    
    for i in string.gmatch(str, "([^;]+)") do
        local k, v = string.match(i, "^-(%w+)=\"?([%w,]+)\"?$")
        if k and v then
            overwrites[k] = v
        end
    end
    
    for key, value in pairs(overwrites) do
        if key == "order" then
            cfg.order = value
        elseif key == "d" or key == "delay" then
            if value == "off" then
                cfg.delayer = nil
            else
                cfg.delayer.delay = base.resolve_time(value)
            end
        elseif key == "dc" or key == "delay_corr" and cfg.delayer ~= nil then
            cfg.delayer.correction = base.resolve_time(value)
        elseif key == "r" or key == "rate" then
            if value == "off" then
                cfg.rate_limiter = nil
            else
                cfg.rate_limiter.rate = base.resolve_bandwidth(value)
            end
        elseif key == "c" or key == "capacity" and cfg.rate_limiter ~= nil then
            cfg.rate_limiter.bucket_capacity = base.resolve_number(value)
        elseif key == "b" or key == "buffer" and cfg.rate_limiter ~= nil then
            cfg.rate_limiter.buffer_capacity = base.resolve_number(value)
        elseif key == "l" or key == "latency" and cfg.rate_limiter ~= nil then
            cfg.rate_limiter.buffer_latency = base.resolve_time(value)
        elseif key == "o" or key == "overhead" and cfg.rate_limiter ~= nil then
            cfg.rate_limiter.additional_overhead = base.resolve_number(value)
        elseif key == "ol1" or key == "overhead_layer1" and cfg.rate_limiter ~= nil then
            cfg.rate_limiter.layer1_overhead = base.resolve_bool(value)
        end
    end
end

local function configure_middleware(m_type, c, cfg, source)
    local out_source = source
    if m_type == "r" or m_type == "rate_limiter" then
        if cfg.rate_limiter ~= nil then
            config.app(c, "rate_limiter", rate_limiter.RateLimiterTS, cfg.rate_limiter)
            config.link(c, source.." -> rate_limiter.input")
            print(source.." -> rate_limiter.input")
            out_source = "rate_limiter.output"
        end
    elseif m_type == "d" or m_type == "delayer" then
        if cfg.delayer ~= nil then
            config.app(c, "delayer", delayer.DelayerTS, cfg.delayer)
            config.link(c, source.." -> delayer.input")
            print(source.." -> delayer.input")
            out_source = "delayer.output"
        end
    end
    
    return out_source
end

function run(args)
    if #args == 0 then
        error("please provide config path")
    end
    
    local path = args[1]
    local rest = table.concat(args, ";", 2)

    local cfg = ini.Ini:parse(path)
    parse_cli(rest, cfg)

    print(base.dump(cfg))

    local c = config.new()

    config.app(c, "nic_in", mellanox.ConnectX, { pciaddress = cfg.input.pci, queues = {{ id = "q1" }}})
    config.app(c, "nic_out", mellanox.ConnectX, { pciaddress = cfg.output.pci, queues = {{ id = "q1" }}})

    config.app(c, "link_in", mellanox.IO, { pciaddress = cfg.input.pci, queue = "q1" })
    config.app(c, "link_out", mellanox.IO, { pciaddress = cfg.output.pci, queue = "q1" })

    config.app(c, "forwarder_in", forwarder.MacForwarder, cfg.input.forwarder)
    config.app(c, "forwarder_out", forwarder.MacForwarder, cfg.output.forwarder)

    local source = "link_in.output"

    if cfg.order ~= nil then
        for middleware in string.gmatch(cfg.order, "[^,]+") do
            source = configure_middleware(middleware, c, cfg, source)
        end
    end
    
    config.link(c, source.." -> forwarder_out.input")
    config.link(c, "forwarder_out.output -> link_out.input")
    print(source.." -> forwarder_out.input")

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
