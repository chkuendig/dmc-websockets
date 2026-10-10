--====================================================================--
-- tests/dmc_websockets_native_spec.lua
--
-- Testing the WebSocket class on the real dmc-sockets async socket,
-- using Luna Test. Only LuaSocket's TCP object is a stand-in, so a
-- connect can be held in progress
--====================================================================--


module(..., package.seeall)




--====================================================================--
--== Test: DMC WebSockets, native transport on dmc-sockets
--====================================================================--


-- Semantic Versioning Specification: http://semver.org/

local VERSION = "0.1.0"



--====================================================================--
--== Stand-ins
--====================================================================--


local frame_listeners = {}

-- one enterFrame
--
local function frame()
	local list = {}
	for i, l in ipairs( frame_listeners ) do list[i] = l end
	for _, l in ipairs( list ) do
		if type( l ) == 'function' then l{ name='enterFrame' } else l:enterFrame{ name='enterFrame' } end
	end
end

-- a TCP socket whose connect never finishes
--
local function pendingTcp()
	local raw = { closed=false }
	function raw:connect() return nil, 'timeout' end
	function raw:settimeout() end
	function raw:setoption() end
	function raw:close() self.closed = true end
	return raw
end


local WebSocket

local saved = {}
local loaded_before = {} -- modules loaded before this suite



--====================================================================--
--== Testing Setup
--====================================================================--


function suite_setup()
	local socket = require 'socket'
	saved.tcp = socket.tcp
	saved.Runtime = _G.Runtime
	saved.timer = _G.timer
	saved.getTimer = system.getTimer
	-- load the library afresh, on the real dmc-sockets
	for name, mod in pairs( package.loaded ) do
		loaded_before[ name ] = mod
		if name:find( 'dmc_websockets', 1, true ) or name:find( 'dmc_sockets', 1, true ) then
			package.loaded[ name ] = nil
		end
	end

	socket.tcp = pendingTcp
	system.getTimer = function() return 0 end
	_G.timer = {
		performWithDelay=function( ms, f ) return { f=f } end,
		cancel=function( t ) t.cancelled = true end
	}
	_G.Runtime = {
		addEventListener=function( self, name, l )
			if name == 'enterFrame' then table.insert( frame_listeners, l ) end
		end,
		removeEventListener=function( self, name, l )
			for i = #frame_listeners, 1, -1 do
				if frame_listeners[i] == l then table.remove( frame_listeners, i ) end
			end
		end
	}

	require 'dmc_corona_boot'
	WebSocket = require 'dmc_websockets'
end

function suite_teardown()
	require( 'socket' ).tcp = saved.tcp
	_G.Runtime = saved.Runtime
	_G.timer = saved.timer
	system.getTimer = saved.getTimer
	-- leave the modules as the other suites had them
	for name in pairs( package.loaded ) do
		if loaded_before[ name ] == nil then package.loaded[ name ] = nil end
	end
	for name, mod in pairs( loaded_before ) do package.loaded[ name ] = mod end
end

function setup()
	frame_listeners = {}
end



--====================================================================--
--== Tests
--====================================================================--


function test_closeWhileConnectingCancelsTheConnect()
	local ws = WebSocket{ uri='ws://example.com/chat' }
	local events = {}
	ws:addEventListener( ws.EVENT, function( e ) table.insert( events, e ) end )
	frame() -- the TCP connect is in progress
	assert_true( #frame_listeners > 0 )

	ws:close()
	assert_equal( 1, #events )
	assert_equal( ws.ONCLOSE, events[1].type )

	-- before, the connect resumed here and found its socket gone:
	-- async_tcp.lua:225: attempt to index field '_socket' (a nil value)
	for _ = 1, 3 do
		local ok, err = pcall( frame )
		assert_true( ok, "a frame after close() raised: " .. tostring( err ) )
	end
	assert_equal( 0, #frame_listeners, "something is still scheduled" )
	assert_equal( 1, #events, "an event came after the close" )
end
