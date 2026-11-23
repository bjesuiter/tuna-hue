# Website screenshots

The walkthrough uses the PNGs in `packages/website/src/assets/screenshots`. Its
preview crops use coordinates in the original PNGs.

| Filename | State | Original pixels |
| --- | --- | --- |
| `find-hue-command.png` | Fuzzy Mode search for `hue`, with **Connect First Hue Bridge** selected and the results list expanded | 1584 × 1652 |
| `choose-bridge.png` | Automatic pairing with **Demo Hue Bridge** selected and **Continue** available | 1128 × 968 |
| `press-link-button.png` | Pairing dialog waiting for the link button on **Demo Hue Bridge** | 1128 × 968 |
| `bridge-connected.png` | Successful pairing with **Demo Hue Bridge** and **Done** | 744 × 608 |
| `manual-connection.png` | **Connect Bridge** manual form with all fields blank | 928 × 1172 |
| `turn-on.png` | **Bedroom** selected with **Turn On** available | 960 × 495 |
| `turn-off.png` | **Living Room** selected with **Turn Off** available and the results list expanded | 1584 × 1652 |
| `check-connection.png` | Offline **Kitchen** selected with **Check Connection** available and the results list expanded | 1584 × 1652 |
| `manage-bridges.png` | **Manage Hue Bridges** dialog with **Demo Hue Bridge** selected | 1008 × 712 |
| `disconnect-bridge.png` | Confirmation after choosing **Disconnect** for **Demo Hue Bridge** | 744 × 692 |

## Regenerate the screenshots

On an Apple Silicon Mac with Tart 2.42.0, Bun and Xcode, run this from the
repository root after preparing the VM below.

```sh
bun run screenshots
```

The command clones the guest, builds and transfers the current extension,
starts the loopback mock, and captures the ten states with Peekaboo. It removes
the clone, verifies the filenames and PNG dimensions, then atomically exchanges
the screenshot directory. The framing preserves the website's crop coordinates.

Use `bun run screenshots:proof` to stage just the launcher, or
`bun run screenshots:proof --all` to stage all ten raw window captures for
inspection.

## Prepare the guest once

