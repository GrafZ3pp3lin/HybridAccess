local vf1 = "00:1c.0"--os.getenv("SNABB_AVF_PF0_VF0")
local vf0 = "00:1b.0"--os.getenv("SNABB_AVF_PF1_VF0") or os.getenv("SNABB_AVF_PF0_VF1")

assert(vf0 ~= nil, "SNABB_AVF_PF0_VF0 is nil")
assert(vf1 ~= nil, "SNABB_AVF_PF1_VF0 is nil")

local src = "c2:27:1d:70:97:ce" --os.getenv("SNABB_AVF_PF0_SRC0")
local dst = "ff:ff:ff:ff:ff:ff" -- os.getenv("SNABB_AVF_PF1_DST0") or os.getenv("SNABB_AVF_PF0_DST1")

assert(src ~= nil, "SNABB_AVF_SRC0 is nil")
assert(dst ~= nil, "SNABB_AVF_DST1 is nil")

-- 1001 is an important test case, descriptors are written back in sets of 4
-- 1001, exercises the interrupt driven write back
local packet_count = 1001

local basic = require("apps.basic.basic_apps")
local intel_avf = require("apps.intel_avf.intel_avf")
local match = require("apps.test.match")
local npackets = require("apps.test.npackets")
local synth = require("apps.test.synth")
local counter = require("core.counter")

local c = config.new()
config.app(c, "synth", synth.Synth, {
       sizes = {64,67,128,133,192,256,384,512,777,1024},
       src=src,
       dst=dst,
       random_payload = true
} )
config.app(c, "tee", basic.Tee)
config.app(c, "match", match.Match)

config.app(c, "npackets", npackets.Npackets, { npackets = packet_count })
config.app(c, "nic0", intel_avf.Intel_avf, { pciaddr = vf0 })
config.app(c, "nic1", intel_avf.Intel_avf, { pciaddr = vf1 })

config.link(c, "synth.output -> npackets.input")
config.link(c, "npackets.output -> tee.input")
config.link(c, "tee.output1 -> nic0.input")
config.link(c, "nic1.output -> match.rx")
config.link(c, "tee.output2 -> match.comparator")

engine.configure(c)

local n0 = engine.app_table['nic0']
local n1 = engine.app_table['nic1']
n0:flush_stats()
n1:flush_stats()

engine.main({duration = 1, report = false})
engine.report_links()
engine.report_apps()

function rx(l1, l2)
   return counter.read(engine.link_table[l1 .. " -> " .. l2].stats.rxpackets)
end
function assert_eq(a,b,msg)
	local an = tonumber(a)
	local bn = tonumber(b)
	assert(an == bn, msg .. " " .. an .. " ~= " .. bn)
end

local s = rx("tee.output1", "nic0.input")
local r = rx("nic1.output", "match.rx")
assert_eq(s, r, "packets_sr_1")

n0:flush_stats()
n1:flush_stats()
assert_eq(counter.read(n0.stats.txpackets), counter.read(n1.stats.rxpackets), "mxbox_sr_stats_1")
assert_eq(counter.read(n0.stats.txpackets), packet_count, "mbox_sr_stats_2")

local m = engine.app_table['match']
assert(#m:errors() == 0, "Corrupt packets.")

local c = config.new()
config.app(c, "synth", synth.Synth, {
       sizes = {64,128,192,256,384,512,1024},
       src=src,
       dst=dst
} )
config.app(c, "nic0", intel_avf.Intel_avf, { pciaddr = vf0 })
config.app(c, "nic1", intel_avf.Intel_avf, { pciaddr = vf1 })
config.app(c, "sink", basic.Sink)
config.link(c, "synth.output -> nic0.input")
config.link(c, "nic1.output -> sink.input")
engine.configure(c)

local tosend = 10 * 1000 * 1000
while true do
	local v = rx("synth.output", "nic0.input")
	if v > tosend then
		break
	end
	engine.main({ duration = 1, no_report = true })
end
engine.report_links()
engine.report_apps()
assert(rx("nic1.output", "sink.input") >= tosend,
       "packets received do not match packets sent")

engine.stop()
main.exit(0)
