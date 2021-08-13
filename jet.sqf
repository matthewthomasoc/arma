/* Use setVelocityTransformation to move between two given points in a specified time */
fn_initiateAttack = {
	params["_jet","_target","_pos1","_pos2","_currTime","_dt","_LIpoints","_key"];
	
	
	// LI using velocity transformation, which smoothly moves vehicle
	_interval = linearConversion [_currTime, _currTime+_dt, time, 0, _LIpoints];
	_jet setVelocityTransformation [ 
		_pos1, 
		_pos2, 
		velocity _jet, 
		velocity _jet, 
		vectorDir _jet, 
		vectorDir _jet, 
		vectorUp _jet, 
		vectorUp _jet, 
		_interval/_LIpoints
	];
	
	// End onEachFrame
	if (_interval > _LIpoints) exitWith {
		_target setVariable ["finished", true];
		[_key, "onEachFrame"] call BIS_fnc_removeStackedEventHandler;
	};
};

/* Calculate jet's vectorUp using path */
fn_calcVectorUp = {
	// Create vector from start point to end point
	_unit_vec = _pos1 vectorFromTo _pos2;
	_unit_vec = vectorNormalized _unit_vec;
	
	// Update velocity to be in the unit vector direction
	_velocity = velocity _jet;
	_velocityMag = vectorMagnitude _velocity;
	_velocityNew = _unit_vec vectorMultiply _velocityMag;
	_jet setVelocity _velocityNew;
	
	// Find angle between unit vector and horizontal
	_horizontal_vec = [_unit_vec select 0, _unit_vec select 1, 0];
	_horizontal_vec = vectorNormalized _horizontal_vec;
	_angle = acos(_unit_vec vectorCos _horizontal_vec);
	_vectorUpEnd = [];
	// Sometimes angle is NaN, if so skip this
	if (typeName _angle == "SCALAR") then {
		// Change the direction of rotation depending on
		// if the plane is going up or down, due to right-hand
		// rule from cross product
		_dz = (_pos2 select 2) - (_pos1 select 2);
		if (_dz < 0) then {
			// Reverse rotation direction
			_angle = _angle * -1;
		};
		// Find cross product between vector and [0,0,1]
		_cross_prod = _unit_vec vectorCrossProduct [0,0,1];
		_cross_prod = vectorNormalized _cross_prod;
		// Rotate [0,0,1] by angle to horizontal using cross product as rotation axis
		_vertical = [0,0,1];
		_vectorUpEnd = [_vertical, _cross_prod, _angle] call fn_rotateVector;
		
		// Set jet to new vectorUp
		_jet setVectorUp _vectorUpEnd;
	} else {
		// If angle is NaN, keep current vectorUp
		_vectorUpEnd = vectorUp _jet;
	};
	
	_vectorUpEnd
};

