local replicatedStorage = game:GetService("ReplicatedStorage")
local starterPlayer = game:GetService("StarterPlayer")
local runService = game:GetService("RunService")

local packages = replicatedStorage.Packages
local shared = replicatedStorage.Shared

local defaultAnimations = require(script.DefaultAnimations)
local characterUtils = require(packages.CharacterUtils)
local animationUtils = require(packages.AnimationUtils)
local threadUtils = require(packages.ThreadUtils)
local CONSTANTS = require(shared.CONSTANTS)
local promise = require(packages.Promise)
local janitor = require(packages.Janitor)
local signal = require(packages.Signal)

local cache: {[Humanoid]: Animate} = setmetatable({}, {__mode = "k"})
local animate = {
	AnimateCreated = signal.new() :: signal.Signal<Animate>,
	AnimateDestroyed = signal.new() :: signal.Signal<Animate>,
}
animate.__index = animate

function animate.PromiseGet(humanoid: Humanoid)
	return promise.new(function(resolve, reject: (...any) -> ())
		local targetAnimate = animate.Get(humanoid)
		if targetAnimate then
			return resolve(targetAnimate)
		end

		local tempJanitor = janitor.new()
		local thread = coroutine.running()

		tempJanitor:Add(animate.AnimateCreated:Connect(function(newAnimate)
			if newAnimate.Humanoid ~= humanoid then
				return
			end

			threadUtils.ResumeThread(thread)
			resolve(newAnimate)
		end))

		threadUtils.YieldThread(thread)
		tempJanitor:Destroy()
	end)
end

function animate.Get(humanoid: Humanoid)
	return cache[humanoid]
end

function animate.new(humanoid: Humanoid)
	local self = setmetatable({}, animate)

	self.Humanoid = humanoid
	self.Janitor = janitor.new()
	self.Anims = {} :: {[string]: {Current: AnimationTrack, Default: AnimationTrack}}
	self.CurrentTrack = nil :: AnimationTrack?
	self.DisabledAnimations = {} :: {string}
	self.AnimationCache = {} :: {[string]: AnimationTrack}
	self.AnimationStacks = {} :: {[string]: {AnimationTrack}}

	self.Janitor:Add(characterUtils.ObserveOnDeath(self.Humanoid, function()
		self:Destroy()
	end))

	for index, value in defaultAnimations do
		self:LoadAnimation(index, value.ID):SetAttribute("BaseSpeed", value.Speed)
	end

	self.Janitor:Add(runService.PreSimulation:Connect(function()
		local rootPart = humanoid.RootPart
		if not rootPart or not self.Humanoid then return end

		local currentState = self.Humanoid:GetState()

		if currentState == Enum.HumanoidStateType.Running then
			local speed = (rootPart.AssemblyLinearVelocity * CONSTANTS.NO_Y_VECTOR).Magnitude
			local landedTrack = self:GetTrack("Landed")
			if landedTrack and landedTrack.IsPlaying then return end

			if speed < 1 then
				self:PlayAnimation("Idle")
			else
				self:PlayAnimation("Run")
				self:AdjustCurrentTrackSpeed(speed / starterPlayer.CharacterWalkSpeed)
			end

		elseif currentState == Enum.HumanoidStateType.Landed then
			self:PlayAnimation("Landed")

		elseif currentState == Enum.HumanoidStateType.Jumping then
			self:PlayAnimation("Jump")

		elseif currentState == Enum.HumanoidStateType.Freefall then
			local jumpTrack = self:GetTrack("Jump")
			if jumpTrack and jumpTrack.IsPlaying then return end
			self:PlayAnimation("FreeFall")

		elseif currentState == Enum.HumanoidStateType.Climbing then
			local speed = rootPart.AssemblyLinearVelocity.Y
			self:PlayAnimation("Climb")
			self:AdjustCurrentTrackSpeed(speed / starterPlayer.CharacterWalkSpeed)

		elseif currentState == Enum.HumanoidStateType.Swimming then
			local speed = rootPart.AssemblyLinearVelocity.Magnitude
			if speed <= 5 then
				self:PlayAnimation("SwimIdle")
			else
				self:PlayAnimation("Swim")
				self:AdjustCurrentTrackSpeed(speed / starterPlayer.CharacterWalkSpeed)
			end

		elseif self.Humanoid.Sit then
			self:PlayAnimation("Sit")
		end
	end))

	cache[humanoid] = self
	animate.AnimateCreated:Fire(self)

	return self
