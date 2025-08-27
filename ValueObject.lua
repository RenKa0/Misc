local packages = script.Parent

local janitor = require(packages.Janitor)

local function isSimilar(a: unknown, b: unknown)
	local typeA = typeof(a)
	local typeB = typeof(b)

	if typeA ~= typeB then
		return false
	end

	if typeA == "table" or typeA == "userdata" then
		if typeA == "userdata" or table.isfrozen(a) or getmetatable(a) then
			return a == b
		else
			return false
		end
	end

	return a == b or (a ~= a and b ~= b) -- handle NaN
end

local valueObject = {}
valueObject.__index = valueObject

function valueObject.new<T>(initialValue: T, checkType: CheckType<T>?)
	local self = setmetatable({}, valueObject) :: ValueObject<T>
	self._Value = initialValue
	self._LastValue = initialValue
	self._Observers = {}
	self.Janitor = janitor.new()
	self._CheckType = checkType
	self:_checkType(initialValue)
	return self
end

function valueObject._checkType<T>(self: ValueObject<T>, value: T)
	local checker = self._CheckType
	if not checker then
		return
	end

	local checkerType = typeof(checker)
	if checkerType == "string" then
		if typeof(value) ~= checker then
			error(`Invalid value type: expected {checker}, got {typeof(value)}`)
		end
	elseif checkerType == "function" then
		local success, err = checker(value)
		assert(success, err or "Value failed custom check")
	end
end

function valueObject.SetValue<T>(self: ValueObject<T>, newValue: T)
	self:_checkType(newValue)

	local lastValue = self._Value

	if not isSimilar(lastValue, newValue) then
		self._LastValue = lastValue
		self._Value = newValue

		for proxy, observer in self._Observers do
			task.spawn(observer, self._Value, self._LastValue, self.Janitor:AddObject(janitor, nil, proxy))
		end
	end
end

function valueObject.Observe<T>(self: ValueObject<T>, callback: ObserverCallback<T>)
	local identifier = newproxy()
	self._Observers[identifier] = callback
	callback(self._Value, self._LastValue, self.Janitor:AddObject(janitor, nil, identifier))

	return function()
		self._Observers[identifier] = nil
		self.Janitor:Remove(identifier)
	end
end

function valueObject.GetValue<T>(self: ValueObject<T>)
	return self._Value
end

function valueObject.Destroy<T>(self: ValueObject<T>)
	self.Janitor:Destroy()
	setmetatable(self, nil)
end

export type CheckType<T> = string | (value: T) -> boolean
export type ObserverCallback<T> = (value: T, lastValue: T, stateJanitor: janitor.Janitor) -> ()
export type ValueObject<T> = {
	_Value: T,
	_LastValue: T,
	_Observers: {[any]: ObserverCallback<T>},
	Janitor: janitor.Janitor,
	_CheckType: CheckType<T>?,
} & typeof(setmetatable({}, valueObject))

return valueObject