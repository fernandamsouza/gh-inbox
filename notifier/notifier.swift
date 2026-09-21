import AppKit
import UserNotifications

// Notificador do gh-inbox: um wrapper minimo sobre o UserNotifications da
// Apple, sem dependencia externa.
//
//   notifier -title T [-subtitle S] -message M [-open URL] [-group ID]
//            [-action ID:TITULO ...] [-action-exec ID:COMANDO ...]
//   notifier -list [ID|ALL]      lista o que esta na Central (tab-separated)
//   notifier -remove ID|ALL      remove da Central
//   notifier                     modo handler: e assim que o macOS reabre o
//                                app quando alguem clica na notificacao
//
// Codigos de saida: 0 ok · 1 falha ao entregar · 2 uso invalido
//                   3 sem permissao de notificacao
//
// Sobre o id: no UserNotifications quem deduplica e o `identifier` — postar
// com o mesmo id SUBSTITUI a notificacao anterior. Por isso o gh-inbox usa um
// id unico por PR: o historico acumula, e um evento repetido no mesmo PR
// atualiza a propria entrada em vez de duplicar.

let MARKER_TIMEOUT: TimeInterval = 8   // teto no modo handler, para nao pendurar

func out(_ s: String) { FileHandle.standardOutput.write(s.data(using: .utf8)!) }
func err(_ s: String) { FileHandle.standardError.write(s.data(using: .utf8)!) }

final class App: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var a: [String: String] = [:]
    var rep: [String: [String]] = [:]
    var mode = "handler"

    // O delegate precisa estar setado ANTES do launch terminar: quando o macOS
    // reabre o app por causa de um clique, a resposta e entregue no momento da
    // abertura, e um delegate setado tarde a perde silenciosamente.
    func applicationWillFinishLaunching(_ n: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let c = UNUserNotificationCenter.current()
        switch mode {
        case "post":   post(c)
        case "list":   list(c)
        case "remove": remove(c)
        default:
            // Reaberto pelo macOS por causa de um clique. Se a resposta nao
            // chegar, sai por conta em vez de virar processo zumbi.
            DispatchQueue.main.asyncAfter(deadline: .now() + MARKER_TIMEOUT) { exit(0) }
        }
    }

    func post(_ c: UNUserNotificationCenter) {
        // Registrar a categoria ANTES do requestAuthorization. Fazer isso no
        // callback, logo antes do add(), e uma corrida: setNotificationCategories
        // e assincrono, e a notificacao pode ser postada antes da categoria
        // propagar — e ai o botao simplesmente nao aparece, sem erro.
        registerCategory(c)
        c.requestAuthorization(options: [.alert, .sound]) { granted, e in
            guard granted else {
                err("""
                    sem permissao de notificacao para este app.
                    Libere em Ajustes do Sistema > Notificacoes.\n
                    """)
                exit(3)
            }
            let n = UNMutableNotificationContent()
            n.title = self.a["-title"] ?? "gh-inbox"
            if let s = self.a["-subtitle"] { n.subtitle = s }
            n.body = self.a["-message"] ?? ""
            var info: [String: Any] = [:]
            if let u = self.a["-open"] { info["open"] = u }

            // Botoes de acao. `-action ID:TITULO` registra; `-action-exec ID:CMD` diz
            // o que rodar. O comando fica no userInfo da propria notificacao, entao
            // sobrevive ao processo morrer e volta quando o macOS reabre o app.
            for spec in self.rep["-action-exec"] ?? [] {
                let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 { info["exec_" + parts[0]] = parts[1] }
            }
            if let cat = self.categoryID() { n.categoryIdentifier = cat }
            n.userInfo = info
            let id = self.a["-group"] ?? UUID().uuidString
            c.add(UNNotificationRequest(identifier: id, content: n, trigger: nil)) { e in
                if let e = e { err("falhou ao entregar: \(e.localizedDescription)\n"); exit(1) }
                exit(0)
            }
        }
    }

    func actionSpecs() -> [UNNotificationAction] {
        (rep["-action"] ?? []).compactMap { spec in
            let p = spec.split(separator: ":", maxSplits: 1).map(String.init)
            guard p.count == 2 else { return nil }
            return UNNotificationAction(identifier: p[0], title: p[1], options: [.foreground])
        }
    }

    func categoryID() -> String? {
        let a = actionSpecs()
        return a.isEmpty ? nil : "ghinbox-" + a.map { $0.identifier }.joined(separator: "-")
    }

    func registerCategory(_ c: UNUserNotificationCenter) {
        let a = actionSpecs()
        guard !a.isEmpty, let cat = categoryID() else { return }
        c.setNotificationCategories([UNNotificationCategory(
            identifier: cat, actions: a, intentIdentifiers: [], options: [])])
    }

    func list(_ c: UNUserNotificationCenter) {
        let want = a["-list"] ?? "ALL"
        c.getDeliveredNotifications { ns in
            out("GroupID\tTitle\tSubtitle\tMessage\tDelivered At\n")
            let f = ISO8601DateFormatter()
            for n in ns where want == "ALL" || n.request.identifier == want {
                let ct = n.request.content
                out([n.request.identifier, ct.title, ct.subtitle, ct.body,
                     f.string(from: n.date)].joined(separator: "\t") + "\n")
            }
            exit(0)
        }
    }

    func remove(_ c: UNUserNotificationCenter) {
        let id = a["-remove"] ?? ""
        if id == "ALL" { c.removeAllDeliveredNotifications() }
        else { c.removeDeliveredNotifications(withIdentifiers: [id]) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) }
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter,
                                didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = r.notification.request.content.userInfo
        if r.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // clique no corpo: comportamento de sempre
            if let s = info["open"] as? String, let url = URL(string: s) {
                NSWorkspace.shared.open(url)
            }
        } else if let cmd = info["exec_" + r.actionIdentifier] as? String {
            // Roda destacado: um review pode levar minutos, e o notificador nao
            // pode ficar segurando o processo.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", cmd]
            let log = FileHandle(forWritingAtPath: NSString(string: "~/Library/Logs/gh-inbox-action.log").expandingTildeInPath)
            if let log = log { log.seekToEndOfFile(); p.standardOutput = log; p.standardError = log }
            try? p.run()
        }
        done()
        exit(0)
    }
}

var parsed: [String: String] = [:]
var repeated: [String: [String]] = [:]   // -action e -action-exec sao repetiveis
var flags: [String] = []
var it = CommandLine.arguments.dropFirst().makeIterator()
while let k = it.next() {
    guard k.hasPrefix("-") else { continue }
    flags.append(k)
    let v = it.next() ?? ""
    if k == "-action" || k == "-action-exec" { repeated[k, default: []].append(v) }
    else { parsed[k] = v }
}

let app = NSApplication.shared
let d = App()
d.a = parsed
d.rep = repeated
if flags.contains("-list")        { d.mode = "list" }
else if flags.contains("-remove") { d.mode = "remove" }
else if flags.contains("-message"){ d.mode = "post" }
else if !flags.isEmpty {
    err("uso: notifier -message M [-title T] [-subtitle S] [-open URL] [-group ID]\n")
    exit(2)
}
app.delegate = d
app.setActivationPolicy(.accessory)   // sem icone no Dock
app.run()
