function tps_experiment() {
    # Generator args
    export TPS=$1
    export OUTPUT_COUNT=$2
    export MEMPOOL_PERIOD=$3
    transaction_generators=$4
    wait_time=$5

    # Create unique directory for each experiment
    experiment_dir="./runs/$(date +%s)"
    mkdir -p $experiment_dir

    GRPC_SERVER="localhost:9084"
    HEADER_LOG_FILE="$experiment_dir/block_headers.json"
    BODY_LOG_FILE="$experiment_dir/block_bodies.json"
    TRANSACTION_LOG_FILE="$experiment_dir/transactions.json"
    INDEXER_METRICS_FILE="$experiment_dir/indexer_metrics.json"
    experiment_args_file="$experiment_dir/experiment_args.log"

    echo "Experiment Args" > $experiment_args_file
    echo "TPS: $TPS" >> $experiment_args_file
    echo "Output Count: $OUTPUT_COUNT" >> $experiment_args_file
    echo "Mempool Period: $MEMPOOL_PERIOD" >> $experiment_args_file
    echo "Transaction Generators: $transaction_generators" >> $experiment_args_file
    echo "Wait Time: $wait_time" >> $experiment_args_file


    templates=$(find ./template -type f)

    for file in $templates; do
        envsubst < $file > $experiment_dir/$(basename $file)
        envsubst < $file | while IFS= read -r line; do
            printf "%b\n" "$line"
        done > $experiment_dir/$(basename $file)
    done

    # echo "Creating docker network"
    # docker network create tps

    echo "Starting Node"
    docker run --network tps --rm --name node -d -p 9085:9085 -p 9084:9084 -p 9095:9095 -v $experiment_dir:/config stratalab/strata-node:0.0.0-8199-3c9a5c8b -- --config /config/node.yaml

    echo "Letting node run for 60 seconds"
    sleep 60

    echo "Starting Generator(s)"
    for i in $(seq 0 $((transaction_generators - 1))); do
        # docker run --network tps --rm --name generator$i -d -v $(pwd)/generator:/generator stratalab/transaction-generator:0.0.0-8199-3c9a5c8b-20241011-1428 -- --config /generator/application.conf
        docker run --network tps --rm --name generator$i -d -v $experiment_dir:/config  admiraladmirable/transaction-generator:latest -- --config /config/generator.conf
    done

    # Wait for the generator to start (arbitraty number)
    sleep 5

    # Start timing the transaction process
    start_time=$(date +%s)

    echo "Sending transactions for $wait_time seconds"
    sleep $wait_time

    echo "Stopping Generator(s)"
    for i in $(seq 0 $((transaction_generators - 1))); do
      docker logs generator$i > $experiment_dir/generatorLogs.txt
      docker rm -f generator$i
    done

    # Wait a bit for node to finalize transactions
    echo "Letting node run for 60 seconds"
    sleep 60
    docker logs node > $experiment_dir/nodeLogs.txt

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    echo "duration: $duration" >> $experiment_args_file

    echo "Statistics over $duration seconds"
    transactions_sent=$(cat $experiment_dir/generatorLogs.txt | grep "Broadcasted transaction" | wc -l)
    echo "Transactions Sent: $transactions_sent"
    echo "Transactions Per Second: $(echo "scale=5; $transactions_sent / $duration" | bc)"
    cat $experiment_dir/nodeLogs.txt | grep "Expiring transaction id" | echo "Expiring Transactions: $(wc -l)"

    echo "Writing Indexer Metrics"
    # grpcurl --plaintext $GRPC_SERVER co.topl.genus.services.NetworkMetricsService.getTxoStats >> $INDEXER_METRICS_FILE
    # grpcurl --plaintext $GRPC_SERVER co.topl.genus.services.NetworkMetricsService.getBlockStats >> $INDEXER_METRICS_FILE
    # grpcurl --plaintext $GRPC_SERVER co.topl.genus.services.NetworkMetricsService.getBlockchainSizeStats >> $INDEXER_METRICS_FILE

    # Step 1: Fetch the block ID at the specified depth (0 for the latest block)
    block_id=$(grpcurl --plaintext -d '{"depth":0}' "$GRPC_SERVER" co.topl.node.services.NodeRpc.FetchBlockIdAtDepth | jq -r '.blockId.value')

    # Step 2: Fetch the block header using the block ID obtained
    block_header=$(grpcurl --plaintext -d "{\"blockId\":{\"value\":\"$block_id\"}}" "$GRPC_SERVER" co.topl.node.services.NodeRpc.FetchBlockHeader)

    # Step 3: Extract the height from the block header
    chain_height=$(echo "$block_header" | jq -r '.header.height')

    # Output the chain height
    echo "Chain height: $chain_height"

    echo "[" >> $HEADER_LOG_FILE
    echo "[" >> $BODY_LOG_FILE

    # Step 4: Traverse from 1 to chain_height, fetch the block ID, then fetch the header, body, and transactions
    for ((height=1; height<=chain_height; height++)); do
        # Fetch the block ID at the current height
        block_id=$(grpcurl --plaintext -d "{\"height\":$height}" "$GRPC_SERVER" co.topl.node.services.NodeRpc.FetchBlockIdAtHeight | jq -r '.blockId.value')

        # Fetch the block header using the block ID
        block_header_response=$(grpcurl --plaintext -d "{\"blockId\":{\"value\":\"$block_id\"}}" "$GRPC_SERVER" co.topl.node.services.NodeRpc.FetchBlockHeader)

        # Fetch the block body using the block ID
        block_body_response=$(grpcurl --plaintext -d "{\"blockId\":{\"value\":\"$block_id\"}}" "$GRPC_SERVER" co.topl.node.services.NodeRpc.FetchBlockBody)

        # Write the block header to the header log file
        # echo "Block Header at Height $height:" >> "$HEADER_LOG_FILE"
        echo "$block_header_response," >> "$HEADER_LOG_FILE"
        # echo "" >> "$HEADER_LOG_FILE"  # Add an empty line for readability

        # Write the block body to the body log file
        # echo "Block Body at Height $height:" >> "$BODY_LOG_FILE"
        echo "$block_body_response," >> "$BODY_LOG_FILE"
        # echo "" >> "$BODY_LOG_FILE"  # Add an empty line for readability

        # Extract transactionIds and fetch each transaction, skipping null values
        transaction_ids=$(echo "$block_body_response" | jq -r '.body.transactionIds[]?.value // empty')

        echo "[" >> $TRANSACTION_LOG_FILE

        if [ -n "$transaction_ids" ]; then
            for transaction_id in $transaction_ids; do
                # Fetch the transaction using the transaction ID
                transaction_response=$(grpcurl --plaintext -d "{\"transactionId\":{\"value\":\"$transaction_id\"}}" "$GRPC_SERVER" co.topl.node.services.NodeRpc.FetchTransaction)

                # Write the transaction response to the transaction log file
                # echo "Transaction for ID $transaction_id at Height $height:" >> "$TRANSACTION_LOG_FILE"
                echo "$transaction_response," >> "$TRANSACTION_LOG_FILE"
                # echo "" >> "$TRANSACTION_LOG_FILE"  # Add an empty line for readability

                # Output progress for each transaction
                echo "Fetched transaction for ID $transaction_id at height $height"
            done
        fi

        echo "]" >> $TRANSACTION_LOG_FILE

        # Output progress for each block header and body
        echo "Fetched block header and body at height $height"
    done

    echo "]" >> $HEADER_LOG_FILE
    echo "]" >> $BODY_LOG_FILE

    echo "All block headers have been written to $HEADER_LOG_FILE"
    echo "All block bodies have been written to $BODY_LOG_FILE"
    echo "All transactions have been written to $TRANSACTION_LOG_FILE"

    echo "Stopping Node"
    docker rm -f node
}

## You can uncomment this to run multiple experiments with random parameters. Maybe neural network could help find the best parameters for highest TPS
# for i in $(seq 1 100); do
#     tps=$((1 + RANDOM % 500))
#     output_count=$((1 + RANDOM % 500))
#     mempool_period=5
#     transaction_generators=$((1 + RANDOM % 3))
#     wait_time=$(((1 + RANDOM % 5) * 60))
#     tps_experiment $tps $output_count $mempool_period $transaction_generators $wait_time
# done

tps_experiment 52 88 5 2 60
