local expr = require("badsector.expr")

local function ctx_with_path(path)
    return {
        request = {
            path = path,
            method = "GET",
            host = "example.com",
            headers = {},
            remote_addr = "1.2.3.4",
        },
        enrich = {},
        vars = {},
        get_var = function() return nil end,
    }
end

describe("badsector.expr", function()
    it("matches path contains wp on /wp-admin", function()
        local ok = expr.eval('path contains "wp"', ctx_with_path("/wp-admin"))
        assert.is_true(ok)
    end)

    it("matches OR expression for .env and wp", function()
        local ok = expr.eval('path contains ".env" or path contains "wp"', ctx_with_path("/wp-admin"))
        assert.is_true(ok)
    end)

    it("does not match unrelated paths", function()
        local ok = expr.eval('path contains "wp"', ctx_with_path("/hello"))
        assert.is_false(ok)
    end)
end)
