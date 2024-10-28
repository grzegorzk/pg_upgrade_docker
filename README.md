# pg_upgrade_docker
Run `pg_upgrade` in docker

# how-to

All you need:

```bash
make pg_upgrade POSTGRES_DATA=<path to postgres data directory> POSTGRES_OLD_VERSION=<upgrading from this version> POSTGRES_NEW_VERSION=<upgrading to this version>
```

Version of postgres data located in `path to postgres data directory` must match `POSTGRES_OLD_VERSION`. Data in this directory will not be modified.
`db/data_migrated_${POSTGRES_NEW_VERSION}` will be created where migrated database will be stored.

Below is the list of targets made available in the utility:

## List available options
```bash
make list
```

All commands below use [podman](https://podman.io/) as default containers management tool. If you prefer docker, add `DOCKER=docker` option to all commands listed below.

## Build image later used to run `pg_upgrade`
```bash
make build_pg_upgrade_image POSTGRES_OLD_VERSION=<upgrading from this version> POSTGRES_NEW_VERSION=<upgrading to this version>
```

Version can be any version recognised by postgres dockerhub

## Start postgres
```bash
make start_postgres POSTGRES_VERSION=<postgres version> POSTGRES_DATA=<path to postgres data directory>
```

## Stop postgres
```bash
make stop_postgres POSTGRES_VERSION=<postgres version>
```

## Upgrade postgres database
```bash
make pg_upgrade POSTGRES_DATA=<path to postgres data directory> POSTGRES_OLD_VERSION=<upgrading from this version> POSTGRES_NEW_VERSION=<upgrading to this version>
```

Version of postgres data located in `path to postgres data directory` must match `POSTGRES_OLD_VERSION`. Data in this directory will not be modified. 
`db/data_migrated_${POSTGRES_NEW_VERSION}` will be created where migrated database will be stored.

## Helper utility to remove migrated data directory created by this utility
```bash
make remove_postgres_data POSTGRES_VERSION=<postgres version> POSTGRES_DATA=<path to postgres data directory>
```

# example
```bash
echo "secret" > "$(pwd)"/secrets/POSTGRES_PASSWORD_FILE
make start_postgres POSTGRES_VERSION=14 POSTGRES_DATA="$(pwd)"/db/pg14
sleep 1
podman exec -it --user postgres pg_14 psql \
    -c "SELECT VERSION();" \
    -c "CREATE USER test_user;" \
    -c "CREATE DATABASE to_be_migrated OWNER test_user;" \
    -c "GRANT CONNECT ON DATABASE to_be_migrated TO test_user;" \
    -c "\connect to_be_migrated" \
    -c "SET ROLE test_user;" \
    -c "CREATE TABLE test_table(pk BIGSERIAL PRIMARY KEY, column1 TEXT);" \
    -c "INSERT INTO test_table(column1) VALUES ('some');" \
    -c "INSERT INTO test_table(column1) VALUES ('more');" \
    -c "\dt" \
    -c "SELECT * FROM test_table;"
make stop_postgres POSTGRES_VERSION=14
make pg_upgrade POSTGRES_DATA="$(pwd)"/db/pg14 POSTGRES_NEW_VERSION=17 POSTGRES_OLD_VERSION=14
make start_postgres POSTGRES_VERSION=17 POSTGRES_DATA="$(pwd)"/db/data_migrated_17
sleep 1
podman exec -it --user postgres pg_17 psql \
    -c "\connect to_be_migrated" \
    -c "\dt" \
    -c "SELECT * FROM test_table;"
make stop_postgres POSTGRES_VERSION=17
make remove_postgres_data POSTGRES_VERSION=14 POSTGRES_DATA="$(pwd)"/db/pg14
make remove_postgres_data POSTGRES_VERSION=17 POSTGRES_DATA="$(pwd)"/db/data_migrated_17
```

Above script results in following output:

```
Removing container POSTGRES_PASSWORD_FILE secret
127b5711f25594a1f0788a414
Creating container POSTGRES_PASSWORD_FILE secret
42c9e410ae3acb2f102719369
8fc202780d0efe09511fc7a3f077edf2974dca1a1b272d1d9c64502905b3b30c
Waiting for postgres to start in pg_14
Postgres running in pg_14
Creating marker within pg_14
pg_14 started
                                                        version                                                        
-----------------------------------------------------------------------------------------------------------------------
 PostgreSQL 14.13 (Debian 14.13-1.pgdg120+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 12.2.0-14) 12.2.0, 64-bit
(1 row)

CREATE ROLE
CREATE DATABASE
GRANT
You are now connected to database "to_be_migrated" as user "postgres".
SET
CREATE TABLE
INSERT 0 1
INSERT 0 1
            List of relations
 Schema |    Name    | Type  |   Owner   
--------+------------+-------+-----------
 public | test_table | table | test_user
(1 row)

 pk | column1 
----+---------
  1 | some
  2 | more
(2 rows)

Stopping pg_14
pg_14
pg_14
Removing container POSTGRES_PASSWORD_FILE secret
42c9e410ae3acb2f102719369
Creating container POSTGRES_PASSWORD_FILE secret
ed31ce75d32c6f6472d9a2512
Start new postgres in '' and create empty db in '/home/grzegorz/work/techgk/github/pg_upgrade_docker/db/data_migrated_17'
Removing container POSTGRES_PASSWORD_FILE secret
ed31ce75d32c6f6472d9a2512
Creating container POSTGRES_PASSWORD_FILE secret
7880270a4a77a07979fc18768
035023fcb9d03865e865b502b1c5686b1b2709fd9af8dbf7df8a8a872632fcf9
Waiting for postgres to start in pg_17
Postgres running in pg_17
Creating marker within pg_17
pg_17 started
Stopping pg_17
pg_17
pg_17
Build pg_upgrade_14_17
[1/2] STEP 1/1: FROM docker.io/library/postgres:14 AS POSTGRES_OLD
--> d4a3e64ed8ed
[2/2] STEP 1/5: FROM docker.io/library/postgres:17
[2/2] STEP 2/5: ARG POSTGRES_OLD_IMAGE_NAME
--> Using cache 7d95bc847671f5cb34fca5ae303fb50ea83b5098018987be1d6e42f4030122d6
--> 7d95bc847671
[2/2] STEP 3/5: ARG POSTGRES_OLD_VERSION
--> Using cache dd3d9f141f0cd021cc0e6db3f5341211c8471e4826fc8e6385e2af9aa09169b5
--> dd3d9f141f0c
[2/2] STEP 4/5: COPY --from=POSTGRES_OLD /usr/lib/postgresql/$POSTGRES_OLD_VERSION /usr/lib/postgresql/$POSTGRES_OLD_VERSION
--> Using cache 9d38279c49db8c4c09416aa49cc0b8b96c4bf9f257a1b6ae92c2055fa34a645c
--> 9d38279c49db
[2/2] STEP 5/5: COPY --from=POSTGRES_OLD /usr/share/postgresql/$POSTGRES_OLD_VERSION /usr/share/postgresql/$POSTGRES_OLD_VERSION
--> Using cache b3389350c01e77802c5e07490ae8a17fb61b9499a090a0cd74106be7cb369f5d
[2/2] COMMIT pg_upgrade_14_17
--> b3389350c01e
Successfully tagged localhost/pg_upgrade_14_17:latest
b3389350c01e77802c5e07490ae8a17fb61b9499a090a0cd74106be7cb369f5d
Run pg_upgrade_14_17
Performing Consistency Checks
-----------------------------
Checking cluster versions                                     ok
Checking database user is the install user                    ok
Checking database connection settings                         ok
Checking for prepared transactions                            ok
Checking for contrib/isn with bigint-passing mismatch         ok
Checking data type usage                                      ok
Creating dump of global objects                               ok
Creating dump of database schemas                             
                                                              ok
Checking for presence of required libraries                   ok
Checking database user is the install user                    ok
Checking for prepared transactions                            ok
Checking for new cluster tablespace directories               ok

If pg_upgrade fails after this point, you must re-initdb the
new cluster before continuing.

Performing Upgrade
------------------
Setting locale and encoding for new cluster                   ok
Analyzing all rows in the new cluster                         ok
Freezing all rows in the new cluster                          ok
Deleting files from new pg_xact                               ok
Copying old pg_xact to new server                             ok
Setting oldest XID for new cluster                            ok
Setting next transaction ID and epoch for new cluster         ok
Deleting files from new pg_multixact/offsets                  ok
Copying old pg_multixact/offsets to new server                ok
Deleting files from new pg_multixact/members                  ok
Copying old pg_multixact/members to new server                ok
Setting next multixact ID and offset for new cluster          ok
Resetting WAL archives                                        ok
Setting frozenxid and minmxid counters in new cluster         ok
Restoring global objects in the new cluster                   ok
Restoring database schemas in the new cluster                 
                                                              ok
Copying user relation files                                   
                                                              ok
Setting next OID for new cluster                              ok
Sync data directory to disk                                   ok
Creating script to delete old cluster                         ok
Checking for extension updates                                ok

Upgrade Complete
----------------
Optimizer statistics are not transferred by pg_upgrade.
Once you start the new server, consider running:
    /usr/lib/postgresql/17/bin/vacuumdb -U postgres --all --analyze-in-stages
Running this script will delete the old cluster's data files:
    ./delete_old_cluster.sh
DB migrated, 
Removing container POSTGRES_PASSWORD_FILE secret
7880270a4a77a07979fc18768
Creating container POSTGRES_PASSWORD_FILE secret
58e80da08b02e7ca511a1531b
82438ef5847e97100935eef7fe995949e4e6df2ced22a9bb6a834cdc90f0fb0b
Waiting for postgres to start in pg_17
Postgres running in pg_17
Creating marker within pg_17
Started postgres on db created by foreign process
pg_17 started
You are now connected to database "to_be_migrated" as user "postgres".
            List of relations
 Schema |    Name    | Type  |   Owner   
--------+------------+-------+-----------
 public | test_table | table | test_user
(1 row)

 pk | column1 
----+---------
  1 | some
  2 | more
(2 rows)

Stopping pg_17
pg_17
pg_17

```

# License

Licensed under Apache-2.0, please read `LICENSE`
