import SwiftUI

struct JITView: View {
    @EnvironmentObject private var engine: Engine
    let bundleID: String
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var controller: JITController
    
    init(bundleID: String, engine: Engine) {
        self.bundleID = bundleID
        _controller = StateObject(wrappedValue: JITController(engine: engine, targetBundleID: bundleID))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PanelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("JIT Status")
                                .font(.headline)
                            
                            statusLabel
                            
                            if !controller.logs.isEmpty {
                                Divider()
                                ScrollViewReader { proxy in
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(Array(controller.logs.enumerated()), id: \.offset) { idx, log in
                                                Text(log)
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(.secondary)
                                                    .id(idx)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(maxHeight: 200)
                                    .onChange(of: controller.logs.count) {
                                        withAnimation {
                                            proxy.scrollTo(controller.logs.count - 1, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if controller.state == .idle || isFailed {
                        Button {
                            Task { await controller.enableJIT() }
                        } label: {
                            Text(isFailed ? "Retry" : "Enable JIT")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    } else if controller.state != .completed {
                        ProgressView()
                            .padding()
                    }
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("Enable JIT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    @ViewBuilder
    private var statusLabel: some View {
        switch controller.state {
        case .idle:
            Text("Ready to enable JIT.")
        case .preparing:
            Text("Preparing device and tunnel...")
        case .launching:
            Text("Launching app...")
        case .attaching:
            Text("Attaching debugger...")
        case .enabling:
            Text("Enabling JIT...")
        case .detaching:
            Text("Detaching debugger...")
        case .completed:
            Label("JIT enabled successfully!", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.headline)
        case .failed(let msg):
            Label("Failed: \(msg)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.headline)
        }
    }
    
    private var isFailed: Bool {
        if case .failed = controller.state { return true }
        return false
    }
}
