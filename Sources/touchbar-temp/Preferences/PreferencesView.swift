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
                Text(tr("Geral", "General")).tag(1)
                Text(tr("Alertas", "Alerts")).tag(2)
                Text("Claude").tag(3)
                Text(tr("Ajuda", "Help")).tag(4)
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
            Text(tr("Arraste a linha inteira para reordenar. Marque o que aparece na Touch Bar e até 2 itens para o botão fixo. Com muitos widgets, a barra rola com o dedo.", "Drag a whole row to reorder. Tick what appears on the Touch Bar and up to 2 items for the pinned button. With many widgets, the bar scrolls with your finger."))
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
                        Text(tr("Fixo", "Pinned")).foregroundStyle(.secondary)
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
                    ? tr("O Tato vai abrir sozinho ao ligar o Mac, para o botão do Claude já aparecer.", "Tato will now open by itself when the Mac starts, so the Claude button is already there.")
                    : tr("Não consegui ativar a abertura automática. Ative em Geral.", "Could not enable launch at login. Turn it on in General.")
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
                Text(tr("Reseta em \(r)", "Resets in \(r)")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var claudeTab: some View {
        let snap = claude.snapshot
        let u = snap.usage
        return Form {
            Section {
                Toggle(tr("Mostrar o Claude na Touch Bar", "Show Claude on the Touch Bar"), isOn: Binding(get: { s.claudeEnabled }, set: { setClaude($0) }))
                if let note = model.claudeNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                Toggle(tr("Usar o login do Claude Code (limites reais)", "Use the Claude Code login (real limits)"), isOn: Binding(get: { s.claudeUseLogin }, set: { s.claudeUseLogin = $0 }))
                    .disabled(!s.claudeEnabled)
                if s.claudeEnabled && s.claudeUseLogin {
                    LabeledContent(tr("Conexão", "Connection"), value: snap.loginState.text + (snap.plan.map { tr(" · plano \($0.capitalized)", " · \($0.capitalized) plan") } ?? ""))
                }
            }
            if s.claudeEnabled {
                Section(tr("Limites do plano", "Plan limits")) {
                    limitBar(tr("Sessão · janela de 5 horas", "Session · 5-hour window"), snap.limits?.sessionPct, snap.limits?.sessionResets)
                    limitBar(tr("Semanal · janela de 7 dias", "Weekly · 7-day window"), snap.limits?.weeklyPct, snap.limits?.weeklyResets)
                    ForEach(Array((snap.limits?.extras ?? []).enumerated()), id: \.offset) { _, e in
                        limitBar(e.name, e.pct, e.resets)
                    }
                    if let cr = snap.limits?.credits {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(tr("Crédito extra · mês", "Extra credit · month"))
                                Spacer()
                                Text("\(cr.used) / \(cr.limit)").font(.title3.bold())
                            }
                            ProgressView(value: min(max(cr.pct / 100, 0), 1)).tint(Color(nsColor: Palette.claudeLimit(cr.pct)))
                        }
                        .padding(.vertical, 2)
                    }
                }
                if let origin = snap.limits?.breakdown, !origin.isEmpty {
                    Section(tr("Semanal por origem", "Weekly by source")) {
                        ForEach(Array(origin.enumerated()), id: \.offset) { _, o in
                            LabeledContent(o.name, value: String(format: tr("%.0f%% do limite", "%.0f%% of the limit"), o.pctOfLimit))
                        }
                    }
                }
                Section(tr("Claude Code neste Mac", "Claude Code on this Mac")) {
                    LabeledContent(tr("Tokens, últimas 5 horas", "Tokens, last 5 hours"), value: snap.loaded ? ClaudeFormat.tokens(u.tokens5h) : "–")
                    LabeledContent(tr("Tokens hoje", "Tokens today"), value: snap.loaded ? ClaudeFormat.tokens(u.tokensToday) : "–")
                    LabeledContent(tr("Tokens, 7 dias", "Tokens, 7 days"), value: snap.loaded ? ClaudeFormat.tokens(u.tokens7d) : "–")
                    LabeledContent(tr("Respostas hoje", "Responses today"), value: snap.loaded ? "\(u.messagesToday)" : "–")
                    LabeledContent(tr("Última atividade", "Last activity"), value: snap.loaded ? ClaudeTime.ago(u.lastActivity) : "–")
                    LabeledContent(tr("Status do serviço", "Service status"), value: snap.status.label)
                }
                if !u.modelsToday.isEmpty {
                    Section(tr("Hoje por modelo", "Today by model")) {
                        ForEach(Array(u.modelsToday.prefix(5).enumerated()), id: \.offset) { _, m in
                            LabeledContent(m.name, value: "\(ClaudeFormat.tokens(m.tokens)) · \(m.responses) \(tr("respostas", "responses"))")
                        }
                    }
                }
            }
            Section {
                Text(tr("Os limites vêm do login que o Claude Code já guarda no Chaveiro, o mesmo usado pelo terminal, pela extensão do VS Code e pelo app. O macOS pede permissão na primeira vez: escolha Permitir sempre. A consulta usa um endereço interno e não documentado da Anthropic, que pode mudar ou limitar chamadas, então o Tato consulta só a cada 5 minutos. Os tokens vêm dos logs locais e o status da página pública status.claude.com. Conversas não são lidas nem enviadas.",
                        "The limits come from the login Claude Code already keeps in the Keychain, the same one used by the terminal, the VS Code extension and the app. macOS asks for permission the first time: choose Always Allow. The request uses an internal, undocumented Anthropic endpoint that may change or rate-limit, so Tato only asks every 5 minutes. Tokens come from local logs and the status from the public page status.claude.com. Conversations are never read or sent."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(tr("Atualizar agora", "Refresh now")) { claude.refreshNow() }.disabled(!s.claudeEnabled)
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
                Text(tr("Como fazer a telemetria aparecer na Touch Bar", "How to get the telemetry on your Touch Bar")).font(.title3.bold())
                step(1, tr("Deixe a Control Strip visível", "Keep the Control Strip visible"),
                     tr("Em Ajustes do Sistema > Teclado > Configurações da Touch Bar, escolha \"Controles do app\" e mantenha a Control Strip ativada (os nomes podem variar um pouco conforme a versão do macOS). Evite o modo \"Control Strip expandida\".",
                        "In System Settings > Keyboard > Touch Bar Settings, choose \"App Controls\" and keep the Control Strip on (names may vary slightly between macOS versions). Avoid the \"Expanded Control Strip\" mode."))
                step(2, tr("Encontre o botão do app", "Find the app button"),
                     tr("À direita da Touch Bar, junto aos controles de brilho e volume, aparece um botão com os valores, por exemplo 67° · 3.2G. Ele fica visível em qualquer app.",
                        "On the right side of the Touch Bar, next to brightness and volume, a button shows the values, for example 67° · 3.2G. It stays visible in every app."))
                step(3, tr("Toque para abrir a barra completa", "Tap to open the full bar"),
                     tr("Tocar no botão abre todos os widgets. Se houver mais do que cabem, deslize o dedo para os lados. O ✕ fecha e o botão continua lá.",
                        "Tapping the button opens all widgets. If there are more than fit, swipe sideways. The ✕ closes it and the button stays."))
                step(4, tr("Escolha o que mostrar", "Choose what to show"),
                     tr("Na aba Widgets, marque o que aparece na barra completa, arraste a linha para mudar a ordem e use \"Fixo\" para escolher até 2 valores do botão.",
                        "In the Widgets tab, tick what appears on the full bar, drag a row to change the order and use \"Pinned\" to pick up to 2 values for the button."))
                step(5, tr("Ajuste a barra de menus", "Tune the menu bar"),
                     tr("Na aba Geral, mostre só valores, valores com rótulo ou apenas o ícone, em negrito se preferir. Clique no ícone da barra de menus para ver o painel completo.",
                        "In the General tab, show values only, values with labels or just the icon, in bold if you like. Click the menu bar item to see the full panel."))
                step(6, tr("Opcional: abrir no login e alertas", "Optional: launch at login and alerts"),
                     tr("Ative \"Abrir ao iniciar sessão\" na aba Geral e, na aba Alertas, defina a temperatura que dispara um aviso.",
                        "Turn on \"Launch at login\" in General and, in Alerts, set the temperature that triggers a notification."))
                Text(tr("Se o botão não aparecer, confira o passo 1 e abra o app de novo. Se um valor mostrar –, o seu Mac não lê essa métrica. Se algo sumir depois de atualizar o macOS, o menu mostra um aviso em laranja.",
                        "If the button does not appear, check step 1 and reopen the app. A value showing – means your Mac cannot read that metric. If something disappears after a macOS update, the menu shows an orange warning."))
                    .font(.callout).foregroundStyle(Color.primary.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Picker(tr("Idioma", "Language"), selection: Binding(get: { s.languageChoice }, set: { s.languageChoice = $0 })) {
                Text(tr("Automático", "Automatic")).tag("auto")
                Text("Português").tag("pt")
                Text("English").tag("en")
            }
            Picker(tr("Touch Bar mostra", "Touch Bar shows"), selection: Binding(
                get: { s.claudeEnabled ? s.displayMode : .macOnly },
                set: { m in if m == .claudeOnly || m == .both { if !s.claudeEnabled { setClaude(true) } }; s.displayMode = m })) {
                Text(tr("Mac e Claude", "Mac and Claude")).tag(Settings.DisplayMode.both)
                Text(tr("Só métricas do Mac", "Mac metrics only")).tag(Settings.DisplayMode.macOnly)
                Text(tr("Só Claude", "Claude only")).tag(Settings.DisplayMode.claudeOnly)
            }
            Picker(tr("Barra de menus", "Menu bar"), selection: Binding(get: { s.menuBarMode }, set: { s.menuBarMode = $0 })) {
                Text(tr("Somente valores", "Values only")).tag(Settings.MenuBarMode.values)
                Text(tr("Valores com rótulo", "Values with labels")).tag(Settings.MenuBarMode.labeled)
                Text(tr("Somente ícone", "Icon only")).tag(Settings.MenuBarMode.icon)
            }
            Toggle(tr("Texto em negrito", "Bold text"), isOn: Binding(get: { s.menuBarBold }, set: { s.menuBarBold = $0 }))
                .disabled(s.menuBarMode == .icon)
            Toggle(tr("Cores por faixa (verde, laranja, vermelho)", "Colours by range (green, orange, red)"), isOn: Binding(get: { s.useColors }, set: { s.useColors = $0 }))
            Picker(tr("Atualizar a cada", "Refresh every"), selection: Binding(get: { s.refreshInterval }, set: { s.refreshInterval = $0 })) {
                Text(tr("2 segundos", "2 seconds")).tag(2.0)
                Text(tr("3 segundos", "3 seconds")).tag(3.0)
                Text(tr("5 segundos", "5 seconds")).tag(5.0)
            }
            Section {
            Toggle(tr("Abrir ao iniciar sessão", "Launch at login"), isOn: Binding(
                get: { model.loginEnabled },
                set: { on in
                    do { try LoginItem.set(on); model.loginError = nil }
                    catch { model.loginError = error.localizedDescription }
                    model.loginEnabled = LoginItem.isEnabled
                }))
            if let e = model.loginError { Text(e).font(.caption).foregroundStyle(.red) }
            Text(tr("Funciona melhor com o app na pasta Aplicativos.", "Works best with the app in the Applications folder.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }

    // MARK: - Alerts

    private var alertsTab: some View {
        Form {
            Toggle(tr("Avisar quando a temperatura passar do limite", "Notify me when the temperature passes the limit"), isOn: Binding(
                get: { s.alertsEnabled },
                set: { on in s.alertsEnabled = on; if on { alerts.requestAuthorization() } }))
            Picker(tr("Limite (CPU ou GPU)", "Limit (CPU or GPU)"), selection: Binding(get: { s.alertThreshold }, set: { s.alertThreshold = $0 })) {
                ForEach([80.0, 85.0, 90.0, 95.0, 100.0], id: \.self) { Text(String(format: "%.0f °C", $0)).tag($0) }
            }
            .disabled(!s.alertsEnabled)
            Button(tr("Enviar notificação de teste", "Send a test notification")) { alerts.requestAuthorization(); alerts.sendTest() }
                .disabled(!s.alertsEnabled)
            Text(tr("O aviso dispara uma vez por pico e só volta a disparar depois que a temperatura cair 5 °C abaixo do limite, com intervalo mínimo de 10 minutos.",
                    "The alert fires once per spike and only re-arms after the temperature drops 5 °C below the limit, with a minimum of 10 minutes between alerts."))
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
            w.title = tr("Preferências", "Preferences")
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
