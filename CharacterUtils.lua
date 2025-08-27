local packages = script.Parent
local instanceUtils = require(packages.InstanceUtils)
local janitor = require(packages.Janitor)

local characterUtils = {}

--[[
⚠️ YIELDS
]]
function characterUtils.WaitForCharacterLoaded(character: Model)
	if not character.PrimaryPart then
		character:GetPropertyChangedSignal("PrimaryPart"):Wait()
	end

	if not character:IsDescendantOf(workspace) then
		character.AncestryChanged:Wait()
	end
end

function characterUtils.GetPlayerHumanoid(player: Player) : Humanoid
	local character = player.Character
	if not character then
		return
	end

	return character:FindFirstChildWhichIsA("Humanoid")
end

function characterUtils.ObserveOnDeath(humanoid: Humanoid, callback: () -> ())
	local mainJanitor = janitor.new()
	mainJanitor:LinkToInstance(humanoid)

	local alreadyDied = false

	local function onDied()
		if alreadyDied then
			return
		end
		alreadyDied = true
		callback()
	end
	mainJanitor:Add(instanceUtils.ObserveProperty(humanoid, "Health", function(health)
		if health > 0 then
			return
		end
		onDied()
	end))
	mainJanitor:Add(instanceUtils.ObserveParent(humanoid, function(parent: Instance)
		if parent ~= nil then
			return
		end
		onDied()
	end))
	mainJanitor:Add(humanoid.Died:Connect(onDied))

	return mainJanitor
end

function characterUtils.IsHumanoidDead(humanoid: Humanoid)
	return humanoid.Health <= 0
		or humanoid:GetState() == Enum.HumanoidStateType.Dead
		or not humanoid:IsDescendantOf(workspace)
end

function characterUtils.GetAliveCharacter(player: Player) : Model?
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if not humanoid or characterUtils.IsHumanoidDead(humanoid) then
		return
	end
	return character
end

function characterUtils.GetAliveRootPart(player: Player) : BasePart?
	local character = characterUtils.GetAliveCharacter(player)
	if not character then
		return
	end
	return character:FindFirstChild("HumanoidRootPart")
end

function characterUtils.GetAlivePlayerHumanoid(player: Player) : Humanoid?
	local humanoid = characterUtils.GetPlayerHumanoid(player)
	if not humanoid or characterUtils.IsHumanoidDead(humanoid) then
		return
	end
	return humanoid
end

function characterUtils.ObserveCharacter(
	player: Player,
	callback: (character: Model, characterJanitor: janitor.Janitor) -> ()
)
	local mainJanitor = janitor.new()
	mainJanitor:LinkToInstance(player)

	local function onCharacterAdded(character: Model)
		characterUtils.WaitForCharacterLoaded(character)
		task.defer(callback, character, mainJanitor:AddObject(janitor, nil, "LastValue"))
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	mainJanitor:Add(player.CharacterAdded:Connect(onCharacterAdded))

	return mainJanitor
end

function characterUtils.ObserveHumanoid(
	player: Player,
	callback: (humanoid: Humanoid, humanoidJanitor: janitor.Janitor) -> ()
)
	return characterUtils.ObserveCharacter(player, function(character: Model, characterJanitor) 
		characterJanitor:Add(
			instanceUtils.ObserveChildrenWhichIsA(character, "Humanoid", function(humanoid: Humanoid, childJanitor) 
				local aliveJanitor = childJanitor:AddObject(janitor)

				aliveJanitor:Add(characterUtils.ObserveOnDeath(humanoid, function()
					aliveJanitor:Cleanup()
				end))

				callback(humanoid, aliveJanitor)
			end)
		)
	end)
end

return characterUtils