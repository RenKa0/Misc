local replicatedStorage = game:GetService("ReplicatedStorage")

local packages = replicatedStorage.Packages
local assets = replicatedStorage.Assets
local animations = assets.Animations
local shared = replicatedStorage.Shared
local statusEffects = shared.StatusEffects
local movesetsFolder = shared.Movesets
local defaultAnims = animations.Default

local animationUtils = require(packages.AnimationUtils)
local bodyMoverUtils = require(packages.BodyMoverUtils)
local quickProps = require(statusEffects.QuickProps)
local network = require(replicatedStorage.Network)
local allMovesets = require(shared.AllMovesets)
local stunned = require(statusEffects.Stunned)
local ragdoll = require(statusEffects.Ragdoll)
local janitor = require(packages.Janitor)
local hitbox = require(packages.Hitbox)
local wcs = require(packages.wcs)

local SLAM_OFFSET = CFrame.Angles(math.rad(90), 0, 0)
local M1_OFFSET = CFrame.new(0, 0, -3)
local UPPERCUT_ROTATIONAL_SPEED = 10
local HITBOX_SIZE = Vector3.one * 5
local RESET_TIME = 1.5

export type M1 = wcs.Skill & {
	Anims: {[string]: {AnimationTrack}, All: {AnimationTrack}},
	LastM1: number,
	LastIndex: number,
}
local m1 = wcs.RegisterSkill("M1") :: M1

function m1.OnConstructServer(self: M1)
	self.Anims = {All = {}}
	self.LastM1 = 0
	self.LastIndex = 1
	self.CheckedByOthers = false
	
	local character = self.Character.Instance
	local movesetName = self.Character:GetMovesetName()
	
	local movesetFolder = movesetsFolder:FindFirstChild(movesetName)
	local m1Folder = movesetFolder:FindFirstChild(movesetName) or defaultAnims.M1

	if not self.Anims[movesetName] then
		self.Anims[movesetName] = {}
	end
	local slamTrack = animationUtils.getOrCreateAnimationTrack(
		character,
		movesetFolder:FindFirstChild("Slam") or defaultAnims:FindFirstChild("Slam")
	)
	self.Anims[movesetName]["Slam"] = slamTrack

	local upperTrack = animationUtils.getOrCreateAnimationTrack(
		character,
		movesetFolder:FindFirstChild("Uppercut") or defaultAnims:FindFirstChild("Uppercut")
	)
	self.Anims[movesetName]["Uppercut"] = upperTrack

	for _, anim in m1Folder:GetChildren() do
		if not anim:IsA("Animation") then
			continue
		end

		local track = animationUtils.getOrCreateAnimationTrack(character, anim)
		self.Anims[movesetName][tonumber(anim.Name)] = track
		table.insert(self.Anims.All, track)
	end
end

