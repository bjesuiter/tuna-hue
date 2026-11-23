# Tuna Hue Control

A native Swift extension for the [Tuna launcher](https://tunaformac.com). It reads rooms and zones from connected Philips Hue bridges over the local CLIP v2 API and offers **Turn On** and **Turn Off** for each group with a `grouped_light` service.

Search for **Benny Wohnzimmer** and choose the **Hue Zone** result to control that zone. If your bridge also has a **Wohnzimmer** room, the **Hue Room** result controls the entire room. Press **Tab** to pick the action. Each result shows the bridge name alongside the group type.

## Build and install

Requires macOS 15 or later, Tuna 0.113 or later with a compatible TunaKit, and Xcode. The project pins TunaKit 1.23.0. From the repository root, build and copy the framework into Tuna’s developer extensions folder.

```sh
xcodebuild -project TunaHue.xcodeproj -scheme TunaHue -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build build

dev_dir="$HOME/Library/Application Support/Tuna/ExtensionsDev"
mkdir -p "$dev_dir"
ditto build/Build/Products/Release/TunaHue.framework "$dev_dir/TunaHue.framework"
```

Quit and reopen Tuna after installation or a rebuild. Tuna supplies the TunaKit framework at runtime. [Tuna extension development guide](https://tunaformac.com/docs/building-an-extension#step-4-run-it)

## Connect and manage bridges

Search globally in Tuna for **Hue** and run **Connect First Hue Bridge**. If it is missing, set **Hue Groups → In global search** to **All** in Sources. Tuna uses Philips Hue's discovery service to find bridges. Choose a bridge and Tuna waits up to 90 seconds for you to press its physical link button. Tuna verifies the connection, saves a separate application key for each bridge in the macOS Keychain, and loads your rooms and zones. Allow local network access for Tuna if macOS asks.

Use **Add Hue Bridge** to connect another bridge. Searching for **Connect Hue Bridge** also finds it. An existing single-bridge connection is migrated on first use with its saved key. Use **Manage Hue Bridges** to select and disconnect a bridge. Disconnect removes that bridge and its saved key from Tuna on this Mac.

### Connect manually

Select **Enter IP Address…** in the bridge picker to enter the bridge details yourself.

1. Find the bridge’s local IPv4 address and its full 16-character hexadecimal bridge ID. The Hue app shows bridge details, and the [Hue discovery service](https://discovery.meethue.com) can return the ID and local IP for bridges on your network.
2. Leave the certificate path blank to use the bundled Hue roots. To use a specific root CA PEM file, enter its absolute path. [Philips Hue HTTPS guidance](https://developers.meethue.com/develop/application-design-guidance/using-https/)
3. Use an existing Hue application key or create one using the bridge’s physical link button, as shown below.

To replace the settings for a bridge, disconnect it in **Manage Hue Bridges**, then add it again.

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

The extension uses the configured address to connect and verifies the certificate against the Hue CA and bridge ID. If a saved address stops responding, the extension tries Hue discovery for an updated address with the same bridge ID. A scan can still load groups from other bridges when one is unavailable. Check the Hue Groups catalog diagnostics for the scan status.
