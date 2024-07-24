//
//  KeyManager.swift
//  Moonlight-ZWM
//
//  Created by ZWM on 2024/7/23.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import UIKit

// Define the RemoteCommand class
@objc public class RemoteCommand: NSObject, NSCoding {
    @objc public var keyboardCmdString: String
    @objc public var alias: String
    
    init(keyboardCmdString: String, alias: String) {
        self.keyboardCmdString = keyboardCmdString
        self.alias = alias
    }
    
    // MARK: - NSCoding
    
    required public init?(coder: NSCoder) {
        guard let keyboardCmdString = coder.decodeObject(forKey: "keyboardCmdString") as? String,
              let alias = coder.decodeObject(forKey: "alias") as? String else {
            return nil
        }
        self.keyboardCmdString = keyboardCmdString
        self.alias = alias
    }
    
    public func encode(with coder: NSCoder) {
        coder.encode(keyboardCmdString, forKey: "keyboardCmdString")
        coder.encode(alias, forKey: "alias")
    }
}

// Define the CommandManager class
@objc public class CommandManager: NSObject {
    @objc public static let shared = CommandManager()
    
    private var commands: [RemoteCommand] = []
    private let keyMappings: [String: UInt16] = [
        "CTRL": 0x11,
        "ALT": 0x12,
        "DEL": 0x2E,
        "F1": 0x70,
        "F2": 0x71
    ]
    
    private weak var viewController: CommandManagerViewController?
    
    private override init() {
        super.init()
        loadCommands()
    }
    
    @objc public func createTestKeyMappings() -> [String: UInt16] {
        return keyMappings
    }
    
    @objc public func extractKeyStrings(from input: String) -> [String]? {
        let keys = keyMappings.keys.joined(separator: "|")
        let pattern = "^((?:\(keys))(?:\\+\(keys))*)$"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let range = NSRange(location: 0, length: input.utf16.count)
        guard let match = regex.firstMatch(in: input, options: [], range: range) else {
            return nil
        }
        
        let matchedString = (input as NSString).substring(with: match.range(at: 1))
        let keyStrings = matchedString.split(separator: "+").map { String($0) }
        return keyStrings
    }
    
    @objc public func addCommand(_ command: RemoteCommand) {
        commands.append(command)
        saveCommands()
        viewController?.reloadTableView()
    }
    
    @objc public func deleteCommand(at index: Int) {
        guard index >= 0 && index < commands.count else {
            return
        }
        commands.remove(at: index)
        saveCommands()
    }
    
    @objc public func getAllCommands() -> [RemoteCommand] {
        return commands
    }
    
    private func loadCommands() {
        if let savedCommandsData = UserDefaults.standard.data(forKey: "savedCommands"),
           let savedCommands = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedCommandsData) as? [RemoteCommand] {
            commands = savedCommands
        }
    }
    
    private func saveCommands() {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: commands, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "savedCommands")
        }
    }
    
    @objc public func setupViewController(_ viewController: CommandManagerViewController) {
        self.viewController = viewController
        //let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(promptForNewCommand))
        //viewController.navigationItem.rightBarButtonItem = addButton
        //viewController.navigationItem.title = "Manage Commands"
        
        //viewController.tableView.delegate = viewController
        //viewController.tableView.dataSource = viewController
    }
}
