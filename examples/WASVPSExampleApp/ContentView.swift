import SwiftUI
import ARKit
import SceneKit
import WASVPS

struct ContentView: View {
    @StateObject private var vpsManager = VPSManager()

    var body: some View {
        ZStack {
            // AR SceneKit View
            ARSCNViewContainer(vpsManager: vpsManager, shouldLoadModel: vpsManager.isFirstLocalizationReceived)
                .edgesIgnoringSafeArea(.all)
            
            // UI Overlay
            VStack {
                // Top statistics
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("VPS Statistics")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text("Status: \(vpsManager.vpsStatus)")
                            .font(.caption)
                            .foregroundColor(statusColor)
                    }
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("✅ Success: \(vpsManager.successCount)")
                                .foregroundColor(.green)
                            Text("❌ Failed: \(vpsManager.failureCount)")
                                .foregroundColor(.red)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("📊 Total: \(vpsManager.totalRequests)")
                                .foregroundColor(.white)
                            Text("📍 Last: \(vpsManager.lastUpdateTime)")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .padding(.horizontal)
                
                Spacer()
                
                // Bottom controls
                VStack(spacing: 16) {
                    // VPS Status indicator
                    if vpsManager.isVPSActive {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 12, height: 12)
                                .scaleEffect(vpsManager.isProcessing ? 1.5 : 1.0)
                                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: vpsManager.isProcessing)
                            
                            Text(vpsManager.isProcessing ? "Processing..." : "VPS Active")
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(20)
                    }
                    
                    // Start/Stop button
                    Button(action: {
                        if vpsManager.isVPSActive {
                            vpsManager.stopVPS()
                        } else {
                            vpsManager.startVPS()
                        }
                    }) {
                        Text(vpsManager.isVPSActive ? "Stop VPS" : "Start VPS")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 200, height: 50)
                            .background(vpsManager.isVPSActive ? Color.red : Color.green)
                            .cornerRadius(25)
                    }
                    
                    // Reset statistics button
                    Button(action: {
                        vpsManager.resetStatistics()
                    }) {
                        Text("Reset Stats")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .frame(width: 120, height: 40)
                            .background(Color.gray)
                            .cornerRadius(20)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
    
    private var statusColor: Color {
        switch vpsManager.vpsStatus {
        case .stopped:
            return .gray
        case .fastLocalized:
            return .orange
        case .normal:
            return .green
        }
    }
}

// MARK: - VPS Manager
class VPSManager: ObservableObject {
    @Published var isVPSActive = false
    @Published var isProcessing = false
    @Published var successCount = 0
    @Published var failureCount = 0
    @Published var lastUpdateTime = "Never"
    @Published var isFirstLocalizationReceived = false
    
    public var vps: VPS?
    private var pendingARSession: ARSession?
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
    
    var totalRequests: Int {
        successCount + failureCount
    }
    
    var vpsStatus: VPSStatus {
        return vps?.vpsStatus ?? .stopped
    }
    
    func startVPS() {
        guard !isVPSActive else { return }
        isVPSActive = true
        
        print("🚀 Starting VPS with real configuration...")
        print("📍 Location ID: marial")
        print("🔑 API Key: 52f80541de1715ba47f43522d648d0800c6e514d8b5e91b9b6e13ef9e1348cb8")
        
        updateLastTime()
        
        // If AR session is already available, initialize VPS immediately
        if let arSession = pendingARSession {
            initializeRealVPS(with: arSession)
        }
    }
    
    func stopVPS() {
        guard isVPSActive else { return }
        isVPSActive = false
        isProcessing = false
        isFirstLocalizationReceived = false // Reset for next session
        vps?.stop()
        updateLastTime()
    }
    
    func resetStatistics() {
        successCount = 0
        failureCount = 0
        isFirstLocalizationReceived = false // Reset PLY display flag
        lastUpdateTime = "Reset"
        updateLastTime()
    }
    
    private func updateLastTime() {
        lastUpdateTime = dateFormatter.string(from: Date())
    }
    
