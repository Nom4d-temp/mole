# Mole 1.3.11

[GitHub repository](https://github.com/Nom4d-temp/mole)

**Meet Mole: your turtle’s next mining adventure.** Mole turns a CC: Tweaked mining turtle into a tunnel miner that searches for nearby ores while leaving ordinary stone in place wherever possible. Answer a few setup questions, give it a chest and some fuel, and let it get to work.

Mole follows connected ore veins, brings its haul back to your chest, and manages refueling and trash disposal. Saved progress and automatic recovery help it pick up after interruptions, while simple commands let you change settings, start a new quarry, or update straight from GitHub. It works with normal and advanced mining turtles, with unfamiliar modded blocks kept by default.

## What you need

- Minecraft with **CC: Tweaked**.
- A **mining turtle** with a diamond pickaxe upgrade. A normal or advanced mining turtle works.
- A chest and some coal or charcoal. Put one stack in the chest to start.
- Internet downloads enabled for turtles. If your server blocks them, ask its owner.

## 1. Download the program onto your turtle

Right-click the mining turtle to open its screen. Type this command and press Enter:

```text
wget https://raw.githubusercontent.com/Nom4d-temp/mole/main/mole.lua mole
```

This downloads Mole and saves it on your turtle as **mole**.

## 2. Place the turtle and chest

1. Choose an area you are happy for the turtle to mine underneath.
2. Put the turtle at the **near-left corner**, facing into the area.
3. Put the chest **directly behind the turtle**, at the same height.
4. Put a stack of coal or charcoal in the **first slot of the chest**. Leave room for the items it brings back.

**Length goes forward. Width goes to the turtle's right. Depth goes down from its starting block.** The column directly below the turtle is included in the mining area.

Keep the starting chest in place. Keep other matching chests away from the mining area: the turtle uses this chest to find its way home after an interrupted move.

## 3. Start mining

Type:

```text
mole
```

The turtle asks:

```text
Length in blocks [16]:
Width in blocks [16]:
Starting world Y coordinate [Enter = unknown]:
Depth below the turtle [64]:
```

Press **Enter** to use the number in brackets, or type a different whole number. Type `q` to cancel setup.

For your first test, choose **3** for length, **3** for width, leave starting Y blank (or enter its actual value), and choose **6** for depth. Check that the chest is behind the turtle, then press Enter at the final prompt to start.

The optional Y coordinate is the turtle's world height. Enter the Y of the turtle's own block, not the block underneath it. Negative numbers are accepted. Leave it blank if you do not know it; Mole then reports depth below the start and does not apply world-height guidance.

When Y is known, Mole displays how many blocks below the turtle reach **Y -62**, then asks for depth. It reduces the default depth if needed. The bedrock caution appears only if you request a bottom below Y -62. If your chosen depth goes deeper, press Enter to shorten it to Y -62, or type `yes` to keep the deeper depth. This override is useful in other dimensions. If the turtle starts at or below Y -62, you must explicitly choose `yes` to mine downward. The requested depth still has the normal 512-block maximum.

Progress and `mole status` show both world Y and blocks below the start when Y is known. For example, a start at Y 64 and a depth of 126 ends at Y -62. Entered Y is used for guidance and reporting; it does not locate the turtle or replace recovery. Existing jobs keep their current dimensions; the optional question is asked only for a new job. Emergency return detours can still move within the saved job area.

Mole saves its starting position and creates an automatic restart file. Your settings and progress are saved for the next time it runs.

If you already use your own startup program, the miner keeps it. To make that existing program resume mining, add `shell.run("mole")` to it.

## What will it dig?

The turtle makes **one-block-high tunnels**, normally with **two columns of stone between them**. It connects the tunnels at their ends. The next tunnel level is **three blocks lower**. It also makes an entry shaft below the starting corner.

At every tunnel step it checks the blocks above, below, in front, behind, left, and right. It leaves ordinary trash blocks alone unless it needs to break them to move. If it finds a block that is not on the trash list, it follows connected non-trash blocks to collect the vein. Unknown blocks from mods are kept by default.

**Mole uses tunnel mining.** Stone stays in the walls, ceiling, and floor. Some isolated ores hidden between tunnels can be missed because the turtle cannot see through stone. Connected veins it finds are followed inside the chosen area. A search has size and depth limits so huge modded deposits cannot make the turtle wander forever; some of a very large deposit may remain.

At the starting chest, Mole reports its current fuel, the target for the next trip, why that target is needed, and its fuel after refueling. The default target is **2,560 fuel units**, equal to 32 coal or charcoal from empty. Existing settings using the former 2,000 target are upgraded to 2,560; other custom targets are kept. Longer routes can require a higher target. It uses coal or charcoal only when below the target. Whole fuel items can take it slightly above the target. When the job finishes, it reports remaining fuel and does not refuel.

The turtle returns to the chest when its inventory is nearly full, it needs fuel, or a tunnel level is finished. It also comes home when it finishes the whole job. It chooses the shortest route through cells it has already visited, and uses known tunnels to get back to work. If a passage becomes blocked, it tries another known route. If none is clear, it tries to mine the obstruction, then digs a detour toward the starting position. It reconnects to known tunnels as soon as it can. Emergency detours can extend one block past the far edges of the chosen width and length, and can reach the surface. Keep that border clear of builds. Protected blocks and machines are still left alone. If every approach is blocked, fuel is insufficient, or inventory space runs out, it saves progress and reports the problem after attempting to return.

## Everyday controls

| Type this | What happens |
| --- | --- |
| `mole` | Start, resume, or answer the questions for a new turtle |
| `mole status` | Show saved progress, depth, and fuel |
| `mole settings` | Change which blocks count as trash |
| `mole return` | Return to the chest and pause |
| `mole new` | Set up a new job after finishing or returning home |
| `mole reset` | Clear saved jobs and recovery data, and restore all default settings |
| `mole delete` | Uninstall Mole after a yes/no confirmation |
| `mole update` | Check GitHub and safely install a newer version |
| `mole help` | Show the short command list |

While the miner is running, hold **Ctrl+T** to stop the program. Then type `mole return` if you want it to go home. Stopping can leave a move unfinished in the save file; automatic chest recovery handles this on the next launch.

**Starting over after a problem:** run `mole reset`. This permanently clears the current job, saved routes, recovery information, previous-job archive, and custom settings, even if a saved file is damaged. It does not move the turtle or change its fuel or inventory. The program and startup file stay installed. Place the turtle at a safe starting corner with the chest behind it, then run `mole` for the normal setup questions.

**Uninstalling:** run `mole delete`, then type `yes` to confirm. Any other answer cancels. This removes the running Mole program file, saved jobs, recovery data, custom settings, its update download/backup files, and its installation record. Fuel and carried items stay in the turtle, and it does not move.

When Mole replaces a supported startup file, it saves the original and restores it on uninstall. If Mole created startup from scratch, uninstall removes it. Unrelated startup scripts are preserved. If you edit startup after installation, uninstall keeps your edited file; remove any Mole launch line yourself. Existing installations from older versions have no original backup: uninstall can remove recognizable Mole startup, but cannot recover a file that was already overwritten. `mole reset` keeps the installation record and startup backup so you can still uninstall later.

Do not pick up, move, or turn the turtle during a saved job. After a job is finished, you can move it to a new starting corner, put the chest behind it, and run `mole new`. If you paused an unfinished job to start a new one, that abandons the old job; its last state is saved as `quarry-data/previous-job` for reference.

## Change the trash list

Run:

```text
mole settings
```

Choose **1** to ignore a block or **2** to keep it. Enter its full Minecraft block ID, such as `minecraft:stone` or a mod's `modname:block_name`. Choose **3** to see the list. Press Enter to finish.

The starter list contains dirt, stone, cobblestone, gravel, granite, and similar common blocks. Ores and unknown modded blocks are not trash by default.

Choose **4** to turn trash dropping on or off. Turning it off keeps tunnel rubble and unloads it into the chest. When dropping is on, the turtle carries trash home and drops it into the empty space below its starting position before unloading valuable items into the chest. It never drops trash while mining. If the space underneath is blocked or a drop fails, it waits at home for you to clear it, keeping the trash out of the chest. Leave this space open. Dropped items are normal world items, so they may be picked up again.

An ore's block ID and the item it drops can be different. The block ID controls whether the turtle follows it; the item ID controls whether a collected item is discarded. Add both IDs only if you want both ignored/discarded. Coal and charcoal are kept for fuel even if added to trash.

## If it stops

| Message or problem | What to do |
| --- | --- |
| Not enough fuel | Add coal/charcoal to the chest's first slots, then run `mole` again. |
| Chest full | Empty the chest, then run `mole` again. |
| No chest behind you during setup | Place it directly behind the turtle at the same height, then press Enter to retry. |
| Protected or unbreakable block | Check what it reported. It tries to return home and pauses. Run `mole` after fixing the cause and follow the resume prompt. |
| Starting chest not found during recovery | Check that the original chest is still there and the chunks are loaded. Clear any new blocks from the return tunnels, then retry `mole`. Recovery will not dig while its position is uncertain. |
| Download says file already exists | Follow the update steps below instead of downloading over the existing file. |
| Download says 404 / not found | Check the username, repository name, branch, and filename in the URL. The repository must be public. |
| Downloads are disabled or blocked | Ask the server owner to allow CC: Tweaked HTTP downloads from GitHub's raw file domain. |

Keep the turtle's mining area and chest loaded. The program cannot load chunks itself. The automatic restart file resumes the saved job when the turtle boots; a stopped or paused program may still need you to run `mole`.

## Update Mole

1. Hold Ctrl+T if Mole is running, to return to the command prompt.
2. Type `mole update`.
3. Mole checks the version on GitHub. If a newer version is available, it downloads it, checks that it is a versioned Mole program with valid Lua syntax, and checks the saved download before replacing the program.
4. Type `mole` to resume your saved job. An interrupted move still uses normal position recovery.

Your job, settings, fuel, inventory, and original startup backup are kept. The previous program is saved as `mole.update-backup`. A failed download leaves the current program in place. If installation fails, Mole tries to restore the previous program. Mole's automatic startup also restores that backup if an interrupted installation leaves the program missing. Custom startup scripts are left alone.

If you need to restore the backup manually, remove the faulty `mole` file, then run `move mole.update-backup mole`. This restores the program only; it does not roll back your job or settings. Syntax checks cannot guarantee a new release is free of bugs.

**Installing this updater for the first time:** versions before 1.3.7 need one manual update. Stop Mole, rename the old file with `move mole mole-backup` (choose another backup name if needed), then download:

```text
wget https://raw.githubusercontent.com/Nom4d-temp/mole/main/mole.lua mole
```

Run `mole` once. Future updates can use `mole update`. Updates become available when the newer `mole.lua` is uploaded to the repository's `main` branch.

## Config file

Mole stores its settings in `quarry-data/config` on the turtle. Most users can use the setup questions and `mole settings`. For advanced changes, stop Mole with Ctrl+T, then type `edit quarry-data/config`.

The file contains the trash list, allowed fuel items, protected blocks, fuel target and reserves, movement retries, and ore-vein search limits. Make a backup before editing, keep the existing format, and save before running `mole` again. Changing dimensions in this file does not resize a saved job; use `mole new` for a different size. `mole reset` restores all default settings and clears the saved job.

## AI disclosure

Mole's code and documentation were generated with OpenAI's ChatGPT, guided by a human who provided requirements and tested the program in Minecraft. It has also been checked with simulated turtle tests. AI-generated code can still contain mistakes, and behavior may vary between modpacks. Test a small quarry before starting a larger job.
