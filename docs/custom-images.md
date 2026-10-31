# Custom workspace images

NodeJS is currently included due to AI tooling dependencies. If you need other project-specific development tools or dependencies, you can add them to a workspace by creating a custom derived `.ai-sandbox/Dockerfile` in your workspace folder, then run `ai-sandbox` as usual. The launcher builds the project image with the installed sandbox base and reuses Docker's cached layers.

## Prerequisites

Docker and `ai-sandbox` must be installed on the host. On Linux, the launcher also requires `flock`, supplied by `util-linux`.

## Example: Add .NET SDK v10 to a project-specific image


1. In the project root, create `.ai-sandbox/Dockerfile`:

   ```dockerfile
   ARG AI_SANDBOX_BASE_IMAGE=ai-sandbox:latest
   FROM ${AI_SANDBOX_BASE_IMAGE}

   RUN curl -fsSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb \
         -o /tmp/packages-microsoft-prod.deb \
       && dpkg -i /tmp/packages-microsoft-prod.deb \
       && rm /tmp/packages-microsoft-prod.deb \
       && apt-get update \
       && apt-get install -y --no-install-recommends dotnet-sdk-10.0 \
       && rm -rf /var/lib/apt/lists/*
   ```

   This example follows Microsoft's [Debian installation instructions](https://learn.microsoft.com/en-us/dotnet/core/install/linux-debian).

2. Commit the Dockerfile and any installation scripts beside it. Docker's build context is the `.ai-sandbox/` folder, so adjust paths accordingly.

3. From the project root, run:

   ```text
   ai-sandbox
   ```

   On first use, you need to approve the workspace's sandbox build and launch definitions. In a noninteractive terminal, you can record that approval explicitly with `ai-sandbox trust` before launching.

4. Inside the sandbox, verify the installation:

   ```sh
   dotnet --list-sdks
   ```

The launcher supplies `AI_SANDBOX_BASE_IMAGE` automatically. Preserve the inherited entrypoint, `sandbox` user, `/opt/ai-sandbox` files, and runtime defaults. Install project tools in system locations accessible to both `root` and the `sandbox` user.

## Rebuild an environment

Every launch checks the project build through Docker's cache. Dockerfile and copied-file changes invalidate the affected layers. Workspaces without `.ai-sandbox/Dockerfile` use the shared base image.

Additional terminals attach to the same workspace container. Cached builds with identical filesystem layers and runtime configuration preserve active sessions, including when Docker's build records change the image ID.

Changes to image contents or launch settings trigger container replacement. `ai-sandbox --rebuild` forces replacement. Replacement stops active sandbox sessions and application processes. Workspace files and the config, authentication, data, and cache volumes survive replacement. A build failure reports an error and preserves the existing container.

Each workspace path has its own container and project image tag. Shared base layers and unchanged project layers can be reused by Docker across workspaces. The launcher records a local base-image snapshot so concurrent updates use a consistent base during each project build.

## Manage workspace trust

Approval applies to the current workspace path and future edits to its sandbox definitions. It is stored under `~/.ai-sandbox/trusted-workspaces/` on the host. Each developer approves their own checkout.

To approve explicitly, run `ai-sandbox trust` in the root workspace folder. To revoke approval, run `ai-sandbox untrust` in the same folder. Revocation requires approval on the next customized launch.

For more complex setups with shared services and runtime settings, see [Workspaces with shared services](workspace-services.md).