1. Start with this pinned vanilla [Tart macOS Tahoe image](https://tart.run/quick-start/).
   Keep the prepared local VM as a frozen versioned image.

   ```sh
   export TART_NO_AUTO_PRUNE=1
   tart clone ghcr.io/cirruslabs/macos-tahoe-vanilla@sha256:eeec54bfe1f076e27786c5d92b89187a05b1d109b5071eb2dcdf02d596e34640 tuna-hue-screenshots-v1
   tart set tuna-hue-screenshots-v1 --display 1600x1000pt --no-display-refit
   tart run tuna-hue-screenshots-v1
   ```

2. Use a dedicated account. Enable automatic login to its desktop and disable
   the screen saver, display sleep and lock on idle. Use English (US), the US
   input source, Light appearance, a fixed wallpaper and the base
   image's system fonts. Verify one display at 1600 × 1000 logical points at
   2×. Run Tart with a Retina main display on the host. Keep these settings,
   installed apps and the guest OS build fixed, and disable automatic macOS updates.
3. Download [Tuna](https://tunaformac.com/download/latest) and confirm the
   signed app is **0.113**, build **2364**, before copying it to
   `/Applications/Tuna.app`. Save this release archive for future guest rebuilds.
   The ZIP SHA-256 is
   `bf134fadc58006c08db32ae89fc66e0a462a2663e74014cefcbe71a14373182f`.
   Complete onboarding, turn off automatic updates and choose the Default
   theme with animations disabled. Update the baked release only when
   explicitly requested. The script opens the search through
   [Tuna's URL scheme](https://tunaformac.com/docs/url-schemes).

   ```sh
   /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Tuna.app/Contents/Info.plist
   /usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Tuna.app/Contents/Info.plist
   codesign --verify --deep --strict Tuna.app
   ```

   Leave Tuna quit with empty Hue pairing state. Keep Tuna's ExtensionsDev
   folder free of the Hue extension. The runner installs it and starts fresh
   mock bridge state on every clone.
4. Install signed [Peekaboo 4.9.9](https://github.com/openclaw/Peekaboo/releases/tag/v4.9.9)
   using the matching app and CLI archives. Put the app in `/Applications` and
   the CLI with its companion files on the guest's PATH. Install `jq`. Open the
   Peekaboo app, complete onboarding and add it to the guest account's Login
   Items. In System Settings under Privacy & Security, grant the app
   **Accessibility** and **Screen & System Audio Recording**. Relaunch it,
   then check the app's Bridge socket. The grant must apply to the Bridge host
   that performs the capture and input.

   ```sh
   socket="$HOME/Library/Application Support/Peekaboo/bridge.sock"
   peekaboo permissions status --bridge-socket "$socket" --json
   peekaboo see --bridge-socket "$socket" --mode screen --no-elements --path /tmp/peekaboo-check.png
   ```

5. In the guest, enable Remote Login and add the host's SSH public key to the
   guest account's `~/.ssh/authorized_keys`. Read the guest's public host key
   from `/etc/ssh/ssh_host_ed25519_key.pub` at its trusted console. On the host,
   store the key as a known-hosts line with the alias
   `tuna-hue-screenshots` followed by the key type and key data in
   `~/.local/state/tuna-hue-screenshots/known_hosts`. The command verifies the
   guest key even when the clone receives a different IP. It uses the private
   key at `~/.local/state/tuna-hue-screenshots/id_ed25519` if present and falls
   back to the host's SSH agent or default SSH identity. To use another key,
   set `TUNA_HUE_SCREENSHOT_SSH_KEY` to its path.
6. Verify the dedicated guest account can run the mock with noninteractive
   `sudo` to bind guest loopback port 443. The runner copies Bun from the host
   and uses the guest's OpenSSL to generate a fresh certificate.
7. Shut down the prepared VM. Future runs clone that image. If you prepared it
   under a different name, set `TUNA_HUE_SCREENSHOT_VM` to its versioned local
   name or an OCI reference pinned by digest. Set `TUNA_HUE_SCREENSHOT_USER`
   if the guest account is other than `admin`. Optional overrides
   `TUNA_HUE_SCREENSHOT_HOST_KEYS` and `TART_BIN` select the host's known-hosts
   file and Tart executable.

## Mock bridge for smoke tests

The mock is the [`@tuna-hue/hue-mock` workspace](../../packages/hue-mock/package.json).
Run these commands from the repo root on a machine with Bun and OpenSSL.

```sh
bun --filter @tuna-hue/hue-mock smoke-test
bun --filter @tuna-hue/hue-mock start
```

The smoke test starts its own server on an available loopback port and checks
HTTPS, discovery, pairing, authentication, and a power update.

To run the mock in a guest without the repo, copy
[`server.ts`](../../packages/hue-mock/server.ts) into the guest.
The server listens on `127.0.0.1:443`, the port the extension uses. If the
guest restricts that port, run `sudo "$(command -v bun)" server.ts`.

```sh
bun server.ts
```

In Tuna, choose **Enter IP Address…**. Use address `127.0.0.1`, bridge ID
`001788fffe000001`, the CA PEM path printed by the server, and the application
key `tuna-hue-demo-key`. The server starts with **Bedroom** off, **Living Room**
on, and **Kitchen** offline. Restart it to reset the rooms. Each server run
generates a new CA, so use the newly printed path when connecting again.

For automatic pairing with the mock, quit Tuna and pass the discovery URL and
CA path when launching it again. Use
`https://127.0.0.1/__mock/discovery` for the direct server, or the Portless URL
below with the same path.

```sh
open -a Tuna \
  --env TUNA_HUE_DISCOVERY_URL=https://127.0.0.1/__mock/discovery \
  --env "TUNA_HUE_DISCOVERY_CA_PEM=$bridge_ca"
```

Set `bridge_ca` to the CA PEM path printed by the mock. After choosing
**Continue** in Tuna, simulate the physical link button.

```sh
curl --fail --cacert "$bridge_ca" -X POST https://127.0.0.1/__mock/link-button
```

The paired bridge keeps the configured CA path for subsequent requests. On a
persistent guest, disconnect the mock before stopping it. When you next
launch Tuna normally, it uses Philips discovery.

### Named mock URL with Portless

In the guest, start the mock on a high port and leave it running. Portless
needs Node.js 24 or later.

```sh
MOCK_HUE_PORT=18443 bun server.ts
```

In a second guest terminal, use the certificate and private key **paths**
printed by the mock. Portless serves that certificate on port 443 so Tuna can
verify the same bridge ID and CA it uses for a direct connection.

```sh
export PORTLESS_STATE_DIR="$HOME/.local/state/tuna-hue-portless"
npx --yes portless@0.18.1 proxy start --cert "$bridge_cert" --key "$bridge_key"
npx --yes portless@0.18.1 alias hue-bridge 18443 --upstream https
curl --fail --cacert "$bridge_ca" https://hue-bridge.localhost/api/config
```

Set `bridge_cert`, `bridge_key`, and `bridge_ca` to the printed bridge
certificate, private key file, and CA PEM paths. In Tuna, enter
`hue-bridge.localhost` as the bridge address and use the same bridge ID, CA PEM,
and application key as above. Portless may request administrator access to bind
port 443 and sync the name for macOS's resolver.

Stop the proxy with `npx --yes portless@0.18.1 proxy stop` from the same
terminal, then stop the mock. Restart both together when the mock generates a
fresh certificate.

## Verification

Use the proof mode to inspect the window captures from a fresh clone. Compare
`tart list --format json` before and after to verify clone cleanup.

For the failure case, set `TUNA_HUE_SCREENSHOT_HOST_KEYS` to a nonexistent
file. With a prepared VM present, the run should fail after cloning, report the
host-key check, remove its clone and leave the original PNGs byte-for-byte
identical. Use `shasum -a 256 packages/website/src/assets/screenshots/*.png` to
compare the original files before and after.
