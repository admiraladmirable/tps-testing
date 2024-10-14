# mv ./runs/1728766744/transactions.log ./runs/1728766744/transactions.json

# Convert all .log to .json
# find ./runs -iname transactions.log -execdir mv '{}' 'transactions.json' \;

sed 's/{[/[/g' ./runs/1728766744/transactions.json > ./runs/1728766744/transactions.json.tmp