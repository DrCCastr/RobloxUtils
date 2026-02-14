local TestUtils = {}

local function formatOutput(sectionName: string, what: string, success: boolean, result: string)
	local symbol = success and "✅" or "❌"
	return `[{symbol} {sectionName} - {what}] {result}`
end

local function newTestEnv()
	local env = {}

	function env.expect(value, label)
		label = label or "Value"
		local obj = {}

		function obj.toBe(expected)
			if value ~= expected then
				error(`{label}: expected {tostring(expected)}, got {tostring(value)}`, 2)
			end
		end

		function obj.toBeTruthy()
			if not value then
				error(`{label}: expected truthy value, got {tostring(value)}`, 2)
			end
		end

		function obj.toBeFalsy()
			if value then
				error(`{label}: expected falsy value, got {tostring(value)}`, 2)
			end
		end

		function obj.toEqual(expected)
			local function deepEqual(a, b)
				if typeof(a) ~= typeof(b) then
					return false
				end
				if typeof(a) ~= "table" then
					return a == b
				end
				for k, v in pairs(a) do
					if not deepEqual(v, b[k]) then
						return false
					end
				end
				for k, v in pairs(b) do
					if a[k] == nil then
						return false
					end
				end
				return true
			end
			if not deepEqual(value, expected) then
				error(`{label}: expected tables to be equal, got {tostring(value)} vs {tostring(expected)}`, 2)
			end
		end

		return obj
	end

	return env
end

function TestUtils.newSuite(sectionName: string)
	local suite = {}
	suite._tests = {}
	suite._beforeEach = nil
	suite._afterEach = nil

	function suite:test(what: string, fn: (env: any) -> ())
		table.insert(suite._tests, { what = what, test = fn })
	end

	function suite:beforeEach(fn)
		self._beforeEach = fn
	end

	function suite:afterEach(fn)
		self._afterEach = fn
	end

	function suite:suite(subName: string, fn: (subSuite: any) -> ())
		local sub = TestUtils.newSuite(sectionName .. " > " .. subName)
		fn(sub)
		table.insert(suite._tests, {
			what = "(suite)",
			test = function()
				sub:run()
			end,
		})
	end

	function suite:run()
		for _, t in suite._tests do
			local env = newTestEnv()
			local success, result

			if self._beforeEach then
				success, result = pcall(self._beforeEach, env)
				if not success then
					warn(formatOutput(sectionName, t.what, false, `beforeEach hook failed: {result}`))
					continue
				end
			end

			success, result = pcall(t.test, env)
			if not success then
				warn(formatOutput(sectionName, t.what, false, result))
			else
				print(formatOutput(sectionName, t.what, true, "Passed"))
			end

			if self._afterEach then
				pcall(self._afterEach, env)
			end
		end
	end

	return suite
end

function TestUtils.runTestScript(script: ModuleScript)
	local compiled = require(script)
	task.spawn(compiled, TestUtils.newSuite(script:GetFullName()))
end

function TestUtils.runTestScriptFolder(folder: Folder)
	for _, child in folder:GetDescendants() do
		if not child.Name:find(".test") then
			continue
		end
		TestUtils.runTestScript(child)
	end
end

return TestUtils
