local function deepEqual(a: any, b: any, visited: { [table]: table }?): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= typeof(b) then
		return false
	end
	if typeof(a) ~= "table" then
		return false -- At this point a ~= b and both share the same non-table type
	end

	visited = visited or {}

	local mapped = visited[a]
	if mapped ~= nil then
		return mapped == b
	end

	visited[a] = b

	for key, value in a do
		if not deepEqual(value, b[key], visited) then
			return false
		end
	end

	for key in b do
		if a[key] == nil then
			return false -- Extra key found in b (a's keys were already validated)
		end
	end

	return true
end

return deepEqual
