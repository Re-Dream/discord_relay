
if not DiscordRelay then
	Error("Woah, we couldn't find ourselves a config file! If this happens, you should reinstall.")
end

DiscordRelay.NextRunTime = DiscordRelay.NextRunTime or SysTime()

DiscordRelay.FileLocations = DiscordRelay.FileLocations or {}
DiscordRelay.FileLocations.ReceivedMessages = "discord_relay/received_messages.txt"
DiscordRelay.Self = DiscordRelay.Self or nil

if not file.IsDir("discord_relay/", "DATA") then
	file.CreateDir("discord_relay")
end
for k, v in pairs(DiscordRelay.FileLocations) do
	if not file.Exists(v, "DATA") then
		file.Write(v, util.TableToJSON({}))
	end

	DiscordRelay[k] = util.JSONToTable(file.Read(v, "DATA") or "") or {}
end

http.Loaded = false
local function checkHTTP()
	http.Post("https://google.com", {}, function()
		http.Loaded = true
	end, function()
		http.Loaded = true
	end)
end
timer.Create("HTTPLoadedCheck", 3, 0, function()
	if not http.Loaded then
		checkHTTP()
	else
		hook.Run("HTTPLoaded")
		timer.Remove("HTTPLoadedCheck")
	end
end)
-- Thanks Author. for this bypass. Need to know when HTTP loads so we can gather some info about the bot and shit
hook.Add("HTTPLoaded", "GetSelf", function()
	HTTP({
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error at line 50: " .. err .. "\n")
		end,
		success = function(code, body, headers)
			DiscordRelay.Self = util.JSONToTable(body)
		end,
		url = "https://discordapp.com/api/users/@me"
	})
end)

local errcodes = {
	[50001] = "Your bot cannot read the channel! Please ensure the bot has 'Read Messages' permission for the channel.",
	[50010] = "Your bot hasn't got an account! Please go back and make one!"
}
function DiscordRelay.VerifyMessageSuccess(code, body, headers)
	body = util.JSONToTable(body)

	if body then
		if body.code then
			ErrorNoHalt("[ERROR] Discord returned error code " .. body.code .. ": " .. body.message .. "\n")

			if DiscordRelay.DEBUG_MODE then
				print("HTML Code", "Headers")
				print(code, headers)
			end

			if errcodes[body.code] then
				print(errcodes[body.code])
			end

			return false
		else
			return true
		end
	else
		return false
	end
end

function DiscordRelay.SendToDiscord(ply, avatar, text, teamchat)
	if not ply then return end

	local nick = (ply:Nick() or ply:SteamID())

	if string.len(nick) > 32 then
		nick = string.sub(nick, 1, 29) .. "..."
	end

	local t_post = {
		content = text,
		username = nick,
		avatar_url = avatar
	}

	local t_struct = {
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error in sending user message to discord: " .. err .. "\n")
		end,
		success = DiscordRelay.VerifyMessageSuccess,
		method = "post",
		url = DiscordRelay.WebhookURL,
		parameters = t_post,
		type = "application/json; charset=utf-8" --JSON Request type, because I'm a good boy.
	}

	HTTP(t_struct)
end
function DiscordRelay.SendToDiscordRaw(username, avatarurl, message)
	local t_post = {
		content = message,
		username = username or "Unknown",
		avatar_url = s_image
	}

	local t_struct = {
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error in sending raw message to discord: " .. err .. "\n")
		end,
		success = DiscordRelay.VerifyMessageSuccess,
		method = "post",
		url = DiscordRelay.WebhookURL,
		parameters = t_post,
		type = "application/json; charset=utf-8" -- JSON Request type, because I'm a good boy.
	}

	HTTP(t_struct)
end

util.AddNetworkString("DiscordRelay_MessageReceived")

