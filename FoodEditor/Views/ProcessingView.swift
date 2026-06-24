import SwiftUI

/// Screen 3 — Processing. Runs the real pipeline behind the mockup's calm terracotta arc:
/// M2 merge+compress → M3 Gemini analysis. For M3 it shows the RAW Gemini JSON on screen (and logs
/// it to the console) so we can verify response quality before building any editing UI. (M4 will
/// parse it into an Edit Plan and fire a completion notification.)
struct ProcessingView: View {
    @Environment(AppRouter.self) private var router
    @Environment(VideoSession.self) private var session
    @Environment(ProjectService.self) private var projects
    @Environment(AnalysisCoordinator.self) private var analysis
    @Environment(TemplateService.self) private var templates

    /// B-roll coverage seeding cap: the brief's lean wins, else the active template's learned heaviness,
    /// else a sane default. Makes the "Lean on b-roll" choice tangibly change how much overlay is placed.
    private var brollCoverageTarget: Double {
        session.brief?.brollLean.coverageTarget ?? templates.active?.profile.broll.heaviness ?? 0.25
    }

    var body: some View {
        ZStack {
            Color.veCream.ignoresSafeArea()
            switch analysis.phase {
            case .done:
                // The plan now lives on the session (written by the coordinator); the raw JSON on the
                // coordinator. If either is briefly missing, fall back to the working spinner.
                if let plan = session.store?.plan, let raw = analysis.rawResponse {
                    doneState(plan, raw)
                } else {
                    workingState
                }
            case .failed(let message):
                errorState(message)
            case .idle, .running:
                workingState
            }
        }
        // Idempotent — safe to fire on every (re)mount; the coordinator runs the pipeline at most once
        // per submitted clip set and survives this view disappearing. The active style (if any) is injected.
        .task { analysis.start(session: session, projects: projects,
                               styleBlock: StyleConstraintBuilder.block(for: templates.active),
                               briefBlock: BriefPromptBuilder.block(for: session.brief),
                               brollCoverageTarget: brollCoverageTarget) }
    }

    // MARK: working

    private var workingState: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().stroke(Color(hex: 0xE7DECE), lineWidth: 5).frame(width: 132, height: 132)
                Circle()
                    .trim(from: 0, to: max(0.02, analysis.progress))
                    .stroke(Color.veTerracotta, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 132, height: 132)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: analysis.progress)
                Text("\(Int(analysis.progress * 100))%")
                    .font(VeFont.serif(34))
                    .foregroundStyle(Color.veTerracotta)
            }
            Text(analysis.label)
                .font(VeFont.serif(25))
                .foregroundStyle(Color.veCharcoal)
                .multilineTextAlignment(.center)
                .animation(.easeInOut, value: analysis.label)
            Text("Analyzing can take a minute on longer videos — hang tight.")
                .font(VeFont.sans(13))
                .foregroundStyle(Color.veWarmGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if let active = templates.active {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").font(.system(size: 10))
                    Text("Cutting in your “\(active.name)” style")
                        .font(VeFont.sans(12.5, weight: .semibold))
                }
                .foregroundStyle(Color.veTerracotta)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Color.veTerracotta.opacity(0.1), in: Capsule())
            }
            Spacer()
        }
        .padding(40)
    }

    // MARK: done (M4 — decoded summary + raw JSON)

    private func doneState(_ plan: EditPlan, _ raw: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top bar so the user is never stuck here (this is pre-editor, so NO stage nav bar):
            // Cancel (left) steps back to the picker, Home (right, mockup style) exits to the Kitchen.
            HStack {
                Button("Cancel") { router.back() }
                    .font(VeFont.sans(13, weight: .semibold))
                    .foregroundStyle(Color.veWarmGray)
                Spacer()
                HomeButton { router.home() }
            }
            .padding(.top, 54)
            .padding(.horizontal, 22)

            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24)).foregroundStyle(Color.veSage)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Analysis ready")
                        .font(VeFont.serif(22)).foregroundStyle(Color.veCharcoal)
                    if let m = session.merged {
                        Text("\(session.clips.count) clips → 1 video · \(m.metadata.fileSizeText) · \(m.metadata.resolutionText)")
                            .font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
                    }
                }
                Spacer()
            }
            .padding(.top, 4)
            .padding(.horizontal, 22)

            summaryCard(plan).padding(.horizontal, 22)

            DisclosureGroup {
                ScrollView {
                    Text(raw)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.veCharcoal)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 240)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } label: {
                Text("Raw JSON (\(raw.count) chars)")
                    .font(VeFont.sans(13, weight: .bold))
                    .foregroundStyle(Color.veWarmGray)
            }
            .tint(Color.veTerracotta)
            .padding(.horizontal, 22)

            Spacer(minLength: 0)

            PrimaryActionButton(title: "See the breakdown") { router.go(.segments) }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
        }
    }

    private func summaryCard(_ plan: EditPlan) -> some View {
        let kept = plan.segments.filter { $0.keep }.count
        let vo = plan.segments.filter { $0.voiceoverCandidate }.count
        let lowConf = plan.segments.filter { $0.isLowConfidence }.count
        return VStack(alignment: .leading, spacing: 12) {
            if !plan.videoSummary.isEmpty {
                Text("“\(plan.videoSummary)”")
                    .font(VeFont.serif(16, italic: true))
                    .foregroundStyle(Color(hex: 0x4A453E))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                statPill("\(plan.segments.count)", "segments")
                statPill("\(kept)", "keep")
                statPill("\(vo)", "voiceover")
                if lowConf > 0 { statPill("\(lowConf)", "to review") }
            }
            if !plan.recommendedHook.isEmpty {
                metaLine("Hook", plan.recommendedHook)
            }
            metaLine("Suggested length", "\(Int(plan.recommendedDuration))s")
            if let notes = plan.styleMatchNotes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WHAT WE DID WITH YOUR BRIEF")
                        .font(VeFont.sans(10, weight: .bold)).tracking(0.4)
                        .foregroundStyle(Color.veFaintGray)
                    Text(notes)
                        .font(VeFont.serif(14, italic: true))
                        .foregroundStyle(Color.veNoteText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.veNote, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.05), radius: 8, y: 2)
    }

    private func statPill(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(VeFont.sans(18, weight: .bold)).foregroundStyle(Color.veTerracotta)
            Text(label).font(VeFont.sans(10.5)).foregroundStyle(Color.veWarmGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.veNote, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(VeFont.sans(10, weight: .bold)).tracking(0.4)
                .foregroundStyle(Color.veFaintGray)
            Text(value).font(VeFont.sans(13)).foregroundStyle(Color.veCharcoal)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: error

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34)).foregroundStyle(Color.veTerracotta)
            Text("Something went wrong")
                .font(VeFont.serif(22)).foregroundStyle(Color.veCharcoal)
            Text(message)
                .font(VeFont.sans(13)).foregroundStyle(Color.veWarmGray)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            HStack(spacing: 10) {
                Button("← Back") { router.back() }
                    .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veWarmGray)
                Button("Retry") { analysis.retry(session: session, projects: projects,
                                                 styleBlock: StyleConstraintBuilder.block(for: templates.active),
                                                 briefBlock: BriefPromptBuilder.block(for: session.brief),
                                                 brollCoverageTarget: brollCoverageTarget) }
                    .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veTerracotta)
            }
            .padding(.bottom, 30)
        }
    }
}
