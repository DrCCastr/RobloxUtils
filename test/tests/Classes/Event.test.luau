local Event = require(game:GetService("ReplicatedStorage").Utils).Classes.Event

return function(suite)
	local TIMEOUT = 1

	suite:beforeEach(function(env)
		env.event = Event.new()
	end)

	suite:afterEach(function(env)
		env.event:Destroy()
	end)

	suite:test("Connect creates a connection", function(env)
		local conn = env.event:Connect(function() end)
		env.expect(conn, "Connect should create a valid connection").toBeTruthy()
		env.expect(conn.Connected, "Connection should be active").toBe(true)
	end)

	suite:test("Fire calls connected callbacks", function(env)
		local called = false
		env.event:Connect(function(arg)
			called = arg
		end)
		env.event:Fire(true)
		local start = tick()
		repeat
			task.wait()
		until called or tick() - start > TIMEOUT
		env.expect(called, "Fire did not call the callback").toBe(true)
	end)

	suite:test("Once disconnects after first fire", function(env)
		local count = 0
		env.event:Once(function()
			count += 1
		end)
		env.event:Fire()
		env.event:Fire()
		local start = tick()
		repeat
			task.wait()
		until count == 1 or tick() - start > TIMEOUT
		env.expect(count, "Once fired more than once").toBe(1)
	end)

	suite:test("Wait yields and returns arguments", function(env)
		local result
		local done = false
		task.spawn(function()
			result = { env.event:Wait() }
			done = true
		end)
		task.delay(0.05, function()
			env.event:Fire("hello", 123)
		end)
		local start = tick()
		repeat
			task.wait()
		until done or tick() - start > TIMEOUT
		env.expect(result, "Wait did not return any arguments").toBeTruthy()
		env.expect(result[1], "Wait did not return first argument correctly").toBe("hello")
		env.expect(result[2], "Wait did not return second argument correctly").toBe(123)
	end)

	suite:test("Disconnect stops callback", function(env)
		local called = false
		local conn = env.event:Connect(function()
			called = true
		end)
		conn:Disconnect()
		env.event:Fire()
		local start = tick()
		repeat
			task.wait()
		until tick() - start > TIMEOUT
		env.expect(called, "Callback was called after disconnect").toBe(false)
	end)

	suite:test("DisconnectAll stops all callbacks", function(env)
		local called = false
		env.event:Connect(function()
			called = true
		end)
		env.event:DisconnectAll()
		env.event:Fire()
		local start = tick()
		repeat
			task.wait()
		until tick() - start > TIMEOUT
		env.expect(called, "Callbacks were called after DisconnectAll").toBe(false)
	end)

	suite:test("BoundArgs prepends arguments to callback", function(env)
		local result
		env.event:Connect(function(a, b)
			result = a + b
		end, 5)
		env.event:Fire(10)
		local start = tick()
		repeat
			task.wait()
		until result ~= nil or tick() - start > TIMEOUT
		env.expect(result, "BoundArgs not applied correctly").toBe(15)
	end)

	suite:run()
end
