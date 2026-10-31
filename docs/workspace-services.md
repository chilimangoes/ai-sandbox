# Workspaces with shared services

A workspace can combine a custom sandbox image with Docker networks, extra published ports, and project environment variables. For example, you could have a separate SQL Server or PostgreSQL database container that your sandbox connects to for development and unit tests.

To coordinate a multi-container sandbox setup like this, you need to tell the launcher about the custom Docker networks and other config settings for your sandbox and create a host script that prepares supporting containers, then invokes `ai-sandbox`.

## Declare container settings

The `.ai-sandbox/workspace.config` file tells `ai-sandbox` how to configure the workspace container when it starts: which Docker networks to join, extra ports to publish from inside your sandbox, and project environment variables to set. For example, a sandbox that connects to a shared SQL Server needs to join that server's Docker network.

The file works with either the shared base image or a custom image. A project-owned host bootstrap script creates supporting resources, such as the SQL container and its network. `workspace.config` tells the sandbox launcher how to connect to those resources.

Place the file in `.ai-sandbox/` under the directory where you run `ai-sandbox`.

Example:

```text
# Join two existing Docker networks.
network=example-project-test-sql
network=example-project-test-cache

# Publish two additional TCP ports.
port=5001
port=5002

# Set three environment variables inside the sandbox.
env=PROJECT_TEST_SQL_CONFIG=/supplemental/test-sql/connection.json
env=PROJECT_CACHE_HOST=test-cache
env=ASPNETCORE_ENVIRONMENT=Development
```

Supported settings are:

- `network=NAME`: join an existing named Docker network. Repeat for multiple networks. The launcher checks that each network exists before building or replacing the sandbox.
- `port=NUMBER`: publish an additional TCP port on the workspace's loopback address, with matching host and container ports. Repeat for multiple ports. Ports range from `1` to `65535`. Ports `3773`, `8080`, and `3000` are published by default.
- `env=NAME=VALUE`: set a project environment variable. Repeat for multiple variables, using a different name for each. Values can contain spaces and `=`. An empty value is valid.

Repeat `network=`, `port=`, and `env=` on separate lines to declare multiple entries. Blank lines and lines starting with `#` are ignored. Values are literal; shell expressions and host environment variables are not expanded. Each network name, port number, and environment variable name should appear only once. Duplicate entries, unknown keys, and reserved environment variables produce an error. Reserved variables are `AI_SANDBOX_*`, `LOCAL_UID`, `LOCAL_GID`, `HOME`, `PATH`, `USER`, and `LOGNAME`.

