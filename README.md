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
  - [x] Squad leader can call in support, i.e. search helicopter,  jet strafe, nearby reinforcements using GL flares
    - [x] Killing a squad leader prevents support from being called
  - [x] Squad leader can deploy white flares at night time to illuminate positions
  - [x] Flare color represents support requested:
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
  - There are no friendlies within' 350 meters of the strike zone
- For firing red flares, a weighted decision making system is used. The weight is impacted by:
  - Level of suppression for whole squad (changes weight over time)
  - Time since last combat (changes weight over time)
  - Advantage of enemy position (affects base weight)
  - Distance to target (affects base weight)
  - Squad casualties (affects base weight and multiplies suppression)
  - To add: being near towns/civilians reduces weight (penalty decreases as desperation increases)
A base required weight is necessary for the chance to fire a red flare to become avaialble. A higher weight past this base increases the chances of firing a red flare, with an exceedingly large weight immediately firing the flare.

# Jet
The jet is a support asset used to deliver devastating firepower to enemy positions. It is armed with bombs and dumb-fire missiles. The jet is called when a squad leader fires a red flare. The weapons chosen by the jet for a strafing run are random, with bombs being more likely than missiles due to the missiles have an exceedingly large area of effect. The jet should force players to not linger in one position in a large engagement. To counter the possiblity of the jet being overpowered due to giving no warning before a strike, the red signal flare will act as a visual warning cue that a strike is incoming. The jet approaches at a very steep angle when using bombs, and a shallow angle when using rockets. Guns are not used because their effect is extremely minimal.

When there are no requested fire missions, the jet patrols randomly around the map or a specified location. When a fire mission is requested, the jet immediately leaves patrol and heads to the engagement zone. If the jet is too close to the mission, it will simply fly a far distance away before turning around and starting the mission.

The pathing system for the jet strafe uses the `setVelocityTransformation` function to smoothly linear interpolate between points on a calculated path that leads to the target. The path consists of two stages:
  1) Transition stage
  2) Attack dive

In the transition stage, the jet smoothly travels upward, then downward, along a curved path that leads directly into the attack dive. This allows for a natural looking flight path. At the end of the transition stage, the jet is perfectly in-line with the attack dive, allowing for seamless transition between the two stages. The attack dive path is generated by four parameters:
  1) Angle of attack
  2) Start height
  3) End height
  4) Number of fire points

A line is drawn in the direction of the jet at the given angle of attack from horizontal. A path is created between the start and end height, giving a linear line between the two points. In between the two points and along the path, the given number of fire points are created. When the jet reaches each of these fire points, it will fire it's select weapon once, causing the jet to fire it's weapon as many times as there are fire points.

At the end of the calculated dive, control is given back to the AI. The AI automatically pitches up and climbs to a given altitude, deploying a random amount of chaff/flares as it leaves the engagement zone. This leads to a smooth transition from the attack to escape phase.

This process is repeatable until the jet runs out of ammo or fuel.
