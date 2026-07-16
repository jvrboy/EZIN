import SwiftUI

/// GAMES tab — a built-in arcade of quick, educational games that run fully on-device.
/// No network, no accounts, no purchases: just playable systems that teach physics,
/// math, music, language, biology and quantum intuition.
struct GamesView: View {
    private let games: [GameInfo] = [
        .init(title: "Quantum Cat Box", subtitle: "Predict superposition, entanglement and collapse", icon: "cat.fill", tint: Glass.accent, concept: "Quantum physics"),
        .init(title: "Frequency Frog", subtitle: "Hop scales and chords across the lily keyboard", icon: "music.note", tint: Glass.accent2, concept: "Music theory"),
        .init(title: "Fraction Fighter", subtitle: "Land hits by solving math faster than the bot", icon: "function", tint: .orange, concept: "Math combat"),
        .init(title: "Gravity Golf", subtitle: "Mini-golf on the Moon, Mars, Jupiter and a black hole", icon: "circle.hexagongrid.fill", tint: .purple, concept: "Orbital physics"),
        .init(title: "Tower of Babel", subtitle: "Stack translation blocks and dodge false friends", icon: "building.columns.fill", tint: .mint, concept: "Languages"),
        .init(title: "Taxonomy Tetris", subtitle: "Sort organisms into the tree of life before the stack rises", icon: "leaf.fill", tint: .green, concept: "Biology")
    ]

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    ForEach(games) { game in
                        NavigationLink { destination(for: game) } label: {
                            GameCard(game: game)
                        }
                        .buttonStyle(.plain)
                    }
                    footer
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EZIN Arcade")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Playable mini-games built into the app. Every game is deterministic enough to be fair, random enough to be replayable, and teaches one real concept while you play.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(14)
        .glassCard()
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill").foregroundStyle(Glass.accent)
            Text("Tip: every game keeps score locally in memory while the tab is open. Switch tabs freely — the arcade resets cleanly with no crashes.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(14)
        .glassCard()
    }

    @ViewBuilder
    private func destination(for game: GameInfo) -> some View {
        switch game.title {
        case "Quantum Cat Box": QuantumCatGame()
        case "Frequency Frog": FrequencyFrogGame()
        case "Fraction Fighter": FractionFighterGame()
        case "Gravity Golf": GravityGolfGame()
        case "Tower of Babel": BabelBuilderGame()
        case "Taxonomy Tetris": TaxonomySortGame()
        default: QuantumCatGame()
        }
    }
}

private struct GameInfo: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let concept: String
}

private struct GameCard: View {
    let game: GameInfo
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(game.tint.opacity(0.22))
                Image(systemName: game.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(game.tint)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.94))
                Text(game.subtitle).font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                Text(game.concept.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(game.tint.opacity(0.9))
            }
            Spacer()
            Image(systemName: "play.fill").foregroundStyle(.white.opacity(0.45))
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Shared game chrome

private struct GameScreen<Content: View>: View {
    let title: String
    let lesson: String
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(lesson).font(.caption).foregroundStyle(.white.opacity(0.58)).padding(12).glassCard()
                    content
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ScoreBar: View {
    let score: Int
    let streak: Int
    let lives: Int
    var body: some View {
        HStack {
            Label("\(score)", systemImage: "star.fill")
            Spacer()
            Label("x\(streak)", systemImage: "flame.fill")
            Spacer()
            Label("\(lives)", systemImage: "heart.fill")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.85))
        .padding(12)
        .glassCard()
    }
}

private struct PrimaryGameButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Image(systemName: icon); Text(title).fontWeight(.semibold) }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Glass.accent.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Game 1: Quantum Cat Box

private struct QuantumCatGame: View {
    enum CatState: String, CaseIterable, Identifiable {
        case alive = "Alive", dead = "Dead", superposition = "Superposition"
        var id: String { rawValue }
        var icon: String { self == .alive ? "heart.fill" : self == .dead ? "xmark.octagon.fill" : "circle.dotted" }
    }

    @State private var level = 1
    @State private var score = 0
    @State private var streak = 0
    @State private var lives = 3
    @State private var opened = false
    @State private var prediction: CatState = .superposition
    @State private var result: CatState = .superposition
    @State private var message = "Seal the box, choose a prediction, then observe."
    @State private var entangled = false

