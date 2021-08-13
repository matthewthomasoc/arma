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

/* Given position in ATL, fire specified flare type above with randomness */
fn_fireFlare = {
	params["_position","_flare"];
	
	// create target for SL to shoot flare at, invisible helipad doesn't work?
	_SLPos = getPosATL _SL;
	_target = "Land_MetalWire_F" createVehicle _SLPos;
	hideObjectGlobal _target;
	
	/* get position for target, adding some randomness */
	_angleRange = 45;
	// add height to position
	_targetPos = _position vectorAdd [0, 0, 150];
	// get distance to position
	_distance = _SLPos vectorDistance _targetPos;
	// randomly scale distance between x.8-x1.8
	_distanceMultiplier = (random 1) + .5;
	_distance = _distance * _distanceMultiplier;
	// get unit vector to target
	_unitvec = _SLPos vectorFromTo _targetPos;
	// get horizontal unit vector
	_horizontal = vectorNormalized [_unitvec#0, _unitvec#1, 0];
	// find angle to horizontal
	_angleToHoriz = acos(_horizontal vectorCos _unitvec);
	// rotate horizontal vector by random angle in _angleRange around z-axis
	_angleRand = (random 2*_angleRange) - _angleRange;
	_newUnit = [_horizontal,[0,0,1],_angleRand] call fn_rotateVector;
	_newUnit = _newUnit vectorAdd [0,0, sin(_angleToHoriz)];
	_newUnit = vectorNormalized _newUnit;
	_targetPos = _newUnit vectorMultiply _distance;
	_targetPos = _targetPos vectorAdd _SLPos;
	
	// move target to position
	_target setPosATL _targetPos;
	
	_SL setUnitPos "MIDDLE";
	uiSleep .25;
	_SL reveal _target;
	_SL lookAt _target;
	_SL doTarget _target;
	
	uiSleep 2;
	
	_SL fire ["GP25Muzzle","Single",_flare];
	
	_SL doWatch objNull;
	_SL setUnitPos "AUTO";
	deleteVehicle _target;
};

/* Check if SL is in imminent danger by being shot at */
fn_inImminentDanger = {
	_endangered = false;
	_requiredTimeSinceEndangered = 5; // 5 seconds
	
	if (count _targets != 0) then {
		// loop through each target
		{
			// save current query
			_query = _x;
			// get target object
			_target = _query#1;
			// get SL target knowledge on target
			_knowledge = _SL targetKnowledge _target;
			// find time since endangered by unit
			_lastEndangered = time - _knowledge#3;
			if (_lastEndangered < _requiredTimeSinceEndangered) exitWith {
				_endangered = true;
			};
		} forEach _targets;
	};
	_endangered
};

/* Check if SL meets conditions to fire any flares */
fn_CanFireFlares = {
	_canFire = false;
	// Check if in combat
	_timeSinceCombat = time - _lastTimeInCombat;
	if (behaviour _SL == "COMBAT" || (_timeSinceCombat < _engagementTime && _lastTimeInCombat != 0)) then {
		// save time
		_lastTimeInCombat = time;
		// Check if in imminent danger
		// Imminent danger is defined as being
		// endangered by an enemy unit in the past
		// 5 seconds
		_endangered = call fn_inImminentDanger;
		if (!_endangered && count _targets != 0) then {
			_canFire = true;
		};
	};
	
	_canFire
};

/* Check if the AI is in a situation a white flare is appropriate */
fn_mostRecentlySeen = {
	_mostRecent = objNull;
	if (count _targets == 0) exitWith {_mostRecent};
	if (count _targets == 1) then {
		_query = _targets#0;
		// Get query target
		_target = _query#1;
		// Get target knowledge on target
		_knowledge = _SL targetKnowledge _target;
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
			_knowledge = _SL targetKnowledge _target;
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
					if(_lastSeen >  _mostRecent#0 && _lastSeen > 0) then {
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
	_mostRecent
};

/* Check if it is dark */
fn_checkIfDark = {
	_isDark = false;
	// these values are just from guessing and trial/error
	// if sunOrMoon < 1, we know for sure it's dark
	if (sunOrMoon < 1) then {
		_isDark = true;
	} else { // check if it's past sunset
		_times = date call BIS_fnc_sunriseSunsetTime;
		_sunSetTime = _times#1;
		if (dayTime > _sunSetTime + 0.15) then {
			_isDark = true;
		};
	};
	
	_isDark
};

/* Initialize SL ammo count and check if SL is a valid unit */
fn_initialize = {
	_valid = true;
	// Check SL has correct weapon
	if (!(_weapon in _weapons) || side _SL == _enemySide) exitWith {
		_valid = false;
	};


	{ // Save ammo count for each type of flare
		_magazine = _x;
		if (_x == _whiteFlare) then {
			_numWhite = _numWhite + 1;
			continue
		};
		if (_x == _redFlare) then {
			_numRed = _numRed + 1;
			continue
		};
		if (_x == _greenFlare) then {
			_numGreen = _numGreen + 1;
			continue
		};
	} forEach _magazines;
	
	_valid
};

/* Remove old flare fires from the buffer array */
fn_flareTimeoutClear = {
	/* White flares */
	// get amount of flares fired
	_length = count _whiteFlaresFired;
	if (_length != 0) then {
		// count backwards, deleting as necessary
		for "_i" from _length-1 to 0 step -1 do {
			_element = _whiteFlaresFired select _i;
			// If time since firing is greater than timeout limit,
			if (time - _element > _whiteFlaresTimeout) then {
				// Remove from array
				_whiteFlaresFired deleteAt _i;
			};
		};
	};
	
	/* Support flares */
	// get amount of flares fired
	_length = count _supportFlaresFired;
	if (_length != 0) then {
		// count backwards, deleting as necessary
		for "_i" from _length-1 to 0 step -1 do {
			_element = _supportFlaresFired select _i;
			// If time since firing is greater than timeout limit,
			if (time - _element > _supportFlaresTimeout) then {
				// Remove from array
				_supportFlaresFired deleteAt _i;
			};
		};
	};
};
/* Check conditions for white flare firing, and fire if all conditions met */
fn_whiteFlares = {
	// Check if base conditions are met to fire white flares
	if (_canFireFlares && _isDark && count _targets != 0 && _numWhite != 0 && _SL distance _target < 300) then {
		// Check if firing flares is appropriate in this situation
		if(time - _lastSeen > 5 && count _whiteFlaresFired < _maxWhiteFlares) then {
			// Fire flares, but only a specified percentage of the time
			if (_fireWhiteFlareChance > random 100) then {
				[_position,_whiteFlare] call fn_fireFlare;
				_whiteFlaresFired pushBack time;
				_numWhite = _numWhite - 1;
			};
		};
	};
};

/* Check conditions for red flare firing, and fire if all conditions met */
fn_redFlares = {
	// Check if base conditions are met to f	ire red flares
	if (_canFireFlares && count _targets != 0 && _numRed != 0 && !(_position isEqualTo objNull) && _redFlareWeight > _redFlareWeightBaseRequirement) then {
		// Check if firing support is appropriate in this situation
		// Check if friendlies are nearby the fire support position
		_nearbyMen = _position nearEntities [["Man"],_fireSupportRedZone];
		_friendlyFire = false;
		{
			if (side _x != _enemySide) exitWith {
				_friendlyFire = true;
			};
		} forEach _nearbyMen;
		// If the enemy isn't being directly engaged, fire support flares are not maxxed, no friendlies nearby, and jet isn't busy already
		if(time - _lastSeen > 5 && count _supportFlaresFired < _maxSupportFlares && !_friendlyFire && !jetStrafeRequested) then {
			// Fire red flares, but only a specified percentage of the time
			_chanceFire = (_redFlareWeight - _redFlareWeightBaseRequirement) * 50;
			if (_chanceFire > random 100 || _redFlareWeight > 1.5) then {
				[_position,_redFlare] call fn_fireFlare;
				// Call for jet support
				jetStrafeRequested = true;
				jetStrafeTarget = [_position#0,_position#1,0];
				_suppressionLevel = 0;
				_supportFlaresFired pushBack time;
				_numWhite = _numWhite - 1;
			};
		};
	};
};

/* Calculate current weighting for deciding to call fire support (more info)
These weightings are based on complete guesses */
fn_updateDecisionWeighting = {
	_redFlareWeight = 0;
	_unitsGroupDead = 0;
	_unitsGroup = units group _SL;
	// locations that an enemy has an advantage
	_dangerousLocations = ["Hill","RockArea","VegetationBroadleaf","VegetationFir","VegetationPalm","ViewPoint","Mount","StrongpointArea"];
	_distance = _position distance _SL; // distance to enemy

	// get nearby dangerous locations to enemy position
	_nearbyLocations = nearestLocations [_position, _dangerousLocations, 300];
	// count number of nearby locations
	_numberLocations = count _nearbyLocations;
	
	/* location and distance affect the base weighting, while 
	 suppression gradually increases the weighting */
	// calculate current base
	_redFlareWeight = _redFlareWeight + (_distance / 1000);
	_redFlareWeight = _redFlareWeight + (_numberLocations / 10);
	
	// Calculate suppression delta
	call fn_updateSuppressionLevel;
	_redFlareWeight = _redFlareWeight + _suppressionLevel;
	_redFlareWeight = _redFlareWeight + _unitsGroupDead * 0.1;
	
};

fn_updateSuppressionLevel = {
	_suppression = 0;
	_delta = 0;
	{ // Sum suppression for the entire squad
		if (!(alive _x)) then {
			_unitsGroupDead = _unitsGroupDead + 1;
		} else {
			_suppression = _suppression + getSuppression _x;
		};
	} forEach _unitsGroup;
	
	_unitsGroupAlive = (count _unitsGroup) - _unitsGroupDead;
	
	// Calculate weight delta
	// delta is average suppression of group, multiplied by number of casualties
	_delta = _suppression / _unitsGroupAlive;
	_delta = _delta * (1 + _unitsGroupDead);
	
	// if not under suppression
	if (_delta == 0) then {
		_delta = -0.025 - (time - _lastSeen) / 1000;
	};
	
	
	_suppressionLevel = _suppressionLevel + _delta;

	if (_suppressionLevel < 0) then {
		_suppressionLevel = 0;
	};
	if (_suppressionLevel > 1) then {
		_suppressionLevel = 1;
	};
};

// Save SL var
_SL = _this;

// Enemy side for SL
_enemySide = east;

// Set weapon/magazine types
_weapon = "CUP_arifle_AK103_GL_top_rail";
_whiteFlare = "CUP_IlumFlareWhite_GP25_M";
_redFlare = "CUP_FlareRed_GP25_M";
_greenFlare = "CUP_FlareGreen_GP25_M";

// initialize ammo count
_numWhite = 0;
_numRed = 0;
_numGreen = 0;

// Save inventory
_weapons = weapons _SL;
_magazines = magazines _SL;

// Check if SL has correct weapon, count ammo
if (!(call fn_initialize)) exitWith {};

// Vars
_lastTimeInCombat = 0;
_engagementTime = 60;
_suppressionLevel = 0;

// Flare parameters
_whiteFlaresFired = [];
_supportFlaresFired = [];
_fireWhiteFlareChance = 25; // percentage
_maxWhiteFlares = 2;
_whiteFlaresTimeout = 60;
_maxSupportFlares = 1;
_supportFlaresTimeout = 300;
_fireSupportRedZone = 350;
_redFlareWeight = 0;
_redFlareWeightBaseRequirement = .5;

_SL addEventHandler ["Fired", {
	[_this#0, _this#1, _this#2, _this#3, _this#4, _this#5, _this#6, _this#7] spawn {
		params ["_unit", "_weapon", "_muzzle", "_mode", "_ammo", "_magazine", "_projectile", "_gunner"];
		// Red flare
		_heightDeleted = 2.5; // meters
		systemChat str[_ammo];
		if (_magazine == "CUP_FlareRed_GP25_M" || _ammo == "F_40mm_Red") then {
			// Wait until flare reaches the ground
			uiSleep 1;
			waitUntil {(getPosATL _projectile select 2) < _heightDeleted};
			
			// Delete flare once it gets near the ground
			deleteVehicle _projectile;
		};
		if (_magazine == "CUP_IlumFlareWhite_GP25_M") then {
			// Wait until flare reaches the ground
			uiSleep 1;
			systemChat str [getPosATL _projectile];
			waitUntil {(getPosATL _projectile select 2) < _heightDeleted};
			// Delete flare once it gets near the ground
			deleteVehicle _projectile;
		};
	};
}];

while {alive _SL} do {
	// Get targets
	_targets = _SL targetsQuery [objNull, _enemySide, "", [], 0];
	
	// Get most recent target
	_mostRecent = call fn_mostRecentlySeen;
	_lastSeen = 0;
	_target = objNull;
	_position = objNull;
	
	// Check if flare timeout array needs to be cleared
	call fn_flareTimeoutClear;
	
	// Check conditions
	_isDark = call fn_checkIfDark;
	_canFireFlares = call fn_CanFireFlares;
	// Make sure the target exists before applying vars
	
	if (!(_mostRecent isEqualTo objNull)) then {
		_lastSeen = _mostRecent#0;
		_target = _mostRecent#1;
		_position = _mostRecent#2;
		
		// Calculate new weight for calling fire support
		if (_lastSeen >= 0) then {
			call fn_updateDecisionWeighting;
		};
		
		call fn_redFlares;
		call fn_whiteFlares;
	};
	uiSleep 3;
};