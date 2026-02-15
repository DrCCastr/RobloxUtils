local DeepUtils = {}

function DeepUtils.Equals(a: any, b: any, visited: { [table]: { [table]: true } }?): boolean
	if a == b then
		return true
	end

	local typeA = typeof(a)
	if typeA ~= typeof(b) then
		return false
	end

	if typeA ~= "table" then
		-- At this point a ~= b and both share the same non-table type, impossible to be equal
		return false
	end

	visited = visited or {}

	if visited[a] and visited[a][b] then
		return true
	end

	visited[a] = visited[a] or {}
	visited[a][b] = true

	for key, value in pairs(a) do
		if not DeepUtils.Equals(value, b[key], visited) then
			return false
		end
	end

	for key in pairs(b) do
		if a[key] == nil then
			-- Extra key found in b (a's keys were already validated)
			return false
		end
	end

	return true
end

return DeepUtils
