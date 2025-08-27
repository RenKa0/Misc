local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local packages = replicatedStorage.Packages

local replicaServer = require(script.ReplicaServer)
local playerUtils = require(packages.PlayerUtils)
local profileStore = require(script.ProfileStore)
local janitor = require(packages.Janitor)
local signal = require(packages.Signal)

local dataStore = {
	Active = {},
	NewDataStore = signal.new() :: signal.Signal<string, dataStore>
}
dataStore.__index = dataStore

function dataStore.new<T>(name: string, template: T, createReplica: boolean?)
	local self = setmetatable({}, dataStore)
	
	self.Name = name
	self.Janitor = janitor.new()
	self.ProfileLoaded = self.Janitor:Add(signal.new()) :: signal.Signal<Player, profileStore.Profile<T>, replicaServer.Replica>
	self.ProfileReleasing = self.Janitor:Add(signal.new()) :: signal.Signal<Player, profileStore.Profile<T>>
	self.Profiles = {}
	
	self.Store = profileStore.New(name, template)
	if createReplica then
		self.ReplicaToken = replicaServer.Token(name)
	end
	
	self.Janitor:Add(
		playerUtils.observePlayers(nil, function(player: Player, playerJanitor)
			local profile = playerJanitor:Add(
				self.Store:StartSessionAsync(`{player.UserId}`, {
					Cancel = function()
						return not player:IsDescendantOf(players)
					end,
				}), "EndSession"
			)
			
			if profile then
				profile:AddUserId(player.UserId)
				profile:Reconcile()
				
				playerJanitor:Add(function()
					self.ProfileReleasing:Fire(player, profile)
				end)
				profile.OnSessionEnd:Connect(function()
					self.Profiles[player] = nil
					player:Kick("Session end - Please rejoin")
				end)
				
				if player:IsDescendantOf(players) then
					self.Profiles[player] = {
						Profile = profile,
					}
					
					if createReplica then
						local replica = replicaServer.New({
							Token = self.ReplicaToken,
							Data = profile.Data
						})
						self.Profiles[player].Replica = replica
						replica:Subscribe(player)
					end
					
					self.ProfileLoaded:Fire(player, profile, self.Profiles[player].Replica)
				else
					profile:EndSession()
				end
			else
				player:Kick("Failed to load data - Please rejoin")
			end
		end)
	)
	
	dataStore.Active[name] = self
	dataStore.NewDataStore:Fire(self.Name, self)
	return self
end

function dataStore.GetProfile(self: dataStore, player: Player)
	return self.Profiles[player]
end

function dataStore.Destroy(self: dataStore)
	self.Janitor:Destroy()
	dataStore.Active[self.Name] = nil
	setmetatable(self, nil)
	table.clear(self)
end

function dataStore.Get(name: string)
	local target = dataStore.Active[name]
	
	if not target then
		local thread = coroutine.running()
		local addedConnection
		local startTime = os.clock()
		task.spawn(function()
			repeat
				task.wait()
			until os.clock() - startTime >= 5 or target ~= nil
			
			if coroutine.status(thread) == "suspended" then
				coroutine.resume(thread)
			end
		end)
		
		addedConnection = dataStore.NewDataStore:Connect(function(_name: string, _dataStore) 
			if _name ~= name then
				return
			end
			target = _dataStore
			addedConnection:Disconnect()
			
			if coroutine.status(thread) == "suspended" then
				coroutine.resume(thread)
			end
		end)
		coroutine.yield()
		return target :: dataStore
	end
	return target
end

function dataStore.GetProfileFromDataStore(player: Player, name: string)
	return dataStore.Get(name):GetProfile(player)
end

export type dataStore = typeof(dataStore.new())

return dataStore