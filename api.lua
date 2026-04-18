-- handles all HTTP communication with the MediaTracker backend
-- change SERVER_URL when the server moves

local ltn12 = require("ltn12")
local rapidjson = require("rapidjson")
local logger = require("logger")

local SERVER_URL = "http://143.47.54.63"

local Api = {}

-- pick http or https based on the url, ssl.https might not be available on all devices
local function getHttpLib(url)
    if url:sub(1, 5) == "https" then
        local ok, https = pcall(require, "ssl.https")
        if ok then return https end
    end
    return require("socket.http")
end

local function post(path, body, token)
    local url = SERVER_URL .. path
    local body_json = rapidjson.encode(body)
    local response_chunks = {}

    local headers = {
        ["Content-Type"] = "application/json",
        ["Content-Length"] = tostring(#body_json),
        ["Accept"] = "application/json",
    }
    if token then
        headers["Authorization"] = "Bearer " .. token
    end

    local lib = getHttpLib(url)
    local ok, status = lib.request({
        url = url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(body_json),
        sink = ltn12.sink.table(response_chunks),
    })

    if not ok then
        logger.warn("MediaTracker: request failed:", status)
        return nil, { success = false, message = tostring(status) }
    end

    -- try to parse json, fall back to raw string if the server returns something unexpected
    local response_str = table.concat(response_chunks)
    local parse_ok, response = pcall(rapidjson.decode, response_str)
    if not parse_ok then
        response = { success = false, message = response_str }
    end

    return status, response
end

function Api.requestCode(email)
    return post("/api/auth/request-code", { Email = email })
end

function Api.verifyCode(email, code)
    return post("/api/auth/verify-code", { Email = email, Code = code })
end

function Api.trackBook(token, title, pages, author, isbn)
    local body = {
        Title    = title,
        Type     = "Book",
        Length   = pages,
        Progress = 100,
    }
    if author and author ~= "" then body.Author = author end
    if isbn   and isbn   ~= "" then body.Isbn   = isbn   end
    return post("/api/tracking", body, token)
end

return Api
