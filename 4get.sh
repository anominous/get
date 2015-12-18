#!/bin/bash
# 4chan image download script - version 2015/12/18-2
# downloads all images from one or multiple boards
# latest version at https://github.com/anominous/4get

# number of CPU cores
cores=4

# limit the number of background download processes; 0 means no limit
max_downloads=20

# board(s) to download, e.g. boards="a c m" for /a/, /c/, and /m/
# command line arguments override this
boards=""

# file types to download, separated by "|"
# example: "jpg|png|gif|webm"
file_types="jpg|png|gif|webm"

# http is less CPU demanding and downloads faster than https, but others might see your downloads
http_string_text=https # used for text file downloads
http_string_pictures=https # used for image downloads
user_agent='Mozilla/5.0 (Windows NT 10.0; WOW64; rv:43.0) Gecko/20100101 Firefox/43.0'

# files are saved in the board's sub directory, e.g. ~Downloads/4chan/b
# the directories are automatically created
download_directory=~/Downloads/4chan

# whitelist: "Download only these threads!"
# case insensitive; supports pattern matching
# https://www.gnu.org/software/bash/manual/html_node/Pattern-Matching.html
# example: "g+(i)rls bo[iy]s something*between"
global_whitelist_enabled=0
global_whitelist=""
# each board can have its own list: append the name of the board, e.g _a, _c, _m ...
# board whitelists override the global whitelist
whitelist_enabled_a=0
whitelist_a=""

# blacklist: "(But) Don't download these threads!"
# blacklist takes precedence over whitelist
global_blacklist_enabled=0
global_blacklist=""
# board-specific blacklists; they override the global blacklist
blacklist_enabled_a=0
blacklist_a=""

# color themes: you can choose one of the default color themes (black or blue)
# or you can create one yourself in the source code below
# leave empty to not use any colors
color_theme=black

# miscellaneous options
hide_blacklisted_threads=0 # do not show blacklisted threads in future loops; verbose overrides this
verbose=0 # shows loop numbers, disk usage, total amount of threads, and previously skipped threads
allowed_filename_characters="A-Za-z0-9_-" # when creating directories, only use these characters
replacement_character="_" # replace unallowed characters with this character
loop_timer=10 # minimum time to wait between board loops; in seconds
max_title_length=62 # dispayed title length (in characters) - this does not change internal values

#############################################################################
# Main script starts below - Only touch this if you know what you're doing! #
#############################################################################
if [ $# -gt 0 ]; then
  boards=$@ # command line arguments override user's boards setting
elif [ "$boards" == "" ]; then
  echo "You must specify one or multiple board names:"
  echo "$0 a b c [...]"
  exit
fi

# foreground colors                            # background colors
fg_black="\e[30m";  fg_gray_dark="\e[90m";     bg_black="\e[40m";  bg_gray_dark="\e[100m"
fg_red="\e[31m";    fg_red_bright="\e[91m";    bg_red="\e[41m";    bg_red_bright="\e[101m"
fg_green="\e[32m";  fg_green_bright="\e[92m";  bg_green="\e[42m";  bg_green_bright="\e[102m"
fg_yellow="\e[33m"; fg_yellow_bright="\e[93m"; bg_yellow="\e[43m"; bg_yellow_bright="\e[103m"
fg_blue="\e[34m";   fg_blue_bright="\e[94m";   bg_blue="\e[44m";   bg_blue_bright="\e[104m"
fg_purple="\e[35m"; fg_purple_bright="\e[95m"; bg_purple="\e[45m"; bg_purple_bright="\e[105m"
fg_teal="\e[36m";   fg_teal_bright="\e[96m";   bg_teal="\e[46m";   bg_teal_bright="\e[106m"
fg_gray="\e[37m";   fg_white="\e[97m";         bg_gray="\e[47m";   bg_white="\e[107m"

case $color_theme in
black)
  bg=$bg_black
  color_script=$fg_yellow
  color_patience=$fg_teal_bright
  color_watched=$fg_gray
  color_skipped=$fg_gray_dark
  color_whitelist=$fg_green_bright
  color_blacklist=$fg_red_bright
  ;;
