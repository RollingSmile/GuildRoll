-- Removed retry system constants

-- Remove RETRY_INTERVAL_SEC and MAX_RETRIES

-- Removed pending message queue variables

-- Remove pending_messages and pending_retry_scheduled

function processPendingMessages()
    -- function logic removed
end

function handleAdminLogMessage(message)
    if message.channel == "GUILD" or message.channel == "OFFICER" then
        -- Skip verifyGuildMember verification for messages from GUILD and OFFICER
        return processMessage(message)
    elseif message.channel == "WHISPER" then
        -- Maintain verifyGuildMember verification only for WHISPER
        verifyGuildMember(message)
    end
    -- Process messages immediately without queueing
    processMessage(message)
end