    private var concept: String {
        switch level {
        case 1...4: return "Superposition: before observation the cat is treated as a probability state, not a secret fact."
        case 5...8: return "Entanglement: two boxes are linked; opening one collapses the partner instantly."
        case 9...12: return "Tunneling: the cat has a small chance to appear past a barrier."
        default: return "Quantum Zeno effect: frequent observations can freeze a state in place."
        }
    }

    var body: some View {
        GameScreen(title: "Quantum Cat Box", lesson: concept) {
            ScoreBar(score: score, streak: streak, lives: lives)
            VStack(spacing: 14) {
                Text("Level \(level)\(entangled ? " · Entangled pair" : "")")
                    .font(.headline).foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 16) {
                    catBox(label: "Box A", state: opened ? result : .superposition)
                    if entangled { catBox(label: "Box B", state: opened ? (result == .alive ? .dead : .alive) : .superposition) }
                }
                HStack(spacing: 8) {
                    ForEach(CatState.allCases) { state in
                        Button { prediction = state } label: {
                            VStack(spacing: 4) {
                                Image(systemName: state.icon)
                                Text(state.rawValue).font(.system(size: 10, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill((prediction == state ? Glass.accent : Color.white).opacity(prediction == state ? 0.4 : 0.06)))
                            .foregroundStyle(.white.opacity(prediction == state ? 1 : 0.55))
                        }
                        .buttonStyle(.plain)
                    }
                }
                PrimaryGameButton(title: opened ? "Seal next box" : "Open the box", icon: opened ? "arrow.clockwise" : "eye.fill") {
                    opened ? nextRound() : reveal()
                }
                Text(message).font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.62)).padding(12).glassCard()
            }
            .padding(14)
            .glassCard()
        }
    }

    private func catBox(label: String, state: CatState) -> some View {
        VStack(spacing: 8) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.5))
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 1))
                VStack(spacing: 6) {
                    Image(systemName: state == .superposition ? "cat.fill" : state.icon)
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(state == .alive ? Glass.buy : state == .dead ? Glass.sell : Glass.accent2)
                    Text(state.rawValue).font(.caption).foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(width: entangled ? 132 : 180, height: 150)
        }
    }

    private func reveal() {
        let roll = Double.random(in: 0...1)
        if level >= 9 && roll < 0.08 {
            result = prediction // Zeno/tunneling gift: careful observation pays off.
        } else {
            result = roll < 0.45 ? .alive : roll < 0.90 ? .dead : .superposition
        }
        opened = true
        if prediction == result {
            streak += 1
            score += 100 + streak * 20 + (entangled ? 40 : 0)
            message = "Correct. Observation collapsed the state you predicted."
        } else {
            streak = 0
            lives -= 1
            message = "Missed. In quantum mechanics, prediction means assigning probabilities — then accepting collapse."
        }
        if lives <= 0 { reset() }
    }

    private func nextRound() {
        level += 1
        entangled = level >= 5 && level <= 8
        opened = false
        message = entangled ? "Entangled boxes: if A is alive, B must be dead." : "Seal the box, choose a prediction, then observe."
    }

    private func reset() {
        level = 1; score = 0; streak = 0; lives = 3; opened = false; entangled = false
        message = "New run. The Professor refilled the boxes."
    }
}

// MARK: - Game 2: Frequency Frog

private struct FrequencyFrogGame: View {
    private let pads: [(note: String, freq: Double)] = [
        ("C", 261.63), ("D", 293.66), ("E", 329.63), ("F", 349.23), ("G", 392.00), ("A", 440.00), ("B", 493.88), ("C5", 523.25)
    ]
    private let modes: [(name: String, sequence: [String], lesson: String)] = [
        ("Major scale", ["C", "D", "E", "F", "G", "A", "B", "C5"], "A major scale follows whole-whole-half-whole-whole-whole-half steps."),
        ("Pentatonic", ["C", "D", "E", "G", "A", "C5"], "Pentatonic removes tense half steps, which is why it sounds open and singable."),
        ("Minor color", ["A", "B", "C", "D", "E", "F", "G", "A"], "Natural minor starts on A and uses the same key signature as C major."),
        ("Chord arpeggio", ["C", "E", "G", "C5", "G", "E", "C"], "A C major triad is root + major third + perfect fifth: C, E, G.")
    ]

    @State private var modeIndex = 0
    @State private var progress = 0
    @State private var score = 0
    @State private var streak = 0
    @State private var lives = 3
    @State private var water = 0.18
    @State private var lastPad: String?
    @State private var message = "Hop the pads in the shown order before the water rises."

    private var mode: (name: String, sequence: [String], lesson: String) { modes[modeIndex % modes.count] }

