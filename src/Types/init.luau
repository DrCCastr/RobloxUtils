local T = {
	string = nil :: string,
	number = nil :: number,
	boolean = nil :: boolean,
	any = nil :: any,
}

function T.array<Type>(t: Type): { Type }
	return nil :: any
end

function T.map<Key, Value>(k: Key, v: Value): { [Key]: Value }
	return nil :: any
end

function T.optional<Type>(t: Type): Type?
	return nil :: any
end

function T.identity<Type>(t: Type): Type
	return nil :: any
end

return T
