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
	_position = _position vectorAdd [0, 0, 150];
	// get distance to position
	_distance = _SLPos vectorDistance _position;
	// randomly scale distance between x.8-x1.8
	_distanceMultiplier = (random 1) + .5;
	_distance = _distance * _distanceMultiplier;
	// get unit vector to target
	_unitvec = _SLPos vectorFromTo _position;
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
	
	_SL reveal _target;
	_SL lookAt _target;
	_SL doTarget _target;
	
	uiSleep 2;
	
	_SL fire ["GP25Muzzle","Single",_flare];
	
	_SL doWatch objNull;
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
	if (behaviour _SL == "COMBAT") then {
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
	_mostRecent = [];
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
		
		_mostRecent = [_lastSeen, _target, _position];
	} else {
		// Find most recently seen target
		{
			_query = _x;
			// Get query target
			_target = _query#1;
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
				if(_lastSeen >  _mostRecent#0) then {
					_mostRecent = [_lastSeen, _forEachIndex, _position];
				};
			};
		} forEach _targets;
		// change index to be object
		_mostRecent = [_lastSeen, _targets#0 select 1];
	};
	
	systemChat format ["%1", _mostRecent];
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

// Save SL var
_SL = _this;

// Enemy side for SL
_enemySide = east;

// Set weapon/magazine types
_weapon = "CUP_arifle_AK103_GL_top_rail";
_whiteFlare = "CUP_IlumFlareWhite_GP25_M";
_redFlare = "CUP_IlumFlareRed_GP25_M";
_greenFlare = "CUP_IlumFlareGreen_GP25_M";

// Save inventory
_weapons = weapons _SL;
_magazines = magazines _SL;

// Check SL has correct weapon
if (!(_weapon in _weapons)) exitWith {};

// initialize ammo count
_numWhite = 0;
_numRed = 0;
_numGreen = 0;

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

_whiteFlaresFired = [];
_fireWhiteFlareChance = 5; // percentage
_maxWhiteFlares = 3;
_whiteFlaresTimeout = 60;
while {alive _SL} do {
	_targets = _SL targetsQuery [objNull, _enemySide, "", [], 0];
	_canFireFlares = call fn_CanFireFlares;
	_isDark = call fn_checkIfDark;
	
	// Check if flare timeout array needs to be cleared
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
	
	if (_canFireFlares && _isDark && count _targets != 0 && _numWhite != 0) then {
		systemChat format ["possible to fire white flares"];
		// Get most recent target
		_mostRecent = call fn_mostRecentlySeen;
		
		_lastSeen = _mostRecent#0;
		_target = _mostRecent#1;
		_position = _mostRecent#2;
		// Check if firing flares is appropriate in this situation
		if(time - _lastSeen > 5 && count _whiteFlaresFired < _maxWhiteFlares) then {
			// Fire flares, but only a specified percentage of the time
			if (_fireWhiteFlareChance <= random 101) then {
				systemChat format ["firing flare"];
				[_position,_whiteFlare] call fn_fireFlare;
				_whiteFlaresFired pushBack time;
				_numWhite = _numWhite - 1;
			};
		};
	};
	uiSleep 3;
};