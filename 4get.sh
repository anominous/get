#!/bin/bash
# 4chan image download script - Version 2015/12/15
# Downloads all images from one or multiple boards

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
http_string_text=https
http_string_pictures=https
user_agent='Mozilla/5.0 (Windows NT 10.0; WOW64; rv:42.0) Gecko/20100101 Firefox/42.0'

# files are saved in the board's sub directory, e.g. ~Downloads/4chan/b
download_directory=~/Downloads/4chan

# whitelist: "Download only these threads!"
# case insensitive; supports pattern matching
# https://www.gnu.org/software/bash/manual/html_node/Pattern-Matching.html
# example: "g+(i)rls bo[iy]s something*between"
global_whitelist_enabled=0
global_whitelist=""
# each board can have its own list: append the name of the board, e.g _a, _c, _m ...
# board whitelists override the standard whitelist
whitelist_enabled_a=0
whitelist_a=""

# blacklist: "(But) Don't download these threads!"
# blacklist takes precedence over whitelist
global_blacklist_enabled=0
global_blacklist=""
# board-specific blacklists; they override the standard blacklist
blacklist_enabled_a=0
blacklist_a=""

# miscellaneous options
verbose=0 # shows loop numbers, disk usage, total amount of threads, and previously skipped threads
allowed_filename_characters="A-Za-z0-9_-" # when creating directories, only use these characters
replacement_character="_" # replace unallowed characters with this character
refresh_timer=10 # minimum time to wait between board refreshes; in seconds
hide_blacklisted_threads=1 # do not show blacklisted threads in future loops; verbose overrides this

#############################################################################
# Main script starts below - Only touch this if you know what you're doing! #
#############################################################################
bg_black="40m"; bg_red="41m"; bg_green="42m"; bg_yellow="43m"
bg_blue="44m"; bg_purple="45m"; bg_teal="46m", bg_gray="47m"
bg=$bg_black # adjust background color here

fg_black="\033[0;30;$bg"
fg_dark_gray="\033[1;30;$bg"
fg_dark_red="\033[0;31;$bg"
fg_red="\033[1;31;$bg"
fg_dark_green="\033[0;32;$bg"
fg_green="\033[1;32;$bg"
fg_dark_yellow="\033[0;33;$bg"
fg_yellow="\033[1;33;$bg"
fg_teal="\033[0;36;$bg"
fg_cyan="\033[1;36;$bg"
fg_gray="\033[0;37;$bg"
fg_white="\033[1;37;$bg"

# adjust script colors below
color_script=$fg_dark_yellow
color_message=$fg_cyan
color_thread_watched=$fg_gray
color_hit=$fg_green
color_miss=$fg_dark_gray
color_blacklist=$fg_red
color_404=$fg_dark_red

declare -a blocked # array for blocked threads
declare -a titlelist # array for thread titles
declare -a picturecount # array for a thread's number of picture files

