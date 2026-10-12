# Mole 1.4.3

[GitHub repository](https://github.com/Nom4d-temp/mole)

**Meet Mole: your turtle’s next mining adventure.** Mole turns a CC: Tweaked mining turtle into a tunnel miner that searches for nearby ores while leaving ordinary stone in place wherever possible. Answer a few setup questions, give it a chest and some fuel, and let it get to work.

Mole follows connected ore veins, brings its haul back to your chest, and manages refueling and trash disposal. Saved progress and automatic recovery help it pick up after interruptions, while simple commands let you change settings, start a new quarry, or update straight from GitHub.

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

If starting Y is known, Mole also asks for an optional **emergency target Y**. Leave it blank to use the starting elevation, or enter a higher Y for a known retrieval level in your dimension. This does not detect open sky, and a starting elevation can still be underground.

Mole saves its starting position and creates an automatic restart file. Your settings and progress are saved for the next time it runs.

If you already use your own startup program, the miner keeps it. To make that existing program resume mining, add `shell.run("mole")` to it.

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

While the miner is running, hold **Ctrl+T** to stop the program. Then type `mole return` if you want it to go home. Stopping can leave a move unfinished in the save file; automatic chest recovery handles this on the next launch.

**Starting over after a problem:** run `mole reset`. This permanently clears the current job, saved routes, recovery information, previous-job archive, and custom settings, even if a saved file is damaged. It does not move the turtle or change its fuel or inventory. The program and startup file stay installed. Place the turtle at a safe starting corner with the chest behind it, then run `mole` for the normal setup questions.

**Uninstalling:** run `mole delete`, then type `yes` to confirm. Any other answer cancels. This removes the running Mole program file, saved jobs, recovery data, custom settings, its update download/backup files, and its installation record. Fuel and carried items stay in the turtle, and it does not move.

When Mole replaces a supported startup file, it saves the original and restores it on uninstall. If Mole created startup from scratch, uninstall removes it. Unrelated startup scripts are preserved. If you edit startup after installation, uninstall keeps your edited file; remove any Mole launch line yourself. Existing installations from older versions have no original backup: uninstall can remove recognizable Mole startup, but cannot recover a file that was already overwritten. `mole reset` keeps the installation record and startup backup so you can still uninstall later.

Do not pick up, move, or turn the turtle during a saved job. After a job is finished, you can move it to a new starting corner, put the chest behind it, and run `mole new`. If you paused an unfinished job to start a new one, that abandons the old job; its last state is saved as `quarry-data/previous-job` for reference.

During normal returns, chest recovery, and emergency escape, Mole checks its own inventory for allowed fuel before stopping on a fuel limit. It uses carried coal, charcoal, or lava buckets when available and reports the new fuel level. Refueling happens before recording the next movement, so interrupted-move recovery remains consistent. If no usable fuel remains and it cannot continue safely, it keeps the saved return or escape state for retry.

## Emergency ascent

If normal home-return routes, return excavation, or chest recovery fail, Mole can switch to a last-resort ascent. It first tries straight up, then tries sideways detours around protected or unbreakable ceilings. Detours stay within eight blocks along each horizontal axis from the emergency navigation anchor and never descend. This can leave the chosen quarry area, so keep it away from builds.

The default destination is the starting elevation. If you entered a starting Y, you can choose a higher emergency target Y during setup. Reaching that height does **not** prove the turtle is above ground. If recovery leaves two possible heights, it uses the deeper estimate, so it may finish slightly above the target.

Emergency movement is saved separately and resumes after a restart. Valuable items are kept. If a full inventory blocks emergency digging, Mole attempts to discard listed trash—even if ordinary trash dropping is off—until two slots are free. It tries below, then in front and above, and can attempt a drop against ordinary stone. Detected inventories, protected blocks, and unknown solid blocks are avoided. Fuel and non-trash items are kept. This is a last-resort exception to normal chest-only disposal. If dropping fails or no disposable trash remains, it saves progress and waits for help. Mole still respects protected blocks and detected machines. It stops with saved progress if fuel is insufficient, inventory cannot accept mined blocks, or no detour fits the available fuel and radius. It cannot escape every obstruction.

After reaching the target, Mole stays paused for retrieval and never automatically resumes the old mining job. `mole status` shows the emergency reason and remaining climb. Retrieve the turtle, position it at a safe starting point, then use `mole reset` and `mole` to begin again; reset permanently clears the old job.

## Refueling with lava buckets

Lava buckets are accepted alongside coal and charcoal. On the first chest visit, Mole records the consecutive fuel slots starting at slot 1; the first empty or non-fuel slot ends that initial area. During later visits, it keeps remaining fuel together at the front of that area, moving returned buckets and output out of its way. It consumes only enough to reach its preferred target.

Empty buckets stay onboard until the refueling pass finishes, then return to the chest. With a supported chest, Mole reorganizes the remaining fuel automatically, so returned buckets and used-up slots do not require routine manual tidying. Leave an empty chest slot for rearrangement and enough room for the haul. Inventories without rearrangement support retain the simple fuel-prefix behavior and may need manual tidying. On the first visit after upgrading an older job, arrange fuel at the front once to establish the managed area.

If the preferred target cannot be reached, Mole can continue when its safe minimum is satisfied. Chest changes or extraction mismatches still stop refueling rather than being treated as a harmless fuel shortage.

Existing configurations gain lava-bucket support once; an explicitly disabled lava-bucket entry is preserved. You can edit allowed fuels in the config file. Mole does not collect lava from the world or refill buckets itself.

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
| Starting chest not found during recovery | Mole attempts its emergency ascent if chest recovery fails. Use `mole status` to check the escape progress, then retrieve the turtle. It uses a conservative height estimate and keeps the old job suspended. |
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

If you need to restore the backup manually, remove the faulty `mole` file, then run `move mole.update-backup mole`. This restores the program only; it does not roll back your job or settings. Syntax checks cannot guarantee a new release is free of bugs. Do not downgrade to a version without emergency-ascent support while an emergency/rescued save exists; retrieve and reset the turtle with the current version first.

**Installing this updater for the first time:** versions before 1.3.7 need one manual update. Stop Mole, rename the old file with `move mole mole-backup` (choose another backup name if needed), then download:

```text
wget https://raw.githubusercontent.com/Nom4d-temp/mole/main/mole.lua mole
```

Run `mole` once. Future updates can use `mole update`. Updates become available when the newer `mole.lua` is uploaded to the repository's `main` branch.

## Config file

Mole stores its settings in `quarry-data/config` on the turtle. Most users can use the setup questions and `mole settings`. For advanced changes, stop Mole with Ctrl+T, then type `edit quarry-data/config`.

The file contains the trash list, allowed fuel items, protected blocks, fuel target and reserves, emergency detour radius and fuel margin, movement retries, and ore-vein search limits. Make a backup before editing, keep the existing format, and save before running `mole` again. Changing dimensions in this file does not resize a saved job; use `mole new` for a different size. `mole reset` restores all default settings and clears the saved job.

## AI disclosure

Mole's code and documentation were generated with OpenAI's ChatGPT, guided by a human who provided requirements and tested the program in Minecraft. It has also been checked with simulated turtle tests. AI-generated code can still contain mistakes, and behavior may vary between modpacks. Test a small quarry before starting a larger job.