blue)
  bg=$bg_blue
  color_script=$fg_teal_bright
  color_patience=$fg_white
  color_watched=$fg_white
  color_skipped=$fg_gray
  color_whitelist=$fg_green_bright
  color_blacklist=$fg_red_bright
  ;;
*) # else do not use any colors
  bg="\e[49m"; color_script=""; color_patience=""; color_watched=""
  color_skipped=""; color_whitelist=""; color_blacklist=""
  ;;
esac

# these arrays are accessible by thread number
declare -a blocked # blocked thread
declare -a title_list # thread title (headline + content)
declare -a displayed_title_list # displayed title which respects $max_title_length
declare -a cached_picture_count # thread's cached total number of picture files
declare -a has_new_pictures # thread is known to have new pictures

# crucial variable checks
if [ ! -v download_directory ]; then
  echo "Missing variable \"download_directory\"."
  echo "Open the script and create the variable like this:"
  echo "download_directory=/path/to/your/download/directory"
  exit;
fi
if [ ! -v cores ]; then cores=1; fi
if [ ! -v max_downloads ]; then max_downloads=20; fi
if [ ! -v file_types ]; then file_types="jpg|png|gif|webm"; fi
if [ ! -v http_string_text ]; then http_string_text=https; fi
if [ ! -v http_string_images ]; then http_string_images=https; fi
if [ ! -v allowed_filename_characters ]; then allowed_filename_characters="A-Za-z0-9_-"; fi
if [ ! -v replacement_character ]; then replacement_character="_"; fi
if [ ! -v loop_timer ]; then loop_timer=10; fi
if [ ! -v max_title_length ] || [ $max_title_length -lt 1 ]; then max_title_length=62; fi

