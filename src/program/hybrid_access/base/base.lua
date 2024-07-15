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
IPV4_ETH_TYPE, HYBRID_ACCESS_ETH_TYPE, ETHER_HEADER_LEN, HA_HEADER_LEN =
    co.ETHER_HEADER_PTR_T, co.IPV4_HEADER_PTR_T, co.HA_HEADER_PTR_T,
    co.IPV4_ETH_TYPE, co.HYBRID_ACCESS_ETH_TYPE, co.ETHER_HEADER_LEN, co.HA_HEADER_LEN

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
    str = string.format("size: %i, dst: %s, src: %s, type: %02X", pkt.length, ethernet:ntop(eth_header.ether_dhost), ethernet:ntop(eth_header.ether_shost), eth_type)
    if eth_type == IPV4_ETH_TYPE then
        local ip_header = cast(IPV4_HEADER_PTR_T, pkt.data + ETHER_HEADER_LEN)
        str = string.format("%s - ttl: %i, proto: %i, src: %s, dst: %s", str, ip_header.ttl, ip_header.protocol, ipv4:ntop(ip_header.src_ip), ipv4:ntop(ip_header.dst_ip))
    elseif eth_type == HYBRID_ACCESS_ETH_TYPE then
        local ha_header = cast(HA_HEADER_PTR_T, pkt.data + ETHER_HEADER_LEN)
        local buf_type = ha_header.buf_type
        str = string.format("%s - seq: %i, buf: %i, type: %i", str, ha_header.seq_no, buf_type, ha_header.type)
        if buf_type == IPV4_ETH_TYPE then
            local ip_header = cast(IPV4_HEADER_PTR_T, pkt.data + ETHER_HEADER_LEN + HA_HEADER_LEN)
            str = string.format("%s - ttl: %i, proto: %i, src: %s, dst: %s", str, ip_header.ttl, ip_header.protocol, ipv4:ntop(ip_header.src_ip), ipv4:ntop(ip_header.dst_ip))
        end
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

function report_links()
    print("link report:")
    for name, l in pairs(engine.link_table) do
       local txpackets = counter.read(l.stats.txpackets)
       local txdrop = counter.read(l.stats.txdrop)
       print(string.format("%20s sent / %20s drop on %s", lib.comma_value(txpackets), lib.comma_value(txdrop), name))
    end
end

function report_apps()
    print("apps report:")
    for name, app in pairs(engine.app_table) do
        if app.report ~= nil and name:sub(1, 3) ~= "nic" then
            print(name .. ":")
            app:report()
        end
    end
end

function report_nics()
    print("nic report:")
    for name, app in pairs(engine.app_table) do
        if name:sub(1, 3) == "nic" then
            print(name .. ":")
            app:check_vport()
            app:print_vport_counter()
        end
    end
end

function resolve_time(time_str)
    local lower_time_str = string.lower(time_str)
    local time_value = string.match(lower_time_str, "^(%d+)ms$")
    if time_value then
        return tonumber(time_value) * 1e6
    end
    time_value = string.match(lower_time_str, "^(%d+)us$")
    if time_value then
        return tonumber(time_value) * 1e3
    end
    time_value = string.match(lower_time_str, "^(%d+)ns$")
    if time_value then
        return tonumber(time_value)
    end
    time_value = string.match(lower_time_str, "^(%d+)s$")
    if time_value then
        return tonumber(time_value) * 1e9
    end
    return tonumber(time_str)
end

function resolve_bandwidth(bandwidth_str)
    local lower_bandwidth_str = string.lower(bandwidth_str)
    local bandwidth_value = string.match(lower_bandwidth_str, "^(%d+)gbit$")
    if bandwidth_value then
        return tonumber(bandwidth_value) * 1e9
    end
    bandwidth_value = string.match(lower_bandwidth_str, "^(%d+)mbit$")
    if bandwidth_value then
        return tonumber(bandwidth_value) * 1e6
    end
    bandwidth_value = string.match(lower_bandwidth_str, "^(%d+)kbit$")
    if bandwidth_value then
        return tonumber(bandwidth_value) * 1e3
    end
    bandwidth_value = string.match(lower_bandwidth_str, "^(%d+)vit$")
    if bandwidth_value then
        return tonumber(bandwidth_value)
    end
    return tonumber(bandwidth_str)
end

function resolve_number(number_str)
    local lower_number_str = string.lower(number_str)
    local number_value = string.match(lower_number_str, "^(%d+)g$")
    if number_value then
        return tonumber(number_value) * 1e9
    end
    number_value = string.match(lower_number_str, "^(%d+)m$")
    if number_value then
        return tonumber(number_value) * 1e6
    end
    number_value = string.match(lower_number_str, "^(%d+)k$")
    if number_value then
        return tonumber(number_value) * 1e3
    end
    return tonumber(number_str)
end

function resolve_bool(bool_str)
    local lower_bool_str = string.lower(bool_str)
    local bool_value = string.match(lower_bool_str, "^(yes|y|1|on|true)$")
    return bool_value ~= nil
end
