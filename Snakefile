# dmc-websockets

try:
	if not gSTARTED: print( gSTARTED )
except:
	MODULE = "dmc-websockets"
	include: "../DMC-Corona-Library/snakemake/Snakefile"

module_config = {
	"name": "dmc-websockets",
	"module": {
		"dir": "dmc_corona",
		"files": [
			"dmc_websockets.lua",
			"dmc_websockets/exception.lua",
			"dmc_websockets/frame.lua",
			"dmc_websockets/handshake.lua",
			"dmc_websockets/message.lua",
			"lib/sha1.lua"
		],
		"requires": [
			"dmc-corona-boot",
			"DMC-Lua-Library",
			"dmc-sockets",
		]
	},
	"examples": {
		"base_dir": "examples",
		"apps": [
			{
				"exp_dir": "dmc-websockets-autobahntestsuite",
				"requires": []
			},
			{
				"exp_dir": "dmc-websockets-echo",
				"requires": []
			},
			{
				"exp_dir": "dmc-websockets-pusher",
				"requires": []
			}
		]
	},
	"tests": {
		"files": [],
		"requires": []
	}
}

register( "dmc-websockets", module_config )

