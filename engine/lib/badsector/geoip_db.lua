--[[
  MaxMind DB helper — supports multiple MMDB files (Country + ASN).
]]

local _M = {}

--- Open an MMDB file.
---@param path string
---@return table|nil db
---@return string|nil err
function _M.open(path)
    if not path or path == "" then
        return nil, "empty path"
    end

    local f = io.open(path, "r")
    if not f then
        return nil, "file not found: " .. path
    end
    f:close()

    local ok, mmdb = pcall(require, "resty.maxminddb")
    if not ok or not mmdb then
        return nil, "resty.maxminddb not available"
    end

    if mmdb.open then
        local db, err = mmdb.open(path)
        if not db then
            return nil, err or "open failed"
        end
        return db
    end

    if mmdb.new then
        local db, err = mmdb.new(path)
        if not db then
            return nil, err or "new failed"
        end
        return db
    end

    if not mmdb.inited() then
        local init_ok, init_err = pcall(mmdb.init, path)
        if not init_ok then
            return nil, init_err or "init failed"
        end
    end

    return { _singleton = true, _mod = mmdb }
end

--- Lookup IP in database.
---@param db table
---@param ip string
---@return table|nil
function _M.lookup(db, ip)
    if not db or not ip then
        return nil
    end

    if db._singleton then
        return db._mod.lookup(ip)
    end

    if db.lookup then
        return db:lookup(ip)
    end

    return nil
end

--- Close database handle if supported.
---@param db table|nil
function _M.close(db)
    if db and db.close then
        pcall(db.close, db)
    end
end

return _M
