# aoc.sh

Advent of Code helper script

## Basic usage

Use `auth` command to sign in.

    $ aoc auth reddit
    reddit username: hellux
    password:
    Fetching CSRF token, reddit login session cookie...
    Signing in to reddit...
    Fetching uh token...
    Authorizing application...
    Logged in as Hellux.

Check current selection.

    $ aoc select
    [ 2015 - 01 - part 1 ] set as current selection.

Check completed puzzles with status command.

    $ aoc status days
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

    $ aoc select 7

View the puzzle description (with `elinks` + `less`).

    $ aoc view desc
    Fetching desc for day 7, 2015...

Create and edit a solution (with `EDITOR` env).

    $ aoc edit
    Solution directory name: 2015/day07_logic-circuit
    Solution file name: solution.hs

Run solution, output should show part 1 answer on first line and optionally
part 2 answer on second line. Source file is compiled with provided Makefile
and input is provided with stdin to executable. Input is fetched if needed.

    $ aoc run
    Fetching input for day 7, 2015...
    [1 of 1] Compiling Main             ( 2015/day07_logic-circuit/solution.hs, build/Main.o )
    Linking 2015/day07_logic-circuit/solution ...
    23989

Run solution on example input to verify. Examples are parsed from the puzzle
description and specified by the number in the order they appear in.

    $ aoc run -e1 65412
    65412

Submit answer for real puzzle input.

    $ ./aoc.sh submit
    Submit answer "23989" for part 1 of day 7, 2015 (y/N)? y

    That's the right answer! You are one gold star closer to powering the weather machine.

View the second part. The description will automatically be refetched if a new
part is available.

    $ aoc view desc
    Fetching desc for day 7, 2015...

## Automation guidelines

This tool follows the [automation guidelines] on the /r/adventofcode community
wiki:

[automation guidelines]: https://www.reddit.com/r/adventofcode/wiki/faqs/automation

- There are no scheduled or repeating requests, all requests are initiated
  manually.
- Inputs and descriptions are cached, and will only be refetched on demand.
- The User-Agent links to this repository.
