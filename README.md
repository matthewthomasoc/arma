# arma
Mission for Arma 3

# Introduction
This mission is to be an insurgency-type mode against a better-equipped force, with a focus on guerrila and unconventional warfare tactics and interesting mission mechanics. The goal is simply to cause as much chaos as possible, which also increases the lethality and desperation of the enemy forces.

# Progress/Ideas:
- Support
  - Jet
    - [x] Jet patrols around map 
    - [x] Jet can strafe a given position reliably and effectively
      - [x] Movement is smooth, realistic
      - [ ] Jet avoids obstacles
    - [ ] Jet can land at the airfield, taxi, refuel, repair, and rearm, creating vulnerability
      - [ ] Taxi movement is smooth, realistic
    - [ ] Jet can take-off and return to normal operations
  - Search helicopter
    - [ ] Helicopter patrols around map
    - [ ] Helicopter can spot and follow player accurately, sending location to nearby troops
    - [ ] Helicopter can land at the airfield, refuel, and repair, creating vulnerability
    - [ ] Helicopter can take-off and return to normal operations
- Infantry
  - [ ] Squads consist of special roles, centered around a GL squad leader
    - [ ] Killing a squad leader greatly impacts squad organization and strategy, placing emphasis on target importance
  - [ ] Squad leader can call in support, i.e. search helicopter,  jet strafe, nearby reinforcements using GL flares
    - [ ] Killing a squad leader prevents support from being called
  - [ ] Squad leader can deploy white flares at night time to illuminate positions
  - [ ] Flare color represents support requested:
     - Blue: search helicopter
     - Red: jet strafe
     - Yellow: nearby reinforcements
  - [ ] Squads have strategies for searching/combing positions after losing contact with enemy

# Squad Leader

The squad leader has an AKM GP-25, with red, green, and white flares.

- In order to fire any flare, the following conditions must be met:
  - The squad leader must be in combat
  - The squad leader must not be in imminent danger (i.e. being directly shot at very recently)
  - The squad leader must know a general location/direction of the enemy

- In order to fire white flares, the following conditions must be met:
  - It must be dark
  - Enemy unit has not been seen for more than 5 seconds (to not disrupt the SL firing)

- In order to fire green flares, the following conditions must be met:
  - The enemy unit has not been seen for more than a minute*

- In order to fire red flares, the following conditions must be met:
  - There are no friendlies within' 200 meters of the strike zone (friendly fire still possible)

- For firing red flares, a weighted decision making system is used. The weight is impacted by:
  - Level of suppression for whole squad (changes weight over time)
  - Time since last combat (changes weight over time)
  - Advantage of enemy position (affects base weight)
  - Distance to target (affects base weight)
  - Squad casualties (affects base weight and multiplies suppression)