    var body: some View {
        GameScreen(title: "Frequency Frog", lesson: mode.lesson) {
            ScoreBar(score: score, streak: streak, lives: lives)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(mode.name).font(.headline).foregroundStyle(.white)
                    Spacer()
                    Button("Change mode") { modeIndex += 1; restartMode() }.font(.caption).foregroundStyle(Glass.accent2)
                }
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.blue.opacity(0.18))
                    VStack {
                        Text(targetText).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                            .padding(.top, 16)
                        Spacer()
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(pads, id: \.note) { pad in
                                Button { tap(pad.note) } label: {
                                    VStack(spacing: 3) {
                                        Text(pad.note).font(.system(size: 18, weight: .bold))
                                        Text(String(format: "%.1f Hz", pad.freq)).font(.system(size: 8, design: .monospaced))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 58)
                                    .background(RoundedRectangle(cornerRadius: 14).fill((lastPad == pad.note ? Glass.accent : Color.white).opacity(lastPad == pad.note ? 0.55 : 0.10)))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.16), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 18)
                    }
                    Rectangle()
                        .fill(LinearGradient(colors: [Color.cyan.opacity(0.05), Color.blue.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 260 * water)
                        .allowsHitTesting(false)
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.14), lineWidth: 1))
                Text(message).font(.caption).foregroundStyle(.white.opacity(0.62)).padding(12).glassCard()
                PrimaryGameButton(title: "Restart lily pond", icon: "arrow.clockwise") { fullReset() }
            }
            .padding(14)
            .glassCard()
        }
    }

    private var targetText: String {
        mode.sequence.enumerated().map { idx, note in idx == progress ? "[\(note)]" : note }.joined(separator: "  ")
    }

    private func tap(_ note: String) {
        lastPad = note
        let expected = mode.sequence[min(progress, mode.sequence.count - 1)]
        if note == expected {
            progress += 1
            streak += 1
            score += 25 + streak * 3
            water = max(0.12, water - 0.025)
            message = "Clean hop. \(Int((Double(progress) / Double(mode.sequence.count)) * 100))% of the phrase complete."
            if progress >= mode.sequence.count {
                score += 150
                message = "Phrase complete — the frog sang a clean \(mode.name)."
                modeIndex += 1
                restartMode(advance: false)
            }
        } else {
            streak = 0
            lives -= 1
            water = min(0.96, water + 0.16)
            message = "Wrong note. The water jumped: expected \(expected), heard \(note)."
            if lives <= 0 || water >= 0.95 { fullReset() }
        }
    }

    private func restartMode(advance: Bool = true) {
        if advance { modeIndex += 0 }
        progress = 0
        water = 0.18
        message = "New phrase. Listen with your eyes: hop the bracketed note next."
    }

    private func fullReset() {
        score = 0; streak = 0; lives = 3; progress = 0; water = 0.18; modeIndex = 0
        message = "Fresh pond. Major scale first."
    }
}

// MARK: - Game 3: Fraction Fighter

private struct FractionFighterGame: View {
    struct Question {
        let prompt: String
        let answer: String
        let damage: Int
        let lesson: String
    }

    @State private var level = 1
    @State private var playerHP = 100
    @State private var enemyHP = 100
    @State private var score = 0
    @State private var streak = 0
    @State private var input = ""
    @State private var question = FractionFighterGame.makeQuestion(level: 1)
    @State private var log: [String] = ["Fight start: solve to strike. Wrong answers let the bot counter."]

