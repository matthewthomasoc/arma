/* Find most recently seen enemy */
_fn_mostRecentlySeen = {
	_targets = _heliD targetsQuery [objNull, _enemySide, "", [], _forgetEnemyTime];
	_mostRecent = objNull;
	if (count _targets == 0) exitWith {_mostRecent};
	if (count _targets == 1) then {
		_query = _targets#0;
		// Get query target
		_target = _query#1;
		// Get target knowledge on target
		_knowledge = _heliD targetKnowledge _target;
		// Get last time seen
		_lastSeen = _knowledge#2;
		// Get position
		_position = _knowledge#6;
		if (side _target == _enemySide) then {
			_mostRecent = [_lastSeen, _target, _position];
		} else {
			_mostRecent = objNull;
		};
	} else {
		// Find most recently seen target
		{
			_query = _x;
			// Get query target
			_target = _query#1;
			if (side _target != _enemySide) then {
				continue
			};
			// Get target knowledge on target
			_knowledge = _heliD targetKnowledge _target;
			// Get last time seen
			_lastSeen = _knowledge#2;
			// Get position
			_position = _knowledge#6;
			
			// find most recently seen enemy, saving
			// the time seen and index in _targets
			// if first object, save as most recent
			if (_forEachIndex == 0) then {
				_mostRecent = [_lastSeen, _forEachIndex, _position];
			} else { // else, check if more recent
				if(!(_mostRecent isEqualTo objNull)) then {
					if(_lastSeen >  _mostRecent#0) then {
						if (_lastSeen < 0) then {
							_lastSeen = time;
						};
						_mostRecent = [_lastSeen, _forEachIndex, _position];
					};
				} else {
					_mostRecent = [_lastSeen, _forEachIndex, _position];
				};
			};
		} forEach _targets;
		
		// change index to be object
		if (!(_mostRecent isEqualTo objNull)) then {
			_mostRecent = [_mostRecent#0, _targets#0 select 1, _mostRecent#2];
		};
	};
	
	// if valid target,
	if !(_mostRecent isEqualTo objNull) then {
		// If last seen is negative, set to current time
		if (_mostRecent#0 < 0) then {
			_mostRecent set [0, time];
		};
		
		// If past time limit, not a valid target
		if (time - _mostRecent#0 > _forgetEnemyTime) then {
			_mostRecent = objNull;
		};
	};
	
	_mostRecent
};

/* Delete all waypoints */
_fn_deleteAllWaypoints = {
	params["_groupSent"];

	for "_i" from count waypoints _groupSent - 1 to 0 step -1 do
	{
		deleteWaypoint [_groupSent, _i];
	};
};

/* Patrol random towns */
_fn_patrol = {
	_exitPatrol = false;
	// Delete all current waypoints
	[_group] call _fn_deleteAllWaypoints;
	
	// Get random town location
	_town = selectRandom _towns;
	_townPos = locationPosition _town;
	_townPos set [2, 0]; // remove z-height
	
	// Create move waypoint at town
	_wp = _group addWaypoint [_townPos, 0];
	_wp setWaypointType "MOVE";
	_wp setWaypointSpeed "FULL";
	
	// Fly at height
	_heli flyInHeight _flyInHeight;
	
	// Wait until heli gets near the town
	_requiredDistance = 800;
	while {_heli distance _townPos > _requiredDistance} do {
		// check for seen enemies
		_mostRecent = call _fn_mostRecentlySeen;
		
		// if enemy seen,
		if (!(_mostRecent isEqualTo objNull) || heliRequested) exitWith {
			// leave patrol and follow him
			_exitPatrol = true;
		};
	};
	
	if (_exitPatrol) exitWith {};
	
	// Delete move waypoint
	[_group] call _fn_deleteAllWaypoints;
	
	// Create loiter waypoint at town
	_wp = _group addWaypoint [_townPos, 0];
	_wp setWaypointType "LOITER";
	_wp setWaypointSpeed "LIMITED";
	_wp setWaypointLoiterAltitude 100;
	_wp setWaypointLoiterRadius 300;
	
	// Loiter for 30-90 seconds
	_loiterTime = 30 + ceil random 60;
	_startTime = time;
	while {time - _startTime < _loiterTime} do {
		// check for seen enemies
		_mostRecent = call _fn_mostRecentlySeen;
		
		// if enemy seen,
		if (!(_mostRecent isEqualTo objNull) || heliRequested) exitWith {
			// leave patrol and follow him
			_exitPatrol = true;
		};
	};
	
	if (_exitPatrol) exitWith {};
	
	// Delete loiter waypoint
	[_group] call _fn_deleteAllWaypoints;
	
	// Fly at height
	_heli flyInHeight _flyInHeight;
};

/* Land */
_fn_land = {
	// fly low
	_heli flyInHeight 100;

	// delete all waypoints
	[_group] call _fn_deleteAllWaypoints;
	
	// move to helipad
	_wp = _group addWaypoint [getPos _helipad, 0];
	_wp setWaypointPosition [getPosASL _helipad, -1];
	_wp setWaypointType "TR UNLOAD";
	_wp setWaypointSpeed "FULL";
	
	// wait until heli reaches pad
	_requiredDistance = 10;
	waitUntil {_heli distance _helipad < _requiredDistance};
	
	_heli engineOn false;
	_heli setFuel 0;
	
	// tell heli to land at helipad
	_heli land "LAND";
	
	waitUntil {isTouchingGround _heli};
	
	// delete all waypoints
	[_group] call _fn_deleteAllWaypoints;
	
	uiSleep 2;
	
	// leave helicopter
	_group leaveVehicle _heli;
	[_crew] orderGetIn false;
	doGetOut [_crew];
	moveOut _heliD;
	
	// wait until crew exits
	waitUntil {count (crew _heli) == 0};
	
	// move away from heli
	_waitPos = getPos heliWait;
	_wp = _group addWaypoint [_waitPos, -1];
	_wp setWaypointSpeed "LIMITED";
	_wp setWaypointBehaviour "SAFE";
	_wp setWaypointType "HOLD";
	
	// wait until at wait point
	waitUntil {_heliD distance _waitPos < 2};
	
	// look at heli and do animation
	_heliD doWatch _heli;
	
	// start maintenance
	_interval = 0;
	_startRepairTime = time;
	_repairNeeded = damage _heli;
	// while heli is alive, pilot is alive, and nobody has entered the heli, repair, rearm, and refuel
	while {_interval < 1 && alive _heli && alive _heliD && (count (crew _heli)) == 0 && behaviour _heliD != "COMBAT"} do {
		// Range 0-1 from time to time + repair time
		_interval = linearConversion [_startRepairTime, _startRepairTime+_repairRefuelTime, time, 0, 1];
		
		// refuel heli
		_heli setFuel _interval;
		
		// repair heli
		_heli setDamage (_repairNeeded * (1 - _interval));
	};
	
	// get in heli
	_heliD assignAsDriver _heli;
	[_crew] orderGetIn true;
	
	// Wait until in heli
	waitUntil {(count (crew _heli)) != 0};
	
	// turn on engine
	_heli engineOn true;
	uiSleep 5;
};

/* Update weight for landing decision */
_fn_updateLandDecisionWeight = {
	// reset to zero
	_landDecisionWeight = 0;
	
	// find amount of used fuel and ammo
	_fuelGone = 1 - fuel _heli;
	
	// refuel needed every 25 minutes
	_fuelWeight = _fuelGone * 10;
	
	// calculate weight from damage
	_damageWeight = (damage _heli) * 6;
	
	// calculate total weight
	_landDecisionWeight = _fuelWeight + _damageWeight;
};

/* Initialize required variables */
_fn_initialize = {
	// Get all towns on the map
	_towns = nearestLocations [[worldSize/2,worldSize/2,0], ["NameVillage","NameCity","NameCityCapital"], worldSize];
};

// heli object
_heli = _this;
_heliD = driver _heli;
_heliD assignAsDriver _heli;
_crew = crew _heli;
deleteVehicle (_crew #1);
_group = group _heli;
_helipad = helipad;

// initialize vars
_towns = []; // list of towns

// parameters
_smallLoiterTime = 180; // 3 minutes
_mediumLoiterTime = 420; // 4 minutes
_smallLoiterRadius = 25; // meters
_mediumLoiterRadius = 100; // meters
_largeLoiterRadius = 250; // meters
_forgetEnemyTime = 720; // 12 minutes
_loiterAltitude = 100; // meters
_loiterRadius = 300; // meters
_flyInHeight = 150; // meters
_landDecisionWeight = 0;
_repairRefuelTime = 180; // seconds
_enemySide = east;
_lastSeen = objNull;

// heli requested vars
heliRequested = False;
heliRequestedPosition = [0,0,0];
heliRequestedTarget = objNull;

// heli global var
heliBusy = false;

// initialize
call _fn_initialize;
while {alive _heli} do {
	// update landing decision weight
	call _fn_updateLandDecisionWeight;
	
	// land
	if (_landDecisionWeight >= 1) then {
		call _fn_land;
	};
	
	// get most recently seen target
	_mostRecent = call _fn_mostRecentlySeen;
	systemChat str [_mostRecent];
	
	// enemies recently seen, loiter around and look for them
	if (!(_mostRecent isEqualTo objNull)) then {
		// heli is now busy, can't be requested for
		heliBusy = true;
		
		_heli flyInHeight 50;
		
		_lastSeen = _mostRecent#0;
		_lastSeenPos = _mostRecent#2;
		_timeSinceSeen = time - _lastSeen;
		_wpType = waypointType [_group, 0];
		systemChat str [_wpType];
		
		_heliD doWatch (ASLtoATL _lastSeenPos);
		
		// if heli is close to the last position and it's current waypoint is not loiter,
		systemChat str [_heli distance _lastSeenPos];
		if (_heli distance _lastSeenPos > (_largeLoiterRadius + 500)) then {
			if(waypointPosition [_group, 0] isEqualTo _lastSeenPos) then {;
				systemChat "moving to position";
				// Delete move waypoint
				[_group] call _fn_deleteAllWaypoints;
				
				// Create fast move waypoint at position
				_wp = _group addWaypoint [_lastSeenPos, 0];
				_wp setWaypointType "MOVE";
				_wp setWaypointSpeed "FULL";
			};
		} else { // if far away, quickly move to position
			if (_wpType != "LOITER") then {
				systemChat "setting loiter";
				// Delete all waypoints
				[_group] call _fn_deleteAllWaypoints;
				
				// Create loiter waypoint at position
				_wp = _group addWaypoint [_lastSeenPos, 0];
				_wp setWaypointType "LOITER";
				_wp setWaypointSpeed "LIMITED";
				_wp setWaypointLoiterAltitude 100;
			};
		};
		if (_timeSinceSeen < _smallLoiterTime) then {
			[_group, 0] setWaypointLoiterRadius _smallLoiterRadius;
		};
		if (_timeSinceSeen < _mediumLoiterTime && _timeSinceSeen > _smallLoiterTime) then {
			[_group, 0] setWaypointLoiterRadius _mediumLoiterRadius;
		};
		if (_timeSinceSeen > _mediumLoiterTime) then {
			[_group, 0] setWaypointLoiterRadius _largeLoiterRadius;
		};
	};
	
	// green flare popped
	if (heliRequested && _mostRecent isEqualTo objNull) then {
		// Delete move waypoint
		[_group] call _fn_deleteAllWaypoints;
	
		// heli is busy, can't be requested for
		heliBusy = true;
		
		// move to position
		_heli move heliRequestedPosition;
		_heli setSpeedMode "FULL";		
		
		waitUntil {_heli distance heliRequestedPosition < 500};
		heliRequested = false;
		
		// target revealed
		_heli reveal [heliRequestedTarget, 1];
	};
	if (!heliRequested && _mostRecent isEqualTo objNull && (_lastSeen isEqualTo objNull || (time - _lastSeen) > _forgetEnemyTime)) then {
		// patrol around
		heliBusy = false;
		systemChat "patrol";
		call _fn_patrol;
	};
	sleep 0.5;
};