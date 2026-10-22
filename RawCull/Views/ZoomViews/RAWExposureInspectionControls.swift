import AppKit
import RawCullCore
import SwiftUI

struct RAWExposureInspectionControls: View {
    @Bindable var session: ZoomSessionModel
    let image: CGImage?
    @State private var showsHistogram = true
    @State private var controlsWidth: CGFloat = 0
    /// Dragging changes only this small view. Commit to the render request on release.
    @State private var draftExposureEV = 0.0

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("EV analysis")
                if session.evaluateRAWExposure {
                    Text("Exposure")
                    Slider(value: $draftExposureEV, in: -5 ... 5, step: 0.1) { editing in
                        if !editing {
                            session.rawExposureEV = draftExposureEV
                            session.committedRAWExposureEV = draftExposureEV
                        }
                    }
                    .frame(width: 180)
                    .accessibilityLabel("RAW inspection exposure")
                    .accessibilityValue("\(draftExposureEV.formatted(.number.precision(.fractionLength(1)))) EV")
                    .help("Adjust RAW exposure from −5 to +5 EV. Release to develop the preview.")
                    Text("\(draftExposureEV.formatted(.number.precision(.fractionLength(1)))) EV")
                        .monospacedDigit()
                        .frame(width: 65, alignment: .trailing)
                    Button("Reset") {
                        draftExposureEV = 0
                        session.rawExposureEV = 0
                        session.committedRAWExposureEV = 0
                    }
                    .disabled(draftExposureEV == 0)
                }
                Toggle("Clipping warning", isOn: $session.showRAWClippingWarning)
                    .toggleStyle(.button)
                    .help("Red: near-white preview pixels. Blue: near-black preview pixels. These warnings do not prove RAW detail is unrecoverable.")
                Button("Close", systemImage: "xmark") {
                    session.endRAWExposureInspection()
                }
                .help("Close EV analysis and restore the previous RAW settings")
            }
            .fixedSize(horizontal: true, vertical: false)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                controlsWidth = width
            }
            DisclosureGroup("Preview histogram", isExpanded: $showsHistogram) {
                RAWExposureHistogramView(image: image)
                    .padding(.top, 4)
            }
            .frame(width: controlsWidth)
        }
        .fixedSize(horizontal: true, vertical: false)
        .font(.caption)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { draftExposureEV = session.committedRAWExposureEV }
        .onChange(of: session.committedRAWExposureEV) { _, value in draftExposureEV = value }
    }
}
