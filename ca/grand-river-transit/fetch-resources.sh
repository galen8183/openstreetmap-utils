#!/bin/sh

usage() {
	cat 1>&2 <<EOF
$0 target
download and post-process GRT data and documents

targets:
	system		full system map PDF
	schedules	route schedule/map PDFs
	stations	station map PDFs
	gtfs		GTFS feed
EOF
	exit 0
}

BASEURL="https://www.grt.ca/en"
CACHE="${XDG_CACHE_HOME:-.$HOME/.cache}/grt-src"
[ ! -d "$CACHE" ] && mkdir -p "$CACHE"

# getpdfresource extracts PDF hyperlinks from grt.ca/en/schedules-maps/$1
# link text is used for deduplication, sorted by date (assuming Y-M-D filenames)
# output is written to $2 with format "URL\tName"
getpdfresource() {
	maybecurl "$BASEURL/schedules-maps/$1" "$2"
	# grep each line with a resource URL
	# transform to "Name	URL"
	# TODO: relying on a very particular format feels suboptimal, can we improve
	# this scraping and transformation easily?
	sed -i \
		-e '\|/en/schedules-maps/resources/[^/]\+/[^.]\+\.pdf|!d' \
		-e 's|<li><a[^>]*href="/en\([^"]*\)"[^>]*>\([^<]*<\)/a>.*|\1\t\2|g' \
		-e 's/&nbsp;\| *<//g' \
		"$2"

	# deduplicate, preferring newer docs
	sort -rfk 2,1 -o "$2" "$2" # reverse, fold case, field 2 then 1, in place
	uniq --skip-fields=1 "$2" "$2.uniq" # uniq 2nd field
	mv "$2.uniq" "$2"
}

# maybecurl uses curl's --time-cond option to download $1 to $2 if the target
# resource isn't already downloaded or has changed since last download, using an
# intermediate file to return whether a download was performed
maybecurl() {
	curl -s -o "$2.new" -z "$2" "$1"
	mv "$2.new" "$2" 1>/dev/null 2>&1
	return "$?"
}

system() {
	SRC="$CACHE/grt-system-map-src"
	echo "downloading system map page..."
	maybecurl "$BASEURL/schedules-maps/system-map.aspx" "$SRC"
	MAP=$(grep -o '/schedules-maps/resources/.*\.pdf' "$SRC")
	# shellcheck disable=SC2046
	maybecurl "$BASEURL/$MAP" system-map.pdf && \
		echo downloaded map from $(echo "$MAP" | grep -o '\(-\?[0-9]\)\{8\}') to system-map.pdf || \
		echo "no change"
}

schedules() {
	SRC="$CACHE/grt-schedules-src"
	mkdir -p schedule && cd schedule || return

	echo "downloading schedules page..."
	getpdfresource "schedules.aspx" "$SRC"

	echo "found $(wc -l < "$SRC") schedules"
	printf "continue? [y/N] "; read -r cont
	case "$cont" in
		y|Y) ;; # ok
		*)
			echo "cancelled"
			exit 0
			;;
	esac

	# download each schedule to NNN.pdf
	# TODO: parallelise - mutate $SRC and hand off to maybecurl?
	while read -r LINE; do
		SCHED=$(echo "$LINE" | cut -f1)
		ROUTE=$(echo "$LINE" | cut -f2)
		NUM=$(echo "$ROUTE" | grep -o '[0-9]\+' | xargs printf "%03d")
		printf "dowloading %s to %s.pdf..." "$ROUTE" "$NUM"
		maybecurl "$BASEURL/$SCHED" "$NUM.pdf" && \
			echo "done!" || echo "no change"
	done < "$SRC"
}

stations() {
	SRC="$CACHE/grt-stations-src"
	mkdir -p station && cd station || return

	echo "downloading stations page..."
	getpdfresource "platform-layouts-ION-connections.aspx" "$SRC"

	echo "found $(wc -l < "$SRC") stations"
	printf "continue? [y/N] "; read -r cont
	case "$cont" in
		y|Y) ;; # ok
		*)
			echo "cancelled"
			exit 0
			;;
	esac

	# download each station to name.pdf
	# TODO: parallelise - mutate $SRC and hand off to maybecurl?
	while read -r LINE; do
		MAP=$(echo "$LINE" | cut -f1)
		STAT=$(echo "$LINE" | cut -f2)
		NAME=$(echo "$STAT" |
			tr '[:upper:]' '[:lower:]' |
			tr -c -s 'a-z0-9-.' '-' |
			sed -e 's/-\(station\|terminal\)-\?//' -e 's/-.pdf/.pdf/'
		)
		printf "dowloading %s to %s.pdf..." "$STAT" "$NAME"
		maybecurl "$BASEURL/$MAP" "$NAME.pdf" && \
			echo "done!" || echo "no change"
	done < "$SRC"
}

gtfs() {
	FEED="https://www.regionofwaterloo.ca/opendatadownloads/GRT_GTFS.zip"
	SRC="feed.zip"
	mkdir -p gtfs && cd gtfs || return

	echo "checking for new feed..."
	maybecurl "$FEED" "$SRC" && \
		echo "found feed from $(stat -c "%y" "$SRC")" || \
		(echo "no change" && return)

	echo "unzipping into ./gtfs/feed..."
	rm -r feed/
	unzip -d feed "$SRC"
	rename '.txt' '.csv' feed/*

	# TODO: post-process feed to (one of?) GeoJSON, OSM, Shapefile
}

# match only unique chars, so we can pass 'sys' and such along with 'system'
case "$1" in
	sy*) system ;;
	sc*) schedules ;;
	st*) stations ;;
	gtfs) gtfs ;;
	*) usage ;;
esac
