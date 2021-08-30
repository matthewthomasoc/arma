/* Use setVelocityTransformation to move between two given points in a specified time */
_fn_initiateAttack = {
	params["_jet","_target","_index","_orientation", "_delta","_pos1","_pos2","_currTime","_dt","_key"];
	
	_dir = _jet getRelDir _target;

	if (_dir > 180) then {
		_dir = _dir - 360;
	};

	// If jet is not facing the correct direction, then set to correct direction
	if (abs _dir > 2.5 && _index != 0) then {
		_jet setDir (direction _jet + (_jet getRelDir _target));
	};

	// LI using velocity transformation, which smoothly moves vehicle
	_interval = linearConversion [_currTime, _currTime+_dt, time, 0, 1];
	_jet setVelocityTransformation [ 
		_pos1, 
		_pos2, 
		velocity _jet, 
		velocity _jet, 
		vectorDir _jet, 
		vectorDir _jet, 
		vectorUp _jet, 
		vectorUp _jet, 
		_interval
	];

	// If first node, slowly change direction towards node
	if (_index == 0) then {
		// Get starting yaw, pitch, roll
		_yaw = getDir _jet;
		_pitch = _orientation#1;
		_roll = _orientation#2;

		// Get change in yaw, pitch, roll required
		_dyaw = _jet getRelDir _target;
		_dpitch = _delta#1;
		_droll = _delta#2;

		// Change format of direction
		if (_dyaw > 180) then {
			_dyaw = _dyaw - 360;
		};

		// set exact yaw, pitch, and roll
		_y = getDir _jet + (_dyaw*_interval*.25); _p = _pitch + (_dpitch*_interval); _r = _roll + (_droll*_interval);
		_jet setVectorDirAndUp [
			[sin _y * cos _p, cos _y * cos _p, sin _p],
			[[sin _r, -sin _p, cos _r * cos _p], -_y] call BIS_fnc_rotateVector2D
		];
	};
	
	// End onEachFrame
	if (_interval >= 1) exitWith {
		_target setVariable ["finished", true];
		[_key, "onEachFrame"] call BIS_fnc_removeStackedEventHandler;
	};
};