/* Create attack profile path */
fn_createPath = {
	// from target, draw line in direction of plane w/ z-axis angle of attack to start altitude
	_vector = (getPosASL _target) vectorFromTo (getPosASL _jet);
	_unit = vectorNormalized _vector;
	_unit_attack = vectorNormalized [_unit select 0, _unit select 1, sin(_angleOfAttack)];

	// get start and end points of attack run
	_attack_start = _startHeight / (_unit_attack select 2);
	_attack_start = (_unit_attack vectorMultiply _attack_start) vectorAdd (getPosASL _target);
	_attack_end = _endHeight / (_unit_attack select 2);
	_attack_end = (_unit_attack vectorMultiply _attack_end) vectorAdd (getPosASL _target);

	// Find dx, dy, dz per point
	_delta = _attack_end vectorDiff _attack_start;
	_dx = (_delta select 0) / (_numPoints+1);
	_dy = (_delta select 1) / (_numPoints+1);
	_dz = (_delta select 2) / (_numPoints+1);
	
	_path = [];
	// Add start point to path
	_path pushBack _attack_start;

	// Create _numPoints between the start and end point
	for "_i" from 1 to (_numPoints) do {
		_change = [_dx * _i, _dy * _i, _dz * _i];
		_point = _attack_start vectorAdd _change;
		_path pushBack _point;
	};

	// Add end point to apth
	_path pushBack _attack_end;
	
	/* Create smooth entry into attack dive */
	// Get jet position and first point position
	_point = _path select 0;
	_pos = getPosASL _jet;
	
	// Get point halfway between start and current jet position
	_vector = _pos vectorFromTo _point;
	_vector = _vector vectorMultiply 0.5;
	_halfPoint = _pos vectorAdd _vector;
	
	// Get unit vector in opposite direction of dive 
	_unit_vec_slope = _path#1 vectorFromTo _path#0;
	_unit_vec_slope = vectorNormalized _unit_vec_slope;
	
	// Get unit vector towards halfway point
	_unit_vec_half = _path#0 vectorFromTo _halfPoint;
	_unit_vec_half = vectorNormalized _unit_vec_half;
	
	// Find the angle between the two unit vectors
	_angle = acos(_unit_vec_half vectorCos _unit_vec_slope);
	
	// Now, we take the cross product to get a perpendicular vector
	_crossproduct = _unit_vec_half vectorCrossProduct _unit_vec_slope;
	_crossproduct = vectorNormalized _crossproduct;

	_rotatedUnit = [_unit_vec_slope, _crossproduct, -1*_angle*(75 / 150)] call fn_rotateVector;
	// Rotate _unit_vec_slope around _crossproduct towards _unit_vec_half, and
	// multiply it by an increasing distance to get a smooth curve
	_numPts = 50;
	_array = [];
	_distance = _halfPoint vectorDistance _point;
	for "_i" from 1 to _numPts do {
		_rotatedUnit = [_unit_vec_slope, _crossproduct, -1*_angle*(_i / _numPts)] call fn_rotateVector;
		_vector = _rotatedUnit vectorMultiply (_distance * (_i / _numPts));
		_newPoint = _point vectorAdd _vector;
		_array pushback _newPoint;
	};
	
	// Reverse array since it's backwards
	reverse _array;
	
	{ // Add dive path to smooth curve
		_array pushBack _x;
	} forEach _path;
	
	_array
};

