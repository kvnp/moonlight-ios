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
@objc public class RemoteCommand: NSObject, NSSecureCoding {
    // MARK: - NSSecureCoding

    public static var supportsSecureCoding: Bool {
        return true
    }
    
    // MARK: - Properties
    
    @objc var keyboardCmdString: String
    @objc var alias: String
    
    // MARK: - Initialization

    init(keyboardCmdString: String, alias: String) {
        self.keyboardCmdString = keyboardCmdString
        self.alias = alias
    }

    // MARK: - NSSecureCoding

    required public init?(coder: NSCoder) {
        guard let keyboardCmdString = coder.decodeObject(of: NSString.self, forKey: "keyboardCmdString") as String?,
              let alias = coder.decodeObject(of: NSString.self, forKey: "alias") as String? else {
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
    
    static let keyMappings: [String: UInt16] = [
        "CTRL": 0x11,
        "ALT": 0x12,
        "DEL": 0x2E,
        "F1": 0x70,
        "F2": 0x71
    ]
    
    private var commands: [RemoteCommand] = []

    public weak var viewController: CommandManagerViewController?
    
    private override init() {
        super.init()
        loadCommands()
    }
    
    @objc public func createTestKeyMappings() -> [String: UInt16] {
        return CommandManager.keyMappings
    }
    
    // extractKeyStrings from keyboardCMDString
    @objc public func extractKeyStrings(from input: String) -> [String]? {
        let keys = CommandManager.keyMappings.keys.joined(separator: "|")
        let pattern = "^(?:(\(keys))(?:\\+(\(keys))*)*)$"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            print("Failed to create regex")
            return nil
        }
        let range = NSRange(location: 0, length: input.utf16.count)
        guard let match = regex.firstMatch(in: input, options: [], range: range) else {
            print("No match found for input: \(input)")
            return nil
        }
        print("Regex matched for input: \(input)")
        
        let matchedString = (input as NSString).substring(with: match.range(at: 0))
        let keyStrings = matchedString.split(separator: "+").map { String($0) }

        guard !keyStrings.isEmpty else {
            print("No key strings found in the matched string")
            return nil
        }
        
        for (index, key) in keyStrings.enumerated() {
            print("Key \(index): \(key)")
        }
        
        return keyStrings
    }
    
    @objc public func addCommand(_ command: RemoteCommand) {
        command.keyboardCmdString = command.keyboardCmdString.uppercased() // convert all letters to upper case
        if(command.alias.trimmingCharacters(in: .whitespacesAndNewlines).count == 0) {command.alias = command.keyboardCmdString} // copy cmd string as alias when alias is empty
        let keyStrings = extractKeyStrings(from: command.keyboardCmdString)
        if (keyStrings == nil) {return}  // in case of non-keyboard command strings, return
        commands.append(command)
        saveCommands()
        viewController?.reloadTableView() // don't know why but this reload has to be called from the CommandManager, doesn't work by calling it in the viewcontroller, probably related with the dialog box.
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
        if let savedCommandsData = UserDefaults.standard.data(forKey: "savedCommands") {
            do {
                // Attempt to unarchive the data into an array of RemoteCommand
                if let savedCommands = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, RemoteCommand.self], from: savedCommandsData) as? [RemoteCommand] {
                    // Assign the unarchived commands to your property
                    print(" Assign the unarchived commands to your property ")
                    commands = savedCommands
                } else {
                    // Handle the case where the data could not be unarchived into the expected type
                    print("Data could not be unarchived into [RemoteCommand]")
                }
            } catch {
                // Handle any errors that occur during unarchiving
                print("Failed to unarchive savedCommands with error: \(error)")
            }
        }
    }

    
    private func saveCommands() {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: commands, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "savedCommands")
        }
    }
}
