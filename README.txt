---------------------------------------------------------------------------------
-- 
-- Arcade: Pacman port to MiSTer by Sorgelig
-- 09 November 2017
-- 
---------------------------------------------------------------------------------
-- A simulation model of Pacman hardware
-- Copyright (c) MikeJ - January 2006
---------------------------------------------------------------------------------
-- 
-- Support screen and controls rotation on HDMI output.
-- Only controls are rotated on VGA output.
-- 
-- 
-- Keyboard inputs :
--
--   F1          : Start Player 1
--   F2          : Start Player 2
--   F3		 : Coin Player 1
--   F5          : Skip to next level
--
-- MAME/IPAC/JPAC Style Keyboard inputs:
--   5           : Coin 1
--   6           : Coin 2
--   1           : Start 1 Player
--   2           : Start 2 Players
--   R,F,D,G     : Player 2 Movements
--
--   UP,DOWN,LEFT,RIGHT arrows : Movements
--
-- Joystick support.
-- 
----------------------------------------------

Hiscore save/load:

Save and load of hiscores is supported for the following games on this core:
 - Alibaba 40 Thieves
 - Crush Roller
 - Dream Shopper
 - Eggor
 - Gorkans
 - Lizard Wizard
 - Mr. TNT
 - Ms. Pacman
 - Pac-Man (Midway)
 - Pacman Club
 - Pacman Plus
 - Ponpoko
 - Puck Man
 - Woodpecker

To save your hiscores manually, press the 'Save Settings' option in the OSD.  Hiscores will be automatically loaded when the core is started.

To enable automatic saving of hiscores, turn on the 'Autosave Hiscores' option and press the 'Save Settings' option in the OSD.  Hiscores will then be automatically saved (if they have changed) any time the OSD is opened.

Hiscore data is stored in /media/fat/config/nvram/ as ```<mra filename>.nvm```

---------------------------------------------------------------------------------

                                 *** Attention ***

ROMs are not included. In order to use this arcade, you need to provide the
correct ROMs.

To simplify the process .mra files are provided in the releases folder, that
specifies the required ROMs with checksums. The ROMs .zip filename refers to the
corresponding file of the M.A.M.E. project.

Please refer to https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms for
information on how to setup and use the environment.

Quickreference for folders and file placement:

/_Arcade/<game name>.mra
/_Arcade/cores/<game rbf>.rbf
/_Arcade/mame/<mame rom>.zip
/_Arcade/hbmame/<hbmame rom>.zip
