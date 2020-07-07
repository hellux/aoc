# aoc.sh

    aoc.sh -- Advent of Code helper script

    usage: aoc.sh [<args>] <command> [<args>]

    flags:
        -y      -- select year
        -d      -- select day
        -p      -- select part
        -q      -- query selection

    commands:
        select  -- save current selection of year, day and part
        status  -- show selection, login and completion status
        auth    -- authenticate user and create session cookie
        fetch   -- fetch puzzle description or input
        view    -- view fetched object
        edit    -- edit source file of puzzle solution
        run     -- compile and execute solution
        submit  -- submit answer for puzzle
        clean   -- delete all build files, fetched items, cookies
        help    -- get help about command

## Basic usage

Use `auth` command to sign in.

    $ ./aoc.sh auth reddit
    reddit username: hellux
    password: 
    Fetching CSRF token, reddit login session cookie...
    Signing in to reddit...
    Fetching uh token...
    Authorizing application...
    Logged in as Hellux.

Check current selection.

    $ ./aoc.sh select
    [ 2015 - 01 - part 1 ] set as current selection.

Check completed puzzles with status command.

    $ ./aoc.sh status days
    Puzzles 2015:
    Day	Stars	Title (solution name)
    1	**	
    2	**	
    3	**	
    4	**	
    5	*	
    6	**	
    7		
    :
    25		

Select the seventh day.

    $ ./aoc.sh select 7

View the puzzle description (with `elinks` + `less`).

    $ ./aoc.sh view desc
    Fetching desc for day 7, 2015...

Create and edit a solution (with `EDITOR` env).

    $ ./aoc.sh edit
    Solution directory name: 2015/day07_logic-circuit
    Provide file extension: solution.hs

Run solution, output should show part 1 answer on first line and optionally
part 2 answer on second line. Source file is compiled with provided Makefile
and input is provided with stdin to executable. Input is fetched if needed.

    $ ./aoc.sh run
    Fetching input for day 7, 2015...
    [1 of 1] Compiling Main             ( 2015/day07_logic-circuit/solution.hs, build/Main.o )
    Linking 2015/day07_logic-circuit/solution ...
    23989

Submit given answer.

    $ ./aoc.sh submit
    Submit answer "23989" for part 1 of day 7, 2015 (y/N)? y

    That's the right answer! You are one gold star closer to powering the weather machine.
