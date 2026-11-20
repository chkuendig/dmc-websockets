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
local raw_sockets = {}
local connect_result

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
	local raw = { closed=false, connects=0, data='' }
	raw_sockets[#raw_sockets+1] = raw
	function raw:connect()
		self.connects = self.connects + 1
		assert( not self.closed, 'resumed a closed TCP socket' )
		if connect_result then return connect_result end
		return nil, 'timeout'
	end
	function raw:send( data ) self.sent = data; return #data end
	function raw:receive() local data=self.data; self.data=''; return nil, 'timeout', data end
	function raw:settimeout() end
	function raw:setoption() end
	function raw:close() self.closed = true end
	return raw
end


local WebSocket, Sockets

local saved = {}
local loaded_before = {} -- modules loaded before this suite



--====================================================================--
--== Testing Setup
--====================================================================--


function suite_setup()
	local socket = require 'socket'
	saved.tcp = socket.tcp
	saved.select = socket.select
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
	socket.select = function() return {}, {} end
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
	Sockets = require 'dmc_sockets'
end

function suite_teardown()
	require( 'socket' ).tcp = saved.tcp
	require( 'socket' ).select = saved.select
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
	raw_sockets = {}
	connect_result = nil
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

	local raw = raw_sockets[1]
	local connects = raw.connects
	ws:close()
	assert_true( raw.closed )
	assert_equal( 1, #events )
	assert_equal( ws.ONCLOSE, events[1].type )

	-- Later frames must neither resume the TCP connect nor report an error.
	for _ = 1, 3 do
		local ok, err = pcall( frame )
		assert_true( ok, "a frame after close() raised: " .. tostring( err ) )
	end
	assert_equal( connects, raw.connects )
	assert_equal( 0, #frame_listeners, "something is still scheduled" )
	assert_equal( 1, #events, "an event came after the close" )
end


function test_closeBeforeFirstFrameCancelsTheConnect()
	local ws = WebSocket{ uri='ws://example.com/chat' }
	ws:close()
	for _=1,3 do frame() end
	assert_equal( 0, raw_sockets[1].connects )
	assert_equal( 0, #frame_listeners )
end

function test_reconnectAfterCancellingPendingConnect()
	local ws = WebSocket{ uri='ws://example.com/chat' }
	local events = {}
	ws:addEventListener( ws.EVENT, function( e ) events[#events+1] = e end )
	frame()
	local old_raw = raw_sockets[1]
	local connects = old_raw.connects
	ws:close()

	connect_result = 1
	ws:connect()
	local conn = ws._conn
	frame()
	local raw = raw_sockets[2]
	assert_not_nil( raw.sent, 'new TCP connection sent its handshake' )
	local key = raw.sent:match( 'Sec%-WebSocket%-Key: ([^\r]+)' )
	local handshake = require 'dmc_websockets.handshake'
	raw.data = 'HTTP/1.1 101 Switching Protocols\r\n'
		.. 'Upgrade: websocket\r\nConnection: Upgrade\r\n'
		.. 'Sec-WebSocket-Accept: ' .. handshake._buildServerKey( key ) .. '\r\n\r\n'
	conn._socket:_readStatus( 'ok' )
	assert_equal( ws.STATE_CONNECTED, ws:getState() )
	assert_equal( ws.ONCLOSE, events[1].type )
	assert_equal( ws.ONOPEN, events[2].type )
	assert_equal( 2, #events )
	for _=1,3 do frame() end
	assert_equal( connects, old_raw.connects, 'cancelled connect never resumes' )
	conn:close()
end

function test_refusedConnectStillReportsAnErrorOnTheFirstFrame()
	local ws = WebSocket{ uri='ws://example.com/chat' }
	local events = {}
	ws:addEventListener( ws.EVENT, function( e ) events[#events+1] = e end )
	raw_sockets[1].connect = function() return nil, 'connection refused' end
	frame()
	assert_equal( 1, #events )
	assert_equal( ws.ONERROR, events[1].type )
	assert_equal( 'connection refused', events[1].emsg )
	for _=1,3 do frame() end
	assert_equal( 1, #events )
	assert_equal( 0, #frame_listeners )
end
