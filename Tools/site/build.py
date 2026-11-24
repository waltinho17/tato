#!/usr/bin/env python3
"""Builds the bilingual site: docs/index.html (English) and docs/pt/index.html (Portuguese),
plus docs/sitemap.xml and docs/robots.txt.  Usage: python3 Tools/site/build.py"""
import html, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
BASE = "https://waltinho17.github.io/tato/"
VERSION = "2.1.0"
template = (pathlib.Path(__file__).parent / "template.html").read_text()

def esc(s): return html.escape(s, quote=True)

# ------------------------------------------------------------------ copy
T = {}

T["en"] = dict(
    htmlLang="en", lang="en", ogLocale="en_US", ogLocaleAlt="pt_BR",
    title="Tato: Mac and Claude metrics on the Touch Bar",
    description="Tato shows CPU/GPU temperature, fan speed, frequency, memory, network, battery and your Claude usage limits right on the Touch Bar of your MacBook Pro. Free and open source.",
    keywords="Touch Bar, MacBook Pro, Touch Bar app, system monitor, CPU temperature, fan speed, Control Strip, menu bar monitor, Claude usage, Claude Code limits, macOS, Apple Silicon",
    ogAlt="Tato app icon and Touch Bar showing Mac and Claude metrics",
    navFeatures="Features", navScreens="Screens", navCompat="Compatibility", navInstall="Install", navSuggest="Feedback",
    switchHref="pt/", switchLang="pt-BR", switchLabel="PT", switchAria="Ler em português", switchName="Português",
    iconAlt="Tato app icon: a white T with an orange dot on graphite",
    h1Plain="Tato: Mac and Claude metrics on your Touch Bar",
    rotWords=["Temperature", "Fan speed", "Memory", "Battery", "Network", "Claude limits"],
    h1Post="on your <span class=\"accent\">Touch Bar</span>.",
    heroLead="CPU and GPU temperature, fan speed, frequency, memory, network, battery and your Claude limits, always in sight on your MacBook Pro. Light, free and open source.",
    dlPrefix="Download Tato", dlLabel="Download for macOS", dlMeta="macOS 13 or newer · MacBook Pro with Touch Bar",
    viewCode="View code", deviceAria="Examples of the Touch Bar running Tato",
    macMode="Mac mode", claudeMode="Claude mode",
    macBarAlt="Touch Bar with CPU, fan, frequency, memory, usage, SSD and battery",
    claudeBarAlt="Touch Bar with Claude session, weekly limit, credit, tokens today, activity and service status",
    featEyebrow="Features", featTitle="Everything that matters, one tap away.",
    featLead="A pinned button on the Control Strip opens a bar with the widgets you choose. No sudo, no weight, no Dock icon.",
    cards=[("🌡️", "Temperature and fan", "CPU and GPU with colours by range, fan speed and history sparklines."),
           ("⚡", "Frequency and usage", "CPU and GPU frequency, plus usage per efficiency and performance cores, read without sudo."),
           ("🧠", "Memory, network and disk", "RAM, memory pressure, download and upload, SSD reads and writes, and the heaviest processes."),
           ("↔️", "Scrollable bar", "Too many widgets? The bar scrolls with your finger. Drag whole rows to reorder them in Preferences."),
           ("🔔", "Alerts", "A notification when the temperature passes your limit, with a cool-down so it never nags."),
           ("✦", "Claude mode", "Session, weekly limit, credit and service status, with the little pixel robot on the Control Strip.")],
    scrEyebrow="Screens", scrTitle="A full panel in the menu bar.",
    scrLead="Click the icon to see every metric with min, average and max, plus your Claude usage.",
    dashAlt="Tato menu bar panel with CPU, memory, network, battery and Claude", dashCap="Menu bar panel",
    tabsAria="Preferences screens",
    tabs=["Widgets", "General", "Alerts", "Claude", "Help"],
    prefAlts=["Preferences, Widgets tab, with a list you can drag to reorder", "Preferences, General tab", "Preferences, Alerts tab",
              "Preferences, Claude tab, with plan limits", "Preferences, Help tab, with the setup guide"],
    prefCap="Preferences, with a Liquid Glass look on macOS 26 and newer",
    robotAlt="Pixel-art Claude robot",
    clEyebrow="Claude mode", clTitle="Your Claude limits, without opening anything.",
    clLead="A second button, separate from the Mac mode. Minimised, it is just the little robot. Tap it to open the full bar.",
    clTicks=["<b>5-hour session and weekly limit</b> with a bar and the time until reset.",
             "<b>Monthly extra credit</b> and weekly usage by source: Claude Code, chats and Cowork.",
             "<b>Tokens today by model</b>, live activity and service status.",
             "<b>Automatic:</b> it uses the login Claude Code already has on your Mac, the same one used by the terminal, VS Code and the app.",
             "<b>There when you start your Mac.</b> Tato opens at login and shows the last known values instantly.",
             "<b>Mac only, Claude only or both.</b> Turn it off and the button disappears completely."],
    clNote="Tato is independent: not affiliated with or endorsed by Anthropic. The limits come from an internal, undocumented endpoint that may change. You can turn it off at any time in Preferences.",
    clCap="Claude bar and Preferences (sample data)",
    cpEyebrow="Compatibility", cpTitle="Made for Macs with a Touch Bar.",
    cpLead="You need a MacBook Pro with a Touch Bar and macOS 13 Ventura or newer.",
    cpThMac="Mac", cpThChip="Chip", cpThStatus="Status",
    cpRows=[("MacBook Pro 13\" (2020)", "Tested on macOS 27", "Apple M1", "ok", "Tested", "All metrics and Claude mode."),
            ("MacBook Pro 13\" (2022)", "", "Apple M2", "ok", "Compatible", "Same sensors and APIs as the M1, not tested yet."),
            ("MacBook Pro 13\", 15\" and 16\" (2016 to 2020)", "", "Intel", "warn", "Partial", "Temperature and fan via SMC, not tested. No CPU/GPU frequency. Claude mode works on any Mac."),
            ("Macs without a Touch Bar", "", "Any", "dim", "No button", "There is no Touch Bar. The menu bar panel may work, but it is not the focus.")],
    cpNote="Tato uses private Apple APIs to pin the button to the Control Strip and read sensors. A macOS update can break something. If it does, the menu shows a warning. Metrics your Mac cannot read disappear on their own.",
    inEyebrow="Install", inTitle="Ready in a minute.",
    inSteps=[("Download and open", "Download the <code>.zip</code> above, unzip it and drag <b>Tato</b> to Applications. The app is not notarised, so macOS may block the first launch. Run this once in Terminal:", "xattr -cr /Applications/Tato.app"),
             ("Keep the Control Strip visible", "In System Settings, Keyboard, Touch Bar Settings, choose “App Controls” and keep the Control Strip on. Names vary a little between macOS versions.", ""),
             ("Tap the button", "On the right of the Touch Bar, next to brightness and volume, you will find the Tato button. Tap it to open the bar and use the ✕ to close it.", ""),
             ("Choose what to show", "Menu bar icon, Preferences: tick, drag to reorder, pick up to 2 values for the button and, if you like, turn on Claude mode.", "")],
    inBuild="Prefer to build it? Clone the repository and run <code>make run</code>. You only need the Xcode Command Line Tools.",
    seEyebrow="Privacy and security", seTitle="Your data stays with you.",
    seLead="The code is open and small, with no third-party libraries, no analytics and no server of its own.",
    seCards=[("What leaves your Mac", "Only two requests: the public status at <code>status.claude.com</code> and, in Claude mode, the limits request to <code>api.anthropic.com</code> with your own login. Nothing goes to the app's author."),
             ("The Claude login", "Read from the Keychain only with your permission, kept in memory only, and sent solely to Anthropic's address, with no redirects followed and no disk cache. It is never written or logged."),
             ("Conversations", "Tokens come from the local Claude Code logs, reading only date, model and counts. Conversation text is never read or sent."),
             ("No sudo, no background network", "No reading needs administrator rights. You can turn Claude mode off, and the request with it, in Preferences.")],
    fbEyebrow="Feedback", fbTitle="Missing something?",
    fbLead="Tell me what you would like to see in Tato: a metric, a Mac it did not work on, an idea.",
    fbType="Type", fbOpt1="Suggestion", fbOpt1v="Suggestion", fbOpt2="Problem on a Mac", fbOpt2v="Problem", fbOpt3="Kind words", fbOpt3v="Kind words",
    fbMsg="Your message", fbPlaceholder="Which Mac do you use, what did you expect and what happened?",
    fbEmail="Your email (optional, so I can reply)", fbSend="Send feedback",
    fbErrEmpty="Please write a message first.",
    fbNoteMail="Your email app will open with the message so you can send it.",
    fbNoteIssue="This opens a public issue on GitHub. Please do not include personal or sensitive data.",
    fbNoteForm="Your message is sent privately through a form service. Add your email only if you want a reply.",
    fbSent="Thank you! Your message was sent.", fbFail="Could not send. Please try again or open an issue on GitHub.", fbSending="Sending…",
    faqTitle="Frequently asked questions",
    faq=[("macOS says the app is damaged or from an unidentified developer.", "Tato is free and not notarised by Apple. Run <code>xattr -cr /Applications/Tato.app</code> in Terminal and open it again."),
         ("The button does not show on my Touch Bar.", "Check System Settings, Keyboard, Touch Bar Settings: the Control Strip must be on and the mode must not be “Expanded Control Strip”. Then reopen Tato."),
         ("A metric shows “–” or is missing.", "Your Mac cannot read that metric. Run <code>make probe</code> in the repository to see exactly what each sensor returns. GPU temperature also shows “–” while the GPU is idle."),
         ("Does it work on Intel or M2 MacBook Pros?", "The M2 shares the M1 sensors and APIs, so it should work, but it is untested. Intel is partial: temperature and fan via SMC, no CPU/GPU frequency. Reports are welcome."),
         ("Is using the Claude login allowed?", "Tato reads your own login, on your own Mac, and queries an internal endpoint that Anthropic does not document. That can change or be restricted at any time, and the choice to use it is yours. It can be turned off."),
         ("How do I uninstall it?", "Quit Tato, delete it from Applications and, if you enabled it, remove it from System Settings, General, Login Items.")],
    ftCode="Code on GitHub", ftReleases="Releases", ftLicense="MIT licence",
    ftLegal="Tato is an independent project. Mac, MacBook Pro and Touch Bar are trademarks of Apple Inc. Claude is a trademark of Anthropic. This project is not affiliated with, sponsored by or endorsed by either. The pixel robot is a hand-drawn approximation.",
    ftCredits="Techniques inspired by MIT projects: MTMR, Stats and macmon.",
)

