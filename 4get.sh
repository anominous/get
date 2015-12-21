#!/bin/bash
# 4chan image download script
# downloads all images from one or multiple boards
# latest version at https://github.com/anominous/4get

# board(s) to download, e.g. boards="a b c" for /a/, /b/, and /c/
# command line arguments override this
boards=""

# files are saved in the board's sub directory, e.g. ~Downloads/4chan/b
# the directories are automatically created
download_directory=~/Downloads/4chan

# file types to download, separated by "|" (if more than one type)
# board-specific lists: file_types_a, file_types_b, ...
# example: "jpg|png|gif|webm"
file_types="jpg|png|gif|webm"

# http is less CPU demanding and downloads faster than https, but others might see your downloads
http_string_text=https # used for text file downloads
http_string_pictures=https # used for image downloads
user_agent='Mozilla/5.0 (Windows NT 10.0; WOW64; rv:43.0) Gecko/20100101 Firefox/43.0'

# whitelists and blacklists are case insensitive
# they support pattern matching: https://www.gnu.org/software/bash/manual/html_node/Pattern-Matching.html
# example: "g+(i)rls bo[iy]s something*between"

# whitelist: "Download only this!"
# board-specific lists: whitelist_a, whitelist_b, ...
whitelist=""

# blacklist: "(But) Don't download this!"
# board-specific lists: blacklist_a, blacklist_b, ...
blacklist=""

# color themes: you can choose one of the default color themes (black or blue)
# or you can create a theme yourself in the source code below
# leave empty to not use any colors
color_theme=black

# miscellaneous options
downloads_per_thread=4 # number of simultaneous download processes per 4chan thread
max_downloads=12 # limits total number of download processes; 0 means no limit (careful!)
max_crawl_jobs=4 # maximum number of threads (with new images) being analyzed at the same time (careful!)
min_images=0 # minimum amount of images a thread must have; note that OP's image counts as zero
hide_blacklisted_threads=0 # do not show blacklisted threads in future loops; verbose overrides this
verbose=1 # shows disk usage, total amount of threads, previously skipped/blacklisted threads
allowed_filename_characters="A-Za-z0-9_-" # when creating directories, only use these characters
replacement_character="_" # replace unallowed characters with this character
loop_timer=15 # minimum time to wait between board loops; in seconds
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
  color_front=$fg_gray
  color_back=$fg_gray_dark
  color_patience=$fg_yellow
  color_whitelist=$fg_green_bright
  color_blacklist=$fg_red_bright
  ;;
blue)
  bg=$bg_blue
  color_front=$fg_white
  color_back=$fg_teal
  color_patience=$fg_teal_bright
  color_whitelist=$fg_green_bright
  color_blacklist=$fg_red_bright
  ;;
*) # else do not use any colors
  bg="\e[49m"; color_front=""; color_patience=""; color_front=""
  color_back=""; color_whitelist=""; color_blacklist=""
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
if [ ! -v downloads_per_thread ]; then downloads_per_thread=4; fi
if [ ! -v max_downloads ]; then max_downloads=12; fi
if [ ! -v max_crawl_jobs ]; then max_crawl_jobs=4; fi
if [ ! -v min_images ]; then min_images=0; fi
if [ ! -v file_types ]; then file_types="jpg|png|gif|webm"; fi
if [ ! -v http_string_text ]; then http_string_text=https; fi
if [ ! -v http_string_images ]; then http_string_images=https; fi
if [ ! -v allowed_filename_characters ]; then allowed_filename_characters="A-Za-z0-9_-"; fi
if [ ! -v replacement_character ]; then replacement_character="_"; fi
if [ ! -v loop_timer ]; then loop_timer=15; fi
if [ ! -v max_title_length ] || [ $max_title_length -lt 1 ]; then max_title_length=62; fi