    // Method to trigger UI update when VPS status changes
    private func refreshStatus() {
        // This will trigger UI update since vpsStatus is a computed property
        objectWillChange.send()
    }
    
    // Set AR session and initialize VPS if needed
    func setARSession(_ arSession: ARSession) {
        pendingARSession = arSession
        
        // If VPS is already active, initialize it now
        if isVPSActive && vps == nil {
            initializeRealVPS(with: arSession)
        }
    }
    
    func initializeRealVPS(with arSession: ARSession) {
        guard isVPSActive && vps == nil else { return }
        
        VPSBuilder.initializeVPS(
            arSession: arSession,
            apiKey: "52f80541de1715ba47f43522d648d0800c6e514d8b5e91b9b6e13ef9e1348cb8",
            locationIds: ["mariel"],
            gpsUsage: false,
            delegate: self
        ) { [weak self] vpsService in
            self?.vps = vpsService
            self?.vps?.start()
        }
    }
}

// MARK: - VPS Service Delegate

extension VPSManager: VPSServiceDelegate {
    
    func positionVPS(pos: ResponseVPSPhoto) {
        print("VPS Localized: \(pos)")
        DispatchQueue.main.async {
            self.isProcessing = false
            if pos.status {
                self.successCount += 1
                
                // Mark first localization
                if !self.isFirstLocalizationReceived {
                    self.isFirstLocalizationReceived = true
                    print("🎯 First VPS localization received! Showing PLY model...")
                }
            } else {
                self.failureCount += 1
            }
            self.updateLastTime()
            self.refreshStatus() // Update UI to reflect VPS status changes
        }
    }
    
    func error(err: NSError) {
        print("VPS Error: \(err.localizedDescription)")
        DispatchQueue.main.async {
            self.isProcessing = false
            self.failureCount += 1
            self.updateLastTime()
            self.refreshStatus() // Update UI to reflect VPS status changes
        }
    }
    
    func sending(requestData: UploadVPSPhoto?) {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.refreshStatus() // Update UI to reflect VPS status changes
        }
    }
    
    func onUpdateSessionId(_ sessionId: String) {
        print("VPS Session ID updated: \(sessionId)")
    }
}

// MARK: - AR SceneKit View Container

struct ARSCNViewContainer: UIViewRepresentable {
    
    let vpsManager: VPSManager
    let shouldLoadModel: Bool
    
    func makeUIView(context: Context) -> ARSCNView {
        let arscnView = ARSCNView(frame: .zero)
        
        // Store reference for point cloud rendering
        context.coordinator.arscnView = arscnView
        
        // Configure AR session with VPS-optimized settings
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        
        // Use the optimal video format for VPS if available
        if let vpsConfig = VPSBuilder.getDefaultConfiguration() {
            configuration.videoFormat = vpsConfig.videoFormat
            print("📹 Using VPS-optimized video format: \(vpsConfig.videoFormat)")
        }
        
        arscnView.session.run(configuration)
        
        // Set up frame delegate for VPS updates
        arscnView.session.delegate = context.coordinator
        
        // Store AR session reference and initialize VPS if needed
        context.coordinator.arSession = arscnView.session
        
        // Provide AR session to VPS manager
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            vpsManager.setARSession(arscnView.session)
        }
        
        return arscnView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        print("🔄 updateUIView called - shouldLoadModel: \(shouldLoadModel), isPLYModelLoaded: \(context.coordinator.isPLYModelLoaded)")
        
        // Update first localization status
        context.coordinator.hasFirstLocalization = shouldLoadModel
        
