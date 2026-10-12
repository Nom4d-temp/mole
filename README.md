# Mole 1.4.10

[GitHub repository](https://github.com/Nom4d-temp/mole)

**Meet Mole: your turtle’s next mining adventure.** Mole turns a CC: Tweaked mining turtle into a tunnel miner that searches for nearby ores while leaving ordinary stone in place wherever possible. Answer a few setup questions, give it a chest and some fuel, and let it get to work.

Mole follows connected ore veins, brings its haul back to your chest, and manages refueling and trash disposal. Saved progress and automatic recovery help it resume after interruptions, while simple commands let you change settings, start a new quarry, or update straight from GitHub.

## What you need

- Minecraft with **CC: Tweaked**.
- A **mining turtle** with a diamond pickaxe upgrade. A normal or advanced mining turtle works.
- A chest and coal, charcoal, or lava buckets. One stack of coal or charcoal is a good starting supply.
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
4. Put fuel in **consecutive chest slots starting at slot 1**. Coal, charcoal, and lava buckets can be mixed. The first empty slot or non-fuel item marks the end of the initial fuel area. Mole remembers and maintains that area during the job. Leave room for the items it brings back.

**Using lava buckets:** Mole returns empty buckets to the chest after refueling and keeps remaining fuel together at the front when the chest supports rearranging items. Leave an empty chest slot for this and room for the haul. Other inventories may need manual tidying. Mole does not collect lava or refill buckets.

**Length goes forward. Width goes to the turtle's right. Depth goes down from its starting block.** The column directly below the turtle is included in the mining area.

Keep the starting chest in place so Mole can unload, refuel, and confirm its position during recovery. Keep other matching chests away from the mining area.

## 3. Start mining

Type:

```text
mole
```

The turtle asks:

```text
Length in blocks [16]:
Width in blocks [16]:
Starting world Y coordinate (required):
Depth below the turtle [64]:
```

Press **Enter** to use the default, or enter a whole number. Type `q` to cancel setup.

For a first test, use **3** for length, **3** for width, and **6** for depth. Enter the turtle’s starting Y coordinate. Check that the chest is behind the turtle, then press Enter at the final prompt to begin.

**Starting Y is required for new jobs.** Enter the world height of the turtle's own block, not the block underneath. Negative whole numbers are accepted. Use your game’s coordinate display to check it before starting.

Mole shows the depth needed to reach **Y -62** and lowers the default depth if necessary. If you request a deeper quarry, it warns you: press Enter to stop at Y -62, or type `yes` to keep your chosen depth, useful in other dimensions. Starting at or below Y -62 also requires `yes` to mine downward. Maximum depth is **512 blocks**.

Progress and `mole status` show world Y and depth. Starting Y does not locate the turtle. Setup questions appear only for new jobs.

**Emergency escape targets the starting elevation automatically.** If you start underground, this may still be underground. Saved jobs without a valid starting Y must be cleared with `mole reset` before starting again.

Mole saves settings and progress and creates an automatic restart file. If you already have your own startup program, Mole keeps it; add `shell.run("mole")` to that file to enable automatic resuming.

## What will it dig?

Mole digs one-block-high tunnels, leaving two columns between them and three blocks between tunnel levels. It checks neighboring blocks and follows connected ores and other non-trash blocks within your chosen area. Ordinary stone is mined only when needed for movement. Some hidden ores and very large veins may be missed.

It returns to the chest when inventory is full or fuel runs low, after each tunnel level, and when finished. It uses known tunnels where possible and tries to clear or dig around blocked return paths. Protected blocks and detected machines are skipped during ore searches; merely spotting one does not stop the quarry. Blocks that obstruct required movement still use normal obstacle handling. Keep the quarry and its one-block emergency border clear of builds.

At the chest, Mole unloads its haul, drops trash underneath the starting position, and reports its fuel target and current level. **The preferred target is 2,560 units—32 coal or charcoal from empty. Mole raises it when the route back to work requires a larger fuel reserve.** If the chest cannot reach that target but the calculated safe departure minimum is met, mining continues. Mole reports both values. For fuel shortages, it waits at home only when the minimum is not met. Finished jobs do not refuel.

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

While the miner is running, hold **Ctrl+T** to stop the program. Then type `mole return` if you want it to go home. Stopping during movement can leave the saved position uncertain. On the next launch, Mole follows saved routes without digging and checks the starting chest before resuming.

**Starting over after a problem:** run `mole reset`. This permanently clears the current job, saved routes, recovery and emergency information, previous-job archive, and custom settings, even if a saved file is damaged. It does not move the turtle or change its fuel or inventory. The program and startup file stay installed. Place the turtle at a safe starting corner with the chest behind it, then run `mole` for the normal setup questions.

**Uninstalling:** run `mole delete`, then type `yes` to confirm. Any other answer cancels. This removes the running Mole program file, saved jobs, recovery data, custom settings, its update download/backup files, and its installation record. Fuel and carried items stay in the turtle, and it does not move.

When Mole replaces a supported startup file, it saves the original and restores it on uninstall. If Mole created startup from scratch, uninstall removes it. Unrelated startup scripts are preserved. If you edit startup after installation, uninstall keeps your edited file; remove any Mole launch line yourself. Existing installations from older versions have no original backup: uninstall can remove recognizable Mole startup, but cannot recover a file that was already overwritten. `mole reset` keeps the installation record and startup backup so you can still uninstall later.

Do not pick up, move, or turn the turtle during a saved job. After a job is finished, you can move it to a new starting corner, put the chest behind it, and run `mole new`. If you paused an unfinished job to start a new one, that abandons the old job; its last state is saved as `quarry-data/previous-job` for reference.

During normal returns, position recovery, and emergency escape, Mole checks its own inventory for allowed fuel before stopping on a fuel limit. It uses carried coal, charcoal, or lava buckets when available and reports the new fuel level. If no usable fuel remains and it cannot continue safely, it keeps the saved return or escape state for retry.

## Keep Mole working while you’re away

If your modpack offers chunk-loading blocks or a tool such as **FTB Chunks**, we recommend using it to keep the whole mining area and starting chest loaded. Mole pauses when its chunk unloads and resumes its saved job when it loads again, using automatic position recovery if movement was interrupted. Keeping the area loaded lets it work while you’re elsewhere, as long as the world or server is running.

## Safety features

- **Saved progress and recovery:** Mole resumes after a restart or chunk reload. After an interrupted move or turn, it checks saved routes without digging and confirms its position at the starting chest. Recovery progress is saved too, so another interruption can be handled. Keep the chest in place and avoid moving or turning the turtle during a job.
- **Safer trips home:** Mole returns when inventory is full or fuel runs low. It uses known tunnels first, then tries to clear or dig around blocked return paths.
- **Fuel reserves:** Mole adjusts its fuel needs for the journey back to work and keeps a return reserve. During returns, recovery, and emergency escape, it can also use fuel carried in its inventory.
- **Protected blocks and valuables:** Mole avoids configured protected blocks and detected machines. It keeps valuable items and normally drops trash only beneath its starting position.
- **Depth guidance:** The starting Y lets Mole suggest a depth ending at Y -62 and warn before deeper mining. You can override this for other dimensions.
- **Emergency escape:** If returning home or finding the chest fails, Mole tries to climb to its starting elevation (or an emergency target saved by an older version), with sideways detours around obstacles. If a full inventory blocks escape, it may discard listed trash while keeping fuel and valuables. At the target, it stays paused for retrieval; use `mole status` to check its progress.

Emergency escape cannot guarantee reaching the surface or getting past every obstacle. If fuel, space, or a safe route runs out, Mole saves its progress and waits for help.

## Change the trash list

Run:

```text
mole settings
```

Choose **1** to ignore a block or **2** to keep it. Enter its full Minecraft block ID, such as `minecraft:stone` or a mod's `modname:block_name`. Choose **3** to see the list. Press Enter to finish.

The starter list contains dirt, stone, cobblestone, gravel, granite, and similar common blocks. Ores and unknown modded blocks are not trash by default.

Choose **4** to turn trash dropping on or off. Turning it off keeps tunnel rubble and unloads it into the chest. When dropping is on, the turtle carries trash home and drops it into the empty space below its starting position before unloading valuable items into the chest. It never drops trash while mining. If the space underneath is blocked or a drop fails, it waits at home for you to clear it, keeping the trash out of the chest. Leave this space open. Dropped items are normal world items, so they may be picked up again.

An ore's block ID and the item it drops can be different. The block ID controls whether the turtle follows it; the item ID controls whether a collected item is discarded. Add both IDs only if you want both ignored/discarded. Allowed fuel items, including coal, charcoal, and lava buckets, are kept even if added to trash.

## If it stops

| Message or problem | What to do |
| --- | --- |
| Not enough fuel | Refill consecutive fuel slots from slot 1 with coal, charcoal, or lava buckets, then run `mole` again. |
| Chest full | Empty the chest, then run `mole` again. |
| No chest behind you during setup | Place it directly behind the turtle at the same height, then press Enter to retry. |
| Protected or unbreakable block | Check what it reported. It tries normal home routes and detours first, then emergency ascent if the return fails. Check `mole status`; a completed emergency escape stays paused for retrieval. |
| Movement interrupted / position uncertain | Run `mole` to attempt automatic chest recovery. If it cannot confirm the chest, it tries emergency ascent; check `mole status`. Keep the original chest in place and other matching chests away from the mining area. |
| Saved job has no valid starting Y | Retrieve the turtle and use `mole reset` to create a new job with its starting Y. |
| Download says file already exists | Follow the update steps below instead of downloading over the existing file. |
| Download says 404 / not found | Check the username, repository name, branch, and filename in the URL. The repository must be public. |
| Downloads are disabled or blocked | Ask the server owner to allow CC: Tweaked HTTP downloads from GitHub's raw file domain. |

Keep the turtle's mining area and chest loaded. The program cannot load chunks itself. The automatic restart file resumes the saved job when the turtle boots; a stopped or paused program may still need you to run `mole`.

## Update Mole

1. Hold Ctrl+T if Mole is running, to return to the command prompt.
2. Type `mole update`.
3. Mole checks the version on GitHub. If a newer version is available, it downloads it, checks that it is a versioned Mole program with valid Lua syntax, and checks the saved download before replacing the program.
4. Type `mole` to resume your saved job. Interrupted movement uses automatic position recovery.

Your job, settings, fuel, inventory, and original startup backup are kept. The previous program is saved as `mole.update-backup`. A failed download leaves the current program in place. If installation fails, Mole tries to restore the previous program. Mole's automatic startup also restores that backup if an interrupted installation leaves the program missing. Custom startup scripts are left alone.

## Config file

Mole stores its settings in `quarry-data/config` on the turtle. Most users can use the setup questions and `mole settings`. For advanced changes, stop Mole with Ctrl+T, then type `edit quarry-data/config`.

The file contains the trash list, allowed fuel items, protected blocks, fuel target and reserves, emergency detour radius and fuel margin, movement retries, and ore-vein search limits. Make a backup before editing, keep the existing format, and save before running `mole` again. Changing dimensions in this file does not resize a saved job; use `mole new` for a different size. `mole reset` restores all default settings and clears the saved job.

## AI disclosure

Mole's code and documentation were generated with OpenAI's ChatGPT, guided by a human who provided requirements and tested the program in Minecraft. It has also been checked with simulated turtle tests. AI-generated code can still contain mistakes, and behavior may vary between modpacks. Test a small quarry before starting a larger job.
