package main

import (
	"context"
	"fmt"
	"math"
	"os"
	"os/exec"
	"strconv"
	"time"

	"github.com/conduitio/conduit-commons/config"
	"github.com/conduitio/conduit-commons/opencdc"
	"github.com/conduitio/conduit-connector-postgres"
	sdk "github.com/conduitio/conduit-connector-sdk"
	"github.com/rs/zerolog"
)

var (
	defaultBatchSize          = 10000
	defaultRecordsToInsert    = 1000000
	defaultRecordsToInsertStr = fmt.Sprintf("%d", defaultRecordsToInsert)
)

func main() {
	ctx := context.Background()
	initStandaloneModeLogger(zerolog.DebugLevel)

	src := newSource(ctx, nil)

	recordsToInsertInt := insertRows("1")
	records, err := src.ReadN(ctx, 1)
	position := records[0].Position

	err = src.Teardown(ctx)
	if err != nil {
		panic(fmt.Errorf("error tearing down: %v", err))
	}

	// Execute the script to insert records
	// The script should take a command line argument for the number of records to insert
	recordsToInsert := defaultRecordsToInsertStr
	if len(os.Args) > 1 {
		recordsToInsert = os.Args[1]
	}
	recordsToInsertInt = insertRows(recordsToInsert)

	src = newSource(ctx, position)
	defer func() {
		teardownErr := src.Teardown(ctx)
		if teardownErr != nil {
			fmt.Printf("error tearing down: %v", teardownErr)
		}
	}()

	// Measure performance of reading records
	fmt.Println("Starting to read records...")

	start := time.Now()

	for i := 0; i < recordsToInsertInt; {
		recs, err := src.ReadN(ctx, defaultRecordsToInsert)
		if err != nil {
			panic(fmt.Errorf("error reading from source: %v", err))
		}

		if i%(10*defaultBatchSize) == 0 {
			elapsed := time.Since(start).Seconds()
			fmt.Printf("total count: %v, elapsed: %v, rate: %v/s\n", i, elapsed, math.Round(float64(i)/elapsed))
		}

		i += len(recs)
	}

	duration := time.Now().Sub(start).Seconds()
	fmt.Println("duration:", duration)

	// Calculate and log performance metrics
	recordsPerSecond := float64(recordsToInsertInt) / duration

	fmt.Printf("Performance Summary:\n")
	fmt.Printf("- Total records read: %d\n", recordsToInsertInt)
	fmt.Printf("- Total read duration: %v\n", duration)
	fmt.Printf("- Read rate: %.2f records/second\n", recordsPerSecond)
}

func newSource(ctx context.Context, pos opencdc.Position) sdk.Source {
	fmt.Printf("creating new position %v\n", pos)
	src := postgres.Connector.NewSource()
	cfg := config.Config{
		"tables":                             "employees",
		"url":                                "postgresql://meroxauser:meroxapass@localhost:5432/meroxadb",
		"cdcMode":                            "logrepl",
		"logrepl.slotName":                   "conduit_slot",
		"logrepl.publicationName":            "conduit_pub",
		"logrepl.autoCleanup":                "true",
		"logrepl.withAvroSchema":             "false",
		"snapshotMode":                       "never",
		"sdk.batch.size":                     fmt.Sprintf("%d", defaultBatchSize),
		"sdk.batch.delay":                    "1s",
		"sdk.schema.extract.key.enabled":     "false",
		"sdk.schema.extract.payload.enabled": "false",
	}
	err := sdk.Util.ParseConfig(ctx, cfg, src.Config(), postgres.Connector.NewSpecification().SourceParams)
	if err != nil {
		panic(fmt.Errorf("error parsing config: %v", err))
	}

	// Open the source with a nil position (start from beginning)
	fmt.Println("opening the connector")
	err = src.Open(ctx, pos)
	if err != nil {
		panic(fmt.Errorf("error opening source: %v", err))
	}

	return src
}

func insertRows(recordsToInsert string) int {
	recordsToInsertInt, nil := strconv.Atoi(recordsToInsert)
	fmt.Printf("Running script to insert %s records...\n", recordsToInsert)

	scriptPath := "./scripts/insert_named_employees.sh"

	// Start writing
	insertDuration, insertRate, err := writeRecords(scriptPath, recordsToInsert)
	if err != nil {
		fmt.Printf("Error executing script: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Insertion completed in %v (%.2f records/second)\n", insertDuration, insertRate)

	return recordsToInsertInt
}

func writeRecords(scriptPath, recordsToInsert string) (time.Duration, float64, error) {
	// Start timing the insert operation
	insertStartTime := time.Now()

	cmd := exec.Command("/bin/bash", scriptPath, recordsToInsert)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return 0, 0, fmt.Errorf("error executing script: %v\nOutput: %s", err, string(output))
	}

	insertDuration := time.Since(insertStartTime)
	insertRate := float64(0)
	// Try to calculate insertion rate if we can convert the record count
	if insertCount, err := strconv.Atoi(recordsToInsert); err == nil {
		insertRate = float64(insertCount) / insertDuration.Seconds()
	}

	fmt.Printf("Script output:\n%s\n", string(output))
	return insertDuration, insertRate, nil
}

// initStandaloneModeLogger will create a default context logger that can be
// used by the plugin in standalone mode. Should not be called in builtin mode.
// copied from the Connector SDK
func initStandaloneModeLogger(level zerolog.Level) {
	// adjust field names to have parity with hclog, go-plugin uses hclog to
	// parse log messages
	zerolog.LevelFieldName = "@level"
	zerolog.CallerFieldName = "@caller"
	zerolog.TimestampFieldName = "@timestamp"
	zerolog.MessageFieldName = "@message"

	logger := zerolog.New(os.Stderr)
	logger = logger.Level(level)

	zerolog.DefaultContextLogger = &logger
}
