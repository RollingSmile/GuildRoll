-- RollParser.lua
-- Parses CSR/SR/MS submission lines and correlates them with system roll lines
-- Normalizes rolls to 1..100 for compatibility with existing rolling logic

local RollParser = {}
RollParser.__index = RollParser

-- Default options
local DEFAULT_OPTS = {
    pending_timeout = 8,  -- seconds to wait for matching system roll
    debug = true          -- enable debug messages
}

-- Helper: normalize a raw roll total from (min..max) to 1..100
local function normalize_roll(total, min, max)
    if not total or not min or not max then
        return nil
    end
    
    local range = max - min
    if range <= 0 then
        return nil
    end
    
    -- Calculate position within the range (0..1)
    local position = (total - min) / range
    
    -- Map to 1..100
    local normalized = math.floor(position * 99 + 1 + 0.5)  -- +0.5 for rounding
    
    -- Clamp to [1, 100]
    if normalized < 1 then normalized = 1 end
    if normalized > 100 then normalized = 100 end
    
    return normalized
end

-- Helper: parse submission line (user-initiated roll declaration)
-- Examples:
--   "[RL] [Lyrandel]: I rolled Cumulative SR 189 - 288 with 48 EP + 100 from SR +40 for 5 consecutive weeks"
--   "[RL] [Lyrandel]: I rolled SR \"149 - 248\" with 48 EP"
--   "[RL] [Lyrandel]: I rolled MS \"49 - 148\" with 48 EP"
local function parse_submission(msg)
    if not msg then return nil end
    
    -- Pattern 1: Cumulative SR with detailed breakdown
    -- "[RL] [PlayerName]: I rolled Cumulative SR MIN - MAX with EP_VALUE EP + ..."
    local player, min, max, ep = string.match(msg, "%[RL%]%s*%[([^%]]+)%]:%s*I rolled Cumulative SR (%d+)%s*%-%s*(%d+) with (%d+) EP")
    if player and min and max and ep then
        return {
            player = player,
            type = "CSR",
            min = tonumber(min),
            max = tonumber(max),
            ep = tonumber(ep)
        }
    end
    
    -- Pattern 2: SR with quoted range
    -- "[RL] [PlayerName]: I rolled SR "MIN - MAX" with EP_VALUE EP"
    player, min, max, ep = string.match(msg, "%[RL%]%s*%[([^%]]+)%]:%s*I rolled SR \"(%d+)%s*%-%s*(%d+)\" with (%d+) EP")
    if player and min and max and ep then
        return {
            player = player,
            type = "SR",
            min = tonumber(min),
            max = tonumber(max),
            ep = tonumber(ep)
        }
    end
    
    -- Pattern 3: MS with quoted range
    -- "[RL] [PlayerName]: I rolled MS "MIN - MAX" with EP_VALUE EP"
    player, min, max, ep = string.match(msg, "%[RL%]%s*%[([^%]]+)%]:%s*I rolled MS \"(%d+)%s*%-%s*(%d+)\" with (%d+) EP")
    if player and min and max and ep then
        return {
            player = player,
            type = "MS",
            min = tonumber(min),
            max = tonumber(max),
            ep = tonumber(ep)
        }
    end
    
    return nil
end

-- Helper: parse system roll line (server-generated roll result)
-- Example: "Lyrandel rolls 240 (189-288)"
local function parse_system_roll(msg)
    if not msg then return nil end
    
    -- Pattern: "PlayerName rolls TOTAL (MIN-MAX)"
    local player, total, min, max = string.match(msg, "^([^%s]+) rolls (%d+) %((%d+)%-(%d+)%)")
    if player and total and min and max then
        return {
            player = player,
            total = tonumber(total),
            min = tonumber(min),
            max = tonumber(max)
        }
    end
    
    return nil
end

-- Helper: check if two ranges match (with tolerance for minor differences)
local function ranges_match(min1, max1, min2, max2, tolerance)
    tolerance = tolerance or 2
    return math.abs(min1 - min2) <= tolerance and math.abs(max1 - max2) <= tolerance
end

-- Constructor
function RollParser.new(on_roll_cb, opts)
    local self = setmetatable({}, RollParser)
    
    self.on_roll_cb = on_roll_cb
    self.opts = opts or {}
    
    -- Apply defaults
    for k, v in pairs(DEFAULT_OPTS) do
        if self.opts[k] == nil then
            self.opts[k] = v
        end
    end
    
    -- Storage for pending submissions (waiting for system roll)
    self.pending = {}
    
    return self
end

-- Main handler for CHAT_MSG_SYSTEM events
function RollParser:on_chat_msg_system(msg, sender)
    if not msg then return end
    
    -- Try to parse as submission line
    local submission = parse_submission(msg)
    if submission then
        self:handle_submission(submission)
        return
    end
    
    -- Try to parse as system roll line
    local system_roll = parse_system_roll(msg)
    if system_roll then
        self:handle_system_roll(system_roll)
        return
    end
end

-- Handle a submission (user declaration)
function RollParser:handle_submission(submission)
    local player = submission.player
    
    if self.opts.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "[RollParser] Submission from %s: type=%s, range=%d-%d, ep=%d",
            player, submission.type, submission.min, submission.max, submission.ep
        ))
    end
    
    -- Store pending submission with timestamp
    self.pending[player] = {
        submission = submission,
        timestamp = GetTime()
    }
end

-- Handle a system roll (server confirmation)
function RollParser:handle_system_roll(system_roll)
    local player = system_roll.player
    local pending = self.pending[player]
    
    if not pending then
        -- No pending submission for this player - might be a normal roll
        if self.opts.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "[RollParser] System roll from %s: %d (%d-%d) - no pending submission",
                player, system_roll.total, system_roll.min, system_roll.max
            ))
        end
        return
    end
    
    local submission = pending.submission
    
    -- Check if ranges match (with tolerance)
    local mismatch = not ranges_match(
        submission.min, submission.max,
        system_roll.min, system_roll.max,
        2  -- tolerance
    )
    
    -- Normalize the roll
    local normalized = normalize_roll(system_roll.total, system_roll.min, system_roll.max)
    
    if not normalized then
        if self.opts.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "[RollParser] ERROR: Failed to normalize roll for %s",
                player
            ))
        end
        self.pending[player] = nil
        return
    end
    
    -- Build metadata
    local metadata = {
        type = submission.type,
        ep = submission.ep,
        raw_total = system_roll.total,
        raw_min = system_roll.min,
        raw_max = system_roll.max,
        mismatch = mismatch
    }
    
    if self.opts.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "[RollParser] Matched roll for %s: normalized=%d (from %d in %d-%d), type=%s, ep=%d, mismatch=%s",
            player, normalized, system_roll.total, system_roll.min, system_roll.max,
            metadata.type, metadata.ep, tostring(mismatch)
        ))
    end
    
    -- Clear pending
    self.pending[player] = nil
    
    -- Call the callback
    if self.on_roll_cb then
        self.on_roll_cb(player, normalized, 1, 100, metadata)
    end
end

-- Cleanup expired pending submissions
function RollParser:cleanup()
    local now = GetTime()
    local timeout = self.opts.pending_timeout
    
    for player, pending in pairs(self.pending) do
        if now - pending.timestamp > timeout then
            if self.opts.debug then
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "[RollParser] Timeout: pending submission from %s expired",
                    player
                ))
            end
            self.pending[player] = nil
        end
    end
end

return RollParser