/* Calculate jet's vectorUp using path */
_fn_calcVectorUp = {
	// Create vector from start point to end point
	_unit_vec = _pos1 vectorFromTo _pos2;
	_unit_vec = vectorNormalized _unit_vec;
	
	// Update velocity to be in the unit vector direction
	_velocity = velocity _jet;
	_velocityMag = vectorMagnitude _velocity;
	_velocityNew = _unit_vec vectorMultiply _velocityMag;
	_jet setVelocity _velocityNew;
	
	// Find angle between unit vector and horizontal
	_horizontal_vec = [_unit_vec#0, _unit_vec#1, 0];
	_horizontal_vec = vectorNormalized _horizontal_vec;
	_angle = acos(_unit_vec vectorCos _horizontal_vec);
	_vectorUpEnd = [];
	// Sometimes angle is NaN, if so skip this
	if (typeName _angle == "SCALAR") then {
		// Change the direction of rotation depending on
		// if the plane is going up or down, due to right-hand
		// rule from cross product
		_dz = (_pos2#2) - (_pos1#2);
		if (_dz < 0) then {
			// Reverse rotation direction
			_angle = _angle * -1;
		};
		// Find cross product between vector and [0,0,1]
		_cross_prod = _unit_vec vectorCrossProduct [0,0,1];
		_cross_prod = vectorNormalized _cross_prod;
		// Rotate [0,0,1] by angle to horizontal using cross product as rotation axis
		_vertical = [0,0,1];
		_vectorUpEnd = [_vertical, _cross_prod, _angle] call _fn_rotateVector;
		
		// Set jet to new vectorUp
		_jet setVectorUp _vectorUpEnd;
	} else {
		// If angle is NaN, keep current vectorUp
		_vectorUpEnd = vectorUp _jet;
	};
	
	_vectorUpEnd
};

/* Create attack profile path */
_fn_createPath = {
	// from target, draw line in direction of plane w/ z-axis angle of attack to start altitude
	_vector = (getPosASL _target) vectorFromTo (getPosASL _jet);
	_unit = vectorNormalized _vector;
	_unit_attack = vectorNormalized [_unit#0, _unit#1, sin(_angleOfAttack)];

	// get start and end points of attack run
	_attack_start = _startHeight / (_unit_attack#2);
	_attack_start = (_unit_attack vectorMultiply _attack_start) vectorAdd (getPosASL _target);
	_attack_end = _endHeight / (_unit_attack#2);
	_attack_end = (_unit_attack vectorMultiply _attack_end) vectorAdd (getPosASL _target);

	// Find dx, dy, dz per point
	_delta = _attack_end vectorDiff _attack_start;
	_dx = (_delta#0) / (_numPoints+1);
	_dy = (_delta#1) / (_numPoints+1);
	_dz = (_delta#2) / (_numPoints+1);
	
	_path = [];
	// Add start point to path
	_path pushBack _attack_start;

	// Create _numPoints between the start and end point
	for "_i" from 1 to (_numPoints) do {
		_change = [_dx * _i, _dy * _i, _dz * _i];
		_point = _attack_start vectorAdd _change;
		_path pushBack _point;
	};

	// Add end point to path
	_path pushBack _attack_end;
	
	/* Create smooth entry into attack dive */
	// Get jet position and first point position
	_point = _path#0;
	_pos = getPosASL _jet;
	
	// Get point halfway between start and current jet position
	_vector = _point vectorDiff _pos;
	_vector = _vector vectorMultiply 0.5;
	_halfPoint = _pos vectorAdd _vector;
	
	// Get unit vector in opposite direction of dive 
	_unit_vec_slope = _path#1 vectorFromTo _path#0;
	
	// Get unit vector towards halfway point
	_unit_vec_half = _path#0 vectorFromTo _halfPoint;
	
	// Find the angle between the two unit vectors
	_angle = acos(_unit_vec_half vectorCos _unit_vec_slope);

	// Multiply angle by .75 to make the arc end above the half point
	_angle = _angle * .75;
	
	// Now, we take the cross product to get a perpendicular vector
	_crossproduct = _unit_vec_half vectorCrossProduct _unit_vec_slope;
	_crossproduct = vectorNormalized _crossproduct;

	// Rotate _unit_vec_slope around _crossproduct towards _unit_vec_half, and
	// multiply it by an increasing distance to get a smooth curve
	_numPts = 200;
	_array = [];
	_distance = _halfPoint vectorDistance _point;
	for "_i" from 1 to _numPts do {
		_rotatedUnit = [_unit_vec_slope, _crossproduct, -1*_angle*(_i / _numPts)] call _fn_rotateVector;
		_vector = _rotatedUnit vectorMultiply (_distance * (_i / _numPts));
		_newPoint = _point vectorAdd _vector;
		_array pushback _newPoint;
	};
	
	// Reverse array since it's backwards
	reverse _array;

	{ // Add dive path to smooth curve
		_array pushBack _x;
	} forEach _path;

	// Update path array
	_path = _array;

	// Create smooth arc from dive entry to jet position
	// Get unit vector in opposite direction of dive 
	_unit_vec_slope = _path#1 vectorFromTo _path#0;
	
	// Get unit vector towards jet
	_unit_vec_jet = _path#0 vectorFromTo _pos;

	// Get angle between two unit vectors
	// Find the angle between the two unit vectors
	_angle = acos(_unit_vec_jet vectorCos _unit_vec_slope);

	// Now, we take the cross product to get a perpendicular vector
	_crossproduct = _unit_vec_jet vectorCrossProduct _unit_vec_slope;
	_crossproduct = vectorNormalized _crossproduct;

	// Rotate _unit_vec_slope around _crossproduct towards _unit_vec_jet, and
	// multiply it by an increasing distance to get a smooth curve
	_numPts = 200;
	_array = [];
	_distance = _pos vectorDistance _path#0;
	_distance = _distance * .9;
	for "_i" from 1 to _numPts do {
		_rotatedUnit = [_unit_vec_slope, _crossproduct, -1*_angle*(_i / _numPts)] call _fn_rotateVector;
		_vector = _rotatedUnit vectorMultiply (_distance * (_i / _numPts));
		_newPoint = _path#0 vectorAdd _vector;
		_array pushback _newPoint;
	};

	// Reverse array since it's backwards
	reverse _array;

	{ // Add approach path to smooth curve
		_array pushBack _x;
	} forEach _path;

	_array
};

/* Rotate one vector around a unit vector axis, using Rodrigues Formula */
_fn_rotateVector = {
	params["_vector","_axis","_theta"];
	
	// using Rodrigues formula
	_result = _vector vectorMultiply cos(_theta);
	_temp = (_axis vectorCrossProduct _vector) vectorMultiply sin(_theta);
	_result = _result vectorAdd _temp;
	_temp = _vector vectorMultiply (_vector vectorDotProduct _axis);
	_temp = _temp vectorMultiply (1 - cos(_theta));
	_result = _result vectorAdd _temp;
	
	_result
};

/* Calculate amount of error in target position due to enviroment */
_environmentVisiblity = {
	_maxError = 150;
	_fogParams = fogParams;
	_fogLevel = _fogParams#0;
	_fogBase = _fogParams#2;
	_rainLevel = rain; // Rain level
	_lightLevel = 1 - sunOrMoon; // Light level

	// If pilot has NVG, reduce light penalty
	_lightWeight = 1;
	if !(hmd _jetD isEqualTo "") then {
		_lightWeight = .25;
	};

	// Check if target is above the fog base
	_pos = getPosASL _target;
	_fogWeight = 1;
	if (_pos#2 > _fogBase) then {
		_fogWeight = .5;
	};


	_errorWeight = _fogLevel * _fogWeight + .5 * _rainLevel + _lightLevel * _lightWeight;
	if (_errorWeight > 1) then {
		_errorWeight = 1;
	};
	_error = _maxError * _errorWeight;

	_error
};


/* Main body for setting up strafe run (more info)
for some reason, CUP jets don't work
they freak out on the attack run and jitter everywhere
they also lose direction sometimes and go sideways
RHS and vanilla work fine */
_fn_strafe = {
	params ["_target", "_jet"];
	systemChat str "strafe called";
	_targetError = call _environmentVisiblity;

	// add slight randomness to target location due to weather
	_targetPosErrored = getPosATL _target vectorAdd [(random 2*_targetError) - _targetError, (random 2*_targetError) - _targetError, 0];
	_target setPosATL _targetPosErrored;
	
	// define properties of attack profile
	// default profile, used if bombs and rockets are out
	_requiredDistanceAway = 5000; // required distance away to start attack
	_weapon = _gun;
	_flyInHeight = 600; // cruising altitude
	_angleOfAttack = 25; // degrees
	_startHeight = 550; // meters
	_endHeight = 350; // meters
	_numPoints = 20; // number of points on the path where the jet shoots
	
	_rand = floor random 10;
	// if using bombs instead (60% chance), change attack profile
	if( (_rand < 6 || _jet ammo _rockets == 0) && _jet ammo _bombs != 0) then {
		_weapon = _bombs;
		_flyInHeight = 600; // cruising altitude
		_angleOfAttack = 80; // degrees
		_startHeight = 800; // meters
		_endHeight = 600; // meters
		_numPoints = 2; // number of points on the path where the jet shoots
	};
	// if using rockets instead (40% chance), change attack profile
	if( (_rand >= 6 || _jet ammo _bombs == 0) && _jet ammo _rockets != 0) then {
		_weapon = _rockets;
		_flyInHeight = 600; // cruising altitude
		_angleOfAttack = 25; // degrees
		_startHeight = 550; // meters
		_endHeight = 350; // meters
		_numPoints = 20; // number of points on the path where the jet shoots
	};
	
	// Cruising altitude
	_jet flyInheight _flyInHeight;
	
	// If too close to the target, fly away far 
	if (_jet distance _target < _requiredDistanceAway) then {
		systemChat str "too close";
		_jet move (_jet getRelPos [_requiredDistanceAway*1.5, 0]);
		waitUntil {_jet distance _target > _requiredDistanceAway*1.25};
	};
	
	// Re-approach the target from far away
	_jet move (getPos _target);
	systemChat str "coming back";
	while {_jet distance _target > _requiredDistanceAway*.85} do {
		_jet move (getPos _target);
		sleep 1.5;
	};

	// Create strafing path
	_path = call _fn_createPath;

	// Save current orientation of plane (for first node)
	// _orientation = [yaw, pitch, roll]
	// Calculate yaw
	_yaw = getDir _jet;
	// Calculate pitch/roll
	_pitchRoll = _jet call BIS_fnc_getPitchBank;
	_pitch = _pitchRoll#0;
	_roll = _pitchRoll#1;

	// Save orientation in array
	_orientation = [_yaw, _pitch, _roll];

	/* Calculate required change in pitch, roll, and yaw for first node */
	// Get required change in pitch
	// Unit vector from jet to next point
	_unit = _path#0 vectorFromTo _path#1;
	// Unit vector in same direction, but horizontal
	_horiz = _unit;
	_horiz set [2,0];
	// Angle between both vectors
	_angleFromHorizontal = acos(_unit vectorCos _horiz);
	// Determine sign of angle
	if (_unit#2 < 0) then {
		_angleFromHorizontal = _angleFromHorizontal * -1;
	};
	// Calculate dpitch
	_dpitch = _angleFromHorizontal - _pitch;

	// Get direction to target from jet
	_dyaw = _jet getRelDir _target;
	// Change format of direction
	if (_dyaw > 180) then {
		_dyaw = _dyaw - 360;
	};

	// Set delta roll so plane has zero roll
	_droll = -1 * _roll;

	_delta = [_dyaw, _dpitch, _droll];

	_minSpeed = 130; // m/s
	_v = vectorMagnitude (velocity _jet);

	// Change speed of not above minimum
	if (_v < _minSpeed) then {
		_v = _minSpeed;
	};

	systemChat str "starting attack";
	{
		// Get positions and start orientation
		_pos1 = getPosASL _jet;
		_pos2 = _x;
		_vectorUpStart = vectorUp _jet;

		// Set velocity
		_unit = _pos1 vectorFromTo _pos2;
		_jet setVelocity (_unit vectorMultiply _v);
		
		// Get end orientation
		_vectorUpEnd = call _fn_calcVectorUp;
		
		// Find required delta time for smooth movement
		_distance = _pos1 distance _pos2;

		// Calculate dt between points
		_dt = _distance / _v;
		
		// Fire weapon, if during strafe
		if ((_forEachIndex) > ((count _path - 1) - _numPoints)) then {
			[_jet, _weapon] call BIS_fnc_fire;
		};

		// Save current time
		_currTime = time;

		// Save current index
		_index = _forEachIndex;

		// call event handler to move to current point
		_key = "strafeHandler";
		_target setVariable ["finished", false]; // set variable to know when EH is finished with execution
		_handler = [_key, "onEachFrame", {[_this#0, _this#1, _this#2, _this#3, _this#4, _this#5, _this#6, _this#7, _this#8, _this#9] call _this#10},[_jet,_target,_index,_orientation,_delta,_pos1,_pos2,_currTime,_dt,_key,_fn_initiateAttack]] call BIS_fnc_addStackedEventHandler;
		
		// Wait until event handler ends before moving on to the next point
		waitUntil { _target getVariable "finished" };
	} forEach _path;
	
	// Fly away from target
	_jet move (_jet getRelPos [_requiredDistanceAway, 0]);

	// Flare twice plus 2 random chances
	for "_i" from 0 to ((floor random 3) + 2) do {
		[_jet, _CM] call BIS_fnc_fire;
		sleep 3;
	};
};

/* Patrol around map (more info)
randomly generate waypoints from
a given center position, using 
random directions and distances */
_fn_patrol = {
	params["_origin","_jet"];
	_cruiseAltitude = 1000; // patrol altitude
	
	// Cruise at altitude
	_jet flyInHeight _cruiseAltitude;
	
	// Generate theta and distance
	_theta = floor random 361;
	_distance = floor random ((_origin#0)+1);
	
	// Get direction unit vector
	_direction = [cos(_theta), sin(_theta), 0];
	
	// Calculate waypoint location
	_waypoint = _direction vectorMultiply _distance;
	_waypoint = _waypoint vectorAdd _center;
	_waypoint = _waypoint vectorAdd [0,0,getPosATL _jet#2];
	
	// Move to waypoint
	_jet move _waypoint;
	
	_startTime = time;
	_maxTime = 120;
	// Wait until the jet makes it, a strafe is requested, or dead
	waitUntil {_jet distance _waypoint < _waypointCompletionRadius || jetStrafeRequested == true || !alive _jet || ((time - _startTime) > _maxTime)};
	
	// Delete all waypoints
	private _group = group _jet;
	for "_i" from count waypoints _group - 1 to 0 step -1 do
	{
		deleteWaypoint [_group, _i];
	};
};

/* Make jet taxi from one node to another, needs some refining */
_fn_taxi = {
	params["_jet","_node","_startTime","_startDir","_startPos","_endPos","_dt","_vector","_angle","_key"];
	// Interval from 0-1
	_interval = linearConversion [_startTime, _startTime+_dt, time, 0, 1];
	_startPos = _startPos vectorAdd [0,0,.002];
	_jet setVelocityTransformation [ 
		ATLtoASL _startPos, 
		ATLtoASl (_startPos vectorAdd _vector), 
		velocity _jet, 
		velocity _jet, 
		vectorDir _jet, 
		vectorDir _jet, 
		vectorUp _jet, 
		vectorUp _jet, 
		_interval
	];
	
	// Change in orientation
	_dtheta = (_angle * _interval);
	
	// Update velocity to be at 5 m/s
	//_jet setVelocity (_jetUnit vectorMultiply 5);
	
	// Update orientation
	_y = _startDir + _dtheta; _p = 4.8; _r = 0; 
	_jet setVectorDirAndUp [ 
		[sin _y * cos _p, cos _y * cos _p, sin _p], 
		[[sin _r, -sin _p, cos _r * cos _p], -_y] call BIS_fnc_rotateVector2D 
	];

	if(_interval >= 1 || !alive _jet || !alive driver _jet) then {
		_node setVariable ["finished", true];
		[_key, "onEachFrame"] call BIS_fnc_removeStackedEventHandler;
	};
};

/* Make jet land, taxi to repair station, then rearm/repair/refuel */
_fn_land = {
	
	// Tell jet to move near the airport, specified location
	while {_jet distance landingApproach > 2500} do {
		_jet move getPos landingApproach;
		sleep 1.5;
	};

	// land
	_jet landAt _airportID;
	
	// wait until landed
	waitUntil {isTouchingGround _jet};
	
	sleep 6;
	
	// taxi velocity
	_velocityJ = 5;

	// disable jet AI
	_jetD disableAI "all";
	_jet disableAI "all";
	
	// Preset height for jet on the runway
	_presetZ = 0.1;
	{
		_node = _x;
		
		// save initial state
		_startDir = direction _jet;
		_startPos = getPosATL _jet;
		_startPos set [2, _presetZ];
		_endPos = getPosATL _node;
		_endPos set [2, _startPos#2];

		// calculate time to get to next node
		_distance = _startPos distance _endPos;
		_dt = _distance / _velocityJ;

		// calculate needed angle change
		// Calculate change in orientation at next point
		_angle = _jet getRelDir (getPos _node);
		
		// change to negative if past 180 degrees
		if (_angle > 180) then {
			_angle = _angle - 360;
		};

		// Vector from jet pos to node pos
		_vector = _endPos vectorDiff _startPos;
		
		// Move to next point
		_startTime = time;
		_node setVariable ["finished", false]; // set variable to know when EH is finished with execution
		_key = "taxiHandler";
		_handler = [_key, "onEachFrame", {[_this#0, _this#1, _this#2, _this#3, _this#4, _this#5, _this#6, _this#7, _this#8,_this#9] call _this#10},[_jet,_node,_startTime,_startDir,_startPos,_endPos,_dt,_vector,_angle, _key, _fn_taxi]] call BIS_fnc_addStackedEventHandler;
		
		// Wait until event handler ends before moving on to the next point
		waitUntil { _node getVariable "finished"};
	} forEach _taxiNodes;
	
	// enable AI again
	_jetD enableAI "all";

	// disable jet attacking AI
	_jet disableAI "TARGET";
	_jet disableAI "AUTOCOMBAT";

	// force jet to stop
	_jet engineOn false;
	_jet setFuel 0;
	
	sleep 3;

	// make pilot get out and stay still
	_jetD setBehaviour "SAFE";
	_jetD setSpeedMode "LIMITED";
	[_jetD] orderGetIn false;
	doGetOut [_jetD];
	moveOut _jetD;
	
	waitUntil {count (crew _jet) == 0};
	
	_waitPos = getPosASL pilotWait;
	_wp = group _jetD addWaypoint [_waitPos, -1];
	_wp setWaypointSpeed "LIMITED";
	_wp setWaypointCombatMode "SAFE";
	_wp setWaypointType "HOLD";
	_wp setWaypointStatements ["true", "_jetD lookAt _jet; _jetD disableAI 'PATH'"];
	
	_interval = 0;
	_startRepairTime = time;
	_repairNeeded = damage _jet;
	
	// while jet is alive, pilot is alive, and nobody has entered the jet, repair, rearm, and refuel
	while {_interval < 1 && alive _jetD && alive _jet && (count (crew _jet)) == 0} do {
		// Range 0-1 from time to time + repair time
		_interval = linearConversion [_startRepairTime, _startRepairTime+_repairRefuelTime, time, 0, 1];
		
		// refuel jet
		_jet setFuel _interval;
		
		// rearm jet
		_jet setVehicleAmmo _interval;
		
		// repair jet
		_jet setDamage (_repairNeeded * (1 - _interval));
		
	};
	
	// once done, pilot get back into vehicle
	_jetD enableAI "PATH";
	[_jetD] orderGetIn true;
	
	// Wait until in jet
	waitUntil {(count (crew _jet)) != 0};
	
	// Wait, to represent setting up the aircraft for takeoff
	sleep 15;
	
	// turn on engine and tell jet to move to close cockpit
	_jet engineOn true;
	_jet move [0,0,0];
	sleep 5;
	
	// Force jet to move forward on the taxiway and takeoff, since he doesn't want to move by himself
	// when anything is nearby
	
	_node = taxiTakeoffNode;
	
	// save initial state
	_startDir = direction _jet;
	_startPos = getPosATL _jet;
	_endPos = getPosATL _node;
	_endPos set [2, _startPos#2];

	// calculate time to get to next node
	_distance = _startPos distance _endPos;
	_dt = _distance / _velocityJ;

	// calculate needed angle change
	// Calculate change in orientation at next point
	_angle = _jet getRelDir (getPos _node);
	
	// change to negative if past 180 degrees
	if (_angle > 180) then {
		_angle = _angle - 360;
	};

	// Vector from jet pos to node pos
	_vector = _endPos vectorDiff _startPos;
	
	// Move to next point
	_startTime = time;
	_node setVariable ["finished", false]; // set variable to know when EH is finished with execution
	_key = "taxiHandler";
	_handler = [_key, "onEachFrame", {[_this#0, _this#1, _this#2, _this#3, _this#4, _this#5, _this#6, _this#7, _this#8,_this#9] call _this#10},[_jet,_node,_startTime,_startDir,_startPos,_endPos,_dt,_vector,_angle, _key, _fn_taxi]] call BIS_fnc_addStackedEventHandler;
	
	waitUntil {_node getVariable "finished"}
};

/* Update landing decision weight (more info)
Decided by ammo count, fuel left, and aircraft damage */
_fn_updateLandDecisionWeight = {
	// reset to zero
	_landDecisionWeight = 0;
	
	// find amount of used fuel and ammo
	_fuelGone = 1 - fuel _jet;
	_bombsGone = _bombAmmo - (_jet ammo _bombs);
	_rocketsGone = _rocketAmmo - (_jet ammo _rockets);
	
	// calculate fuel and ammo weight
	_ammoWeight = ((_bombsGone / _bombAmmo) + (_rocketsGone / _rocketAmmo)) / 2;
	
	// refuel needed every 15 minutes
	_fuelWeight = _fuelGone * 2.5;
	
	// calculate weight from damage
	_damageWeight = (damage _jet) * 4;
	
	// calculate total weight
	_landDecisionWeight = _ammoWeight + _fuelWeight + _damageWeight;
};

/* Initialize variables and setup script */
_fn_initialize = {
	// save taxi path to array
	_numTaxiNodes = 30;
	_taxiNodes = [];
	for "_i" from 1 to _numTaxiNodes do {
		_var = "taxi_" + str _i;
		
		_node = missionNamespace getVariable [_var , objNull]; //Get the object variable
		_taxiNodes pushBack _node;
	};
	
	// disable jet attacking AI
	_jet disableAI "TARGET";
	_jet disableAi "AUTOCOMBAT";
};

// initialize variables
_jet = _this;
_jetD = driver _jet;
_jetD assignAsDriver _jet;
_repairPoint = repairPoint;
_airportID = 0; // northwest airfield, chernarus
_landDecisionWeight = 0;
_taxiNodes = [];
_mapRadius = worldSize / 2;
_center = [_mapRadius, _mapRadius, 0];
_waypointCompletionRadius = 2500;
_repairRefuelTime = 30; // 180 seconds

// jet weapon names
_rockets = "rhs_weap_s5m1";
_bombs = "rhs_weap_rbk250_ptab25";
_gun = "rhs_weap_gsh302";
_CM = "rhs_weap_CMDispenser_ASO2";

// rocket and bomb ammo
_rocketAmmo = _jet ammo _rockets;
_bombAmmo = _jet ammo _bombs;

// initialize strafe globals
jetStrafeTarget = [0,0,0];
jetStrafeRequested = false;

// create target
_target = "Land_HelipadEmpty_F" createVehicle jetStrafeTarget;

call _fn_initialize;
while {alive _jet} do {
	// update landing decision weight
	call _fn_updateLandDecisionWeight;
	call _environmentVisiblity;

	_jet disableAI "AUTOCOMBAT";
	_jet disableAI "AUTOTARGET";
	_jet disableAI "CHECKVISIBLE";
	_jet disableAI "TARGET";
	_jet disableAI "WEAPONAIM";
	
	// if a strafe is requested
	if jetStrafeRequested then {
		_target setPosATL jetStrafeTarget;
		[_target, _jet] call _fn_strafe;
		jetStrafeRequested = false;
	};
	// if needs to land
	if (_landDecisionWeight >= 1) then {
		call _fn_land;
	} else { // if else, patrol
		[_center, _jet] call _fn_patrol;
	};
};