    var body: some View {
        GameScreen(title: "Fraction Fighter", lesson: question.lesson) {
            ScoreBar(score: score, streak: streak, lives: max(0, playerHP / 34))
            VStack(spacing: 12) {
                hpBar(title: "You", hp: playerHP, tint: Glass.buy)
                hpBar(title: "Bot", hp: enemyHP, tint: Glass.sell)
                Text(question.prompt).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    TextField("answer", text: $input)
                        .keyboardType(.numbersAndPunctuation)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.14), lineWidth: 1))
                        .onSubmit(attack)
                    PrimaryGameButton(title: "Strike", icon: "bolt.fill") { attack() }
                        .frame(width: 132)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(log.prefix(6).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption).foregroundStyle(.white.opacity(0.62))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassCard()
            }
            .padding(14)
            .glassCard()
        }
    }

    private func hpBar(title: String, hp: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption).foregroundStyle(.white.opacity(0.65)); Spacer(); Text("\(max(0, hp)) HP").font(.caption2).foregroundStyle(.white.opacity(0.5)) }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(tint.opacity(0.75)).frame(width: geo.size.width * CGFloat(max(0, hp)) / 100)
                }
            }
            .frame(height: 8)
        }
    }

    private func attack() {
        let guess = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !guess.isEmpty else { return }
        if FractionFighterGame.normalized(guess) == FractionFighterGame.normalized(question.answer) {
            let dmg = min(60, question.damage + streak * 6)
            enemyHP -= dmg
            streak += 1
            score += dmg
            log.insert("Hit \(dmg): \(question.prompt) = \(question.answer).", at: 0)
            if enemyHP <= 0 {
                level += 1
                enemyHP = 100
                playerHP = min(100, playerHP + 25)
                log.insert("Bot down. Level \(level) begins — questions scale up.", at: 0)
            }
        } else {
            streak = 0
            playerHP -= 14
            log.insert("Missed. Correct was \(question.answer); bot counters for 14.", at: 0)
            if playerHP <= 0 {
                log.insert("Knockout. Resetting the gym — study the lesson and run it back.", at: 0)
                level = 1; playerHP = 100; enemyHP = 100; streak = 0; score = 0
            }
        }
        input = ""
        question = FractionFighterGame.makeQuestion(level: level)
    }

    private static func makeQuestion(level: Int) -> Question {
        if level <= 3 {
            let a = Int.random(in: 2...9), b = Int.random(in: 2...9)
            return Question(prompt: "Punch: \(a) × \(b) = ?", answer: "\(a * b)", damage: 18, lesson: "Multiplication facts build attack speed. Fast correct answers chain into combos.")
        }
        if level <= 6 {
            let den = [2, 3, 4, 6, 8].randomElement() ?? 4
            let num = Int.random(in: 1...9) * den + Int.random(in: 1..<den)
            let g = gcd(num, den)
            return Question(prompt: "Fraction Slash: reduce \(num)/\(den)", answer: "\(num / g)/\(den / g)", damage: 26, lesson: "Reduce fractions by dividing numerator and denominator by their greatest common divisor.")
        }
        if level <= 9 {
            let a = Int.random(in: 3...9), b = Int.random(in: 3...9)
            let c = Int.random(in: 2...7)
            return Question(prompt: "Algebra Kick: \(a)x + \(b) = \(a * c + b). Find x", answer: "\(c)", damage: 32, lesson: "Isolate x by subtracting the constant first, then dividing by the coefficient.")
        }
        let a = Int.random(in: 3...12), b = Int.random(in: 3...12)
        let c2 = a * a + b * b
        return Question(prompt: "Pythagorean Blast: a=\(a), b=\(b). c² = ?", answer: "\(c2)", damage: 42, lesson: "In a right triangle, c² = a² + b². Here the answer asks for c², not c.")
    }

    private static func normalized(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "=", with: "").lowercased()
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }
}

// MARK: - Game 4: Gravity Golf

private struct GravityGolfGame: View {
    struct Body: Identifiable {
        let id = UUID()
        let name: String
        let gravity: Double
        let drag: Double
        let note: String
    }

    private let bodies: [Body] = [
        .init(name: "Moon", gravity: 1.62, drag: 0.0, note: "Low gravity: the ball sails far and bounces high. Use less power."),
        .init(name: "Mars", gravity: 3.71, drag: 0.04, note: "Thin atmosphere: dust drag nudges long shots off line."),
        .init(name: "Earth", gravity: 9.81, drag: 0.02, note: "Baseline physics: projectile range ≈ v² sin(2θ) / g."),
        .init(name: "Jupiter", gravity: 24.79, drag: 0.08, note: "Heavy gravity crushes arcs. You need power and a higher launch angle."),
        .init(name: "Black Hole Edge", gravity: 70.0, drag: 0.0, note: "Extreme gravity bends the ideal arc; timing the accretion window matters.")
    ]

    @State private var bodyIndex = 0
    @State private var power: Double = 46
    @State private var angle: Double = 42
    @State private var strokes = 0
    @State private var score = 0
    @State private var holeDistance: Double = 82
    @State private var lastRange: Double?
    @State private var message = "Set power and angle, then launch. Land within 4 m of the hole."

    private var bodyObj: Body { bodies[bodyIndex % bodies.count] }