function DiscordRelay.HandleChat(code, body, headers)
	if not body then return end

	if body == nil then
		MsgC(Color(255, 255, 0), "Non fatal error: No messages retrieved from discord, perhaps a connectivity error is to blame?\n")

		return
	end

	if not DiscordRelay.VerifyMessageSuccess(code, body, headers) then return end
	body = util.JSONToTable(body)

	if body.message == "You are being rate limited." then
		DiscordRelay.NextRunTime = SysTime() + body.retry_after
		MsgC(Color(255, 0, 0), "Discord error: You are being rate limited. The relay will not check for messages again for another " .. body.retry_after .. " seconds.\n")
		ErrorNoHalt("Discord Rate Limiting Detected. Message retrieval will be disabled for approximately " .. body.retry_after .. " seconds.")
		DiscordRelay.SendToDiscordRaw("Relay", false, "The bot is being rate limited! Players on the server will not see your messages for another " .. body.retry_after .. " seconds.")

		return
	end

	for i = DiscordRelay.MaxMessages, 1, -1 do
		local gotitalready = false
		if not body[i] then continue end
		if body[i].webhook_id then continue end

		for k, v in pairs(DiscordRelay.ReceivedMessages) do
			if (v.id == body[i].id) then
				gotitalready = true
			end
		end

		if string.len(body[i].content) > 126 then
			if not gotitalready then
				DiscordRelay.SendToDiscordRaw("Relay", false, "Sorry " .. body[i].author.username .. ", but that message was too long and wasn't relayed.")
			end

			table.insert(DiscordRelay.ReceivedMessages, {
				id = body[i].id,
				content = body[i].content,
				author = {
					id = body[i].author.id,
					username = body[i].author.username
				}
			})

			file.Write(DiscordRelay.FileLocations.ReceivedMessages, util.TableToJSON(DiscordRelay.ReceivedMessages, true))
			continue
		end

		if body[i].mentions then
			for k, v in pairs(body[i].mentions) do
				local tofind = "(<@!" .. v.id .. ">)"
				local toreplace = "@" .. v.username
				body[i].content = string.gsub(body[i].content, tofind, toreplace, 1)
			end
		end

		if gotitalready == false then
			MsgC(COLOR_DISCORD, "[Discord] ", COLOR_USERNAME, body[i].author.username, COLOR_COLON, ": ", COLOR_MESSAGE, body[i].content, "\n")
			net.Start("DiscordRelay_MessageReceived")
				net.WriteString(body[i].author.username)
				net.WriteString(body[i].content)
			net.Broadcast()

			table.insert(DiscordRelay.ReceivedMessages, {
				id = body[i].id,
				content = body[i].content,
				author = {
					id = body[i].author.id,
					username = body[i].author.username
				}
			})

			file.Write(DiscordRelay.FileLocations.ReceivedMessages, util.TableToJSON(DiscordRelay.ReceivedMessages, true))
		end
	end
end
function DiscordRelay.GetMessages()
	if SysTime() < DiscordRelay.NextRunTime then return end

	if not DiscordRelay.BotToken or DiscordRelay.BotToken == "" then
		Error("Invalid Bot Token!")
	end

	if not DiscordRelay.DiscordChannelID or DiscordRelay.DiscordChannelID == "" then
		Error("Invalid Channel ID.")
	end

	local t_struct = {
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error at line 256: " .. err .. "\n")
		end,
		success = DiscordRelay.HandleChat,
		url = "http://ptb.discordapp.com/api/channels/" .. DiscordRelay.DiscordChannelID .. "/messages",
		method = "get",
		headers = {
			Authorization = "Bot " .. DiscordRelay.BotToken
		}
	}

	HTTP(t_struct)
end
hook.Add("Think", "Discord_Check_Messages", function()
	if SysTime() >= DiscordRelay.NextRunTime then
		DiscordRelay.GetMessages()
		DiscordRelay.NextRunTime = SysTime() + DiscordRelay.MessageDelay
	end
end)

hook.Add("PlayerSay", "Discord_Webhook_Chat", function(ply, text, teamchat)
	if not IsValid(ply) then return end
	if ply:IsBot() then return end

	http.Fetch("https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=" .. DiscordRelay.SteamWebAPIKey .. "&steamids=" .. ply:SteamID64() .. "&format=json", function(body, size, headers, code)
		local response = util.JSONToTable(body)
		local plyInfo
		local image
		if response then
			response = response.response
			if response then
				if not response.players[1] then
					image = false
				else
					plyInfo = response.players[1]
					image = plyInfo.avatarfull
				end
			end
		end

		DiscordRelay.SendToDiscord(ply, image, text, teamchat)
	end)
end)

hook.Add("PlayerConnect", "Discord_Player_Connect", function(ply)
	-- Player connected message
end)
hook.Add("PlayerDisconnected", "Discord_Player_Disconnect", function(ply)
	-- Player disconnected message
end)

hook.Add("HTTPLoaded", "Discord_Announce_Active", function()
	-- Server turned on
	hook.Remove("HTTPLoaded", "Discord_Announce_Active") -- Just in case
end)

hook.Add("InitPostEntity", "CreateAFuckingBot", function()
	if DiscordRelay.AvoidUsingBots == false then
		print("Adding a bot to kick things off")
		game.ConsoleCommand("bot\n")

		for k, v in pairs(player.GetBots()) do
			v:Kick("Thanks for helping us out bot!")
		end
	else
		print("Attempting to force sv_hibernate_think to 1. Don't blame me for this!")
		game.ConsoleCommand("sv_hibernate_think 1\n")
	end

	hook.Remove("InitPostEntity", "CreateAFuckingBot")
end)

