-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local raw = require("apps.socket.raw")
local ini = require("program.hybrid_access.base.ini")
local basics = require("apps.basic.basic_apps")
-- local rate_limiter = require("apps.rate_limiter.rate_limiter")
-- local source = require("program.hybrid_access.base.ordered_source")
local roundrobin = require("program.hybrid_loadbalancer.roundrobin")
local w_roundrobin = require("program.hybrid_loadbalancer.weighted_roundrobin")
local tokenbucket = require("program.hybrid_loadbalancer.tokenbucket")

local function dump(o)
    if type(o) == 'table' then
        local s = '{'
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. k .. '=' .. dump(v) .. ','
        end
        return s .. '}'
    else
        return tostring(o)
    end
end

function run()
    local cfg = ini.Ini:parse("/home/student/snabb/src/program/hybrid_loadbalancer/config.ini")
    print(dump(cfg))

    local c = config.new()
    config.app(c, "source", basics.Source)
    config.app(c, "out1", raw.RawSocket, cfg.link_out_1)
    config.app(c, "out2", raw.RawSocket, cfg.link_out_2)
    --config.app(c, "rate_limiter1", rate_limiter.RateLimiter, { rate=, })

    if cfg.loadbalancer.type == "RoundRobin" then
        config.app(c, "loadbalancer", roundrobin.RoundRobin)
    elseif cfg.loadbalancer.type == "WeightedRoundRobin" then
        config.app(c, "loadbalancer", w_roundrobin.WeightedRoundRobin, cfg.loadbalancer.config)
    elseif cfg.loadbalancer.type == "TokenBucket" then
        config.app(c, "loadbalancer", tokenbucket.TokenBucket, cfg.loadbalancer.config)
    end

    config.link(c, "source.output -> loadbalancer.input")
    config.link(c, "loadbalancer.output1 -> out1.rx")
    config.link(c, "loadbalancer.output2 -> out2.rx")

    engine.configure(c)
    print("start loadbalancer")
    engine.busywait = true
    engine.main({ duration = cfg.duration, report = { showlinks = true, showapps = true } })
    print("stop loadbalancer")
end
