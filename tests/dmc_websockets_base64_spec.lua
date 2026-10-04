--====================================================================--
-- tests/dmc_websockets_base64_spec.lua
--
-- Testing the base64 module used by the HTML5 bridge, using Luna Test
--====================================================================--


module(..., package.seeall)




--====================================================================--
--== Test: DMC WebSockets, Base64
--====================================================================--


-- Semantic Versioning Specification: http://semver.org/

local VERSION = "0.1.0"



local Base64

local function allBytes()
	local list = {}
	for i = 0, 255 do list[ #list+1 ] = string.char( i ) end
	return table.concat( list )
end



--====================================================================--
--== Testing Setup
--====================================================================--


function suite_setup()
	require 'dmc_corona_boot'
	Base64 = require 'dmc_websockets.base64'
end



--====================================================================--
--== Tests
--====================================================================--


function test_rfc4648Vectors()
	local vectors = {
		{ '', '' }, { 'f', 'Zg==' }, { 'fo', 'Zm8=' }, { 'foo', 'Zm9v' },
		{ 'foob', 'Zm9vYg==' }, { 'fooba', 'Zm9vYmE=' }, { 'foobar', 'Zm9vYmFy' }
	}
	for _, v in ipairs( vectors ) do
		assert_equal( v[2], Base64.encode( v[1] ) )
		assert_equal( v[1], Base64.decode( v[2] ) )
	end
end

function test_everyByte()
	local bytes = allBytes()
	assert_equal( 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/w==',
		Base64.encode( bytes ) )
	assert_true( Base64.decode( Base64.encode( bytes ) ) == bytes )
end

function test_largerThanOneChunk()
	-- not a multiple of the internal chunk size, nor of 3
	local data = allBytes():rep( 50 ) .. 'xy'
	assert_true( Base64.decode( Base64.encode( data ) ) == data )
end

function test_invalidInput()
	local bad = { 'Zg', 'Zg=a', 'Zh==', 'Zm9=', '@@@@', 'Zm9v====', 'Zm 9v', '=Zm9' }
	for _, s in ipairs( bad ) do
		local data, emsg = Base64.decode( s )
		assert_nil( data, s )
		assert_string( emsg, s )
	end
end
