local janitor = require(script.Parent.Janitor)

local instanceUtils = {}

function instanceUtils.SyncProperties(target: Instance, source: Instance)
	assert(target.ClassName == source.ClassName, "Instances are not the same class")
	
	local mainJanitor = janitor.new()
	
	mainJanitor:Add(source.Changed:Connect(function(property: string)
		target[property] = source[property]
	end))
	
	return mainJanitor
end

function instanceUtils.ObserveChildren(
	parent: Instance,
	callback: (child: Instance, childJanitor: janitor.Janitor) -> (),
	paredicate: (child: Instance) -> boolean?
)
	local mainJanitor = janitor.new()
	mainJanitor:LinkToInstance(parent)

	local function onChildAdded(child: Instance)
		if paredicate and not paredicate(child) then
			return
		end
		callback(child, mainJanitor:AddObject(janitor, nil, child))
	end

	for _, child in parent:GetChildren() do
		task.spawn(onChildAdded, child)
	end
	mainJanitor:Add(parent.ChildAdded:Connect(onChildAdded))
	mainJanitor:Add(parent.ChildRemoved:Connect(function(child: Instance)
		mainJanitor:Remove(child)
	end))

	return mainJanitor
end

function instanceUtils.ObserveDescendants(
	parent: Instance,
	callback: (descendant: Instance, descendantJanitor: janitor.Janitor) -> (),
	paredicate: (descendant: Instance) -> boolean?
)
	local mainJanitor = janitor.new()
	mainJanitor:LinkToInstance(parent)

	local function onDescendantAdded(descendant: Instance)
		if paredicate and not paredicate(descendant) then
			return
		end
		callback(descendant, mainJanitor:AddObject(janitor, nil, descendant))
	end

	for _, descendant in parent:GetDescendants() do
		task.spawn(onDescendantAdded, descendant)
	end
	mainJanitor:Add(parent.DescendantAdded:Connect(onDescendantAdded))
	mainJanitor:Add(parent.DescendantRemoving:Connect(function(descendant: Instance)
		mainJanitor:Remove(descendant)
	end))

	return mainJanitor
end

function instanceUtils.ObserveChildrenWhichIsA(
	parent: Instance,
	className: string,
	callback: (child: Instance, childJanitor: janitor.Janitor) -> ()
)
	return instanceUtils.ObserveChildren(parent, callback, function(child: Instance)
		return child:IsA(className)
	end)
end

function instanceUtils.ObserveDescendantsWhichIsA(
	parent: Instance,
	className: string,
	callback: (descendant: Instance, descendantJanitor: janitor.Janitor) -> ()
)
	return instanceUtils.ObserveDescendants(parent, callback, function(descendant: Instance)
		return descendant:IsA(className)
	end)
end

function instanceUtils.ObserveChildrenOfName(
	parent: Instance,
	name: string,
	callback: (child: Instance, childJanitor: janitor.Janitor) -> ()
)
	return instanceUtils.ObserveChildren(parent, callback, function(child: Instance)
		return child.Name == name
	end)
end

function instanceUtils.ObserveDescendantsOfName(
	parent: Instance,
	name: Instance,
	callback: (descendant: Instance, descendantJanitor: janitor.Janitor) -> ()
)
	return instanceUtils.ObserveDescendants(parent, callback, function(descendant: Instance)
		return descendant.Name == name
	end)
end

function instanceUtils.ObserveParent(
	instance: Instance,
	callback: (parent: Instance, parentJanitor: janitor.Janitor) -> (),
	predicate: (parent: Instance) -> boolean?
)
	return instanceUtils.ObserveProperty(instance, "Parent", callback, predicate)
end

--[[
⚠️ YIELDS
]]
function instanceUtils.WaitForChildWhichIsA(parent: Instance, className: string)
	local child = parent:FindFirstChildWhichIsA(className)
	if child then
		return child
	end

	while not child do
		child = parent:FindFirstChildWhichIsA(className)
		task.wait()
	end

	return child
end

function instanceUtils.ObserveProperty(
	instance: Instance,
	propertyName: string,
	callback: (value: any, propertyJanitor: janitor.Janitor) -> (),
	predicate: (value: any) -> boolean?
)
	local mainJanitor = janitor.new()
	mainJanitor:LinkToInstance(instance)

	local function onPropertyChanged()
		if predicate and not predicate(instance[propertyName]) then
			return
		end
		
		callback(instance[propertyName], mainJanitor:AddObject(janitor, nil, "LastValue"))
	end
	task.spawn(onPropertyChanged)
	mainJanitor:Add(instance:GetPropertyChangedSignal(propertyName):Connect(onPropertyChanged))

	return mainJanitor
end

function instanceUtils.ObserveAttribute(
	instance: Instance,
	attributeName: string,
	callback: (value: any, propertyJanitor: janitor.Janitor) -> (),
	predicate: (value: any) -> boolean?
)
	local mainJanitor = janitor.new()
	mainJanitor:LinkToInstance(instance)

	local function onAttributeChanged()
		local value = instance:GetAttribute(attributeName)
		if predicate and not predicate(value) then
			return
		end
		
		callback(value, mainJanitor:AddObject(janitor, nil, "LastValue"))
	end
	task.spawn(onAttributeChanged)
	mainJanitor:Add(instance:GetAttributeChangedSignal(attributeName):Connect(onAttributeChanged))
	
	return mainJanitor
end

return instanceUtils