# Tuna Hue Control

A native Swift extension for the [Tuna launcher](https://tunaformac.com). It reads rooms and zones from one Philips Hue Bridge over the local CLIP v2 API and offers **Turn On** and **Turn Off** for each group with a `grouped_light` service.

Search for **Benny Wohnzimmer** and choose the **Hue Zone** result to control that zone. If your bridge also has a **Wohnzimmer** room, the **Hue Room** result controls the entire room. Press **Tab** to pick the action. Group names come from your bridge.

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

## Connect the bridge

1. Find the bridge’s local IPv4 address and its full 16-character hexadecimal bridge ID. The Hue app shows bridge details, and the [Hue discovery service](https://discovery.meethue.com) can return the ID and local IP for bridges on your network.
2. Download the root CA PEM for your bridge from [Philips Hue’s HTTPS guidance](https://developers.meethue.com/develop/application-design-guidance/using-https/) and save it locally. That page may require a Hue developer login.
3. Use an existing Hue application key or create one using the bridge’s physical link button, as shown below.
4. In Tuna, open **Settings → Sources → Extensions → Hue Control**. Enter the bridge address, bridge ID, application key, and absolute path to the PEM file. Tuna stores the key in the macOS Keychain.
5. Rescan **Hue Groups** in Sources or restart Tuna. If macOS asks for local network access, allow it for Tuna.

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

The extension uses the configured address to connect and the bridge ID to verify the certificate against the supplied Hue CA. If a scan fails, check the address, ID, key, and CA in the extension settings, then look at the catalog diagnostics. This proof of concept uses manual setup and explicit on/off actions. It does not show current power state.
