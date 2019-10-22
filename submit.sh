# usage: ./get_input.sh <year> <day> <part> <answer>

JAR="cookies.jar"
[ -f "$JAR" ] || (echo "no session cookie" && exit)

year="$1"
[ -z "$year" ] && exit 1
day="$2"
[ -z "$day" ] && exit 1
part="$3"
[ -z "$part" ] && exit 1
ans="$4"
[ -z "$ans" ] && exit 1

curl --data "level=$part&answer=$ans" -b "$JAR" \
    "https://adventofcode.com/$year/day/$day/answer" \
    | elinks -dump --no-references --no-numbering
