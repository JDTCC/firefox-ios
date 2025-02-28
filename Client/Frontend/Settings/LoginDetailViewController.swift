// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation
import Storage
import Shared

enum InfoItem: Int {
    case breachItem = 0
    case websiteItem
    case usernameItem
    case passwordItem
    case lastModifiedSeparator
    case deleteItem

    var indexPath: IndexPath {
        return IndexPath(row: rawValue, section: 0)
    }
}

struct LoginDetailUX {
    static let InfoRowHeight: CGFloat = 58
    static let DeleteRowHeight: CGFloat = 44
    static let SeparatorHeight: CGFloat = 84
}

private class CenteredDetailCell: ThemedTableViewCell {
    override func layoutSubviews() {
        super.layoutSubviews()
        var f = detailTextLabel?.frame ?? CGRect()
        f.center = CGPoint(x: frame.center.x - safeAreaInsets.right, y: frame.center.y)
        detailTextLabel?.frame = f
    }
}

class LoginDetailViewController: SensitiveViewController {
    private let profile: Profile

    private lazy var tableView: UITableView = .build { [weak self] tableView in
        guard let self = self else { return }

        tableView.separatorColor = UIColor.theme.tableView.separator
        tableView.backgroundColor = UIColor.theme.tableView.headerBackground
        tableView.accessibilityIdentifier = "Login Detail List"
        tableView.delegate = self
        tableView.dataSource = self

        // Add empty footer view to prevent separators from being drawn past the last item.
        tableView.tableFooterView = UIView()
    }

    private weak var websiteField: UITextField?
    private weak var usernameField: UITextField?
    private weak var passwordField: UITextField?
    // Used to temporarily store a reference to the cell the user is showing the menu controller for
    private var menuControllerCell: LoginDetailTableViewCell?
    private var deleteAlert: UIAlertController?
    weak var settingsDelegate: SettingsDelegate?
    private var breach: BreachRecord?
    private var login: LoginRecord {
        didSet {
            tableView.reloadData()
        }
    }
    var webpageNavigationHandler: ((_ url: URL?) -> Void)?

    private var isEditingFieldData: Bool = false {
        didSet {
            if isEditingFieldData != oldValue {
                tableView.reloadData()
            }
        }
    }

    init(profile: Profile, login: LoginRecord, webpageNavigationHandler: ((_ url: URL?) -> Void)?) {
        self.login = login
        self.profile = profile
        self.webpageNavigationHandler = webpageNavigationHandler
        super.init(nibName: nil, bundle: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(dismissAlertController), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    func setBreachRecord(breach: BreachRecord?) {
        self.breach = breach
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(edit))

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        tableView.estimatedRowHeight = 44.0
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Normally UITableViewControllers handle responding to content inset changes from keyboard events when editing
        // but since we don't use the tableView's editing flag for editing we handle this ourselves.
        KeyboardHelper.defaultHelper.addDelegate(self)
    }
}

// MARK: - UITableViewDataSource
extension LoginDetailViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch InfoItem(rawValue: indexPath.row)! {
        case .breachItem:
            let breachCell = cell(forIndexPath: indexPath)
            guard let breach = breach else { return breachCell }
            breachCell.isHidden = false
            let breachDetailView = BreachAlertsDetailView()
            breachCell.contentView.addSubview(breachDetailView)

            NSLayoutConstraint.activate([
                breachDetailView.leadingAnchor.constraint(equalTo: breachCell.contentView.leadingAnchor, constant: LoginTableViewCellUX.HorizontalMargin),
                breachDetailView.topAnchor.constraint(equalTo: breachCell.contentView.topAnchor, constant: LoginTableViewCellUX.HorizontalMargin),
                breachDetailView.trailingAnchor.constraint(equalTo: breachCell.contentView.trailingAnchor, constant: LoginTableViewCellUX.HorizontalMargin),
                breachDetailView.bottomAnchor.constraint(equalTo: breachCell.contentView.bottomAnchor, constant: LoginTableViewCellUX.HorizontalMargin)
            ])
            breachDetailView.setup(breach)

            breachDetailView.learnMoreButton.addTarget(self, action: #selector(LoginDetailViewController.didTapBreachLearnMore), for: .touchUpInside)
            let breachLinkGesture = UITapGestureRecognizer(target: self, action: #selector(LoginDetailViewController
                .didTapBreachLink(_:)))
            breachDetailView.goToButton.addGestureRecognizer(breachLinkGesture)
            breachCell.isAccessibilityElement = false
            breachCell.contentView.accessibilityElementsHidden = true
            breachCell.accessibilityElements = [breachDetailView]

            return breachCell

        case .usernameItem:
            let loginCell = cell(forIndexPath: indexPath)
            loginCell.highlightedLabelTitle = .LoginDetailUsername
            loginCell.descriptionLabel.text = login.decryptedUsername
            loginCell.descriptionLabel.keyboardType = .emailAddress
            loginCell.descriptionLabel.returnKeyType = .next
            loginCell.isEditingFieldData = isEditingFieldData
            usernameField = loginCell.descriptionLabel
            usernameField?.accessibilityIdentifier = "usernameField"
            return loginCell

