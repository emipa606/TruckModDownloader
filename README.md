# TruckModDownloader

Automatically downloads, unpacks and updates mods for Euro Truck Simulator 2 and American Truck Simulator.

The mod-info is gathered from defined RSS-feeds from atsmods.lt and ets2.lt and the script will move mods to the correct game mod-folder depending on the feed-address.

Version-number is removed from the file-name removing the need to reselect the mod in the game-client after a mod update.

Can be run with the switch -Silent to only update previously downloded mods.

Without the switch it will ask the user when a new mod is found in the RSS-flow.

Requires the Standalone Console-version of 7zip from from https://www.7-zip.org/download.html
