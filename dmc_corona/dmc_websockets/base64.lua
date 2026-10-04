--====================================================================--
-- dmc_corona/dmc_websockets/base64.lua
--
-- Documentation: https://github.com/dmccuskey/dmc-websockets
--====================================================================--

--[[

The MIT License (MIT)

Copyright (C) 2014-2015 David McCuskey. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]]



--====================================================================--
--== DMC Corona Library : DMC WebSockets Base64
--====================================================================--


--[[

Base64 (RFC 4648, standard alphabet, padded, no line breaks) in plain
Lua, for binary messages crossing the HTML5 bridge.

LuaSocket's mime.b64 isn't available in HTML5 builds, and plain Lua has
no bit operations, so this uses arithmetic. Decoding is strict: any
character outside the alphabet, or misplaced padding, is an error.

--]]


-- Semantic Versioning Specification: http://semver.org/

local VERSION = "1.0.0"



--====================================================================--
--== Setup, Constants


local mfloor = math.floor
local sbyte = string.byte
local schar = string.char
local tconcat = table.concat

local ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local PAD = sbyte( '=' )

-- groups encoded or decoded before joining, so a large message
-- isn't one table entry per group
local CHUNK = 3 * 1024

local ENC = {} -- 6-bit value -> character
local ENC2 = {} -- 12-bit value -> two characters
local DEC = {} -- character byte -> 6-bit value

for i = 1, 64 do
	local c = ALPHABET:sub( i, i )
	ENC[ i-1 ] = c
	DEC[ sbyte( c ) ] = i-1
end
for i = 0, 4095 do
	ENC2[ i ] = ENC[ mfloor( i/64 ) ] .. ENC[ i%64 ]
end



--====================================================================--
--== Support Functions


local function encode( str )
	local len = #str
	local full = len - len%3
	local out, parts = {}, {}

	for s = 1, full, CHUNK do
		local e = s + CHUNK - 1
		if e > full then e = full end
		local n = 0
		for i = s, e, 3 do
			local a, b, c = sbyte( str, i, i+2 )
			local v = a*65536 + b*256 + c
			n = n + 1
			parts[ n ] = ENC2[ mfloor( v/4096 ) ] .. ENC2[ v%4096 ]
		end
		out[ #out+1 ] = tconcat( parts, '', 1, n )
	end

	local rest = len - full
	if rest == 1 then
		local v = sbyte( str, len ) * 16
		out[ #out+1 ] = ENC2[ v ] .. '=='
	elseif rest == 2 then
		local a, b = sbyte( str, len-1, len )
		local v = ( a*256 + b ) * 4
		out[ #out+1 ] = ENC2[ mfloor( v/64 ) ] .. ENC[ v%64 ] .. '='
	end

	return tconcat( out )
end


-- returns the decoded string, or nil and a message
--
local function decode( str )
	local len = #str
	if len % 4 ~= 0 then return nil, "base64 length is not a multiple of 4" end
	if len == 0 then return '' end

	-- the last group may be padded
	local pad = 0
	if sbyte( str, len ) == PAD then
		pad = sbyte( str, len-1 ) == PAD and 2 or 1
	end
	local full = len - ( pad > 0 and 4 or 0 )

	local out, parts = {}, {}
	local step = CHUNK / 3 * 4

	for s = 1, full, step do
		local e = s + step - 1
		if e > full then e = full end
		local n = 0
		for i = s, e, 4 do
			local a, b, c, d = sbyte( str, i, i+3 )
			a, b, c, d = DEC[a], DEC[b], DEC[c], DEC[d]
			if not ( a and b and c and d ) then
				return nil, "invalid base64 character"
			end
			local v = a*262144 + b*4096 + c*64 + d
			n = n + 1
			parts[ n ] = schar( mfloor( v/65536 ), mfloor( v/256 )%256, v%256 )
		end
		out[ #out+1 ] = tconcat( parts, '', 1, n )
	end

	if pad > 0 then
		local a, b, c = sbyte( str, len-3, len-1 )
		a, b = DEC[a], DEC[b]
		if not ( a and b ) then return nil, "invalid base64 character" end
		if pad == 2 then
			if b%16 ~= 0 then return nil, "invalid base64 padding" end
			out[ #out+1 ] = schar( a*4 + mfloor( b/16 ) )
		else
			c = DEC[c]
			if not c then return nil, "invalid base64 character" end
			if c%4 ~= 0 then return nil, "invalid base64 padding" end
			local v = a*4096 + b*64 + c
			out[ #out+1 ] = schar( mfloor( v/1024 ), mfloor( v/4 )%256 )
		end
	end

	return tconcat( out )
end



--====================================================================--
--== Module Facade
--====================================================================--


return {
	VERSION = VERSION,
	encode = encode,
	decode = decode
}