if [ $# -gt 0 ]; then
  boards=$@ # command line arguments override user's boards setting
elif [ "$boards" == "" ]; then
  echo "You must specify a board name."
  exit
fi

timestamp_cleanup=$SECONDS

# fill screen with selected background color
echo -e "\033[$bg"
clear

# MAIN LOOP
###########
while :
do

timestamp_boards=$SECONDS

# BOARDS LOOP
#############
for board in $boards
do

download_dir=$download_directory/$board
mkdir -p $download_dir
if [ ! $? -eq 0 ]; then exit; fi

if [ -v "blacklist_enabled_$board" ]; then blacklist_enabled=$(eval echo "\$blacklist_enabled_$board")
else blacklist_enabled=$global_blacklist_enabled; fi
if [ -v "blacklist_$board" ]; then blacklist=$(eval echo "\$blacklist_$board")
else blacklist=$global_blacklist; fi
if [ -v "whitelist_enabled_$board" ]; then whitelist_enabled=$(eval echo "\$whitelist_enabled_$board")
else whitelist_enabled=$gobal_whitelist_enabled; fi
if [ -v "whitelist_$board" ]; then whitelist=$(eval echo "\$whitelist_$board")
else whitelist=$global_whitelist; fi

# THREADS LOOP INITIALIZATION
#############################
echo -e "$color_script""Target Board: /$board/"
# show size of current board's download directory
if [ $verbose == "1" ]; then echo -e "$color_script$(du -sh $download_dir | cut -f1) in $download_dir"; fi
# download catalog
while :
do
  if [ $verbose == "1" ]; then echo -en "$color_message""Downloading board index ..."; fi
  catalog=$(curl -A "$user_agent" -f -s "$http_string_text://boards.4chan.org/$board/catalog")
  if [[ ${#catalog} -lt 1000 ]]; then
    echo -en "\r$color_message""Could not find the board /$board/. Retrying ..."
    sleep 5
    echo -en "\033[2K\r" # clear whole line
  else
    if [ $verbose == "1" ]; then echo -en "\033[2K\r$color_message""Analyzing catalog ..."; fi
    unset -v grab
    unset -v subs
    unset -v teasers
    IFS=$'\n'
    # grab relevant catalog pieces and analyze them
    grab=($(echo "$catalog" | grep -Po '[0-9][0-9]*?\":.*?\"teaser\".*?\},' | sed -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&\#039;/'/g" -e 's/&amp;\#44;/,/g' -e 's/&amp;/\&/g' -e 's/\\//g'))
    thread_numbers=($(echo "${grab[@]}" | grep -o '[0-9][0-9]*\":' | rev | cut -c3- | rev))
    picture_numbers=($(echo "${grab[@]}" | grep -Po '\"i\":.*?,' | cut -c5- | rev | cut -c2- | rev))
    i=0
    for thread in ${thread_numbers[@]}; do
      subs[$thread]=$(echo ${grab[$i]} | grep -Po 'sub\":\".*?\",\"teaser' | cut -c7- | rev | cut -c10- | rev)
      teasers[$thread]=$(echo ${grab[$i]} | grep -Po 'teaser\":\".*?\"' | cut -c10- | rev | cut -c2- | rev)
      # combine subs and teasers into titles, and remove possible whitespace
      titlelist[$thread]="$(echo "${subs[$thread]} ${teasers[$thread]}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      # make sure titles are not longer than 100 characters
      if [ ${#titlelist[$thread]} -gt 100 ]; then titlelist[$thread]="$(echo ${titlelist[$thread]} | cut -c1-100)..."; fi
      # check if a thread has new pictures
      if [ ! "${picture_numbers[$i]}" == "${picturecount[$thread]}" ]; then
        found_new_pictures[$thread]="1"
        picturecount[$thread]=${picture_numbers[$i]}
      else unset -v "found_new_pictures[$thread]"
      fi
      ((i++)) # count total numbers of threads
    done
    if [ $verbose == "1" ]; then echo -en "\033[2K\r"; fi
    if [ $debug == "1" ]; then
      echo "Grabs: ${#grab[@]}"
      echo "Threads: ${#thread_numbers[@]}"
      echo "Subs: ${#subs[@]}"
      echo "Teasers: ${#teasers[@]}"
    fi
    unset IFS
    # Catalog error protection
    if [ $i -gt 200 ]; then
      echo -en "\r$color_message""Server buggy. Retrying ..."
      sleep 10
      echo -en "\033[2K\r"
      continue
    else
      if [ $verbose == "1" ]; then echo -e "$color_script""Found $i threads"; fi
      echo
      break
    fi
  fi
done

# THREADS LOOP
##############
for thread_number in ${thread_numbers[@]}
do

# show line numbers
if [ $verbose == "1" ]; then echo -en "$color_script$((i--)) $color_thread_watched$thread_number "; fi

# skip current thread loop iteration if thread has been blocked previously
if [[ ${blocked[$thread_number]} == 1 ]]; then
  if [ $verbose == "1" ]; then echo -e "$fg_dark_gray${titlelist[$thread_number]}"; fi
  continue # start next thread iteration
fi

# blacklist & whitelist
set -f # prevent file globbing
title_lower_case=" ${titlelist[$thread_number],,} " # need those spaces
skip=0
# blacklist before whitelist
if [ "$blacklist_enabled" == "1" ] && [ ${#blacklist} -gt 0 ]; then
  for match in ${blacklist,,}; do
    if [[ "$title_lower_case" == *$match* ]]; then
      echo -e "$color_blacklist$match $color_miss${titlelist[$thread_number]}"
      if [ $hide_blacklisted_threads == "1" ] && [ ! $verbose == "1" ]; then blocked[$thread_number]=1; fi
      skip=1
      break
      set +f
    fi
  done
  if [ $skip -eq 1 ]; then continue; fi # start next thread iteration
fi
# whitelist
if [ "$whitelist_enabled" == "1" ] && [ ${#whitelist} -gt 0 ]; then
  skip=1
  for match in ${whitelist,,}; do
    if [[ "$title_lower_case" == *$match* ]]; then
      skip=0
      break
    fi
  done
  # ignore thread permanently if whitelist active, but thread not whitelisted
  if [ $skip -eq 1 ]; then
    echo -e "$color_miss${titlelist[$thread_number]}"
    blocked[$thread_number]=1
    set +f
    continue # start next thread iteration
  fi
fi
set +f # re-enable file globbing

# skip thread iteration if no new pictures
if [ ! "${found_new_pictures[$thread_number]}" == "1" ]; then
  if [ "$whitelist_enabled" == "1" ] && [ ${#whitelist} -gt 0 ]; then echo -en "$color_miss$match "; fi
  echo -e "$color_thread_watched${titlelist[$thread_number]} $color_script[${picturecount[$thread_number]}]"
  continue # start next thread iteration
fi

# else download thread
thread=$(curl -A "$user_agent" -f -s $(echo $thread_number | sed 's/^/'$http_string_text':\/\/boards.4chan.org\/'$board'\/res\//g'))
# do nothing more if thread is 404'd
if [ ${#thread} -eq 0 ]
then echo -e "$color_404""404 Not Found"
# else try to save thread's images
else
  # show user the thread is updated, with colors and "*"
  if [ "$whitelist_enabled" == "1" ] && [ ${#whitelist} -gt 0 ]; then echo -en "$color_hit$match "; else echo -en "$color_hit""* "; fi

  # get real thread title from the downloaded file
  title=$(echo $thread | grep -Po '<meta name="description" content=".*? \- \&quot;' | cut -c35- | rev | cut -c 10- | rev | sed -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&\#039;/'/g" -e 's/&amp;\#44;/,/g' -e 's/&amp;/\&/g')
  echo -en "$color_thread_watched$title $color_script[${picturecount[$thread_number]}] "

  # convert thread title into filesystem compatible format
  title_dir=$(echo "$title" | sed -e 's/[^'$allowed_filename_characters']/'$replacement_character'/g')
  mkdir -p $download_dir/$title_dir
  cd $download_dir/$title_dir

  # search thread for images & download
  files=$(echo $thread | grep -Po //i\.4cdn\.org/$board/[0-9][0-9]*?\.\("$file_types"\) | sort -u | sed 's/^/'$http_string_pictures':/g')
  if [ ${#files} -gt 0 ]; then
    # create download queue, only new files
    queue=""
    number_of_new_files=0
    for file in $files; do
      if [ ! -e $(basename $file) ]; then
        queue+="$file
        " # inserting a new line
        ((number_of_new_files++))
      fi
    done
    # download files in background processes
    if [ $number_of_new_files -gt 0 ]; then
      echo -e "$color_hit[+$number_of_new_files]"
      echo "$queue" | xargs -n 1 -P $cores curl -A "$user_agent" -O -f -s &
      # wait before the next thread iteration if too many downloads
      if [ $max_downloads -gt 0 ]; then
        download_count=$(ps -C curl --no-heading | wc -l)
        until [ $download_count -lt $max_downloads ]; do
          echo -en "\r$color_message""Download limit reached [$download_count/$max_downloads]. Waiting ..."
          sleep 1
          download_count=$(ps -C curl --no-heading | wc -l)
        done
        echo -en "\033[2K\r"
      fi
    else echo
    fi
  else echo
  fi
fi

done # threads loop end
echo

done # boards loop end

if [ $refresh_timer -gt 0 ]; then
  while (($SECONDS - $timestamp_boards < $refresh_timer)); do
    echo -en "\033[1K\r$color_message""Waiting $(($refresh_timer - $SECONDS + $timestamp_boards))"
    sleep 1
  done
  echo -en "\033[2K\r"
fi

# clean up arrays periodically (24h)
if (($SECONDS - $timestamp_cleanup > 86400)); then
  unset -v blocked
  unset -v titlelist
  unset -v picturecount
  unset -v found_new_pictures
  timestamp_cleanup=$SECONDS
fi

done # main loop end
