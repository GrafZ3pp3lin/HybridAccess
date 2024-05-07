module(..., package.seeall)

local raw = require("apps.socket.raw")
local relay = require("program.forwarder.relay")

function run(args)
    if not (#args == 2) then
        print("Usage: forwarder <interface> <interface>")
        main.exit(1)
     end
     local input = args[1]
     local output = args[2]

    local c = config.new()
    config.app(c, "input", raw.RawSocket, input)
    config.app(c, "output", raw.RawSocket, output)
    config.app(c, "relay1", relay.Relay, { name = "forward" })
    config.app(c, "relay2", relay.Relay, { name = "backwards" })

    config.link(c, "input.tx -> relay1.input")
    config.link(c, "relay1.output -> output.rx")
    config.link(c, "output.tx -> relay2.input")
    config.link(c, "relay2.output -> input.rx")

    engine.configure(c)
    print("start forwarder")
    engine.main({ report = { showlinks = true } })
end