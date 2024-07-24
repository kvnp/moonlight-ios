//
//  KeyManagerViewController.swift
//  Moonlight-ZWM
//
//  Created by ZWM on 2024/7/23.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import UIKit

@objc public class CommandManagerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    public let tableView = UITableView()
    private let addButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    private let exitButton = UIButton(type: .system)
    private let viewBackgroundColor = UIColor(white: 0.2, alpha: 1.0);
    private let highlightColor = UIColor(white: 0.3, alpha: 1.0);
    private let titleLabel = UILabel()
    
    private var isEditingMode: Bool = false {
        didSet {
            updateEditingMode()
        }
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        setupViews()
        updateEditingMode()
        
        tableView.dataSource = self
        tableView.delegate = self
        
        // Register the cell class
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        //pass self to the CommandManager
        CommandManager.shared.viewController = self
    }
    
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        setupConstraints()
    }
    
    private func setupViews() {
        
        // Set corner radius
        view.layer.cornerRadius = 20  // Adjust the corner radius
        view.layer.masksToBounds = true
        
        // Set up the title label
        titleLabel.text = SwiftLocalizationHelper.localizedString(forKey: "Send Commands")
        titleLabel.font = UIFont.boldSystemFont(ofSize: 20)  // Adjust font size as needed
        titleLabel.textColor = UIColor.white  // Adjust color as needed
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)
        
        view.backgroundColor = viewBackgroundColor
        tableView.backgroundColor = .clear
        tableView.rowHeight = 60
        tableView.separatorColor = highlightColor
        // Configure buttons
        addButton.setTitle(SwiftLocalizationHelper.localizedString(forKey: "Add"), for: .normal)
        deleteButton.setTitle(SwiftLocalizationHelper.localizedString(forKey: "Delete"), for: .normal)
        editButton.setTitle(SwiftLocalizationHelper.localizedString(forKey: "Edit"), for: .normal)
        exitButton.setTitle(SwiftLocalizationHelper.localizedString(forKey: "Exit"), for: .normal)
        addButton.titleLabel?.font = UIFont.systemFont(ofSize: 20) // Adjust the size as needed
        deleteButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        editButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        exitButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        
        // Add subviews
        view.addSubview(tableView)
        view.addSubview(addButton)
        view.addSubview(deleteButton)
        view.addSubview(editButton)
        view.addSubview(exitButton)
        
        // Setup button targets
        addButton.addTarget(self, action: #selector(addButtonTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        editButton.addTarget(self, action: #selector(editButtonTapped), for: .touchUpInside)
        exitButton.addTarget(self, action: #selector(exitButtonTapped), for: .touchUpInside)
    }
    
    private func setupConstraints() {
        
        guard let superview = view.superview else {
            return
        }
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        addButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.translatesAutoresizingMaskIntoConstraints = false
        exitButton.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            
            // Set the width and height of the view
            view.widthAnchor.constraint(equalTo: view.superview!.widthAnchor, multiplier: 0.7),
            view.heightAnchor.constraint(equalTo: view.superview!.heightAnchor, multiplier: 0.9),
            
            // Center the view horizontally and vertically
            view.centerXAnchor.constraint(equalTo: view.superview!.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: view.superview!.centerYAnchor),
            
            // ViewTitle constrains
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 13.5),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            
            
            // TableView constraints
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            tableView.topAnchor.constraint(equalTo: view.topAnchor, constant: 50),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -60),
            
            // ExitButton constraints
            exitButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 25),
            exitButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            
            // EditButton constraints
            editButton.leadingAnchor.constraint(equalTo: exitButton.trailingAnchor, constant: 50),
            editButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            
            // AddButton constraints
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -25),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            
            // DeleteButton constraints
            deleteButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -50),
            deleteButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])
    }
    
    private func updateEditingMode() {
        addButton.isEnabled = isEditingMode
        deleteButton.isEnabled = isEditingMode
        if(isEditingMode){ editButton.setTitle(SwiftLocalizationHelper.localizedString(forKey: "Done"), for: .normal) }
        else{ editButton.setTitle(SwiftLocalizationHelper.localizedString(forKey: "Edit"), for: .normal) }
    }
    
    @objc private func addButtonTapped() {
        let alert = UIAlertController(title: "New Command", message: "Enter a new command and alias", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Command" }
        alert.addTextField { $0.placeholder = "Alias" }
        
        let submitAction = UIAlertAction(title: "Add", style: .default) { [unowned alert] _ in
            let keyboardCmdString = alert.textFields?[0].text ?? ""
            let alias = alert.textFields?[1].text ?? keyboardCmdString
            let newCommand = RemoteCommand(keyboardCmdString: keyboardCmdString, alias: alias)
            CommandManager.shared.addCommand(newCommand)
            //self.reloadTableView() // don't know why but this reload has to be called from the CommandManager, it doesn't work here.
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alert.addAction(submitAction)
        alert.addAction(cancelAction)
        
        if let selectedIndexPath = self.tableView.indexPathForSelectedRow {
            let selectedCommand = CommandManager.shared.getAllCommands()[selectedIndexPath.row]
            alert.textFields?[0].text = selectedCommand.keyboardCmdString // load selected keyboard cmd string
            //alert.textFields?[1].text = selectedCommand.alias
        }
        
        self.present(alert, animated: true)
    }
    
    
    @objc private func deleteButtonTapped() {
        guard let selectedIndexPath = tableView.indexPathForSelectedRow else {
            return
        }
        CommandManager.shared.deleteCommand(at: selectedIndexPath.row)
        reloadTableView()
    }
    
    @objc private func editButtonTapped() {
        isEditingMode.toggle()
    }
    
    @objc private func exitButtonTapped() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc public func reloadTableView() {
        let previouslySelectedIndexPath = tableView.indexPathForSelectedRow
        tableView.layoutIfNeeded()
        tableView.reloadData()

        if let indexPath = previouslySelectedIndexPath {
            // Make sure the indexPath is still valid and scroll to the selected indexPath
            if indexPath.row < tableView.numberOfRows(inSection: indexPath.section) {
                tableView.selectRow(at: indexPath, animated: true, scrollPosition: .middle) // keep the entry of previous index selected.
            }
        }
    }
    
    // UITableViewDataSource
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return CommandManager.shared.getAllCommands().count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        // Configure cell appearance
        cell.backgroundColor = viewBackgroundColor // Set background color of the cell
        cell.textLabel?.textColor = UIColor.white // Set font color of the text
        
        // Set selected background view
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = highlightColor // Color for the selected state
        cell.selectedBackgroundView = selectedBackgroundView
        
        
        let command = CommandManager.shared.getAllCommands()[indexPath.row]
        cell.textLabel?.text = command.alias
        return cell
    }
    
    // UITableViewDelegate
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        if let cell = tableView.cellForRow(at: indexPath) {
            // Set the cell background color to the flashing color
            // Animate the flash effect
            UIView.animate(withDuration: 0.1, animations: {
                cell.selectedBackgroundView?.backgroundColor = self.viewBackgroundColor
            }) { _ in
                // Reset the cell background color after the animation
                UIView.animate(withDuration: 0.1) {
                    cell.selectedBackgroundView?.backgroundColor = self.highlightColor
                }
            }
        }
        
        if !isEditingMode {
            // Call the dummy method for key-value sending implementation
            let command = CommandManager.shared.getAllCommands()[indexPath.row]
            sendKeyboardCommand(command)
            dismiss(animated: false, completion: nil) // dimiss the view in sending mode
        }
    }
    
    private func sendKeyboardCommand(_ cmd: RemoteCommand) {
        // Dummy implementation
        print("Sending key-value")
        
        let keyboardCmdStrings = CommandManager.shared.extractKeyStrings(from: cmd.keyboardCmdString)
        for keyStr in keyboardCmdStrings! {
            LiSendKeyboardEvent(CommandManager.keyMappings[keyStr]!,Int8(KEY_ACTION_DOWN), 0)
            print("keycode: \(CommandManager.keyMappings[keyStr] ?? 0xFF)")
            Thread.sleep(forTimeInterval: 0.05)
        }
        for keyStr in keyboardCmdStrings! {
            LiSendKeyboardEvent(CommandManager.keyMappings[keyStr]!,Int8(KEY_ACTION_UP), 0)
        }
    }
}

