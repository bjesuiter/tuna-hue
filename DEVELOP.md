# Developing Tuna Hue Control

## Build and install from source

Requires macOS 15 or later, Tuna 0.113 or later with a compatible TunaKit, and Xcode. The project pins TunaKit 1.23.0. From the repository root, run the Bun workspace build and copy the framework into Tuna’s developer extensions folder.

```sh
bun run build:plugin

dev_dir="$HOME/Library/Application Support/Tuna/ExtensionsDev"
mkdir -p "$dev_dir"
ditto packages/plugin/build/Build/Products/Release/TunaHue.framework "$dev_dir/TunaHue.framework"
```

Quit and reopen Tuna after installation or a rebuild. Tuna supplies the TunaKit framework at runtime. [Tuna extension development guide](https://tunaformac.com/docs/building-an-extension#step-4-run-it)

Check **Tuna Settings → Sources** after restarting. **Hue Groups** is the catalog exposed by the extension.

## Package a release for review

With Xcode and a compatible Tuna release installed, run `security find-identity -v -p codesigning` to find your Apple Development identity. Supply its team ID and SHA-1 from the repository root.

```sh
TUNA_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
TUNA_CODE_SIGN_IDENTITY=YOUR_IDENTITY_SHA1 \
bun run package:plugin
```

The command builds a signed Release framework with Tuna’s pinned upstream packager and writes the `.tunaextension` to `build/package-plugin/`. Set `TUNA_BINARY` if Tuna is installed outside the default search locations. The archive is for review. Tuna’s maintainer handles store signing and publication. [Tuna distribution guide](https://tunaformac.com/docs/extension-distribution)

## Bridge integration

Tuna Hue Control uses the local Hue CLIP v2 API for rooms, zones, and their grouped lights. It reads group power and device connectivity on catalog scans. **Check Connection** refreshes the selected offline group from its bridge and updates the available actions.

The extension stores a separate application key for each bridge in the macOS Keychain and migrates existing single-bridge settings on first use. It verifies the bridge certificate against the Hue CA and bridge ID. If a saved address stops responding, the extension searches discovery results for an updated address with the same bridge ID. A scan can still load groups from other bridges when one bridge is unavailable. Check the **Hue Groups** catalog diagnostics for scan status.

## Create an application key for manual setup

Use this procedure if you need a key for **Enter IP Address…**. Get the bridge’s local IPv4 address and full 16-character hexadecimal bridge ID from the [Hue discovery service](https://discovery.meethue.com) while on the same network.

Have the Hue root CA PEM file available for the command below. The plugin itself uses the bundled Hue roots when you leave its certificate field blank. [Philips Hue HTTPS guidance](https://developers.meethue.com/develop/application-design-guidance/using-https/)

To create a key, set the shell variables to your bridge details, press the physical link button, then run:

```sh
bridge_ip='192.168.1.50'
bridge_id='001788fffe000000'
hue_ca="$HOME/Downloads/hue-ca.pem"

/usr/bin/curl --silent --show-error --fail --noproxy '*' \
  --cacert "$hue_ca" --resolve "$bridge_id:443:$bridge_ip" \
  -H 'Content-Type: application/json' --data '{"devicetype":"tuna-hue#mac"}' \
  "https://$bridge_id/api"
```

Copy the returned `success.username` into Tuna’s **Application key** field. If the bridge reports that the link button was not pressed, press it again immediately before retrying. [Philips Hue pairing guide](https://developers.meethue.com/develop/get-started-2/)

## Marketing site

With `bgproc` installed, run `bun install` and then `bun run dev` from the
repository root. Open `http://localhost:4321/tuna-hue/`. Run
`bgproc stop -n tuna-hue-website` to stop the server. The static build command is `bun run build`,
which writes to `packages/website/dist`. Run `bun run preview` to serve that build
locally. The Astro config uses the repository GitHub Pages path.

The build renders the link preview image `og.png` from
`packages/website/og-image/og.html` with [Takumi](https://takumi.kane.tw)
(`src/pages/og.png.ts`). Open `og.html` in a browser to edit the design, and check
the result at `http://localhost:4321/tuna-hue/og.png`. Takumi supports a subset of
browser CSS and only the fonts the route passes to it (Geist and Geist Mono).

## Website screenshots

See the [screenshot inventory and Tart guest setup](scripts/screenshots/README.md).
