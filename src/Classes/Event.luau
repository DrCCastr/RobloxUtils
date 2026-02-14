--[[
Event Class
Pure Luau bindable event alternative

This module provides a custom Event system similar to Roblox's BindableEvent,
but fully implemented in pure Luau with coroutine pooling and argument optimization.

---

Types:

Connection<Params...>
- Represents a single listener attached to an Event.
- Fields:
    Event        : The Event this connection belongs to
    BoundArgs    : Optional table of arguments bound to the callback
    Callback     : The function to call when the event fires
    Connected    : Boolean indicating if the connection is active
    Disconnect() : Disconnects this listener
    Reconnect()  : Reconnects a previously disconnected listener

Event<Params...>
- Represents a custom event that can have multiple connections.
- Methods:
    Connect(callback, ...): Creates a new Connection with optional bound arguments
    Once(callback)       : Connects a listener that will automatically disconnect after firing once
    Wait()               : Yields the current thread until the event fires, then returns event parameters
    Fire(...)            : Fires the event, calling all connected callbacks with given parameters
    DisconnectAll()      : Disconnects all listeners
    Destroy()            : Disconnects all listeners and clears internal data
- Fields:
    _rbxConn    : Optional wrapped RBXScriptConnection (if using Event.wrap)
    _head       : First Connection in the linked list of listeners
    _destroyed  : Boolean indicating if the event has been destroyed

---

Usage Examples:

-- Creating a new Event
local Event = require(path.to.Event)
local myEvent = Event.new()

-- Connecting a callback
local conn = myEvent:Connect(function(msg)
    print("Received message:", msg)
end)

-- Connecting a one-time callback
myEvent:Once(function(msg)
    print("This prints only once:", msg)
end)

-- Firing the event
myEvent:Fire("Hello World!")

-- Waiting for an event
local msg = myEvent:Wait()
print("Waited and got:", msg)

-- Disconnecting a single listener
conn:Disconnect()

-- Disconnecting all listeners
myEvent:DisconnectAll()

-- Destroying the event
myEvent:Destroy()

---

Advanced Notes:
- Bound arguments: You can pass extra arguments when connecting a callback.
- They will be prepended to the arguments passed when firing the event.
- Coroutine pooling: The module reuses coroutines for firing callbacks to reduce garbage collection.
- Event.wrap(signal): Wraps a Roblox RBXScriptSignal into this custom Event class.
]]

-- Types
export type Connection<Params...> = {
	Event: Event<Params...>,
	BoundArgs: { any },
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
	_destroyed: boolean,
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
function Connection.new<Params...>(event: Event<Params...>, callback: (Params...) -> (), ...): Connection<Params...>
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
	self._destroyed = false
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
		if coroutine.status(thread) == "suspended" then
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
