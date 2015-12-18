####4chan image download script
Download all images from multiple boards. Supports blacklisting and whitelisting. This script works great on a Raspberry Pi 2, and it should also run on NAS devices.

All you need is a Unix OS with Bash and cURL installed.
```
sudo apt-get install curl
```
####Quick Start
The default download directory is ~/Downloads/4chan.
You may want to take your time to adjust your download directory inside the script. There are various other options you might want to change.
If you run a virtual terminal, make sure you use Bash. The script uses Bash-only functions and will most likely break in other shells.

Then run the script like this:
```
./4get.sh BOARD BOARD BOARD ...
```
Where BOARD is just the board's letters, e.g. a for /a/ (Anime & Manga).
```
./4get.sh a b c ...
```
When a board runs for the first time, it may take a while. But subsequent loops are generally much faster.

Cancel it with CTRL-C.

######What do all those signs mean?
```
Start of a line:
[ ] The thread has been skipped
[!] The thread has been blacklisted (the first word after this is the matching blacklist entry)
[*] The thread is watched, but no new images have been found
[+] The thread is watched, and has new images

End of a line:
[+number] Number of new images that are downloaded
[-] The thread has new images, but they are of a type you don't want to download
```

####Advanced Options
Say you only want to download wallpapers and artwork.
Then just add "wallpapers artwork" to the whitelist:
```
whitelist="wallpapers artwork"
```
"Whitelist" here means all threads which don't contain either "wallpapers" or "artwork" are ignored.
You can further limit this with a blacklist. If you don't want to download Naruto images, then just add "naruto" to the blacklist:
```
blacklist="naruto"
```
Then wallpapers and artwork are still downloaded, but only if the thread title does not contain "naruto".
Upper or lower case don't matter.

You can use pattern matching to further refine your lists. See a manual at
https://www.gnu.org/software/bash/manual/html_node/Pattern-Matching.html#Pattern-Matching
In case you wonder, inside the script all list items are converted to lower case and automatically embedded in "*" characters.

Donald Duck, Daisy Duck, and Scrooge McDuck, but no other Ducks?
```
+(Donald|Daisy|Scrooge)*Duck
```
Something short like "no", but make sure it's a single word?
```
[[:space:]]no[[:space:][:punct:]]
```
https://en.wikipedia.org/wiki/Regular_expression#Character_classes

You can also create board-specific lists. Just append _BOARD at the end, e.g.
```
whitelist_a="download this"
blacklist_a="i hate this"
```
for board /a/.

The global lists "whitelist" and "blacklist" are automatically merged with existing board-specific lists.
If you want to disable lists without deleting them, just comment them:
```
Active:
whitelist="download this"
blacklist_a="dragonball"

Disabled:
#whitelist="download this"
#blacklist_a="dragonball"
```

####Tips
While the multi board option is useful for your average boards, some boards are very active and get updates every few seconds. You might want to run them in separate terminals or background processes:
```
./4get.sh a &> /dev/null &
./4get.sh b &> /dev/null &
...
```
If you try this and don't know how to terminate them, use
```
killall 4get.sh
```