/* Rotate one vector around a unit vector axis, using Rodrigues Formula */
fn_rotateVector = {
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

/* Main body for setting up strafe run (more info)
for some reason, CUP jets don't work
they freak out on the attack run and jitter everywhere
they also lose direction sometimes and go sideways
RHS and vanilla work fine */
fn_strafe = {
	params ["_target", "_jet"];
	_targetError = 50;
	// add slight randomness to target location
	_targetPosErrored = getPosATL _target vectorAdd [(random 2*_targetError) - _targetError, (random 2*_targetError) - _targetError, 0];
	_target setPosATL _targetPosErrored;
	
	// define properties of attack profile
	_requiredDistanceAway = 5000; // required distance away to start attack
	_weapon = _gun;
	_flyInHeight = 600; // cruising altitude
	_angleOfAttack = 25; // degrees
	_startHeight = 550; // meters
	_endHeight = 350; // meters
	_numPoints = 20; // number of points on the path where the jet shoots
	
	// if using bombs instead (60% chance), change attack profile
	if( (floor random 10 < 6 && _jet ammo _bombs != 0)) then {
		_weapon = _bombs;
		_flyInHeight = 600; // cruising altitude
		_angleOfAttack = 55; // degrees
		_startHeight = 600; // meters
		_endHeight = 400; // meters
		_numPoints = 1; // number of points on the path where the jet shoots
	};
	// if using rockets instead (40% chance), change attack profile
	if( (floor random 10 >= 6 && _jet ammo _rockets != 0) || _jet ammo _bombs == 0) then {
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
		_jet move (_jet getRelPos [_requiredDistanceAway*1.5, 0]);
		waitUntil {_jet distance _target > _requiredDistanceAway*1.25};
	};
	
	// Re-approach the target from far away
	_jet move (getPos _target);
	waitUntil {_jet distance _target < _requiredDistanceAway*.85};
	
	// Create strafing path
	_path = call fn_createPath;

	// Align direction to target
	_jet setDir (_jet getDir _target);

	{
		// Get positions and start orientation
		_pos1 = getPosASL _jet;
		_pos2 = _x;
		_vectorUpStart = vectorUp _jet;
		
		// Get end orientation
		_vectorUpEnd = call fn_calcVectorUp;
		
		// Find required delta time for smooth movement
		_distance = _pos1 distance _pos2;
		_v = vectorMagnitude (velocity _jet);
		_dt = _distance / _v;
		
		// Set number of LI points
		_LIpoints = 100;
		
		// Fire weapon, if during strafe
		if ((_forEachIndex) > ((count _path - 1) - _numPoints)) then {
			[_jet, _weapon] call BIS_fnc_fire;
		};

		// Save current time
		_currTime = time;

		// call event handler to move to current point
		_key = "handler";
		_target setVariable ["finished", false]; // set variable to know when EH is finished with execution
		_handler = [_key, "onEachFrame", {[_this select 0, _this select 1, _this select 2, _this select 3, _this select 4, _this select 5, _this select 6, _this select 7] call fn_initiateAttack},[_jet,_target,_pos1,_pos2,_currTime,_dt,_LIpoints,_key]] call BIS_fnc_addStackedEventHandler;
		
		// Wait until event handler ends before moving on to the next point
		waitUntil { _target getVariable "finished" };
	} forEach _path;
	
	// Fly away from target
	_jet move (_jet getRelPos [_requiredDistanceAway, 0]);
	
	// Flare twice
	for "_i" from 0 to ((floor random 4) + 3) do {
		[_jet, _CM] call BIS_fnc_fire;
		uiSleep 3;
	};
};

/* Patrol around map (more info)
randomly generate waypoints from
a given center position, using 
random directions and distances */
fn_patrol = {
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
	_waypoint = _waypoint vectorAdd [0,0,getPosATL _jet select 2];
	
	// Move to waypoint
	_jet move _waypoint;
	
	// Wait until the jet makes it, a strafe is requested, or dead
	waitUntil {_jet distance _waypoint < _waypointCompletionRadius || jetStrafeRequested == true || !alive _jet};
	
	// Delete all waypoints
	private _group = group _jet;
	for "_i" from count waypoints _group - 1 to 0 step -1 do
	{
		deleteWaypoint [_group, _i];
	};
};

fn_land = {
	_jet landAt _airportID;
	
	waitUntil {isTouchingGround _jet};
};

fn_updateLandDecisionWeight = {
	_fuelGone = 1 - fuel _jet;
	_bombsGone = _bombAmmo - (_jet ammo _bombs);
	_rocketsGone = _rocketAmmo - (_jet ammo _rockets);
	
	_ammoWeight = ((_bombsGone / _bombAmmo) + (_rocketsGone / _rocketAmmo)) / 2;
	_fuelWeight = _fuelGone / 1;
	
	_damageWeight = (damage _jet) * 5;
	
	_landDecisionWeight = _ammoWeight + _fuelWeight + _damageWeight;
};

_jet = _this;

_mapRadius = worldSize / 2;
jetStrafeTarget = [0,0,0];
_center = [_mapRadius, _mapRadius, 0];
_waypointCompletionRadius = 1000;
_target = "Land_HelipadEmpty_F" createVehicle jetStrafeTarget;
_rockets = "rhs_weap_s5m1";
_bombs = "rhs_weap_fab250";
_gun = "rhs_weap_gsh302";
_CM = "rhs_weap_CMDispenser_ASO2";
_airportID = 0; // northwest airfield
_landDecisionWeight = 0;
_refuelLimit = 0.75;

_rocketAmmo = _jet ammo _rockets;
_bombAmmo = _jet ammo _bombs;

jetStrafeRequested = false;
_jet disableAI "TARGET";
_jet disableAi "AUTOCOMBAT";
while {alive _jet} do {
	_target setPosATL jetStrafeTarget;
	call fn_updateLandDecisionWeight;
	call fn_land;
	systemChat str [_landDecisionWeight];
	if jetStrafeRequested then {
		[_target, _jet] call fn_strafe;
		jetStrafeRequested = false;
	};
	if (_landDecisionWeight >= 1) then {
		call fn_land;
	} else {
		[_center, _jet] call fn_patrol;
	};
};