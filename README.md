# conduit-connector-postgres-test

A slightly modified version
of https://github.com/raulb/conduit-pipelines/tree/add-connector-test/pg-connector-test.

To run the test with the latest official version of the Postgres connector,
execute: `make use-latest-pg-connector run`.

To run the test with the updated version of the Postgres connector (that uses a
buffered channel), execute: `make use-latest-pg-connector run`.

**Design of the test**

The test measures the performance of the Postgres connector in CDC mode. We use
a similar approach as in https://github.com/ConduitIO/streaming-benchmarks,
where we insert test data while the connector is not running. In other words:

1. A new source is created.
2. A single record is inserted and read (so we get a CDC position).
3. The source is stopped.
4. The source is recreated.
5. The source starts reading from the position in step no. 2.