T["pt"] = dict(
    htmlLang="pt-BR", lang="pt", ogLocale="pt_BR", ogLocaleAlt="en_US",
    title="Tato: métricas do Mac e do Claude na Touch Bar",
    description="O Tato mostra temperatura de CPU e GPU, cooler, frequência, memória, rede, bateria e os limites de uso do Claude direto na Touch Bar do seu MacBook Pro. Gratuito e de código aberto.",
    keywords="Touch Bar, MacBook Pro, app para Touch Bar, monitor de sistema, temperatura da CPU, cooler, Control Strip, monitor na barra de menus, limites do Claude, uso do Claude Code, macOS, Apple Silicon",
    ogAlt="Ícone do Tato e Touch Bar mostrando métricas do Mac e do Claude",
    navFeatures="Recursos", navScreens="Telas", navCompat="Compatibilidade", navInstall="Instalar", navSuggest="Sugestões",
    switchHref="../", switchLang="en", switchLabel="EN", switchAria="Read in English", switchName="English",
    iconAlt="Ícone do Tato: um T branco com um ponto laranja sobre grafite",
    h1Plain="Tato: métricas do Mac e do Claude na sua Touch Bar",
    rotWords=["Temperatura", "Cooler", "Memória", "Bateria", "Rede", "Limites do Claude"],
    h1Post="na sua <span class=\"accent\">Touch Bar</span>.",
    heroLead="Temperatura de CPU e GPU, cooler, frequência, memória, rede, bateria e os limites do Claude, sempre à vista no seu MacBook Pro. Leve, gratuito e de código aberto.",
    dlPrefix="Baixar Tato", dlLabel="Baixar para macOS", dlMeta="macOS 13 ou mais novo · MacBook Pro com Touch Bar",
    viewCode="Ver código", deviceAria="Exemplos da Touch Bar com o Tato",
    macMode="Modo Mac", claudeMode="Modo Claude",
    macBarAlt="Touch Bar com CPU, cooler, frequência, memória, uso, SSD e bateria",
    claudeBarAlt="Touch Bar com sessão, limite semanal, crédito, tokens de hoje, atividade e status do Claude",
    featEyebrow="Recursos", featTitle="Tudo o que importa, num toque.",
    featLead="Um botão fixo na Control Strip abre uma barra com os widgets que você escolher. Sem sudo, sem peso, sem ícone no Dock.",
    cards=[("🌡️", "Temperatura e cooler", "CPU e GPU com cores por faixa, rotação da ventoinha e histórico em mini-gráficos."),
           ("⚡", "Frequência e uso", "Frequência de CPU e GPU, uso por núcleos de eficiência e desempenho, lidos sem sudo."),
           ("🧠", "Memória, rede e disco", "RAM, pressão de memória, download e upload, leitura e escrita do SSD e processos que mais pesam."),
           ("↔️", "Barra rolável", "Muitos widgets? A barra rola com o dedo. Reordene arrastando a linha inteira nas Preferências."),
           ("🔔", "Alertas", "Notificação quando a temperatura passar do limite, com intervalo para não incomodar."),
           ("✦", "Modo Claude", "Sessão, limite semanal, crédito e status do serviço, com o robozinho na Control Strip.")],
    scrEyebrow="Telas", scrTitle="Um painel completo na barra de menus.",
    scrLead="Clique no ícone para ver cada métrica com mínimo, média e máximo, além do uso do Claude.",
    dashAlt="Painel do Tato na barra de menus com CPU, memória, rede, bateria e Claude", dashCap="Painel da barra de menus",
    tabsAria="Telas de preferências",
    tabs=["Widgets", "Geral", "Alertas", "Claude", "Ajuda"],
    prefAlts=["Preferências, aba Widgets, com lista para arrastar e reordenar", "Preferências, aba Geral", "Preferências, aba Alertas",
              "Preferências, aba Claude, com limites do plano", "Preferências, aba Ajuda, com o passo a passo"],
    prefCap="Preferências com visual Liquid Glass no macOS 26 ou mais novo",
    robotAlt="Robozinho pixelado do Claude",
    clEyebrow="Modo Claude", clTitle="Os limites do Claude, sem abrir nada.",
    clLead="Um segundo botão, separado do modo Mac. Minimizado, é só o robozinho. Ao tocar, abre a barra com tudo.",
    clTicks=["<b>Sessão de 5 horas e limite semanal</b> com barra e tempo para resetar.",
             "<b>Crédito extra do mês</b> e o uso semanal por origem: Claude Code, chats e Cowork.",
             "<b>Tokens de hoje por modelo</b>, atividade em tempo real e status do serviço.",
             "<b>Automático:</b> usa o login que o Claude Code já tem no Mac, o mesmo do terminal, do VS Code e do app.",
             "<b>Já aparece ao ligar o Mac.</b> O Tato abre no login e mostra os últimos valores na hora.",
             "<b>Só Mac, só Claude ou os dois.</b> Desligou? O botão some por completo."],
    clNote="O Tato é independente: não é afiliado nem endossado pela Anthropic. Os limites vêm de um endereço interno e não documentado, que pode mudar. Dá para desligar a qualquer momento nas Preferências.",
    clCap="Barra e Preferências do modo Claude (dados de exemplo)",
    cpEyebrow="Compatibilidade", cpTitle="Feito para quem tem Touch Bar.",
    cpLead="Precisa de um MacBook Pro com Touch Bar e macOS 13 Ventura ou mais novo.",
    cpThMac="Mac", cpThChip="Chip", cpThStatus="Situação",
    cpRows=[("MacBook Pro 13\" (2020)", "Testado no macOS 27", "Apple M1", "ok", "Testado", "Todas as métricas e o modo Claude."),
            ("MacBook Pro 13\" (2022)", "", "Apple M2", "ok", "Compatível", "Mesmos sensores e APIs do M1, ainda não testado."),
            ("MacBook Pro 13\", 15\" e 16\" (2016 a 2020)", "", "Intel", "warn", "Parcial", "Temperatura e cooler pelo SMC, ainda não testados. Sem frequência de CPU e GPU. O modo Claude funciona em qualquer Mac."),
            ("Macs sem Touch Bar", "", "Qualquer", "dim", "Sem botão", "Não há Touch Bar. O painel da barra de menus pode funcionar, mas não é o foco.")],
    cpNote="O Tato usa APIs privadas da Apple para fixar o botão na Control Strip e ler sensores. Uma atualização do macOS pode quebrar algo. Se isso acontecer, o menu mostra um aviso. As métricas que o seu Mac não lê somem sozinhas.",
    inEyebrow="Instalar", inTitle="Pronto em um minuto.",
    inSteps=[("Baixe e abra", "Baixe o <code>.zip</code> acima, descompacte e arraste o <b>Tato</b> para Aplicativos. Como o app não é notarizado, o macOS pode bloquear o primeiro uso. Rode isto uma vez no Terminal:", "xattr -cr /Applications/Tato.app"),
             ("Deixe a Control Strip visível", "Em Ajustes do Sistema, Teclado, Configurações da Touch Bar, escolha “Controles do app” e mantenha a Control Strip ativada. Os nomes variam um pouco conforme o macOS.", ""),
             ("Toque no botão", "À direita da Touch Bar, junto de brilho e volume, aparece o botão do Tato. Toque para abrir a barra e use o ✕ para fechar.", ""),
             ("Escolha o que mostrar", "Ícone na barra de menus, Preferências: marque, arraste para reordenar, escolha até 2 valores para o botão e, se quiser, ative o modo Claude.", "")],
    inBuild="Prefere compilar? Clone o repositório e rode <code>make run</code>. Só é preciso o Xcode Command Line Tools.",
    seEyebrow="Privacidade e segurança", seTitle="Seus dados ficam com você.",
    seLead="O código é aberto e pequeno, sem bibliotecas de terceiros, sem análise de uso e sem servidor próprio.",
    seCards=[("O que sai do seu Mac", "Apenas duas consultas: o status público em <code>status.claude.com</code> e, no modo Claude, a consulta dos limites em <code>api.anthropic.com</code> com o seu próprio login. Nada vai para o autor do app."),
             ("Login do Claude", "Lido do Chaveiro só com a sua permissão, mantido apenas na memória e enviado somente ao endereço da Anthropic, sem seguir redirecionamentos e sem cache em disco. Nunca é gravado nem registrado."),
             ("Conversas", "Os tokens vêm dos logs locais do Claude Code, lendo apenas data, modelo e contagem. O texto das conversas nunca é lido nem enviado."),
             ("Sem sudo e sem rede de fundo", "Nenhuma leitura exige administrador. Dá para desligar o modo Claude, e com ele a consulta, nas Preferências.")],
    fbEyebrow="Sugestões", fbTitle="Faltou alguma coisa?",
    fbLead="Conte o que você gostaria de ver no Tato: uma métrica, um Mac que não funcionou, uma ideia.",
    fbType="Tipo", fbOpt1="Sugestão", fbOpt1v="Sugestão", fbOpt2="Problema em um Mac", fbOpt2v="Problema", fbOpt3="Elogio", fbOpt3v="Elogio",
    fbMsg="Sua mensagem", fbPlaceholder="Qual Mac você usa, o que esperava ver e o que aconteceu?",
    fbEmail="Seu e-mail (opcional, para eu responder)", fbSend="Enviar sugestão",
    fbErrEmpty="Escreva uma mensagem antes de enviar.",
    fbNoteMail="A mensagem será aberta no seu app de e-mail para você enviar.",
    fbNoteIssue="Isto abre uma issue pública no GitHub. Não inclua dados pessoais ou sensíveis.",
    fbNoteForm="Sua mensagem é enviada em particular por um serviço de formulários. Informe o e-mail só se quiser resposta.",
    fbSent="Obrigado! Sua mensagem foi enviada.", fbFail="Não foi possível enviar. Tente de novo ou abra uma issue no GitHub.", fbSending="Enviando…",
    faqTitle="Perguntas frequentes",
    faq=[("O macOS diz que o app está danificado ou de desenvolvedor não identificado.", "O Tato é gratuito e não é notarizado pela Apple. Rode <code>xattr -cr /Applications/Tato.app</code> no Terminal e abra de novo."),
         ("O botão não aparece na Touch Bar.", "Confira em Ajustes do Sistema, Teclado, Configurações da Touch Bar, se a Control Strip está ativa e se o modo não é “Control Strip expandida”. Depois reabra o Tato."),
         ("Uma métrica aparece como “–” ou sumiu.", "O seu Mac não lê essa métrica. Rode <code>make probe</code> no repositório para ver exatamente o que cada sensor devolve. A temperatura da GPU também mostra “–” quando ela está parada."),
         ("Funciona em MacBook Pro M2 ou Intel?", "O M2 usa os mesmos sensores e APIs do M1, então deve funcionar, mas não foi testado. O Intel é parcial: temperatura e cooler pelo SMC, sem frequência de CPU e GPU. Relatos são bem-vindos."),
         ("O uso do login do Claude é permitido?", "O Tato lê o seu próprio login, no seu próprio Mac, e consulta um endereço interno que a Anthropic não documenta. Isso pode mudar ou ser restringido a qualquer momento, e a decisão de usar é sua. O recurso pode ser desligado."),
         ("Como desinstalar?", "Feche o Tato, apague-o da pasta Aplicativos e, se tiver ativado, remova-o de Ajustes do Sistema, Geral, Itens de Início.")],
    ftCode="Código no GitHub", ftReleases="Versões", ftLicense="Licença MIT",
    ftLegal="Tato é um projeto independente. Mac, MacBook Pro e Touch Bar são marcas da Apple Inc. Claude é marca da Anthropic. Este projeto não é afiliado, patrocinado nem endossado por nenhuma das duas. O robozinho é uma aproximação desenhada à mão.",
    ftCredits="Técnicas inspiradas em projetos MIT: MTMR, Stats e macmon.",
)

