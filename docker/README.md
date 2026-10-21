# Browser sandbox

`browser-seccomp.json` is Playwright's Docker seccomp profile. It permits the `clone`, `setns`, and `unshare` operations Chrome needs to create its sandbox namespaces. The profile uses `SCMP_ACT_ERRNO` for system calls outside its allow rules.

Source: [microsoft/playwright, commit ae935a43d9e376e4759548f6b3c6905c7b282333](https://github.com/microsoft/playwright/blob/ae935a43d9e376e4759548f6b3c6905c7b282333/utils/docker/seccomp_profile.json). Copyright Microsoft Corporation. The Apache 2.0 license is in [browser-seccomp.LICENSE](browser-seccomp.LICENSE).
