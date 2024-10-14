directory=$1

echo $directory/transactions.json

inputs_outputs=$(cat $directory/transactions.json | jq '[.[].transaction | (.inputs | length) + (.outputs | length)] | add')
wait_time=$(cat $directory/experiment_args.log | grep "Wait Time:" | sed 's/[^0-9]*//g')
tps=$(echo "scale=5; $inputs_outputs / $wait_time" | bc)

echo "Inputs + Outputs: $inputs_outputs over $wait_time seconds is: $tps"
