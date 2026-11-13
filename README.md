# Halo VPN

Halo VPN is an iOS app. Open `VPN.xcodeproj` in Xcode and select the `VPN` scheme. Set up signing for the app and the Packet Tunnel extension before building for a device.

The VPN backend, Apphud, and AppsFlyer read their configuration from Xcode build settings. To enable these integrations, create a local `Secrets.xcconfig` in the project root with the values for your deployment.

```xcconfig
VPN_BACKEND_APP_SECRET =
APPHUD_API_KEY =
APPSFLYER_DEV_KEY =
```

Build with that configuration file.

```sh
xcodebuild -project VPN.xcodeproj -scheme VPN -xcconfig Secrets.xcconfig build
```

For CI, supply the same build settings from your CI secret store.
