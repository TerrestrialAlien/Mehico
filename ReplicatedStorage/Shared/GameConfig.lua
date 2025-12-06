local GameConfig = {}

-- Movement
GameConfig.Movement = {
    SlideSpeed = 51.5,
    SlideCooldown = 7.5,
    WallJumpPower = 1.2,
    HoverSpeed = 45,
    DiveSpeed = 70,
    DiveCooldown = 9.5,
    HoverCooldown = 6.5,
}

-- Upgrades
GameConfig.Upgrades = {
    Health = { Costs = {2, 3, 5}, Values = {100, 105, 115, 120} },
    Respawn = { Costs = {2, 4, 6}, Values = {8, 7.0, 6.0, 5.0} },
    Speed = { Costs = {1, 2, 3}, Values = {21, 22, 23, 24} }
}

-- SplatBomb
GameConfig.Bomb = {
    FuseTime = 2.5,
    Cooldown = 12,
    Damage = 100,
    ThrowSpeedMin = 30,
    ThrowSpeedMax = 90,
    ThrowUpForce = 30,
    BlastRadiusKill = 8,
    BlastRadiusOuter = 18
}

-- Game Settings
GameConfig.Game = {
    IntermissionTime = 15,
    RoundTime = 480,
    BaseRespawnTime = 8,
    PointsPerKill = 1,
    PassivePointRate = 120,
    DynamicMapThreshold = 0.5,
    BaseJumpPower = 50.03
}

-- Terminal Frenzy
GameConfig.TerminalFrenzy = {
    TotalHackPoints = 80,
    HackMilestonePercent = 0.25,
    RevealCooldown = 3,
    ProximityRevealRange = 80
}

-- Zone Control
GameConfig.ZoneControl = {
    CaptureTime = 1.5,
    TargetPoints = 45,
    DamageTick = 0.5,
    DamageAmount = 4,
    LossPenalty = 5
}

return GameConfig