    var body: some View {
        GameScreen(title: "Gravity Golf", lesson: bodyObj.note) {
            ScoreBar(score: score, streak: 0, lives: 3)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(bodyObj.name).font(.headline).foregroundStyle(.white)
                    Spacer()
                    Button("Next body") { bodyIndex += 1; newHole() }.font(.caption).foregroundStyle(Glass.accent2)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.22))
                    HStack {
                        Image(systemName: "figure.golf").font(.system(size: 28)).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: bodyObj.name.contains("Black") ? "circle.circle.fill" : "flag.fill")
                            .font(.system(size: 30)).foregroundStyle(bodyObj.name.contains("Black") ? .purple : Glass.buy)
                    }
                    .padding(.horizontal, 24)
                }
                .frame(height: 150)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.14), lineWidth: 1))
                HStack { Text("Hole: \(Int(holeDistance)) m").font(.caption).foregroundStyle(.white.opacity(0.62)); Spacer(); if let r = lastRange { Text("Last: \(String(format: "%.1f", r)) m").font(.caption).foregroundStyle(Glass.accent2) } }
                sliderRow("Power", value: $power, range: 5...100, unit: "m/s")
                sliderRow("Angle", value: $angle, range: 10...80, unit: "°")
                PrimaryGameButton(title: "Launch ball", icon: "paperplane.fill") { shoot() }
                Text(message).font(.caption).foregroundStyle(.white.opacity(0.62)).padding(12).glassCard()
                HStack { Text("Strokes: \(strokes)").font(.caption).foregroundStyle(.white.opacity(0.6)); Spacer(); Text("Score: \(score)").font(.caption).foregroundStyle(.white.opacity(0.6)) }
            }
            .padding(14)
            .glassCard()
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label).font(.caption).foregroundStyle(.white.opacity(0.7)); Spacer(); Text("\(Int(value.wrappedValue))\(unit)").font(.caption2).foregroundStyle(.white.opacity(0.5)) }
            Slider(value: value, in: range).tint(Glass.accent)
        }
    }

    private func shoot() {
        strokes += 1
        let theta = angle * .pi / 180
        var range = (power * power * sin(2 * theta)) / bodyObj.gravity
        range *= max(0.55, 1 - bodyObj.drag * Double.random(in: 0...1.8))
        if bodyObj.name.contains("Black") { range *= 0.82 } // relativistic-looking curve, simplified for play.
        lastRange = range
        let miss = abs(range - holeDistance)
        if miss <= 4 {
            let points = max(50, 300 - strokes * 25)
            score += points
            message = "Holed it in \(strokes) stroke(s) on \(bodyObj.name). +\(points) points."
            strokes = 0
            newHole()
        } else {
            message = range < holeDistance ? "Short by \(String(format: "%.1f", miss)) m. Add power or reduce drag losses." : "Long by \(String(format: "%.1f", miss)) m. Lower power or flatten the angle."
            if strokes >= 6 { strokes = 0; newHole(); message += " New hole." }
        }
    }

    private func newHole() {
        holeDistance = Double.random(in: 35...140)
        lastRange = nil
    }
}

// MARK: - Game 5: Tower of Babel Builder

private struct BabelBuilderGame: View {
    struct Pair: Identifiable {
        let id = UUID()
        let english: String
        let match: String
        let decoy: String
        let language: String
        let note: String
    }

    private let rounds: [Pair] = [
        .init(english: "cat", match: "gato", decoy: "gusto", language: "Spanish", note: "gato = cat; gusto = pleasure/taste."),
        .init(english: "dog", match: "chien", decoy: "chaîne", language: "French", note: "chien = dog; chaîne = chain."),
        .init(english: "water", match: "水", decoy: "火", language: "Japanese", note: "水 is water; 火 is fire."),
        .init(english: "embarrassed", match: "avergonzado", decoy: "embarazada", language: "Spanish", note: "Classic false friend: embarazada means pregnant, not embarrassed."),
        .init(english: "gift", match: "Geschenk", decoy: "Gift", language: "German", note: "German Gift means poison — a dangerous false friend."),
        .init(english: "library", match: "bibliothèque", decoy: "librairie", language: "French", note: "librairie is a bookshop; bibliothèque is a library.")
    ]

    @State private var round = 0
    @State private var tower = 0
    @State private var score = 0
    @State private var streak = 0
    @State private var lives = 3
    @State private var message = "Pick the true translation block to stack the tower higher."

    private var pair: Pair { rounds[round % rounds.count] }
    private var choices: [String] { [pair.match, pair.decoy].shuffled() }

