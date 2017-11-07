
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

http.Loaded = http.Loaded and http.Loaded or false
local function checkHTTP()
	http.Post("https://google.com", {}, function()
		http.Loaded = true
	end, function()
		http.Loaded = true
	end)
end
if not http.Loaded then
	timer.Create("HTTPLoadedCheck", 3, 0, function()
		if not http.Loaded then
			checkHTTP()
		else
			hook.Run("HTTPLoaded")
			timer.Remove("HTTPLoadedCheck")
		end
	end)
end
-- Thanks Author. for this bypass. Need to know when HTTP loads so we can gather some info about the bot and shit
hook.Add("HTTPLoaded", "GetSelf", function()
	HTTP({
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error: " .. err .. "\n")
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
function DiscordRelay.SendToDiscordRaw(username, avatar, message)
	local t_post = {
		username = username,
		avatar_url = avatar,
	}
	if istable(message) then
		t_post.embeds = message
	else
		t_post.content = message
	end

	local body = util.TableToJSON(t_post, true)
	local t_struct = {
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error in sending raw message to discord: " .. err .. "\n")
		end,
		success = DiscordRelay.VerifyMessageSuccess,
		method = "POST",
		url = DiscordRelay.WebhookURL,
		parameters = t_post,
		body = body,
		headers = {
			["Content-Type"] = "application/json",
			["Content-Length"] = body:len() or "0",
		},
		type = "application/json"
	}

	HTTP(t_struct)
end

function DiscordRelay.GetGuild()
	if not DiscordRelay.BotToken or DiscordRelay.BotToken == "" then
		Error("Invalid Bot Token!")
	end

	if not DiscordRelay.DiscordGuildID or DiscordRelay.DiscordGuildID == "" then
		Error("Invalid Guild ID.")
	end

	local t_struct = {
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error: " .. err .. "\n")
		end,
		success = function(code, body, headers)
			DiscordRelay.Guild = util.JSONToTable(body)
		end,
		url = "http://discordapp.com/api/guilds/" .. DiscordRelay.DiscordGuildID,
		method = "GET",
		headers = {
			Authorization = "Bot " .. DiscordRelay.BotToken
		}
	}

	HTTP(t_struct)
end
function DiscordRelay.GetMembers()
	if not DiscordRelay.BotToken or DiscordRelay.BotToken == "" then
		Error("Invalid Bot Token!")
	end

	if not DiscordRelay.DiscordGuildID or DiscordRelay.DiscordGuildID == "" then
		Error("Invalid Guild ID.")
	end

	local t_struct = {
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error: " .. err .. "\n")
		end,
		success = function(code, body, headers)
			DiscordRelay.Members = util.JSONToTable(body)
		end,
		url = "http://discordapp.com/api/guilds/" .. DiscordRelay.DiscordGuildID .. "/members?limit=1000",
		method = "GET",
		headers = {
			Authorization = "Bot " .. DiscordRelay.BotToken
		}
	}

	HTTP(t_struct)
end
local function membersAction(callback)
	if not DiscordRelay.Members then
		DiscordRelay.GetMembers()
		return
	end

	return callback()
end
local function guildAction(callback)
	if not DiscordRelay.Guild then
		DiscordRelay.GetGuild()
		return
	end

	return callback()
end
-- TODO: Separate into other files
function DiscordRelay.GetMemberByID(id)
	return membersAction(function()
		for k, user in next, DiscordRelay.Members do
			if user.user.id == id then
				return user
			end
		end
	end)
end
function DiscordRelay.MemberHasRoleID(member, roleId)
	return membersAction(function()
		for k, user in next, DiscordRelay.Members do
			if user.user.id == member.id then
				for k, role in next, user.roles do
					if role:match(roleId) then
						return true
					end
				end
			end
		end
		return false
	end)
end
function DiscordRelay.GetMemberNick(member)
	local username = member.username
	membersAction(function()
		for _, user in next, DiscordRelay.Members do
			if user.user.username == username and user.nick then
				username = user.nick
			end
		end
	end)
	return username
end

-- From Discord

util.AddNetworkString("DiscordRelay_MessageReceived")

DiscordRelay.CmdPrefix = "^[%$%.!/]"
DiscordRelay.AdminRoles = { -- TODO: Use permission system instead
	["282267464941699072"] = true, -- Boss of this Gym
	["293169922069102592"] = true, -- Colonel
	["284101946158219264"] = true, -- Janitor
}
function DiscordRelay.IsMemberAdmin(member)
	for roleId, _ in next, DiscordRelay.AdminRoles do
		if DiscordRelay.MemberHasRoleID(member, roleId) then
			return true
		end
	end
	return false
end
DiscordRelay.HexColors = {
	Red = 0xFF4040,
	LightBlue = 0x40C0FF,
	Green = 0x7FFF40,
	Purple = 0x9B65BD,
	Yellow = 0xFFFF40
}
DiscordRelay.Commands = {
	status = function(msg)
		local time = CurTime()
		local uptime = string.format("**Uptime**: %.2d:%.2d:%.2d",
			math.floor(CurTime() / 60 / 60), -- hours
			math.floor(CurTime() / 60 % 60), -- minutes
			math.floor(CurTime() % 60) -- seconds
		)
		local players = {}
		for _, ply in next, player.GetAll() do
			players[#players + 1] = ply:Nick()
		end
		players = table.concat(players, ", ")
		DiscordRelay.SendToDiscordRaw(nil, nil, {
			{
				author = {
					name = GetHostName(),
					url = "http://gmlounge.us/join",
					icon_url = "https://gmlounge.us/media/redream-logo.png"
				},
				description = uptime .. " - **Map**: " .. game.GetMap(),
				fields = {
					{
						name = "Players: " .. player.GetCount() .. " / " .. game.MaxPlayers(),
						value = [[```]] .. players .. [[```]]
					}
				},
				color = DiscordRelay.HexColors.LightBlue
			}
		})
	end,
	l = function(msg, args)
		local nick = DiscordRelay.GetMemberNick(msg.author)
		local admin = DiscordRelay.IsMemberAdmin(msg.author)
		local msg
		local ret
		if admin then
			MsgC(COLOR_DISCORD, "[Discord Lua] ", COLOR_MESSAGE, "from ", COLOR_USERNAME, nick .. ": ", COLOR_MESSAGE, args, "\n")
			local err
			ret = CompileString(args, "discord_lua", false)
			if isstring(ret) then
				msg = {
					{
						title = "Lua Error:",
						description = ret,
						color = DiscordRelay.HexColors.Red
					}
				}
			else
				local ok, ret = pcall(ret)
				if ok == false then
					msg = {
						{
							title = "Lua Error:",
							description = ret,
							color = DiscordRelay.HexColors.Red
						}
					}
				else
					msg = ret and {
						{
							title = "Result:",
							description = "```" .. tostring(ret) .. "```",
							color = DiscordRelay.HexColors.Purple
						}
					} or ":white_check_mark:"
				end
			end
		else
			msg = {
				{
					title = "No access!",
					color = DiscordRelay.HexColors.Red
				}
			}
		end
		DiscordRelay.SendToDiscordRaw(nil, nil, msg)
	end,
	rocket = function(msg, args)
		local admin = DiscordRelay.IsMemberAdmin(msg.author)
		if not admin then
			DiscordRelay.SendToDiscordRaw(nil, nil, {
				{
					title = "No access!",
					color = DiscordRelay.HexColors.Red
				}
			})
			return
		end

		DiscordRelay.SendToDiscordRaw(nil, nil, "Running rocket command...")

		local t_post = {
			cmd = args
		}
		local t_struct = {
			failed = function(err)
				MsgC(Color(255, 0, 0), "HTTP error: " .. err .. "\n")
			end,
			success = function(code, body, headers)
				local msg
				if code == 500 then
					msg = {
						{
							title = "Internal Error",
							color = DiscordRelay.HexColors.Red
						}
					}
				else
					local desc = "```" .. tostring(body) .. "```"
					if #desc >= 1995 then
						desc = desc:sub(0, 1000) .. "\n[...]\n" .. desc:sub(-995)
						print(desc)
					end
					msg = {
						{
							title = "Rocket command run, result:",
							description = desc,
							color = DiscordRelay.HexColors.Purple
						}
					}
				end
				DiscordRelay.SendToDiscordRaw(nil, nil, msg)
			end,
			method = "POST",
			url = "https://gmlounge.us/redream/rcon/bot/index.php",
			parameters = t_post,
			headers = {
				Authorization = "Bot " .. DiscordRelay.BotToken
			}
		}

		HTTP(t_struct)
	end,
	help = function()
		local helpText = {}
		for cmd, _ in next, DiscordRelay.Commands do
			helpText[#helpText + 1] = cmd
		end
		helpText = table.concat(helpText, ", ")
		DiscordRelay.SendToDiscordRaw(nil, nil, {
			{
				title = "Available commands:",
				description = "```" .. helpText .. "```",
				color = DiscordRelay.HexColors.Purple
			}
		})
	end
}
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
		DiscordRelay.SendToDiscordRaw(nil, nil, "The bot is being rate limited! Players on the server will not see your messages for another " .. body.retry_after .. " seconds.")

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

		if body[i].embeds then
			for k, embed in next, body[i].embeds do
				if embed.title and embed.description then
					body[i].content = embed.title .. " - " .. embed.description
				end
			end
		end
		if string.len(body[i].content) > 256 then
			if not gotitalready then
				DiscordRelay.SendToDiscordRaw(nil, nil, "Sorry " .. body[i].author.username .. ", but that message was too long and wasn't relayed.")
			end

			table.insert(DiscordRelay.ReceivedMessages, {
				id = body[i].id,
				content = body[i].content,
				author = {
					id = body[i].author.id,
					username = body[i].author.username
				}
			})

			file.Write(DiscordRelay.FileLocations.ReceivedMessages, util.TableToJSON(DiscordRelay.ReceivedMessages))
			continue
		end
		if body[i].mentions then
			for k, v in next, body[i].mentions do
				local tofind = "(<@!?" .. v.id .. ">)"
				local username = DiscordRelay.GetMemberNick(v)
				local toreplace = "@" .. username
				body[i].content = string.gsub(body[i].content, tofind, toreplace)
			end
		end
		body[i].content = body[i].content:gsub("<(:%w*:)%d+>", "%1") -- custom emoji fix

		if gotitalready == false then
			MsgC(COLOR_DISCORD, "[Discord] ", COLOR_USERNAME, body[i].author.username, COLOR_COLON, ": ", COLOR_MESSAGE, body[i].content, "\n")
			local msg = body[i].content
			local prefix = msg:match(DiscordRelay.CmdPrefix)

			if prefix then
				local cmd = msg:Split(" ")
				cmd = cmd[1]:sub(prefix:len() + 1):lower()

				local args = msg:sub(prefix:len() + 1 + cmd:len() + 1)

				local callback = DiscordRelay.Commands[cmd:lower()]
				if callback then
					callback(body[i], args)
				end
			end

			local username = DiscordRelay.GetMemberNick(body[i].author)
			net.Start("DiscordRelay_MessageReceived")
				net.WriteString(username)
				net.WriteString(msg)
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
			MsgC(Color(255, 0, 0), "HTTP error: " .. err .. "\n")
		end,
		success = DiscordRelay.HandleChat,
		url = "http://discordapp.com/api/channels/" .. DiscordRelay.DiscordChannelID .. "/messages",
		method = "GET",
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
timer.Create("Discord_GuildInfo", 10, 0, function()
	DiscordRelay.GetMembers()
	DiscordRelay.GetGuild()
end)

-- To Discord
hook.Add("PlayerSay", "Discord_Webhook_Chat", function(ply, text, teamchat)
	local nick = ply:Nick()
	local sid = ply:SteamID()
	local sid64 = ply:SteamID64()

	local text = text:gsub("(@everyone)", "\\@no one")
	if DiscordRelay.Members then
		text = text:gsub("@(%w+)", function(name)
			for _, user in next, DiscordRelay.Members do
				local username = user.nick or user.user.username
				if username:lower():match(name:lower()) then
					return "<@" .. user.user.id .. ">"
				end
			end
		end)
	else
		DiscordRelay.GetMembers()
	end

	http.Fetch("http://steamcommunity.com/profiles/" .. sid64 .. "?xml=1", function(content, size)
		local avatar = content:match("<avatarFull><!%[CDATA%[(.-)%]%]></avatarFull>")
		DiscordRelay.SendToDiscordRaw(nick, avatar, text)
	end)
end)
gameevent.Listen("player_connect")
hook.Add("player_connect", "Discord_Player_Connect", function(ply)
	local nick = ply.name
	local sid = ply.networkid
	local sid64 = util.SteamIDTo64(ply.networkid)

	http.Fetch("http://steamcommunity.com/profiles/" .. sid64 .. "?xml=1", function(content, size)
		local avatar = content:match("<avatarFull><!%[CDATA%[(.-)%]%]></avatarFull>")
		DiscordRelay.SendToDiscordRaw(nil, nil, {
			{
				author = {
					name = nick .. " is joining the server!",
					url = "https://steamcommunity.com/profiles/" .. sid64,
					icon_url = avatar
				},
				description = sid .. " / " .. sid64,
				fields = {
					{
						name = "Join",
						value = "steam://connect/play.gmlounge.us"
					}
				},
				color = DiscordRelay.HexColors.Green
			}
		})
	end)
end)
hook.Add("PlayerDisconnected", "Discord_Player_Disconnect", function(ply)
	local nick = ply.RealName and ply:RealName() or ply:Nick()
	local sid = ply:SteamID()
	local sid64 = ply:SteamID64()

	http.Fetch("http://steamcommunity.com/profiles/" .. sid64 .. "?xml=1", function(content, size)
		local avatar = content:match("<avatarFull><!%[CDATA%[(.-)%]%]></avatarFull>")
		DiscordRelay.SendToDiscordRaw(nil, nil, {
			{
				author = {
					name = nick .. "  left the server.",
					url = "https://steamcommunity.com/profiles/" .. sid64,
					icon_url = avatar
				},
				description = sid .. " / " .. sid64,
				fields = {
					{
						name = "Join",
						value = "steam://connect/play.gmlounge.us"
					}
				},
				color = DiscordRelay.HexColors.Red
			}
		})
	end)
end)
hook.Add("HTTPLoaded", "Discord_Announce_Active", function()
	DiscordRelay.SendToDiscordRaw(nil, nil, {
		{
			author = {
				name = GetHostName(),
				url = "http://gmlounge.us/join",
				icon_url = "https://gmlounge.us/media/redream-logo.png"
			},
			description = "is now online, playing **" .. game.GetMap() .. "**.",
			fields = {
				{
					name = "Join",
					value = "steam://connect/play.gmlounge.us"
				}
			},
			color = DiscordRelay.HexColors.Yellow
		}
	})
	hook.Remove("HTTPLoaded", "Discord_Announce_Active") -- Just in case
end)

-- Initialize
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

