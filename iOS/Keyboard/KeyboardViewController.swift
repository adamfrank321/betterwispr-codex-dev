import UIKit
import BetterWisprShared

final class KeyboardViewController: UIInputViewController {
    private let stack = UIStackView()
    override func viewDidLoad() {
        super.viewDidLoad()
        stack.axis = .vertical; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 250)
        ])
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reload() }
    override func textDidChange(_ textInput: (any UITextInput)?) { super.textDidChange(textInput); reload() }

    private func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let controls = UIStackView(); controls.distribution = .fillEqually
        let next = UIButton(type: .system); next.setTitle("Next keyboard", for: .normal)
        next.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        controls.addArrangedSubview(next)
        let refresh = UIButton(type: .system); refresh.setTitle("Refresh", for: .normal)
        refresh.addAction(UIAction { [weak self] _ in self?.reload() }, for: .touchUpInside)
        controls.addArrangedSubview(refresh); stack.addArrangedSubview(controls)
        guard hasFullAccess else { label("Enable Full Access in Keyboard Settings to read your saved transcripts."); return }
        do {
            guard let group = Bundle.main.object(forInfoDictionaryKey: "BetterWisprAppGroup") as? String,
                  let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                label("Open BetterWispr to set up your transcript library."); return
            }
            let url = folder.appendingPathComponent("keyboard.json")
            guard FileManager.default.fileExists(atPath: url.path) else { label("Record a dictation in BetterWispr first."); return }
            let items = try JSONDecoder().decode([Transcript].self, from: Data(contentsOf: url))
            if items.isEmpty { label("Record a dictation in BetterWispr first.") }
            for item in items.prefix(3) {
                let button = UIButton(type: .system)
                button.setTitle(item.text, for: .normal)
                button.titleLabel?.numberOfLines = 2; button.contentHorizontalAlignment = .leading
                button.accessibilityLabel = "Insert: \(item.text)"
                button.addAction(UIAction { [weak self] _ in self?.textDocumentProxy.insertText(item.text) }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
        } catch { label("Could not read transcripts. Open BetterWispr and retry.") }
    }
    private func label(_ text: String) {
        let label = UILabel(); label.text = text; label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .subheadline); stack.addArrangedSubview(label)
    }
}
