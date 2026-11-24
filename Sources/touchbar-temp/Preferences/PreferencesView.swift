import SwiftUI
import AppKit

/// Re-renders the SwiftUI views whenever any setting changes.
final class PrefsModel: ObservableObject {
    @Published var revision = 0
    @Published var tab = 0
    @Published var claudeNote: String?
    // Kept here instead of @State: the SwiftUI @State macro needs the full Xcode toolchain.
    @Published var loginEnabled = LoginItem.isEnabled
    @Published var loginError: String?
    init() {
        for name in [Settings.didChange, ClaudeEngine.didUpdate] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.revision += 1
            }
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: PrefsModel
    let engine: MetricsEngine
    let alerts: AlertManager
    let claude: ClaudeEngine
    private var s: Settings { Settings.shared }

    var body: some View {
        let _ = model.revision   // dependency: refresh on every settings change
        VStack(spacing: 12) {
            Picker("", selection: Binding(get: { model.tab }, set: { model.tab = $0 })) {
                Text("Widgets").tag(0)
                Text("Geral").tag(1)
                Text("Alertas").tag(2)
                Text("Claude").tag(3)
                Text("Ajuda").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 470)

            switch model.tab {
            case 0: widgetsTab
            case 1: generalTab
            case 2: alertsTab
            case 3: claudeTab
            default: helpTab
            }
        }
        .frame(width: 500, height: 470)
        .padding(.top, 30)
        .tint(Color(nsColor: Palette.clay))   // room for the transparent title bar
    }

    // MARK: - Widgets

