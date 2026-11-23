# Tuna Hue Control

Control Philips Hue rooms and zones from the [Tuna launcher](https://tunaformac.com) on your Mac. Connect one or more Hue Bridges, then search for a room or zone by name to turn its lights on or off.

## Get started

You’ll need macOS 15 or later, Tuna 0.113 or later, and a Philips Hue Bridge on the same network as your Mac. The extension is currently installed from source. [Build and installation instructions](DEVELOP.md#build-and-install-from-source)

1. In Tuna, search for **Hue** and choose **Connect First Hue Bridge**. If the command is missing, open Tuna’s **Sources** settings and set **Hue Groups → In global search** to **All**.
2. Select your bridge and choose **Continue**. When prompted, press the physical link button on that bridge. You have about 90 seconds. If the prompt times out, choose **Try Again**.
3. Allow Tuna to access the local network if macOS asks. Once the bridge is connected, its rooms and zones appear in Tuna search.

## Control your lights

Search for the name of a room or zone. Look for **Hue Room** or **Hue Zone** in the result details to distinguish them. The details also show which bridge the group belongs to.

- **Turn On** appears when the bridge reports the group is off. **Turn Off** appears when it’s on. Tuna offers both actions if the bridge can’t report the current power state.
- If every light in the group is unreachable, the result says **Offline**. Choose **Check Connection** to ask the bridge for an updated status. Power controls return when at least one light is reachable.

Press **Tab** to choose an available action.

## Manage your bridges

Use **Add Hue Bridge** to connect another bridge. Use **Manage Hue Bridges** to disconnect a bridge from Tuna. To change a bridge’s manual settings, disconnect it and add it again.

If your bridge doesn’t appear in the picker, check that your Mac and bridge are on the same network, then choose **Refresh**. You can also choose **Enter IP Address…** and provide the bridge’s local address, its 16-character bridge ID, and a Hue application key. Leave the optional certificate field blank for a standard Hue setup. [How to create an application key](DEVELOP.md#create-an-application-key-for-manual-setup)