    var body: some View {
        GameScreen(title: "Tower of Babel", lesson: pair.note) {
            ScoreBar(score: score, streak: streak, lives: lives)
            VStack(spacing: 14) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<max(1, min(tower, 10)), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Glass.accent.opacity(0.22 + Double(i) * 0.04))
                            .frame(width: 26, height: CGFloat(18 + i * 7))
                    }
                }
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .glassCard()
                Text("English block: \(pair.english.uppercased())").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Text("Language: \(pair.language)").font(.caption).foregroundStyle(Glass.accent2)
                HStack(spacing: 10) {
                    ForEach(choices, id: \.self) { choice in
                        Button { pick(choice) } label: {
                            Text(choice)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.14), lineWidth: 1))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(message).font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.62)).padding(12).glassCard()
                PrimaryGameButton(title: "Reset tower", icon: "arrow.clockwise") { tower = 0; score = 0; streak = 0; lives = 3; round = 0 }
            }
            .padding(14)
            .glassCard()
        }
    }

    private func pick(_ choice: String) {
        if choice == pair.match {
            tower += 1
            streak += 1
            score += 60 + streak * 10
            message = "Block stacked. \(pair.note)"
        } else {
            lives -= 1
            streak = 0
            tower = max(0, tower - 2)
            message = "False friend collapsed two blocks. \(pair.note)"
            if lives <= 0 { tower = 0; lives = 3; score = 0 }
        }
        round += 1
    }
}

// MARK: - Game 6: Taxonomy Tetris

private struct TaxonomySortGame: View {
    struct Organism: Identifiable {
        let id = UUID()
        let name: String
        let correct: String
        let hint: String
    }

    private let ranks = ["Animal", "Plant", "Fungus", "Protist", "Bacteria", "Extinct"]
    private let deck: [Organism] = [
        .init(name: "Lion", correct: "Animal", hint: "Multicellular, moves, eats other organisms."),
        .init(name: "Oak", correct: "Plant", hint: "Photosynthetic with cellulose cell walls."),
        .init(name: "Mushroom", correct: "Fungus", hint: "Chitin walls; absorbs nutrients."),
        .init(name: "Amoeba", correct: "Protist", hint: "Mostly unicellular eukaryote."),
        .init(name: "E. coli", correct: "Bacteria", hint: "Prokaryote: no nucleus."),
        .init(name: "T. rex", correct: "Extinct", hint: "Known from fossils, no living populations."),
        .init(name: "Fern", correct: "Plant", hint: "Vascular plant reproducing by spores."),
        .init(name: "Yeast", correct: "Fungus", hint: "Single-celled fungus used in fermentation."),
        .init(name: "Paramecium", correct: "Protist", hint: "Ciliated protist."),
        .init(name: "Falcon", correct: "Animal", hint: "Chordate with feathers and flight adaptations.")
    ]

    @State private var index = 0
    @State private var score = 0
    @State private var streak = 0
    @State private var lives = 3
    @State private var speed = 1
    @State private var message = "Tap the correct kingdom/rank before the falling organism reaches the bottom."

    private var organism: Organism { deck[index % deck.count] }

    var body: some View {
        GameScreen(title: "Taxonomy Tetris", lesson: organism.hint) {
            ScoreBar(score: score, streak: streak, lives: lives)
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05))
                    VStack {
                        Spacer()
                        Text(organism.name).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text(organism.hint).font(.caption).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center).padding(.horizontal, 20)
                        Spacer()
                        HStack { Image(systemName: "arrow.down").foregroundStyle(Glass.accent); Text("stack speed \(speed)").font(.caption2).foregroundStyle(.white.opacity(0.45)) }
                            .padding(.bottom, 10)
                    }
                }
                .frame(height: 170)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.14), lineWidth: 1))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(ranks, id: \.self) { rank in
                        Button { choose(rank) } label: {
                            Text(rank).font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14), lineWidth: 1))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(message).font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.62)).padding(12).glassCard()
                PrimaryGameButton(title: "Reset lab", icon: "arrow.clockwise") { score = 0; streak = 0; lives = 3; speed = 1; index = 0 }
            }
            .padding(14)
            .glassCard()
        }
    }

    private func choose(_ rank: String) {
        if rank == organism.correct {
            streak += 1
            score += 40 + streak * 5 + speed * 5
            if streak % 4 == 0 { speed += 1 }
            message = "Correct. \(organism.name) → \(rank)."
        } else {
            streak = 0
            lives -= 1
            message = "Misclassified. \(organism.name) belongs in \(organism.correct): \(organism.hint)"
            if lives <= 0 { score = 0; lives = 3; speed = 1 }
        }
        index += 1
    }
}