# ------------------------------------------------------------------ fragments
def fragments(lang, c):
    root = "" if lang == "en" else "../"
    f = {}
    f["root"] = root
    f["canonical"] = BASE if lang == "en" else BASE + "pt/"
    on = ' class="on"'
    f["rotSpans"] = "".join("<span%s>%s</span>" % (on if i == 0 else "", esc(w)) for i, w in enumerate(c["rotWords"]))
    f["featCards"] = "\n      ".join(
        f'<div class="card rv" style="--d:{i*0.06:.2f}s"><div class="ico">{ic}</div><h3>{esc(t)}</h3><p>{esc(p)}</p></div>'
        for i, (ic, t, p) in enumerate(c["cards"]))
    f["tabButtons"] = "\n            ".join(
        f'<button role="tab" aria-selected="{"true" if i == 0 else "false"}" data-img="{root}assets/{lang}/prefs-tab{i}.png" data-alt="{esc(c["prefAlts"][i])}">{esc(name)}</button>'
        for i, name in enumerate(c["tabs"]))
    f["prefAlt0"] = c["prefAlts"][0]
    f["prefAlt3"] = c["prefAlts"][3]
    f["clTicks"] = "\n        ".join(f"<li>{t}</li>" for t in c["clTicks"])
    rows = []
    for mac, sub, chip, kind, status, note in c["cpRows"]:
        small = f"<small>{esc(sub)}</small>" if sub else ""
        rows.append(f'<tr><td>{esc(mac)}{small}</td><td>{esc(chip)}</td><td><span class="pill {kind}">{esc(status)}</span><small>{esc(note)}</small></td></tr>')
    f["cpRows"] = "\n          ".join(rows)
    steps = []
    for title, text, code in c["inSteps"]:
        pre = f"<pre>{esc(code)}</pre>" if code else ""
        steps.append(f'<li class="rv"><div><h3>{esc(title)}</h3><p>{text}</p>{pre}</div></li>')
    f["inSteps"] = "\n      ".join(steps)
    f["seCards"] = "\n      ".join(
        f'<div class="card rv" style="--d:{i*0.06:.2f}s"><h3>{esc(t)}</h3><p>{p}</p></div>' for i, (t, p) in enumerate(c["seCards"]))
    f["faqItems"] = "\n    ".join(
        f'<details class="rv"><summary>{esc(q)}</summary><p>{a}</p></details>' for q, a in c["faq"])
    # structured data: the app, plus the FAQ for rich results
    strip = lambda s: html.unescape(__import__("re").sub(r"<[^>]+>", "", s))
    f["jsonld"] = json.dumps({
        "@context": "https://schema.org",
        "@graph": [
            {"@type": "SoftwareApplication", "name": "Tato", "applicationCategory": "UtilitiesApplication",
             "operatingSystem": "macOS 13+", "softwareVersion": VERSION, "inLanguage": ["en", "pt-BR"],
             "description": c["description"], "url": f["canonical"], "image": BASE + "assets/og.png",
             "downloadUrl": "https://github.com/waltinho17/tato/releases/latest",
             "license": "https://opensource.org/licenses/MIT", "isAccessibleForFree": True,
             "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
             "author": {"@type": "Person", "name": "waltinho17", "url": "https://github.com/waltinho17"}},
            {"@type": "FAQPage", "mainEntity": [
                {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": strip(a)}} for q, a in c["faq"]]},
        ]}, ensure_ascii=False)
    return f

def build(lang):
    c = T[lang]
    values = {k: v for k, v in c.items() if isinstance(v, str)}
    # attribute-safe copies for text used inside attributes
    for k in ("title", "description", "keywords", "ogAlt", "iconAlt", "switchAria", "deviceAria", "macBarAlt", "claudeBarAlt",
              "dashAlt", "tabsAria", "robotAlt", "dlPrefix", "dlLabel", "dlMeta", "fbErrEmpty", "fbNoteMail", "fbNoteIssue", "fbNoteForm",
              "fbSent", "fbFail", "fbSending", "fbPlaceholder", "fbOpt1v", "fbOpt2v", "fbOpt3v"):
        values[k] = esc(c[k])
    values.update(fragments(lang, c))
    out = template
    for k, v in values.items():
        out = out.replace(f"[[{k}]]", v)
    left = __import__("re").findall(r"\[\[[A-Za-z0-9]+\]\]", out)
    assert not left, f"unfilled placeholders in {lang}: {set(left)}"
    return out

(DOCS / "pt").mkdir(parents=True, exist_ok=True)
(DOCS / "index.html").write_text(build("en"))
(DOCS / "pt" / "index.html").write_text(build("pt"))

(DOCS / "robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {BASE}sitemap.xml\n")
(DOCS / "sitemap.xml").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <url>
    <loc>{BASE}</loc>
    <xhtml:link rel="alternate" hreflang="en" href="{BASE}"/>
    <xhtml:link rel="alternate" hreflang="pt-BR" href="{BASE}pt/"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="{BASE}"/>
  </url>
  <url>
    <loc>{BASE}pt/</loc>
    <xhtml:link rel="alternate" hreflang="en" href="{BASE}"/>
    <xhtml:link rel="alternate" hreflang="pt-BR" href="{BASE}pt/"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="{BASE}"/>
  </url>
</urlset>
''')
print("built docs/index.html, docs/pt/index.html, sitemap.xml, robots.txt")
