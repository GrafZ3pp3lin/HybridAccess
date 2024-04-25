-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")
local raw = require("apps.socket.raw")
local sink = require("program.hybrid_access.base.ordered_sink")
local source = require("program.hybrid_access.base.ordered_source")
local dropper = require("program.hybrid_access.base.packet_dropper")
local w_roundrobin = require("program.hybrid_loadbalancer.weighted_roundrobin")
local recombination = require("program.hybrid_recombinator.recombination")

local function show_usage(status)
    print(require("program.hybrid_access.README_inc"))
    main.exit(status)
end

local function read_config(file)
    local value = lib.readfile(file, "*a")
    local config = {}
    for key, val in string.gmatch(value, "([^%s,;]+)=([^%s,;]+)") do
        config[key] = val
    end
    return config
end

local function dump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
end

local function start(cfg)
    local c = config.new()
    config.app(c, "source", source.OrderedSource)
    config.app(c, "loadbalancer", w_roundrobin.WeightedRoundRobin, {bandwidths={output1=100,output2=10}})
    config.app(c, "dropper1", dropper.PacketDropper, {mode="nth",value=100})
    config.app(c, "out1", raw.RawSocket, cfg.link_out_1)
    config.app(c, "out2", raw.RawSocket, cfg.link_out_2)

    config.app(c, "in1", raw.RawSocket, cfg.link_in_1)
    config.app(c, "in2", raw.RawSocket, cfg.link_in_2)
    config.app(c, "recombination", recombination.Recombination)
    config.app(c, "sink", sink.OrderedSink)

    config.link(c, "source.output -> loadbalancer.input")
    config.link(c, "loadbalancer.output1 -> dropper1.input")
    config.link(c, "dropper1.output -> out1.rx")
    config.link(c, "loadbalancer.output2 -> out2.rx")

    config.link(c, "in1.tx -> recombination.input1")
    config.link(c, "in2.tx -> recombination.input2")
    config.link(c, "recombination.output -> sink.input")

    engine.configure(c)
    local start = engine.now()
    engine.main({duration=10, report = {showlinks=true,showapps=true}})
    local stop = engine.now()
    print("main report:")
    print(string.format("%20s ms", (stop - start) * 1000))
end
 

function run (args)
    local cfg
    if #args == 1 then
        cfg = read_config(args[1])
    elseif #args == 4 then
        cfg = {}
        cfg.link_out_1 = args[1]
        cfg.link_out_2 = args[2]
        cfg.link_in_1 = args[3]
        cfg.link_in_2 = args[4]
    else
        show_usage(1)
    end

    print(dump(cfg))

    start(cfg)
end