        // Show PLY model when first localization is received
        if shouldLoadModel && !context.coordinator.isPLYModelLoaded {
            print("🎯 updateUIView: First localization received, loading PLY model...")
            context.coordinator.loadPLYModel()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(vpsManager: vpsManager)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        let vpsManager: VPSManager
        var arSession: ARSession?
        var arscnView: ARSCNView?
        var isPLYModelLoaded = false
        var plyPoints: [PlyPoint] = [] // Will hold parsed PLY points
        
        // SceneKit properties for point cloud rendering
        var pointCloudNode: SCNNode?
        var hasFirstLocalization: Bool = false
        var currentPointAlpha: Float = 1.0
        
        init(vpsManager: VPSManager) {
            self.vpsManager = vpsManager
            super.init()
        }
        
        func loadPLYModel() {
            guard !isPLYModelLoaded else { return }
            
            print("🎯 Loading model at zero transform after first VPS localization...")
            
            // Step 1: Read Data from model.ply file
            guard let plyURL = Bundle.main.url(forResource: "model", withExtension: "ply") else {
                print("❌ PLY file 'model.ply' not found in bundle")
                print("📦 Bundle path: \(Bundle.main.bundlePath)")
                print("📂 Bundle contents:")
                if let bundleContents = try? FileManager.default.contentsOfDirectory(atPath: Bundle.main.bundlePath) {
                    for file in bundleContents.prefix(10) { // Show first 10 files
                        print("   - \(file)")
                    }
                }
                isPLYModelLoaded = true
                return
            }
            
            print("✅ Found PLY file at: \(plyURL)")
            
            do {
                let plyData = try Data(contentsOf: plyURL)
                print("📊 PLY file size: \(plyData.count) bytes")
                
                // Step 2: Parse PLY data using PlyParser
                do {
                    let parsedPoints = try PlyParser.parsePlyData(plyData)
                    print("✅ Successfully parsed \(parsedPoints.count) points from PLY file")
                    
                    DispatchQueue.main.async { [weak self] in
                        self?.plyPoints = parsedPoints
                        self?.updatePlyPointCloud()
                    }
                } catch {
                    print("❌ Failed to parse PLY data: \(error)")
                }
                
            } catch {
                print("❌ Failed to read PLY file: \(error)")
            }
            
            isPLYModelLoaded = true
        }
        
        // MARK: - SceneKit Point Cloud Rendering
        
        func updatePlyPointCloud() {
            pointCloudNode?.removeFromParentNode()
            guard let arscnView, !plyPoints.isEmpty, hasFirstLocalization else { return }

            let vertices = plyPoints.map { SCNVector3($0.position.x, $0.position.y, $0.position.z) }
            let vertexSource = SCNGeometrySource(vertices: vertices)

            // Используем цвета из PLY файла
            var colors = plyPoints.map { plyPoint in
                SIMD4<Float>(plyPoint.color.x, plyPoint.color.y, plyPoint.color.z, currentPointAlpha)
            }
            let colorsData = Data(bytes: &colors, count: colors.count * MemoryLayout<SIMD4<Float>>.stride)
            let colorSource = SCNGeometrySource(
                data: colorsData,
                semantic: .color,
                vectorCount: colors.count,
                usesFloatComponents: true,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.stride,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD4<Float>>.stride
            )

            let indices = (0..<plyPoints.count).map { UInt32($0) }
            let pointsElement = SCNGeometryElement(indices: indices, primitiveType: .point)
            pointsElement.pointSize = 8.0
            pointsElement.minimumPointScreenSpaceRadius = 2
            pointsElement.maximumPointScreenSpaceRadius = 20

            let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [pointsElement])
            geometry.firstMaterial?.isDoubleSided = true
            geometry.firstMaterial?.lightingModel = .constant
            geometry.firstMaterial?.writesToDepthBuffer = false
            geometry.firstMaterial?.transparency = CGFloat(currentPointAlpha)

            let node = SCNNode(geometry: geometry)
            arscnView.scene.rootNode.addChildNode(node)
            pointCloudNode = node
            
            print("Отрисовано \(plyPoints.count) точек из PLY файла")
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Call frameUpdated for VPS interpolation if VPS is active
            if vpsManager.isVPSActive {
                vpsManager.vps?.frameUpdated()
            }
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("AR Session failed with error: \(error.localizedDescription)")
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            print("AR Session was interrupted")
            vpsManager.vps?.stop()
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            print("AR Session interruption ended")
            if vpsManager.isVPSActive {
                vpsManager.vps?.start()
            }
        }
    }
}

#Preview {
    ContentView()
}
