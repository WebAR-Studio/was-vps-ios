# WAS-VPS SDK (iOS)

This is **WAS-VPS** SDK for Native iOS apps. Main features are:
- High-precision global user position localization for your AR apps
- Easy to use public API with mandatory API key authentication
- Integration in SceneKit and RealityKit
- Works both for UIKit and SwiftUI apps
- Secure authentication with x-vps-apikey header

## Requirements

- iOS 12.0+
- Xcode 12+
- Swift 5+
- ARKit supported device

## Installation

### From sources

You can build WAS-VPS framework from this repository. 

Clone this repository and integrate the source files into your project. Add the necessary dependencies and link the framework to your app.

## Examples

Example implementations can be found in the repository demonstrating VPS service integration.

## Migration from v1.0.xd

**Breaking Changes in v1.1.0:**
- API key is now **required** for all VPS initialization
- Updated server endpoint to `https://was-vps.web-ar.xyz/vps/api/v3`
- Simplified initialization API

**Old way (v1.0.x):**
```swift
let settings = Settings(
    url: "https://was-vps.web-ar.xyz/vps/api/v3",
    locationIds: ["location_id"]
)
VPSBuilder.initializeVPS(arSession: session, settings: settings, ...)
```

**New way (v1.1.0+):**
```swift
VPSBuilder.initializeVPS(
    arSession: session,
    apiKey: "your-api-key-here",
    locationIds: ["location_id"],
    delegate: self
) { vpsService in
    self.vps = vpsService
}
```

## Usage

### User permissions

Add these permission flags to your `Info.plist` to access camera and location services:

```xml
<key>NSCameraUsageDescription</key>
    <string>This app requires access to the camera to display augmented reality content.</string>
<key>NSLocationWhenInUseUsageDescription</key>
    <string>This app needs access to your location to place AR content accurately in the real world.</string>
<key>NSLocationTemporaryUsageDescriptionDictionary</key>
    <dict>
        <key>VPSLocalization</key>
        <string>Enable precise location for accurate AR content positioning and visual localization.</string>
    </dict>
```

### Configuration

Before using the VPS service, you need to configure the initialization with required parameters:

- **apiKey**: API key for server authentication (required)
- **locationIds**: Array of location identifiers for your VPS maps
- **url**: VPS server endpoint (default: `https://was-vps.web-ar.xyz/vps/api/v3`)

### UIKit

* You must define a `ARSCNViewDelegate` delegate and call the method `vps?.frameUpdated()` each frame
* Assign the default configuration using a method `getDefaultConfiguration()` that will return nil if the device is not supported.
* You can use the delegate method `sessionWasInterrupted` to stop the VPS when the application moves foreground and start it again in `sessionInterruptionEnded`

```swift
import WASVPS
import UIKit
import ARKit

class Example: UIViewController, ARSCNViewDelegate {
    var arview: ARSCNView!
    var configuration: ARWorldTrackingConfiguration!
    var vps: VPSService?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        arview.scene = SCNScene()
        arview.delegate = self
        if let config = VPSBuilder.getDefaultConfiguration() {
            configuration = config
        } else {
            fatalError()
        }
        
        // Initialize VPS with required API key
        VPSBuilder.initializeVPS(
            arSession: arview.session,
            apiKey: "your-api-key-here",
            locationIds: ["your_location_id"],
            url: "https://was-vps.web-ar.xyz/vps/api/v3", // Optional, uses default if empty
            gpsUsage: false,
            delegate: self
        ) { vpsService in
            self.vps = vpsService
            self.vps?.start()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        arview.session.run(configuration)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        vps?.frameUpdated()
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        vps?.stop()
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        vps?.start()
    }
}

extension Example: VPSServiceDelegate {
    func positionVPS(pos: ResponseVPSPhoto) {
        print("Pos", pos)
    }
    
    func error(err: NSError) {
        print("err", err)
    }
    
    func sending(requestData: UploadVPSPhoto? = nil) {
        print("Start sending")
    }
}
```

### Custom Position for First Request

You can set custom position values for the first request after session ID update. This is useful when you want to provide specific coordinates instead of using the current device position.

```swift
// Set custom position values before starting VPS
vps?.setCustomLocPosForFirstRequest(
    x: 10.0,      // X coordinate
    y: 5.0,       // Y coordinate  
    z: 2.0,       // Z coordinate
    roll: 0.0,    // Roll angle in degrees
    pitch: 15.0,  // Pitch angle in degrees
    yaw: 90.0     // Yaw angle in degrees
)

// Start VPS - the first request will use custom values
vps?.start()

// Clear custom position if needed
vps?.clearCustomLocPos()
```



### RealityKit

Using RealityKit is similar to using SceneKit. Instead of using `func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval)` you need to use `func session(_ session: ARSession, didUpdate frame: ARFrame)` using ARSessionDelegate to call the method `vps?.frameUpdated()` each frame.

```swift
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    vps?.frameUpdated()
}
```

### SwiftUI
For better use in SwiftUI, you should use the MVVM architecture. Here is a quick example:
```swift
import SwiftUI
import ARKit
import WASVPS

struct ContentView: View {
    @StateObject var vm = ViewModel()
    @State var vpsStarted = false
    var body: some View {
    VStack {
        ARView(vm: vm)
            .background(Color.gray)
            .cornerRadius(20)
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        Button(vpsStarted ? "stop" : "start") {
            vpsStarted ? vm.vps?.stop() : vm.vps?.start()
            withAnimation(.linear) {
                vpsStarted.toggle()
            }
        }
        .frame(width: 300, height: 50, alignment: .center)
        .background(vpsStarted ? Color.red : Color.green)
        .cornerRadius(20)
        .padding()
    }
    }
}

class ViewModel: NSObject, ObservableObject, ARSCNViewDelegate, VPSServiceDelegate {
    
    var vps: VPSService?
    func initVPS(session: ARSession) {
        // Initialize VPS with required API key
        VPSBuilder.initializeVPS(
            arSession: session,
            apiKey: "your-api-key-here",
            locationIds: ["your_location_id"],
            gpsUsage: false,
            delegate: self
        ) { vpsService in
            self.vps = vpsService
        }
    }
    
    func positionVPS(pos: ResponseVPSPhoto) {
        print("POS",pos)
    }
    
    func error(err: NSError) {
        
    }
    
    func sending(requestData: UploadVPSPhoto? = nil) {
        
    }
}

struct ARView: UIViewRepresentable {
    
    @ObservedObject var vm: ViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView()
        sceneView.scene = SCNScene()
        sceneView.autoenablesDefaultLighting = true
        sceneView.delegate = vm
        vm.initVPS(session: sceneView.session)
        let config = VPSBuilder.getDefaultConfiguration()!
        config.isAutoFocusEnabled = true
        sceneView.session.run(config)
        return sceneView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
    }
    
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ()) {
        uiView.delegate = nil
    }
}
```

## License 

This project is licensed under [MIT License](LICENSE).