        case .passwordItem:
            let loginCell = cell(forIndexPath: indexPath)
            loginCell.highlightedLabelTitle = .LoginDetailPassword
            loginCell.descriptionLabel.text = login.decryptedPassword
            loginCell.descriptionLabel.returnKeyType = .default
            loginCell.displayDescriptionAsPassword = true
            loginCell.isEditingFieldData = isEditingFieldData
            setCellSeparatorHidden(loginCell)
            passwordField = loginCell.descriptionLabel
            passwordField?.accessibilityIdentifier = "passwordField"
            return loginCell

        case .websiteItem:
            let loginCell = cell(forIndexPath: indexPath)
            loginCell.highlightedLabelTitle = .LoginDetailWebsite
            loginCell.descriptionLabel.text = login.hostname
            websiteField = loginCell.descriptionLabel
            websiteField?.accessibilityIdentifier = "websiteField"
            loginCell.isEditingFieldData = false
            if isEditingFieldData {
                loginCell.contentView.alpha = 0.5
            }
            return loginCell

        case .lastModifiedSeparator:
            let cell = CenteredDetailCell(style: .subtitle, reuseIdentifier: nil)
            let created: String = .LoginDetailCreatedAt
            let lastModified: String = .LoginDetailModifiedAt

            let lastModifiedFormatted = String(format: lastModified, Date.fromTimestamp(UInt64(login.timePasswordChanged)).toRelativeTimeString(dateStyle: .medium))
            let createdFormatted = String(format: created, Date.fromTimestamp(UInt64(login.timeCreated)).toRelativeTimeString(dateStyle: .medium, timeStyle: .none))
            // Setting only the detail text produces smaller text as desired, and it is centered.
            cell.detailTextLabel?.text = createdFormatted + "\n" + lastModifiedFormatted
            cell.detailTextLabel?.numberOfLines = 2
            cell.detailTextLabel?.textAlignment = .center
            cell.backgroundColor = view.backgroundColor
            setCellSeparatorHidden(cell)
            return cell

        case .deleteItem:
            let deleteCell = cell(forIndexPath: indexPath)
            deleteCell.textLabel?.text = .LoginDetailDelete
            deleteCell.textLabel?.textAlignment = .center
            deleteCell.textLabel?.textColor = UIColor.theme.general.destructiveRed
            deleteCell.accessibilityTraits = UIAccessibilityTraits.button
            deleteCell.backgroundColor = UIColor.theme.tableView.rowBackground
            setCellSeparatorFullWidth(deleteCell)
            return deleteCell
        }
    }

    private func cell(forIndexPath indexPath: IndexPath) -> LoginDetailTableViewCell {
        let loginCell = LoginDetailTableViewCell()
        loginCell.selectionStyle = .none
        loginCell.delegate = self
        return loginCell
    }

    private func setCellSeparatorHidden(_ cell: UITableViewCell) {
        // Prevent seperator from showing by pushing it off screen by the width of the cell
        cell.separatorInset = UIEdgeInsets(top: 0,
                                           left: 0,
                                           bottom: 0,
                                           right: view.frame.width)
    }

    private func setCellSeparatorFullWidth(_ cell: UITableViewCell) {
        cell.separatorInset = .zero
        cell.layoutMargins = .zero
        cell.preservesSuperviewLayoutMargins = false
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 6
    }
}

// MARK: - UITableViewDelegate
extension LoginDetailViewController: UITableViewDelegate {
    private func showMenuOnSingleTap(forIndexPath indexPath: IndexPath) {
        guard let item = InfoItem(rawValue: indexPath.row) else { return }
        if ![InfoItem.passwordItem, InfoItem.websiteItem, InfoItem.usernameItem].contains(item) {
            return
        }

        guard let cell = tableView.cellForRow(at: indexPath) as? LoginDetailTableViewCell else { return }

        cell.becomeFirstResponder()

        let menu = UIMenuController.shared
        menu.showMenu(from: tableView, rect: cell.frame)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath == InfoItem.deleteItem.indexPath {
            deleteLogin()
        } else if !isEditingFieldData {
            showMenuOnSingleTap(forIndexPath: indexPath)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch InfoItem(rawValue: indexPath.row)! {
        case .breachItem:
            guard let _ = breach else { return 0 }
            return UITableView.automaticDimension
        case .usernameItem, .passwordItem, .websiteItem:
            return LoginDetailUX.InfoRowHeight
        case .lastModifiedSeparator:
            return LoginDetailUX.SeparatorHeight
        case .deleteItem:
            return LoginDetailUX.DeleteRowHeight
        }
    }
}

// MARK: - KeyboardHelperDelegate
extension LoginDetailViewController: KeyboardHelperDelegate {

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
        let coveredHeight = state.intersectionHeightForView(tableView)
        tableView.contentInset.bottom = coveredHeight
    }

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
        tableView.contentInset.bottom = 0
    }
}

