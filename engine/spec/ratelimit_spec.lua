describe("badsector.ratelimit", function()
    local ratelimit

    setup(function()
        package.path = "./engine/lib/?.lua;./engine/lib/?/init.lua;" .. package.path
        ratelimit = require("badsector.ratelimit")
    end)

    it("parses window strings", function()
        assert.are.equal(60, ratelimit.parse_window("60"))
        assert.are.equal(60, ratelimit.parse_window("60s"))
        assert.are.equal(120, ratelimit.parse_window("2m"))
        assert.are.equal(3600, ratelimit.parse_window("1h"))
    end)

    it("matches path patterns", function()
        local ctx = {
            request = { path = "/api/users", method = "GET" },
        }
        assert.is_true(ratelimit.rule_matches({ paths = { "/*" } }, ctx))
        assert.is_true(ratelimit.rule_matches({ paths = { "/api/*" } }, ctx))
        assert.is_false(ratelimit.rule_matches({ paths = { "/admin/*" } }, ctx))
    end)

    it("matches methods", function()
        local ctx = {
            request = { path = "/", method = "POST" },
        }
        assert.is_true(ratelimit.rule_matches({ methods = { "POST" } }, ctx))
        assert.is_false(ratelimit.rule_matches({ methods = { "GET" } }, ctx))
    end)
end)
