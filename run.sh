# usage: ./run.sh year day
#        ./run.sh -i "INPUT" year day
#        ./run.sh -I INPUT_FILE year day

input=""
input_file=""
exec_name=solution
while getopts i:I:e: flag; do
    case "$flag" in
        i) input=$OPTARG;;
        I) input_file=$OPTARG;;
        e) exec_name=$OPTARG;;
    esac
done
shift $((OPTIND-1))

year=$1
day=$(printf "%02d" $2)
day_dir="$(echo $year/day$day*)"
executable="$day_dir/$exec_name"

if [ -z "$input" ]; then
    [ -z "$input_file" ] && input_file="$day_dir/input"
    [ ! -r $input_file ] && echo "can't read input file" && exit 1
    input="$(cat "$input_file")"
fi

make -s $executable && printf "%s" "$input" | "./$executable"