function matchcut() {
  #  properly trims and displays thread titles
  #+ when blacklist/whitelist matches are displayed on the same line
  remaining_space=$((max_title_length-${#match}-1))
  if [ $remaining_space -gt 0 ]
  then echo "$1" | cut -c1-$remaining_space
  else echo "..."
  fi
}

# activate selected background color
echo -e "$bg"
if [ ! $debug == "1" ]; then
  if [ ! "$bg" == '\e[49m' ]; then clear; fi
fi

timestamp_cleanup=$SECONDS # for cleanup procedure at the end of the script

# MAIN LOOP
###########
while :
do

timestamp_boards=$SECONDS # for $loop_timer

# BOARDS LOOP
#############
for board in $boards
do

# try to create download directory; exit on error
download_dir=$download_directory/$board
mkdir -p $download_dir
if [ ! $? -eq 0 ]; then exit; fi

# check for existing custom board lists
if [ -v "blacklist_enabled_$board" ]
then blacklist_enabled=$(eval echo "\$blacklist_enabled_$board")
else blacklist_enabled=$global_blacklist_enabled
fi
if [ -v "blacklist_$board" ]
then blacklist=$(eval echo "\$blacklist_$board")
else blacklist=$global_blacklist
fi
if [ -v "whitelist_enabled_$board" ]
then whitelist_enabled=$(eval echo "\$whitelist_enabled_$board")
else whitelist_enabled=$gobal_whitelist_enabled
fi
if [ -v "whitelist_$board" ]
then whitelist=$(eval echo "\$whitelist_$board")
else whitelist=$global_whitelist
fi

# THREADS LOOP INITIALIZATION
#############################
echo -e "$color_script""Target Board: /$board/"
# show size of current board's download directory
if [ $verbose == "1" ]; then echo -e "$color_script$(du -sh $download_dir | cut -f1) in $download_dir"; fi
# download catalog
while :
do
  catalog=$(curl -A "$user_agent" -f -s "$http_string_text://boards.4chan.org/$board/catalog")
  if [[ "${#catalog}" -lt 1000 ]]; then
    echo -en "\r$color_patience""Could not find the board /$board/. Retrying ... "
    sleep 5
    echo -en "\033[2K\r" # clear whole line
  else
    echo -en "\033[2K\r$color_patience""Analyzing board index ... "
    unset -v title_list
    unset -v displayed_title_list
    unset -v has_new_pictures
    IFS=$'\n' # necessary to create lines for sed
    # grab relevant catalog pieces, cut & split them; replace HTML entities
    grabs=($(echo "$catalog" | grep -Po '[0-9][0-9]*?\":.*?\"teaser\".*?\},' | sed -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&\#039;/'/g" -e 's/&amp;\#44;/,/g' -e 's/&amp;/\&/g' -e 's/\\//g'))
    thread_numbers=$(echo "${grabs[*]}" | sed 's/":.*$//')
    current_picture_count=($(echo "${grabs[*]}" | sed -e 's/^.*"i"://' -e 's/,.*$//'))
    subs=($(echo "${grabs[*]}" | sed -e 's/^.*sub":"//' -e 's/","teaser.*$//' -e 's/^/ /')) # last sed: insert a space character in case the sub is emtpy
    teasers=($(echo "${grabs[*]}" | sed -e 's/^.*teaser":"//' -e 's/"}\+,.*$//' -e 's/$/ /')) # see above
    unset IFS
    i=0
    for thread_number in $thread_numbers; do
      # combine subs and teasers into titles, and remove whitespace
      title_list[$thread_number]="$(echo "${subs[$i]} ${teasers[$i]}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      # make sure displayed titles are not longer than user specified length
      if [ ${#title_list[$thread_number]} -gt $max_title_length ]; then
        displayed_title_list[$thread_number]="$(echo "${title_list[$thread_number]}" | cut -c1-$((max_title_length)))"
      else displayed_title_list[$thread_number]="${title_list[$thread_number]}"
      fi
      # check if a thread has new pictures
      if [ ! "${current_picture_count[$i]}" == "${cached_picture_count[$thread_number]}" ]; then
        has_new_pictures[$thread_number]="1"
        cached_picture_count["$thread_number"]="${current_picture_count[$i]}"
      else unset -v has_new_pictures[$thread_number]
      fi
      ((i++)) # count total numbers of threads
    done
    # catalog error protection
    if [ $i -gt 200 ]; then
      echo -en "\033[2K\r$color_patience""Server buggy. Retrying ... "
      sleep 5
      continue
    else
      echo -en "\033[2K\r"
      if [ $debug == "1" ]; then
        echo "Grabs: ${#grabs[@]}"
        echo "Subs: ${#subs[@]}"
        echo "Teasers: ${#teasers[@]}"
      fi
      if [ $verbose == "1" ]; then echo -e "$color_script""Found $i threads"; fi
      echo
      break
    fi
  fi
done

# THREADS LOOP
##############
for thread_number in $thread_numbers
do

# show line numbers
if [ $verbose == "1" ]; then 
  if [ $i -lt 100 ]; then echo -en "$color_script""0"; fi
  if [ $i -lt 10 ]; then echo -en "$color_script""0"; fi
  echo -en "$color_script$((i--)) $color_watched$thread_number "
fi

# skip current thread loop iteration if thread has been blocked previously
if [[ ${blocked[$thread_number]} == 1 ]]; then
  if [ $verbose == "1" ]; then echo -e "$color_skipped[ ] ${displayed_title_list[$thread_number]} $color_skipped[${cached_picture_count[$thread_number]}]"; fi
  continue # start next thread iteration
fi

# blacklist & whitelist
title_lower_case=" ${title_list[$thread_number],,} " # need those spaces for matching
skip=0
# blacklist before whitelist
if [ "$blacklist_enabled" == "1" ] && [ ${#blacklist} -gt 0 ]; then
  set -f # prevent file globbing
  for match in ${blacklist,,}; do
    if [[ "$title_lower_case" == *$match* ]]; then
      echo -e "$color_blacklist[!] $match $color_skipped$(matchcut "${displayed_title_list[$thread_number]}") $color_skipped[${cached_picture_count[$thread_number]}]"
      if [ $hide_blacklisted_threads == "1" ] && [ ! $verbose == "1" ]; then blocked[$thread_number]=1; fi
      skip=1
      set +f
      break
    fi
  done
  if [ $skip -eq 1 ]; then continue; fi # start next thread iteration
fi
# whitelist
if [ "$whitelist_enabled" == "1" ] && [ ${#whitelist} -gt 0 ]; then
  skip=1
  set -f
  for match in ${whitelist,,}; do
    if [[ "$title_lower_case" == *$match* ]]; then
      skip=0
      break
    fi
  done
  # ignore thread permanently if whitelist active, but thread not whitelisted
  if [ $skip -eq 1 ]; then
    echo -e "$color_skipped[ ] ${displayed_title_list[$thread_number]} $color_skipped[${cached_picture_count[$thread_number]}]"
    blocked[$thread_number]=1
    set +f
    continue # start next thread iteration
  fi
fi

# skip thread iteration if no new pictures
if [ ! "${has_new_pictures[$thread_number]}" == "1" ]; then
  if [ "$whitelist_enabled" == "1" ] && [ ${#whitelist} -gt 0 ]
  then echo -e "$color_skipped[*] $match $color_watched$(matchcut "${displayed_title_list[$thread_number]}") [${cached_picture_count[$thread_number]}]"
  else echo -e "$color_skipped[ ] $color_watched${displayed_title_list[$thread_number]} [${cached_picture_count[$thread_number]}]"
  fi
  continue # start next thread iteration
fi

# show user the thread is going to be updated
echo -en "$color_whitelist[+] "
if [ "$whitelist_enabled" == "1" ] && [ ${#whitelist} -gt 0 ]
then echo -en "$match "
fi
# download thread
thread=$(curl -A "$user_agent" -f -s $(echo "$thread_number" | sed 's/^/'$http_string_text':\/\/boards.4chan.org\/'$board'\/res\//g'))
# do nothing more if thread is 404'd
if [ ${#thread} -eq 0 ]
then echo -e "$color_blacklist""404 Not Found"
# else try to save thread's images
else
  # get real thread title from the downloaded file
  title=$(echo "$thread" | sed -e 's/^.*<meta name="description" content="//' -e 's/ - &quot;\/.*$//' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&\#039;/'/g" -e 's/&amp;\#44;/,/g' -e 's/&amp;/\&/g')
  echo -en "$color_watched$(matchcut "$title") [${cached_picture_count[$thread_number]}] "

  # convert thread title into filesystem compatible format
  title_dir=$(echo "$title" | sed -e 's/[^'$allowed_filename_characters']/'$replacement_character'/g')
  mkdir -p $download_dir/$title_dir
  cd $download_dir/$title_dir

  # search thread for images & download
  files=$(echo "$thread" | grep -Po //i\.4cdn\.org/$board/[0-9][0-9]*?\.\("$file_types"\) | sort -u | sed 's/^/'$http_string_images':/g')
  if [ ${#files} -gt 0 ]; then
    # create download queue, only new files
    queue=""
    number_of_new_files=0
    for file in $files; do
      if [ ! -e $(basename $file) ]; then
        queue+="$file
        " # inserting a source code new line
        ((number_of_new_files++))
      fi
    done
    # download files in background processes
    if [ $number_of_new_files -gt 0 ]; then
      echo -e "$color_whitelist[+$number_of_new_files]"
      echo "$queue" | xargs -n 1 -P $cores curl -A "$user_agent" -O -f -s &
      # wait before the next thread iteration if too many downloads
      if [ $max_downloads -gt 0 ]; then
        download_count=$(ps -C curl --no-heading | wc -l)
        until [ $download_count -lt $max_downloads ]; do
          echo -en "\r$color_patience""Download limit reached [$download_count/$max_downloads]. Waiting ... "
          sleep 1
          download_count=$(ps -C curl --no-heading | wc -l)
        done
        echo -en "\033[2K\r"
      fi
    else echo -e "$color_whitelist[-]"
    fi
  else echo
  fi
fi

done # threads loop end
echo

done # boards loop end

if [ $loop_timer -gt 0 ]; then
  while (($SECONDS - $timestamp_boards < $loop_timer)); do
    echo -en "\033[1K\r$color_patience""Waiting $(($loop_timer - $SECONDS + $timestamp_boards)) "
    sleep 1
  done
  echo -en "\033[2K\r"
fi

# clean up arrays periodically (24h)
if (($SECONDS - $timestamp_cleanup > 86400)); then
  unset -v blocked
  unset -v cached_picture_count
  timestamp_cleanup=$SECONDS
fi

done # main loop end