function m1.OnStartServer(self: M1, ...)
	if os.clock() - self.LastM1 >= RESET_TIME then
		self.LastIndex = 1
	end
	
	local function stopAnims()
		for _, anim in self.Anims.All do
			anim:Stop()
		end
	end
	stopAnims()
	
	local wcsCharacter = self.Character
	local mainHumanoid = wcsCharacter.Humanoid
	local mainRootPart = mainHumanoid.RootPart
	local character = wcsCharacter.Instance
	
	local m1Hitbox = self.Janitor:Add(hitbox.new({
		RefPart = character:FindFirstChild("HumanoidRootPart"),
		IgnoreStates = {ragdoll},
		Ignore = {character},
		Offset = M1_OFFSET,
		Size = HITBOX_SIZE,
		Debug = true,
	}))

	local movesetName = wcsCharacter:GetMovesetName()
	local targetAnims = self.Anims[movesetName]
	local maxM1 = table.maxn(targetAnims)
	local isMaxM1 = self.LastIndex >= maxM1
	local m1Type = "Regular"

	local targetTrack: AnimationTrack = targetAnims[self.LastIndex]

	if isMaxM1 then
		local maxTempStunned = stunned.new(wcsCharacter)
		maxTempStunned:Start(1)
		
		m1Hitbox.HumanoidHit:Once(function()
			maxTempStunned:Destroy()
		end)
		
		local floorMaterial = mainHumanoid.FloorMaterial
		local currentState = mainHumanoid:GetState()

		if floorMaterial == Enum.Material.Air or currentState == Enum.HumanoidStateType.Freefall then
			targetTrack = targetAnims.Slam
			m1Type = "Slam"
		elseif mainHumanoid.Jump then
			targetTrack = targetAnims.Uppercut
			m1Type = "Uppercut"
		end
	end
	
	local defaultM1Time = wcsCharacter.MovesetSettings.M1Time
	local stunTime = wcsCharacter.MovesetSettings.M1StunTime
	local cooldown = isMaxM1 and stunTime or defaultM1Time

	targetTrack:Play()
	
	--network.VFX:Fire("M1", {
	--	CharacterId = character:GetAttribute("ID"),
	--	MovesetName = movesetName,
	--	Index = self.LastIndex,
	--})
	
	local hitSomeone = false
	self.Janitor:Add(m1Hitbox.HumanoidHit:Connect(function(otherWcsCharacter)
		local otherCharacter = otherWcsCharacter.Instance
		--network.VFX:Fire("M1Hit", {
		--	VictimId = otherCharacter:GetAttribute("ID"),
		--	AttackerId = character:GetAttribute("ID"),
		--	MovesetName = movesetName,
		--	Index = self.LastIndex,
		--})
		
		local otherStunned = stunned.new(otherWcsCharacter)
		otherStunned:Start(1)
		
		local otherRootPart = otherWcsCharacter.Humanoid.RootPart
		
		if isMaxM1 then
			local tempRagdoll = ragdoll.new(otherWcsCharacter)
			tempRagdoll:Start(2)
			
			local mainRootPartCF = mainHumanoid.RootPart.CFrame
			bodyMoverUtils.BodyVelocity(
				otherRootPart,
				m1Type == "Regular" and mainRootPartCF.LookVector * 20
					or mainRootPartCF.UpVector * (m1Type == "Uppercut" and 30 or -20),
				0.25
			).MaxForce = Vector3.one * 40_000
			
			if m1Type == "Slam" then
				otherWcsCharacter.Instance:PivotTo(otherRootPart.CFrame * SLAM_OFFSET)
			elseif m1Type == "Uppercut" then
				bodyMoverUtils.AngularVelocity(
					otherRootPart,
					Vector3.new(
						math.random(-UPPERCUT_ROTATIONAL_SPEED, UPPERCUT_ROTATIONAL_SPEED),
						math.random(-UPPERCUT_ROTATIONAL_SPEED, UPPERCUT_ROTATIONAL_SPEED),
						math.random(-UPPERCUT_ROTATIONAL_SPEED, UPPERCUT_ROTATIONAL_SPEED)
					),
					0.1
				)
			end
		else
			local direction = mainRootPart.CFrame.LookVector * 10
			bodyMoverUtils.BodyVelocity(mainRootPart, direction, 0.1)
			bodyMoverUtils.BodyVelocity(otherRootPart, direction, 0.1)
		end
		
		otherWcsCharacter:TakeDamage(self:CreateDamageContainer(3))
	end))

	self.Janitor:Add(self.Character.SkillStarted:Connect(function(skill)
		if skill == self then
			return
		end
		stopAnims()
	end))
	self.Janitor:Add(targetTrack:GetMarkerReachedSignal("hitStart"):Connect(function()
		m1Hitbox:Start()
	end))
	self.Janitor:Add(targetTrack:GetMarkerReachedSignal("hitEnd"):Connect(function()
		hitSomeone = m1Hitbox:HitSomeone()
		m1Hitbox:Stop()

		if isMaxM1 and hitSomeone or not isMaxM1 then
			return
		end

		local tempStunned = stunned.new(wcsCharacter)
		tempStunned:Start(1)
	end))
	
	local noJump = quickProps.new(wcsCharacter, "Server")
	noJump:SetMetadata({JumpPower = {0, "Set"}})
	noJump:Start(cooldown + 0.1)
	
	self.LastIndex = (self.LastIndex % maxM1) + 1
	self.LastM1 = os.clock()
	
	self:ApplyCooldown(cooldown)
	task.wait(cooldown)
	self:Stop()
end

function m1.OnConstructClient(self: M1)
	self.IgnoreHotbar = true
end

return m1