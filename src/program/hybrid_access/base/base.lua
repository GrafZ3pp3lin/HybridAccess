---@diagnostic disable: undefined-field
module(..., package.seeall)

local ffi = require("ffi")
local engine = require("core.app")
local counter = require("core.counter")
local lib = require("core.lib")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")

local co = require("program.hybrid_access.base.constants")

local cast = ffi.cast

local ETHER_HEADER_PTR_T, IPV4_HEADER_PTR_T, HA_HEADER_PTR_T,
IPV4_ETH_TYPE, HYBRID_ACCESS_ETH_TYPE, ETHER_HEADER_LEN =
    co.ETHER_HEADER_PTR_T, co.IPV4_HEADER_PTR_T, co.HA_HEADER_PTR_T,
    co.IPV4_ETH_TYPE, co.HYBRID_ACCESS_ETH_TYPE, co.ETHER_HEADER_LEN

function dump(o)
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

function pkt_to_str(pkt)
    local str = ""
    local eth_header = cast(ETHER_HEADER_PTR_T, pkt.data)
    local eth_type = lib.ntohs(eth_header.ether_type)
    str = string.format("dst: %s, src: %s, type: %02X", ethernet:ntop(eth_header.ether_dhost), ethernet:ntop(eth_header.ether_shost), eth_type)
    if eth_type == IPV4_ETH_TYPE then
        local ip_header = cast(IPV4_HEADER_PTR_T, pkt.data + ETHER_HEADER_LEN)
        str = string.format("%s - ttl: %i, proto: %i, src: %s, dst: %s", str, ip_header.ttl, ip_header.protocol, ipv4:ntop(ip_header.src_ip), ipv4:ntop(ip_header.dst_ip))
    elseif eth_type == HYBRID_ACCESS_ETH_TYPE then
        local ha_header = cast(HA_HEADER_PTR_T, pkt.data + ETHER_HEADER_LEN)
        str = string.format("%s - seq: %i, buf: %i, type: %i", str, ha_header.seq_no, lib.ntohs(ha_header.buf_type), ha_header.type)
    end
    return str
end

function data_to_str(d, len)
    local text = ""
    for i = 0, len - 1, 1 do
        text = string.format("%s %02X", text, d[i])
    end
    return text
end

function number_to_hex(i)
    return string.format("%x", i)
end

local function link_loss_rate(drop, sent)
    sent = tonumber(sent)
    if not sent or sent == 0 then return 0 end
    return tonumber(drop) * 100 / (tonumber(drop)+sent)
 end

local function report_links_to_file(f)
    f:write("\nlink report:\n")
    for name, l in pairs(engine.link_table) do
       local txpackets = counter.read(l.stats.txpackets)
       local txdrop = counter.read(l.stats.txdrop)
       f:write(string.format("%20s sent on %s (loss rate: %d%%)\n", lib.comma_value(txpackets), name, link_loss_rate(txdrop, txpackets)))
    end
 end

function report_to_file(file_path, start, stop)
    local f = io.open(file_path, "w")
    if f ~= nil then
        f:write("main report:", "\n")
        f:write(string.format("%20s ms", (stop - start) * 1000), "\n")

        for name, app in pairs(engine.app_table) do
            if app.file_report then
                f:write(name .. " report:\n")
                app:file_report(f)
            end
        end

        report_links_to_file(f)

        f:close()
    end
end
