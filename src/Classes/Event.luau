--[[
Event Class

Pure luau bindable event implementation
]]

-- Types
export type Connection<Params...> = {
	Event: Event<Params...>,
	BoundArgs: { any }?,
	Callback: (Params...) -> (),
	Connected: boolean,

	Disconnect: (self: Connection<Params...>) -> (),
	Reconnect: (self: Connection<Params...>) -> (),

	_prev: Connection<Params...>?,
	_next: Connection<Params...>?,
}

export type Event<Params...> = {
	Connect: (self: Event<Params...>, callback: (Params...) -> ()) -> Connection<Params...>,
	Once: (self: Event<Params...>, callback: (Params...) -> ()) -> Connection<Params...>,
	Wait: (self: Event<Params...>) -> Params...,
	Fire: (self: Event<Params...>, Params...) -> (),
	DisconnectAll: (self: Event<Params...>) -> (),
	Destroy: (self: Event<Params...>) -> (),

	_rbxConn: RBXScriptConnection?,
	_head: Connection<Params...>?,
}

--#Class: Event
local Event = {}
Event.__index = Event

--#Class: Connection
local Connection = {}
Connection.__index = Connection

--[[ Threads pooling ]]
local freeThreads = {}

local function runCallback(callback, thread, ...)
	callback(...)
	freeThreads[#freeThreads + 1] = thread
end

local function yielder()
	while true do
		runCallback(coroutine.yield())
	end
end

local function spawn(callback, ...)
	local thread = table.remove(freeThreads)

	if not thread then
		thread = coroutine.create(yielder)
		coroutine.resume(thread)
	end

	coroutine.resume(thread, callback, thread, ...)
end

--[[ Connection class implementation ]]
function Connection.new<Params..., BoundArgs...>(event: Event<Params...>, callback: (Params...) -> (), ...: BoundArgs...): Connection<Params...>
	local self: Connection<Params...> = setmetatable({}, Connection)

	self.Event = event
	self.BoundArgs = { ... }
	self.BoundArgs = if #self.BoundArgs ~= 0 then self.BoundArgs else nil
	self.Callback = callback
	self.Connected = true

	self._prev = nil
	self._next = event._head

	if event._head then
		event._head._prev = self
	end

	event._head = self

	return self
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end

	self.Connected = false

	local prev = self._prev
	local next = self._next

	if prev then
		prev._next = next
	else
		self.Event._head = next
	end

	if next then
		next._prev = prev
	end

	self._prev = nil
	self._next = nil
end

function Connection:Reconnect()
	if self.Connected then
		return
	end

	self.Connected = true

	self._next = self.Event._head
	self._prev = nil

	if self.Event._head then
		self.Event._head._prev = self
	end

	self.Event._head = self
end

--[[ Event class implementation ]]
function Event.new<Params...>(): Event<Params...>
	local self: Event<Params...> = setmetatable({}, Event)

	self._head = nil

	return self
end

function Event.wrap(signal: RBXScriptSignal)
	local self = Event.new()

	signal:Connect(function(...)
		self:Fire(...)
	end)

	return self
end

function Event:Connect<Params...>(callback: (Params...) -> (), ...): Connection<Params...>
	return Connection.new(self, callback, ...)
end

function Event:Once<Params...>(callback: (Params...) -> ()): Connection<Params...>
	local connection: Connection<Params...>?

	connection = self:Connect(function(...: Params...)
		if connection then
			connection:Disconnect()
		end
		callback(...)
	end)

	return connection
end

function Event:Wait<Params...>(): Params...
	local thread = coroutine.running()
	local connection: Connection<Params...>?

	connection = self:Connect(function(...: Params...)
		connection:Disconnect()
		if coroutine.status(thread) ~= "suspended" then
			task.spawn(thread, ...)
		end
	end)

	return coroutine.yield()
end

function Event:Fire<Params...>(...: Params...)
	if self._destroyed then
		return
	end

	local current: Connection<Params...> = self._head

	while current do
		if current.Connected then
			if not current.BoundArgs then
				spawn(current.Callback, ...)
			else
				local args = current._argsPool or {}
				current._argsPool = args

				local len = #current.BoundArgs
				for i = 1, len do
					args[i] = current.BoundArgs[i]
				end

				local extraCount = len
				for i, value in ipairs({ ... }) do
					extraCount += 1
					args[extraCount] = value
				end

				task.spawn(function()
					current.Callback(table.unpack(args, 1, extraCount))
				end)

				for i = extraCount, len + 1, -1 do
					args[i] = nil
				end
			end
		end
		current = current._next
	end
end

function Event:DisconnectAll()
	local current = self._head

	while current do
		current.Connected = false
		current = current._next
	end

	self._head = nil
end

function Event:Destroy()
	self:DisconnectAll()
	if self._rbxConn then
		self._rbxConn:Disconnect()
		self._rbxConn = nil
	end
	setmetatable(self, nil)
end

return Event
