## TPS Experiment for <name> Blockchain

Run it using `tps.sh`. It can be run in 2 modes depending on what lines you comment out. You can run it many times with a bunch of randomized parameters, or run it a single time with your customized parameters.

Each time it runs, a folder will be created in the `runs` folder where you can validate the results.

The steps on how to run are:

1. `./tps.sh`
2. (if ranking many results) `./compare-tps.sh`
3. (if getting results for one run) `./analyze-run.sh`

## Current Issues
The json formatting doesn't work very well and needs some manual intervention. Sometimes it appends an empty array which is invalid JSON. In VSCode you can search for instances using the regex search pattern `\]\n\[` which finds instances of:

```
]
[
```

Also, check the second to last line of the json and delete the final comma for `jq` to work.