function matchcut {
  #  properly trims and displays thread titles
  #+ when blacklist/whitelist matches are displayed on the same line
  remaining_space=$((max_title_length-${#match}-1))
  if [ $remaining_space -gt 0 ]
  then displayed_title_list[$thread_number]=$(echo "${displayed_title_list[$thread_number]}" | cut -c1-$remaining_space)
  else displayed_title_list[$thread_number]="..."
  fi
}

# activate selected background color
echo -e "$bg"
if [ ! "$debug" == "1" ]; then
  if [ ! "$bg" == '\e[49m' ]; then clear 2> /dev/null; fi
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
download_dir="$download_directory/$board"
mkdir -p "$download_dir"
if [ ! $? -eq 0 ]; then exit; fi

# check for board-specific lists
if [ -v blacklist_$board ]
then internal_blacklist="$blacklist $(eval echo "\$blacklist_$board")"
else internal_blacklist="$blacklist"
fi
internal_blacklist=$(echo "$internal_blacklist" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
if [ -v whitelist_$board ]
then internal_whitelist="$whitelist $(eval echo "\$whitelist_$board")"
else internal_whitelist="$whitelist"
fi
internal_whitelist=$(echo "$internal_whitelist" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
# check for board-specific file types
if [ -v file_types_$board ]
then internal_file_types="$(eval echo "\$file_types_$board")"
else internal_file_types="$file_types"
fi

# THREADS LOOP INITIALIZATION
#############################
echo -e "$color_front""Target Board: /$board/"
# show size of current board's download directory
if [ $verbose == "1" ]; then echo -e "$color_front$(du -sh $download_dir | cut -f1) in $download_dir"; fi
# download catalog
while :
do
  catalog=$(curl -A "$user_agent" -f -s "$http_string_text://boards.4chan.org/$board/catalog")
  if [[ "${#catalog}" -lt 1000 ]]; then
    echo -en "\r$color_patience""Could not find the board /$board/. Retrying ... "
    sleep 5
    echo -en "\e[2K\r" # clear whole line
  else
    echo -en "\e[2K\r$color_patience""Analyzing board index "
    unset -v title_list
    unset -v displayed_title_list
    unset -v has_new_pictures
    IFS=$'\n' # necessary to create lines for sed
    # grab relevant catalog pieces, cut & split them; replace HTML entities
    grabs=($(echo "$catalog" | grep -Po '[0-9][0-9]*?\":.*?\"teaser\".*?\},' | sed -e 's/&amp;/&/g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&#039;/'/g" -e 's/&#44;/,/g' -e 's/\\//g'))
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
      echo -en "\e[2K\r$color_patience""Server buggy. Retrying ... "
      sleep 5
      continue
    else
      echo -en "\e[2K\r"
      if [ "$debug" == "1" ]; then
        echo "Grabs: ${#grabs[@]}"
        echo "Subs: ${#subs[@]}"
        echo "Teasers: ${#teasers[@]}"
      fi
      if [ $verbose == "1" ]; then echo -e "$color_front""Found $i threads"; fi
      echo
      break
    fi
  fi
done

# THREADS LOOP
##############
for thread_number in $thread_numbers
do

# skip current thread loop iteration if thread has been blocked previously
if [[ ${blocked[$thread_number]} == 1 ]]; then
  if [ $verbose == "1" ]; then
    echo -e "$color_back[ ] ${displayed_title_list[$thread_number]} $color_back[${cached_picture_count[$thread_number]}]"
  fi
  continue # start next thread iteration
fi

# blacklist & whitelist
title_lower_case=" ${title_list[$thread_number],,} " # need those spaces for matching
skip=0
# blacklist before whitelist
if [ ${#internal_blacklist} -gt 0 ]; then
  set -f # prevent file globbing
  for match in ${internal_blacklist,,}; do
    if [[ "$title_lower_case" == *$match* ]]; then
      matchcut
      echo -e "$color_blacklist[!] $match $color_back${displayed_title_list[$thread_number]} $color_back[${cached_picture_count[$thread_number]}]"
      if [ $hide_blacklisted_threads == "1" ] && [ ! $verbose == "1" ]; then blocked[$thread_number]=1; fi
      skip=1
      set +f
      break
    fi
  done
  if [ $skip -eq 1 ]; then continue; fi # start next thread iteration
fi
# whitelist
if [ ${#internal_whitelist} -gt 0 ]; then
  match_found=0
  set -f
  for match in ${internal_whitelist,,}; do
    if [[ "$title_lower_case" == *$match* ]]; then
      match_found=1
      matchcut
      break
    fi
  done
  set +f
  # skip thread if match has been found but thread's image number too low
  if [ $match_found -eq 1 ] && [ "${cached_picture_count[$thread_number]}" -lt $min_images ]; then
    echo -e "$color_back[i] $match $color_front${displayed_title_list[$thread_number]} [${cached_picture_count[$thread_number]}]"
    continue # start next thread iteration
  fi
  # ignore thread permanently if whitelist active, but thread not whitelisted
  if [ $match_found -eq 0 ]; then
    echo -e "$color_back[ ] ${displayed_title_list[$thread_number]} $color_back[${cached_picture_count[$thread_number]}]"
    blocked[$thread_number]=1
    continue # start next thread iteration
  fi
fi

# the only threads left are threads we watch
# skip thread iteration if no new pictures
if [ ! "${has_new_pictures[$thread_number]}" == "1" ]; then
  if [ ${#internal_whitelist} -gt 0 ]
  then echo -e "$color_back[ ] $match $color_front${displayed_title_list[$thread_number]} [${cached_picture_count[$thread_number]}]"
  else echo -e "$color_back[ ] $color_front"${displayed_title_list[$thread_number]}" [${cached_picture_count[$thread_number]}]"
  fi
  continue # start next thread iteration
fi

# wait if too many crawl jobs running
if [ ${#crawl_jobs[@]} -ge $max_crawl_jobs ]; then
  wait "${crawl_jobs[$crawl_index]}"
  unset -v crawl_jobs[$((crawl_index++))]
fi

# wait if too many download processes
if [ $max_downloads -gt 0 ]; then
  while [ $(ps -fu $USER | grep -c curl.*4cdn) -ge $max_downloads ]; do
    sleep 1
  done
fi

# download and analyze thread in background ("crawl job")
{
thread=$(curl -A "$user_agent" -f -s $(echo "$thread_number" | sed 's/^/'$http_string_text':\/\/boards.4chan.org\/'$board'\/res\//g'))
# do nothing more if thread is 404'd
if [ ${#thread} -eq 0 ]; then
  if [ ${#internal_whitelist} -gt 0 ]
  then echo -e "$color_blacklist[x] $color_back$match $color_front${displayed_title_list[$thread_number]} [${cached_picture_count[$thread_number]}]"
  else echo -e "$color_blacklist[x] $color_front${displayed_title_list[$thread_number]} [${cached_picture_count[$thread_number]}]"
fi
# else try to save thread's images
else
  # get real thread title from the downloaded file
  title=$(echo "$thread" | sed -e 's/^.*<meta name="description" content="//' -e 's/ - &quot;\/.*$//' -e 's/&amp;/&/g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&#039;/'/g" -e 's/&#44;/,/g')

  # convert thread title into filesystem compatible format
  title_dir=$(echo "$title" | sed -e 's/[^'"$allowed_filename_characters"']/'"$replacement_character"'/g')
  mkdir -p "$download_dir/$title_dir"
  cd "$download_dir/$title_dir"

  # search thread for images and download them
  files=$(echo "$thread" | grep -Po //i\.4cdn\.org/$board/[0-9][0-9]*?\.\("$internal_file_types"\) | sort -u | sed 's/^/'$http_string_images':/g')
  unset -v thread
  if [ ${#files} -gt 0 ]; then
    # create download queue; only new files that don't yet exist in the download folder
    queue=""
    number_of_new_files=0
    for file in $files; do
      if [ ! -e $(basename $file) ]; then
        queue+="$file
        " # inserting a source code new line
        ((number_of_new_files++))
      fi
    done
    # text output first, then background download
    if [ $number_of_new_files -gt 0 ]; then
      if [ ${#internal_whitelist} -gt 0 ]
      then echo -e "$color_whitelist[+] $match $color_front${displayed_title_list[$thread_number]} [${cached_picture_count[$thread_number]}] $color_whitelist[+$number_of_new_files]"
      else echo -e "$color_whitelist[+] $color_front${displayed_title_list[$thread_number]} [${cached_picture_count[$thread_number]}] $color_whitelist[+$number_of_new_files]"
      fi
      #download new files in background processes
      {
        echo "$queue" | xargs -n 1 -P $downloads_per_thread curl -A "$user_agent" -O -f -s
      } &
    # no new files
    else
      if [ ${#internal_whitelist} -gt 0 ]
      then echo -e "$color_back[-] $match $color_front${displayed_title_list[$thread_number]} [${cached_picture_count[$thread_number]}]"
      else echo -e "$color_back[-] $color_front${displayed_title_list[$thread_number]} [${cached_picture_count[$thread_number]}]"
      fi
    fi
  fi
fi
} &

# save current crawl job's process ID in an array
crawl_jobs+=("$!")

done # threads loop end

# wait for all crawl jobs to complete, then clean up
wait
unset -v crawl_jobs
unset -v crawl_index

# wait before the next board iteration if too many download processes
if [ $max_downloads -gt 0 ]; then
  download_count=$(ps -fu $USER | grep -c curl.*4cdn)
  until [ $download_count -lt $max_downloads ]; do
    echo -en "\e[2K\r$color_patience""Download limit [$download_count/$max_downloads] "
    sleep 5
    download_count=$(ps -fu $USER | grep -c curl.*4cdn)
  done
fi

echo -e "\e[2K\r"

done # boards loop end

if [ $loop_timer -gt 0 ]; then
  while (($SECONDS - $timestamp_boards < $loop_timer)); do
    echo -en "\e[1K\r$color_patience""Waiting $(($loop_timer - $SECONDS + $timestamp_boards)) "
    sleep 1
  done
  echo -en "\e[2K\r"
fi

# clean up arrays periodically (24h)
if (($SECONDS - $timestamp_cleanup > 86400)); then
  unset -v blocked
  unset -v cached_picture_count
  timestamp_cleanup=$SECONDS
fi

done # main loop end