Startup settings require [workspace trust](custom-images.md#manage-workspace-trust), including when a workspace uses the shared base image. Changes to settings or supplemental mounts trigger workspace container replacement on the next successful launch.

Configure the application to listen on a container network interface, such as `0.0.0.0`. For an extra port such as `5001`, open `http://<workspace-host-address>:5001` from the host. The workspace address appears in the shell's default service URLs.

## Example: Create a shared SQL Server container

The [shared SQL example](../examples/shared-sql/) includes a custom .NET sandbox Dockerfile, workspace network settings, a Compose file, and host bootstrap scripts for Windows and Linux. Docker Compose v2 and an x86-64 Docker host are required. The SQL service has a `3 GiB` container memory limit. Microsoft documents the supported platforms in its [SQL Server container guide](https://learn.microsoft.com/en-us/sql/linux/quickstart-install-connect-docker?view=sql-server-ver17).

1. Copy the example's `.ai-sandbox/` and `dev/` directories into your project. If these directories exist, merge the example files with your project's definitions. Commit the supplied `.ai-sandbox/supplemental-folders.config`, which contains this portable mapping:

   ```text
   .local/test-sql/client|test-sql|ro
   ```

   The bootstrap launches `ai-sandbox` from the project root, so every checkout resolves this relative path to its own generated connection file. Add other project folder mappings to the same committed file.

2. Choose a service-group name for your project. Replace `example-project-test-sql` in `.ai-sandbox/workspace.config` and both host scripts with that name. Keep the name consistent across checkouts that share SQL Server on a host.

3. Add this entry to the project's `.gitignore`:

   ```gitignore
   .local/test-sql/
   ```

   The example includes this entry in its `.gitignore`. Generated SQL files live outside `.ai-sandbox/`, the directory used for image building.

4. On Windows, run the project bootstrap from PowerShell:

   ```powershell
   .\dev\sandbox.ps1
   ```

   On Linux, run:

   ```sh
   bash dev/sandbox.sh
   ```

   Approve the workspace when `ai-sandbox` prompts. These commands also accept sandbox arguments, such as `t3` or `--rebuild`.

The bootstrap serializes setup for the service group using a temporary helper container on Docker. Its name is `<service-group>-bootstrap-lock`. Each checkout waits for that same helper, which is removed after setup and expires after ten minutes if a bootstrap exits unexpectedly.

For a new SQL instance, the bootstrap uses the current checkout's saved passwords or generates them on first use. The SQL container stores both passwords in its environment. When the shared SQL container exists, the bootstrap reads those passwords through host-side Docker inspection and refreshes the current checkout's local files. It starts or reuses SQL, waits for a successful SQL health check, and provisions the `sandbox_test` login. A second connection verifies that the test login works before the sandbox launches.

Each checkout keeps its generated state under `<workspace>/.local/test-sql/`, ignored by Git:

- `server.env` contains `MSSQL_SA_PASSWORD` for SQL initialization and `TEST_SQL_PASSWORD` for the test login. Compose reads this file on the host.
- `client/connection.json` contains the test connection's `server`, `user`, and `password` fields. The committed folder mapping exposes this directory read-only at `/supplemental/test-sql/`.

The runtime variable `PROJECT_TEST_SQL_CONFIG` names the mounted JSON file. Project tests must read its fields to build their connection string. The example uses SQL Server's generated certificate; local test clients must explicitly trust that certificate.

Each sandbox connects to `test-sql,1433` through the shared network. The Compose file publishes no SQL port to the host. Docker operations run in the host script, while agents use SQL connections inside their sandboxes.

## Run tests concurrently

All participating checkouts use the same Compose project name and network. Each checkout has its own `.local/test-sql/` directory with credentials refreshed from the shared SQL container. Each workspace also has its own sandbox container and persisted volumes.

Give each test run a unique database name, such as `integration_<random-id>`. Create the database before the test and drop that database during cleanup. The example grants `dbcreator` to the shared test login. That role permits operations on other databases, so this setup assumes trusted agents using disposable development data.

Ordinary bootstrap runs preserve the running SQL container. The example's SQL data lives in the container's writable layer: stopping and starting the container preserves it; removing the container discards it. See [SQL Server container storage](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-deployment?view=sql-server-ver17#persist-your-data).

## Manage shared-service lifetime

Use `ai-sandbox stop`, `ai-sandbox rm`, and `ai-sandbox --rebuild` for a workspace. The shared SQL instance has a separate lifecycle. Maintenance commands `stop`, `rm`, and `reset-state` work independently of custom builds, workspace settings, and supplemental-folder validation.

To inspect the example service on Windows, set its group and state directory, then run Compose:

```powershell
$env:TEST_SQL_GROUP = 'example-project-test-sql'
$env:TEST_SQL_STATE_DIR = Join-Path (Get-Location).Path '.local/test-sql'
docker compose --project-name $env:TEST_SQL_GROUP --file dev/compose.yaml ps
```

On Linux, run:

```sh
export TEST_SQL_GROUP=example-project-test-sql
export TEST_SQL_STATE_DIR="$PWD/.local/test-sql"
docker compose --project-name "$TEST_SQL_GROUP" --file dev/compose.yaml ps
```

Run these commands from the project root after its bootstrap has completed. With those variables set, replace `ps` with `stop sql` to stop SQL Server. To discard all test databases, first stop test activity in every participating sandbox, then replace `ps` with `down`. Removing the SQL container deletes its database files. Run the project bootstrap to create a blank instance with the invoking checkout's saved development credentials. The external network and each checkout's local credentials files survive `down`.

Use a single project checkout to administer the shared service. The bootstrap's `--no-recreate` option preserves a running service during launches from other worktrees. To apply changes to the SQL image or service definition, stop test activity and recreate the service explicitly from that checkout.