end

function animate.LoadAnimation(self: Animate, name: string, animation: Animation | number | string)
	if self.AnimationCache[name] then
		self.Anims[name] = {
			Current = self.AnimationCache[name],
			Default = self.AnimationCache[name],
		}
		return self.AnimationCache[name]
	end

	local track = animationUtils.getOrCreateAnimationTrack(self.Humanoid, animation)

	self.AnimationCache[name] = track
	self.Anims[name] = {
		Current = track,
		Default = track,
	}

	self.Janitor:Add(function()
		local cachedTrack = self.Anims[name]
		if cachedTrack and cachedTrack.Current then
			cachedTrack.Current:Stop()
		end
		self.Anims[name] = nil
	end, nil, `{name}_Track`)

	return track
end

function animate.GetTrack(self: Animate, name: string)
	local trackData = self.Anims[name]
	if not trackData then return end
	return trackData.Current
end

function animate.PlayAnimation(self: Animate, name: string)
	if table.find(self.DisabledAnimations, name) then
		local track = self:GetTrack(name)
		if not track then return end
		if track == self.CurrentTrack then
			self.CurrentTrack:Stop()
			self.CurrentTrack = nil
		end
		return
	end

	local track = self:GetTrack(name)
	if not track or track.IsPlaying or self.CurrentTrack == track then return end

	if self.CurrentTrack then
		self.CurrentTrack:Stop()
	end

	track:Play()
	self.CurrentTrack = track
end

function animate.AdjustCurrentTrackSpeed(self: Animate, speed: number)
	if not self.CurrentTrack then return end
	self.CurrentTrack:AdjustSpeed(speed * (self.CurrentTrack:GetAttribute("BaseSpeed") or 1))
end

function animate.UpdateAnimation(self: Animate, name: string, newTrack: AnimationTrack | Animation | string | number)
	if typeof(newTrack) ~= "Instance" or not newTrack:IsA("AnimationTrack") then
		newTrack = animationUtils.getOrCreateAnimationTrack(self.Humanoid, newTrack)
	end

	if not self.Anims[name] then
		self.Anims[name] = {
			Current = newTrack,
			Default = newTrack,
		}
	end

	self.AnimationStacks[name] = self.AnimationStacks[name] or {}
	local stack = self.AnimationStacks[name]

	if not table.find(stack, newTrack) then
		table.insert(stack, newTrack)
	end

	self.Anims[name].Current = stack[#stack]

	if self.CurrentTrack == self.Anims[name].Current then return newTrack end
	self:PlayAnimation(name)

	return newTrack
end

function animate.RemoveAnimation(self: Animate, name: string, trackToRemove: AnimationTrack | Animation | string | number)
	if typeof(trackToRemove) ~= "Instance" or not trackToRemove:IsA("AnimationTrack") then
		trackToRemove = animationUtils.getOrCreateAnimationTrack(self.Humanoid, trackToRemove)
	end

	local stack = self.AnimationStacks[name]
	if not stack then return end

	local index = table.find(stack, trackToRemove)
	if not index then return end

	table.remove(stack, index)

	local nextTrack = stack[#stack] or self.Anims[name].Default
	self.Anims[name].Current = nextTrack

	if self.CurrentTrack == trackToRemove then
		self:PlayAnimation(name)
	end
end

function animate.SetToDefault(self: Animate, name: string)
	self.AnimationStacks[name] = {}
	local trackData = self.Anims[name]
	if not trackData then return end
	self.Anims[name].Current = trackData.Default
	self:PlayAnimation(name)
end

function animate.DisableAnimation(self: Animate, name: string)
	if name == "All" then
		for animName in self.Anims do
			table.insert(self.DisabledAnimations, animName)
		end
		return
	end
	table.insert(self.DisabledAnimations, name)
end

function animate.EnableAnimation(self: Animate, name: string)
	if name == "All" then
		for i = 1, #self.DisabledAnimations do
			self.DisabledAnimations[i] = nil
		end
		return
	end
	table.remove(self.DisabledAnimations, table.find(self.DisabledAnimations, name))
end

function animate.Destroy(self: Animate)
	animate.AnimateDestroyed:Fire(self)

	for _, track in self.AnimationCache do
		track:Stop()
		track:Destroy()
	end
	cache[self.Humanoid] = nil
	self.Janitor:Destroy()
	setmetatable(self, nil)
	table.clear(self)
end

export type Animate = typeof(animate.new())

return animate