// MARK: - Selectors
extension LoginDetailViewController {

    @objc func dismissAlertController() {
        deleteAlert?.dismiss(animated: false, completion: nil)
    }

    @objc func didTapBreachLearnMore() {
        webpageNavigationHandler?(BreachAlertsManager.monitorAboutUrl)
    }

    @objc func didTapBreachLink(_ sender: UITapGestureRecognizer? = nil) {
        guard let domain = breach?.domain else { return }
        var urlComponents = URLComponents()
        urlComponents.host = domain
        urlComponents.scheme = "https"
        webpageNavigationHandler?(urlComponents.url)
    }

    func deleteLogin() {
        profile.hasSyncedLogins().uponQueue(.main) { yes in
            self.deleteAlert = UIAlertController.deleteLoginAlertWithDeleteCallback({ [unowned self] _ in
                self.profile.logins.deleteLogin(id: self.login.id).uponQueue(.main) { _ in
                    _ = self.navigationController?.popViewController(animated: true)
                }
            }, hasSyncedLogins: yes.successValue ?? true)

            self.present(self.deleteAlert!, animated: true, completion: nil)
        }
    }

    func onProfileDidFinishSyncing() {
        // Reload details after syncing.
        profile.logins.getLogin(id: login.id).uponQueue(.main) { result in
            if let successValue = result.successValue, let syncedLogin = successValue {
                self.login = syncedLogin
            }
        }
    }

    @objc func edit() {
        isEditingFieldData = true
        guard let cell = tableView.cellForRow(at: InfoItem.usernameItem.indexPath) as? LoginDetailTableViewCell else { return }
        cell.descriptionLabel.becomeFirstResponder()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneEditing))
    }

    @objc func doneEditing() {
        isEditingFieldData = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(edit))

        defer {
            // Required to get UI to reload with changed state
            tableView.reloadData()
        }

        // Only update if user made changes
        guard let username = usernameField?.text, let password = passwordField?.text else { return }

        guard username != login.decryptedUsername || password != login.decryptedPassword else { return }

        let updatedLogin = LoginEntry(
            fromLoginEntryFlattened: LoginEntryFlattened(
                id: login.id,
                hostname: login.hostname,
                password: password,
                username: username,
                httpRealm: login.httpRealm,
                formSubmitUrl: login.formSubmitUrl,
                usernameField: login.usernameField,
                passwordField: login.passwordField
            )
        )

        if updatedLogin.isValid.isSuccess {
            _ = profile.logins.updateLogin(id: login.id, login: updatedLogin)
        }
    }
}

// MARK: - Cell Delegate
extension LoginDetailViewController: LoginDetailTableViewCellDelegate {
    func textFieldDidEndEditing(_ cell: LoginDetailTableViewCell) { }
    func textFieldDidChange(_ cell: LoginDetailTableViewCell) { }

    func canPerform(action: Selector, for cell: LoginDetailTableViewCell) -> Bool {
        guard let item = infoItemForCell(cell) else { return false }

        switch item {
        case .websiteItem:
            // Menu actions for Website
            return action == MenuHelper.SelectorCopy || action == MenuHelper.SelectorOpenAndFill
        case .usernameItem:
            // Menu actions for Username
            return action == MenuHelper.SelectorCopy
        case .passwordItem:
            // Menu actions for password
            let showRevealOption = cell.descriptionLabel.isSecureTextEntry ? (action == MenuHelper.SelectorReveal) : (action == MenuHelper.SelectorHide)
            return action == MenuHelper.SelectorCopy || showRevealOption
        default:
            return false
        }
    }

    private func cellForItem(_ item: InfoItem) -> LoginDetailTableViewCell? {
        return tableView.cellForRow(at: item.indexPath) as? LoginDetailTableViewCell
    }

    func didSelectOpenAndFillForCell(_ cell: LoginDetailTableViewCell) {
        guard let url = (login.formSubmitUrl?.asURL ?? login.hostname.asURL) else { return }

        navigationController?.dismiss(animated: true, completion: {
            self.settingsDelegate?.settingsOpenURLInNewTab(url)
        })
    }

    func shouldReturnAfterEditingDescription(_ cell: LoginDetailTableViewCell) -> Bool {
        let usernameCell = cellForItem(.usernameItem)
        let passwordCell = cellForItem(.passwordItem)

        if cell == usernameCell {
            passwordCell?.descriptionLabel.becomeFirstResponder()
        }

        return false
    }

    func infoItemForCell(_ cell: LoginDetailTableViewCell) -> InfoItem? {
        if let index = tableView.indexPath(for: cell),
            let item = InfoItem(rawValue: index.row) {
            return item
        }
        return nil
    }
}
