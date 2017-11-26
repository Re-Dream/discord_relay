
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
				description = uptime .. " - **Map**: `" .. game.GetMap() .. "`",
				fields = {
					{
						name = "Players: " .. player.GetCount() .. " / " .. game.MaxPlayers(),
						value = players:Trim() ~= "" and [[```]] .. players .. [[```]] or "It's lonely in here."
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

		DiscordRelay.SendToDiscordRaw(nil, nil, 'Running rocket command "' .. args .. '"...')

		local t_post = {
			cmd = args
		}
		local t_struct = {
			failed = function(err)
				MsgC(Color(255, 64, 64), "HTTP error: " .. err .. "\n")
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
					end
					msg = {
						{
							title = 'Rocket command "' .. args .. '" run, result:',
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

hook.Add("MingebanInitialized", "DiscordRelay_rocketcommand", function()
	local rocket = mingeban.CreateCommand({"rocket", "liftoff"}, function(caller, line)
		if IsValid(caller) then
			caller:ChatAddText(Color(155, 255, 64), 'rocket - Running command "'.. line .. '"...')
		end

		Msg"[rocket] "print('Running command "'.. line .. '"...')

		local t_post = {
			cmd = line
		}
		local t_struct = {
			failed = function(err)
				MsgC(Color(255, 64, 64), "HTTP error: " .. err .. "\n")
			end,
			success = function(code, body, headers)
				local msg
				if code == 500 then
					if IsValid(caller) then
						caller:ChatAddText(Color(255, 64, 64), "rocket - 500 Internal Error")
					end

					Msg"[rocket] "MsgC(Color(255, 64, 64), "500 Internal Error\n")
				else
					if IsValid(caller) then
						caller:ChatAddText(Color(155, 255, 64), 'rocket - Command "' .. line .. '" run, result in console')

						for _, line in next, body:Split("\n") do
							caller:PrintMessage(HUD_PRINTCONSOLE, line)
						end
					end

					Msg"[rocket] "print('Command "' .. line .. '" run, result in console')
					MsgC(Color(192, 192, 192), body .. "\n")
				end
			end,
			method = "POST",
			url = "https://gmlounge.us/redream/rcon/bot/index.php",
			parameters = t_post,
			headers = {
				Authorization = "Bot " .. DiscordRelay.BotToken
			}
		}

		HTTP(t_struct)
	end)
end)
if istable(GAMEMODE) and mingeban then
	hook.GetTable().MingebanInitialized["DiscordRelay_rocketcommand"]()
end

