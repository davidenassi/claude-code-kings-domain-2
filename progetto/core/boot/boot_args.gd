class_name BootArgs
extends RefCounted
## Parses user command-line arguments passed after "--":
##   --kd-screenshot=<path>     save a PNG of the viewport and quit
##   --kd-view=local|global     the map on the table at the start (Rebirth: the valley or the world; default local)
##   --kd-camera=x,y,mpp        initial camera position (metres of the map on the table) and zoom (metres per pixel);
##                              also settlement,mpp / home,dx,dy,mpp (offset from the player's settlement) /
##                              domain[,mpp] (the whole valley) on the local map; player[,mpp] / global[,mpp] (the
##                              homeland on the map of the world); army,mpp (the first army of the crown)
##   --kd-debug                 show the developer's box (F3) from the start
##   --kd-seed=N                the campaign seed of the new game (the same world and the same people every time)
##   --kd-frames=N              frames to wait before the screenshot (default 30)
##   --kd-build=def,dx,dy       hold the ghost of a building over (dx, dy) metres from the home fire (screenshots)
##   --kd-speed=N               initial simulation speed index
##   --kd-days=N                simulate N days instantly before rendering
##   --kd-hours=N               then N hours more, with the valley watched (the new game starts at 8 in the morning)
##   --kd-hide-debug            hide the debug overlay
##   --kd-no-events             switch the events off (clean screenshots)
##   --kd-menu                  stay on the main menu instead of entering the game
##   --kd-pause                 open the pause menu straight away
##   --kd-save-to=<path>        after the scenario is set up, save the world there (for the standard screenshots)
##   --kd-load=<path>           start from that saved world instead of a new game
##   --kd-years=N               years of the pilot in the kingdom_grown scenario (default 20)
##   --kd-scenario=stress_city  a town of --kd-people=N inhabitants (default 1500) built at once (Phase 19)
##   --kd-scenario=stress_war   every realm in arms and at war with its neighbours (Phase 19)
##   --kd-no-autosave           never write the automatic save of the year (screenshots and benchmarks never do)
##   --kd-benchmark=S           fly the camera for S seconds and print fps, draw calls and memory
##   --kd-bench-home            ... circling the player's settlement instead of crossing the continent
##   --kd-hide-layers=A,B       profiling: take those children of WorldView out of the picture


static func parse() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--kd-"):
			continue
		var body := arg.substr(5)
		var eq := body.find("=")
		if eq < 0:
			out[body] = true
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


static func camera_from(args: Dictionary) -> Dictionary:
	if not args.has("camera"):
		return {}
	var parts := String(args["camera"]).split(",")
	if parts.size() < 3:
		return {}
	return {"pos": Vector2(parts[0].to_float(), parts[1].to_float()), "mpp": parts[2].to_float()}

