# Tuna Hue Control

Control Philips Hue rooms and zones from the [Tuna launcher](https://tunaformac.com) on your Mac. Connect one or more Hue Bridges, then search for a room or zone by name to turn its lights on or off.

## Connect your first Hue Bridge

You’ll need macOS 15 or later, Tuna 0.113 or later, and a Philips Hue Bridge on the same network as your Mac. The extension is currently installed from source. [Build and installation instructions](DEVELOP.md#build-and-install-from-source)

1. In Tuna, search for **Hue** and choose **Connect First Hue Bridge**. If the command is missing, open Tuna’s **Sources** settings and set **Hue Groups → In global search** to **All**.
2. Select your bridge and choose **Continue**. When prompted, press the physical link button on that bridge. You have about 90 seconds. If the prompt times out, choose **Try Again**.
3. Allow Tuna to access the local network if macOS asks. Once the bridge is connected, its rooms and zones appear in Tuna search.

## Turn a room on or off

1. Search for the room by name in Tuna and select the **Hue Room** result.
2. Press **Tab**, then choose **Turn On** or **Turn Off**. To switch it back, search for the room again and choose the other action.

See the [full walkthrough](https://bjesuiter.github.io/tuna-hue/how-it-works/) for screenshots, manual pairing, bridge management, and checking offline lights.