    private var widgetsTab: some View {
        let supported = Set(engine.supported)
        let order = s.widgetOrder.filter(supported.contains)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Arraste a linha inteira para reordenar. Marque o que aparece na Touch Bar e até 2 itens para o botão fixo. Com muitos widgets, a barra rola com o dedo.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            List {
                ForEach(order, id: \.self) { id in
                    let pinned = s.stripWidgets.filter(supported.contains)
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Toggle("", isOn: Binding(
                            get: { s.enabledWidgets.contains(id) },
                            set: { on in
                                var l = s.enabledWidgets
                                if on { if !l.contains(id) { l.append(id) } } else { l.removeAll { $0 == id } }
                                s.enabledWidgets = l
                            }))
                            .labelsHidden()
                        Text(MetricStyle.menuName(id))
                        Spacer()
                        Text("Fixo").foregroundStyle(.secondary)
                        Toggle("", isOn: Binding(
                            get: { pinned.contains(id) },
                            set: { on in
                                var l = pinned
                                if on { if l.count < Settings.maxStripWidgets { l.append(id) } } else if l.count > 1 { l.removeAll { $0 == id } }
                                s.stripWidgets = l
                            }))
                            .labelsHidden()
                            .disabled(!pinned.contains(id) && pinned.count >= Settings.maxStripWidgets)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())      // every pixel of the row starts a drag
                }
                .onMove { from, to in
                    var l = order
                    l.move(fromOffsets: from, toOffset: to)
                    s.widgetOrder = l + s.widgetOrder.filter { !l.contains($0) }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Claude

    private func setClaude(_ on: Bool) {
        s.claudeEnabled = on
        if on {
            if !LoginItem.isEnabled {
                // The Claude button should be there after a restart without opening anything.
                try? LoginItem.set(true)
                model.loginEnabled = LoginItem.isEnabled
                model.claudeNote = model.loginEnabled
                    ? "O Tato vai abrir sozinho ao ligar o Mac, para o botão do Claude já aparecer."
                    : "Não consegui ativar a abertura automática. Ative em Geral."
            }
        } else if s.displayMode == .claudeOnly {
            s.displayMode = .both
        }
    }

    private func limitBar(_ title: String, _ pct: Double?, _ resets: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(pct.map { String(format: "%.0f%%", $0) } ?? "–").font(.title3.bold())
            }
            ProgressView(value: min(max((pct ?? 0) / 100, 0), 1))
                .tint(Color(nsColor: Palette.claudeLimit(pct ?? 0)))
            if let r = ClaudeFormat2.reset(resets) {
                Text("Reseta em \(r)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var claudeTab: some View {
        let snap = claude.snapshot
        let u = snap.usage
        return Form {
            Section {
                Toggle("Mostrar o Claude na Touch Bar", isOn: Binding(get: { s.claudeEnabled }, set: { setClaude($0) }))
                if let note = model.claudeNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                Toggle("Usar o login do Claude Code (limites reais)", isOn: Binding(get: { s.claudeUseLogin }, set: { s.claudeUseLogin = $0 }))
                    .disabled(!s.claudeEnabled)
                if s.claudeEnabled && s.claudeUseLogin {
                    LabeledContent("Conexão", value: snap.loginState.text + (snap.plan.map { " · plano \($0.capitalized)" } ?? ""))
                }
            }
            if s.claudeEnabled {
                Section("Limites do plano") {
                    limitBar("Sessão · janela de 5 horas", snap.limits?.sessionPct, snap.limits?.sessionResets)
                    limitBar("Semanal · janela de 7 dias", snap.limits?.weeklyPct, snap.limits?.weeklyResets)
                    ForEach(Array((snap.limits?.extras ?? []).enumerated()), id: \.offset) { _, e in
                        limitBar(e.name, e.pct, e.resets)
                    }
                    if let cr = snap.limits?.credits {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Crédito extra · mês")
                                Spacer()
                                Text("\(cr.used) / \(cr.limit)").font(.title3.bold())
                            }
                            ProgressView(value: min(max(cr.pct / 100, 0), 1)).tint(Color(nsColor: Palette.claudeLimit(cr.pct)))
                        }
                        .padding(.vertical, 2)
                    }
                }
                if let origin = snap.limits?.breakdown, !origin.isEmpty {
                    Section("Semanal por origem") {
                        ForEach(Array(origin.enumerated()), id: \.offset) { _, o in
                            LabeledContent(o.name, value: String(format: "%.0f%% do limite", o.pctOfLimit))
                        }
                    }
                }
                Section("Claude Code neste Mac") {
                    LabeledContent("Tokens, últimas 5 horas", value: snap.loaded ? ClaudeFormat.tokens(u.tokens5h) : "–")
                    LabeledContent("Tokens hoje", value: snap.loaded ? ClaudeFormat.tokens(u.tokensToday) : "–")
                    LabeledContent("Tokens, 7 dias", value: snap.loaded ? ClaudeFormat.tokens(u.tokens7d) : "–")
                    LabeledContent("Respostas hoje", value: snap.loaded ? "\(u.messagesToday)" : "–")
                    LabeledContent("Última atividade", value: snap.loaded ? ClaudeTime.ago(u.lastActivity) : "–")
                    LabeledContent("Status do serviço", value: snap.status.label)
                }
                if !u.modelsToday.isEmpty {
                    Section("Hoje por modelo") {
                        ForEach(Array(u.modelsToday.prefix(5).enumerated()), id: \.offset) { _, m in
                            LabeledContent(m.name, value: "\(ClaudeFormat.tokens(m.tokens)) · \(m.responses) respostas")
                        }
                    }
                }
            }
            Section {
                Text("Os limites vêm do login que o Claude Code já guarda no Chaveiro, o mesmo usado pelo terminal, pela extensão do VS Code e pelo app. O macOS pede permissão na primeira vez: escolha Permitir sempre. A consulta usa um endereço interno e não documentado da Anthropic, que pode mudar ou limitar chamadas, então o Tato consulta só a cada 5 minutos. Os tokens vêm dos logs locais e o status da página pública status.claude.com. Conversas não são lidas nem enviadas.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Atualizar agora") { claude.refreshNow() }.disabled(!s.claudeEnabled)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal)
    }

    // MARK: - Help

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(Color.primary.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var helpTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Como fazer a telemetria aparecer na Touch Bar").font(.title3.bold())
                step(1, "Deixe a Control Strip visível",
                     "Em Ajustes do Sistema > Teclado > Configurações da Touch Bar, escolha \"Controles do app\" e mantenha a Control Strip ativada (os nomes podem variar um pouco conforme a versão do macOS). Evite o modo \"Control Strip expandida\".")
                step(2, "Encontre o botão do app",
                     "À direita da Touch Bar, junto aos controles de brilho e volume, aparece um botão com os valores, por exemplo 67° · 3.2G. Ele fica visível em qualquer app.")
                step(3, "Toque para abrir a barra completa",
                     "Tocar no botão abre todos os widgets. Se houver mais do que cabem, deslize o dedo para os lados. O ✕ fecha e o botão continua lá.")
                step(4, "Escolha o que mostrar",
                     "Na aba Widgets, marque o que aparece na barra completa, arraste a linha para mudar a ordem e use \"Fixo\" para escolher até 2 valores do botão.")
                step(5, "Ajuste a barra de menus",
                     "Na aba Geral, mostre só valores, valores com rótulo ou apenas o ícone, em negrito se preferir. Clique no ícone da barra de menus para ver o painel completo.")
                step(6, "Opcional: abrir no login e alertas",
                     "Ative \"Abrir ao iniciar sessão\" na aba Geral e, na aba Alertas, defina a temperatura que dispara um aviso.")
                Text("Se o botão não aparecer, confira o passo 1 e abra o app de novo. Se um valor mostrar –, o seu Mac não lê essa métrica. Se algo sumir depois de atualizar o macOS, o menu mostra um aviso em laranja.")
                    .font(.callout).foregroundStyle(Color.primary.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Picker("Touch Bar mostra", selection: Binding(
                get: { s.claudeEnabled ? s.displayMode : .macOnly },
                set: { m in if m == .claudeOnly || m == .both { if !s.claudeEnabled { setClaude(true) } }; s.displayMode = m })) {
                Text("Mac e Claude").tag(Settings.DisplayMode.both)
                Text("Só métricas do Mac").tag(Settings.DisplayMode.macOnly)
                Text("Só Claude").tag(Settings.DisplayMode.claudeOnly)
            }
            Picker("Barra de menus", selection: Binding(get: { s.menuBarMode }, set: { s.menuBarMode = $0 })) {
                Text("Somente valores").tag(Settings.MenuBarMode.values)
                Text("Valores com rótulo").tag(Settings.MenuBarMode.labeled)
                Text("Somente ícone").tag(Settings.MenuBarMode.icon)
            }
            Toggle("Texto em negrito", isOn: Binding(get: { s.menuBarBold }, set: { s.menuBarBold = $0 }))
                .disabled(s.menuBarMode == .icon)
            Toggle("Cores por faixa (verde, laranja, vermelho)", isOn: Binding(get: { s.useColors }, set: { s.useColors = $0 }))
            Picker("Atualizar a cada", selection: Binding(get: { s.refreshInterval }, set: { s.refreshInterval = $0 })) {
                Text("2 segundos").tag(2.0)
                Text("3 segundos").tag(3.0)
                Text("5 segundos").tag(5.0)
            }
            Section {
            Toggle("Abrir ao iniciar sessão", isOn: Binding(
                get: { model.loginEnabled },
                set: { on in
                    do { try LoginItem.set(on); model.loginError = nil }
                    catch { model.loginError = error.localizedDescription }
                    model.loginEnabled = LoginItem.isEnabled
                }))
            if let e = model.loginError { Text(e).font(.caption).foregroundStyle(.red) }
            Text("Funciona melhor com o app na pasta Aplicativos.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }

    // MARK: - Alerts

    private var alertsTab: some View {
        Form {
            Toggle("Avisar quando a temperatura passar do limite", isOn: Binding(
                get: { s.alertsEnabled },
                set: { on in s.alertsEnabled = on; if on { alerts.requestAuthorization() } }))
            Picker("Limite (CPU ou GPU)", selection: Binding(get: { s.alertThreshold }, set: { s.alertThreshold = $0 })) {
                ForEach([80.0, 85.0, 90.0, 95.0, 100.0], id: \.self) { Text(String(format: "%.0f °C", $0)).tag($0) }
            }
            .disabled(!s.alertsEnabled)
            Button("Enviar notificação de teste") { alerts.requestAuthorization(); alerts.sendTest() }
                .disabled(!s.alertsEnabled)
            Text("O aviso dispara uma vez por pico e só volta a disparar depois que a temperatura cair 5 °C abaixo do limite, com intervalo mínimo de 10 minutos.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}

/// The only place the app uses Liquid Glass: the whole Preferences window sits on a glass surface (macOS 26+).
final class PreferencesWindowController {
    private var window: NSWindow?
    private var hosting: NSView?
    private let model = PrefsModel()

    /// The SwiftUI content, for debug snapshots.
    var contentView: NSView? { hosting }
    var windowNumber: Int? { window?.windowNumber }
    func select(tab: Int) { model.tab = tab }

    func show(engine: MetricsEngine, alerts: AlertManager, claude: ClaudeEngine) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 470),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Preferências"
            w.isReleasedWhenClosed = false
            w.titlebarAppearsTransparent = true

            let host = NSHostingView(rootView: PreferencesView(model: model, engine: engine, alerts: alerts, claude: claude))
            hosting = host
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.style = .regular
                // A tint keeps text legible over any wallpaper; it follows light / dark mode.
                glass.tintColor = NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(white: 0.04, alpha: 0.42) : NSColor(white: 1, alpha: 0.45)
                }
                glass.contentView = host
                w.contentView = glass
                w.isOpaque = false
                w.backgroundColor = .clear
            } else {
                w.contentView = host
            }
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
