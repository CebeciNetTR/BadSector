--[[
  BadSector Pipeline Executor

  Loads site pipeline configuration and executes modules in order.
  Stops immediately on terminal decisions.
]]

local decision = require("badsector.decision")
local RequestContext = require("badsector.context")
local executor = require("badsector.executor")

local _M = {}

--- Execute the request pipeline for a site.
---@param site table Site config including pipeline definition
---@return table ctx RequestContext with final decision
function _M.run(site)
    local ctx = RequestContext.new(site)
    local pipeline = site.pipeline or {}

    for _, stage in ipairs(pipeline) do
        if stage.enabled == false then
            ctx:trace(stage.module, decision.CONTINUE, "module disabled")
            goto continue
        end

        local mod = _M.load_module(stage.module)
        if not mod then
            ngx.log(ngx.WARN, "badsector: module not found: ", stage.module)
            goto continue
        end

        local ok, result = pcall(mod.run, ctx, stage.config)
        if not ok then
            ngx.log(ngx.ERR, "badsector: module error [", stage.module, "]: ", result)
            ctx:trace(stage.module, decision.BLOCK, "module error")
            ctx:set_decision(decision.block(500, "Internal Server Error"))
            executor.apply(ctx)
            return ctx
        end

        if not result then
            result = decision.CONTINUE
        end

        ctx:trace(stage.module, result, nil)

        if decision.is_terminal(result) then
            ctx:set_decision(result)
            executor.apply(ctx)
            return ctx
        end

        ::continue::
    end

    -- No terminal decision — default ALLOW to backend
    ctx:set_decision(decision.ALLOW)
    return ctx
end

--- Load a module by name from registry or plugins path.
---@param name string Module name
---@return table|nil
function _M.load_module(name)
    local ok, mod = pcall(require, "badsector.modules." .. name)
    if ok then
        return mod
    end

    ok, mod = pcall(require, "plugins." .. name)
    if ok then
        return mod
    end

    return nil
end

--- Initialize all modules for a worker process.
---@param sites table[] All site configurations
function _M.init_worker(sites)
    local seen = {}

    for _, site in ipairs(sites or {}) do
        for _, stage in ipairs(site.pipeline or {}) do
            local name = stage.module
            if not seen[name] then
                seen[name] = true
                local mod = _M.load_module(name)
                if mod and mod.init then
                    local ok, err = pcall(mod.init, stage.config or {})
                    if not ok then
                        ngx.log(ngx.ERR, "badsector: init failed [", name, "]: ", err)
                    end
                end
            end
        end
    end
end

--- Hot reload module configurations.
---@param sites table[] Updated site configurations
function _M.reload(sites)
    local geo_lookup = require("badsector.geo_lookup")
    geo_lookup.reset()
    for _, site in ipairs(sites or {}) do
        for _, stage in ipairs(site.pipeline or {}) do
            local mod = _M.load_module(stage.module)
            if mod and mod.reload then
                pcall(mod.reload, stage.config or {})
            end
        end
    end
end

return _M
