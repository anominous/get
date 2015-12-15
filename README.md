# image-download-script
4chan image download script - download all images from multiple boards in no time (provided your connection can handle it)

All you need a Unix OS with Bash and cURL installed.
This script works great on a Raspberry Pi 2.
sudo apt-get install curl

Quick Start
-----------
The default download directory is ~/Downloads/4chan.
You may want to take your time to adjust your download directory inside the script. There are various other options you might want to change.
If you run a virtual terminal, make sure you use Bash. The script uses Bash-only functions and will most likely break in other shells.

Then run the script like this:

./4get.sh BOARD BOARD BOARD ...

Where BOARD is just the board's letters, e.g. a for /a/ (Anime & Manga).

./4get.sh a b c ...

Cancel it with CTRL-C.
