#!/bin/sh

usage() {
	cat 1>&2 <<EOF
$0 target
download and post-process GRT data and documents

targets:
	system		full system map PDF
	schedules	route schedule/map PDFs
	stations	station map PDFs
EOF
	exit 0
}

BASEURL="https://www.grt.ca/en"

# getpdfresource extracts PDF hyperlinks from grt.ca/en/schedules-maps/$2
# link text is used for deduplication, sorted by date (assuming Y-M-D filenames)
# output is written to $1 with format "URL\tName"
getpdfresource() {
	curl -s -o "$1" "$BASEURL/en/schedules-maps/$2"
	# grep each line with a resource URL
	# transform to "Name	URL"
	# TODO: relying on a very particular format feels suboptimal, can we improve
	# this scraping and transformation easily?
	sed -i \
		-e '\|/en/schedules-maps/resources/[^/]\+/[^.]\+\.pdf|!d' \ # isolate links
		-e 's|<li><a[^>]*href="/en\([^"]*\)"[^>]*>\([^<]*<\)/a>.*|\1\t\2|g' \ # get path
		-e 's/&nbsp;\| *<//g' \ # remove spaces
		"$1"

	# deduplicate, preferring newer docs (sort seemingly implicitly sorts by the
	# first field after the second)
	sort -rfk 2 -o "$1" "$1" # reverse, fold case, 2nd field, in place
	uniq --skip-fields=1 "$1" "$1.uniq" # uniq 2nd field
	mv "$1.uniq" "$1"
}

system() {
	SRC=/tmp/grt-system-map-src
	echo downloading system map page...
	curl -s -o "$SRC" "$BASEURL/schedules-maps/system-map.aspx"
	MAP=$(grep -o '/schedules-maps/resources/.*\.pdf' "$SRC")
	curl -s -o system-map.pdf "$BASEURL/$MAP"
	echo downloaded map from $(echo "$MAP" | grep -o '\(-\?[0-9]\)\{8\}') to system-map.pdf
}

schedules() {
	SRC=/tmp/grt-schedules-src
	cd schedule

	echo downloading schedules page...
	getpdfresource "$SRC" "schedules.aspx"

	echo found $(wc -l < "$SRC") schedules
	read -p "continue? [y/N]" cont
	case "$cont" in
		y|Y) ;; # ok
		*)
			echo cancelled
			exit 0
			;;
	esac

	# download each schedule to NNN.pdf
	while read LINE; do
		SCHED=$(echo "$LINE" | cut -f1)
		ROUTE=$(echo "$LINE" | cut -f2)
		NUM=$(echo "$ROUTE" | grep -o '[0-9]\+' | xargs printf "%03d")
		printf "dowloading %s to %s.pdf..." "$ROUTE" "$NUM"
		curl -s -o "$NUM.pdf" "$BASEURL/$SCHED"
		echo done!
	done < "$SRC"
}

stations() {
	SRC=/tmp/grt-stations-src
	cd station

	echo downloading stations page...
	getpdfresource "$SRC" "platform-layouts-ION-connections.aspx"

	echo found $(wc -l < "$SRC") stations
	read -p "continue? [y/N]" cont
	case "$cont" in
		y|Y) ;; # ok
		*)
			echo cancelled
			exit 0
			;;
	esac

	# download each station to name.pdf
	while read LINE; do
		MAP=$(echo "$LINE" | cut -f1)
		STAT=$(echo "$LINE" | cut -f2)
		NAME=$(echo "$STAT" |
			tr '[:upper:]' '[:lower:]' |
			tr -c -s 'a-z0-9-.' '-' |
			sed -e 's/-\(station\|terminal\)-\?//' -e 's/-.pdf/.pdf/'
		)
		printf "dowloading %s to %s.pdf..." "$STAT" "$NAME"
		curl -s -o "$NAME.pdf" "$BASEURL/$MAP"
		echo done!
	done < "$SRC"
}

# match only unique chars, so we can pass 'sys' and such along with 'system'
case "$1" in
	sy*) system ;;
	sc*) schedules ;;
	st*) stations ;;
	*) usage ;;
esac
