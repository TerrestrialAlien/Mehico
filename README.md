# Installation Guide

This guide explains where to place each script and module within your Roblox game hierarchy to use the new Modular Architecture.

## **ReplicatedStorage**
Place these files in `game.ReplicatedStorage`.

*   **Folder:** `Shared`
    *   `GameConfig` (ModuleScript) - Contains all game constants and configuration.
*   **Folder:** `Controllers`
    *   `MovementController` (ModuleScript) - Client-side movement logic (Slide, Dive, WallJump, Hoverboard).
    *   `AbilityController` (ModuleScript) - Client-side ability logic (SplatBomb input/aiming).
    *   `InterfaceController` (ModuleScript) - Client-side UI logic (HUD, Health, Upgrades, Zone Visuals).
    *   `AudioController` (ModuleScript) - Client-side audio management.
*   **Note:** Assets required by the Client (e.g., Particles like `GrindSparks`, Sounds like `WallJumpSound`) should generally remain in `ReplicatedStorage` so they are accessible to LocalScripts.

## **ServerStorage**
Place these files in `game.ServerStorage`.

*   **Folder:** `Assets`
    *   (Place your Maps, Tools, and server-side assets here)

## **ServerScriptService**
Place these files in `game.ServerScriptService`.

*   `ServerLoader` (Script) - **The Main Server Script**. This loads and starts all services.
*   `KillScript` (Script) - Handles "KillBrick" tagged parts independently.
*   **Folder:** `Services`
    *   `GameLoopService` (ModuleScript) - Manages the main game loop (Intermission, Round Timer).
    *   `GamemodeService` (ModuleScript) - Manages map selection and mode logic.
    *   `PlayerService` (ModuleScript) - Manages player data, stats, teams, and upgrades.
    *   `PhysicsService` (ModuleScript) - Manages server-side physics validation (Anti-Cheat) and Hoverboard replication.
    *   `TerminalFrenzyLogic` (ModuleScript) - Specific logic for the Terminal Frenzy gamemode.
    *   `ZoneControlLogic` (ModuleScript) - Specific logic for the Zone Control gamemode.

## **StarterPlayer > StarterPlayerScripts**
Place these files in `game.StarterPlayer.StarterPlayerScripts`.

*   `ClientLoader` (LocalScript) - **The Main Client Script**. This loads and starts all controllers.

---

### **How it Works**
1.  **Server:** When the server starts, `ServerLoader` runs. It requires every ModuleScript in `ServerScriptService/Services` and calls their `:Init()` and `:Start()` methods.
2.  **Client:** When a player joins, `ClientLoader` runs. It requires every ModuleScript in `ReplicatedStorage/Controllers` and calls their `:Init()` and `:Start()` methods.
3.  **Config:** Both Server and Client require `ReplicatedStorage/Shared/GameConfig` to ensure they use the exact same values for speeds, cooldowns, etc.
