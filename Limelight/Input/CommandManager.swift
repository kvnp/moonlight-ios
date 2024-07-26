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
    
    static let keyMappings: [String: Int16] = [
        // Windows Key Codes
        "CTRL": 0x11,        // VK_CONTROL
        "SHIFT": 0x10,       // VK_SHIFT
        "ALT": 0x12,         // VK_MENU
        "F1": 0x70,          // VK_F1
        "F2": 0x71,          // VK_F2
        "F3": 0x72,          // VK_F3
        "F4": 0x73,          // VK_F4
        "F5": 0x74,          // VK_F5
        "F6": 0x75,          // VK_F6
        "F7": 0x76,          // VK_F7
        "F8": 0x77,          // VK_F8
        "F9": 0x78,          // VK_F9
        "F10": 0x79,         // VK_F10
        "F11": 0x7A,         // VK_F11
        "F12": 0x7B,         // VK_F12
        "A": 0x41,           // 'A' key
        "B": 0x42,           // 'B' key
        "C": 0x43,           // 'C' key
        "D": 0x44,           // 'D' key
        "E": 0x45,           // 'E' key
        "F": 0x46,           // 'F' key
        "G": 0x47,           // 'G' key
        "H": 0x48,           // 'H' key
        "I": 0x49,           // 'I' key
        "J": 0x4A,           // 'J' key
        "K": 0x4B,           // 'K' key
        "L": 0x4C,           // 'L' key
        "M": 0x4D,           // 'M' key
        "N": 0x4E,           // 'N' key
        "O": 0x4F,           // 'O' key
        "P": 0x50,           // 'P' key
        "Q": 0x51,           // 'Q' key
        "R": 0x52,           // 'R' key
        "S": 0x53,           // 'S' key
        "T": 0x54,           // 'T' key
        "U": 0x55,           // 'U' key
        "V": 0x56,           // 'V' key
        "W": 0x57,           // 'W' key
        "X": 0x58,           // 'X' key
        "Y": 0x59,           // 'Y' key
        "Z": 0x5A,           // 'Z' key
        "0": 0x30,           // '0' key
        "1": 0x31,           // '1' key
        "2": 0x32,           // '2' key
        "3": 0x33,           // '3' key
        "4": 0x34,           // '4' key
        "5": 0x35,           // '5' key
        "6": 0x36,           // '6' key
        "7": 0x37,           // '7' key
        "8": 0x38,           // '8' key
        "9": 0x39,           // '9' key
        "ESC": 0x1B,         // VK_ESCAPE
        "SPACE": 0x20,       // VK_SPACE
        "ENTER": 0x0D,       // VK_RETURN
        "TAB": 0x09,         // VK_TAB
        "BACKSPACE": 0x08,   // VK_BACK
        "INSERT": 0x2D,      // VK_INSERT
        "DEL": 0x2E,      // VK_DELETE
        "HOME": 0x24,        // VK_HOME
        "END": 0x23,         // VK_END
        "PG_UP": 0x21,     // VK_PRIOR
        "PG_DOWN": 0x22,   // VK_NEXT
        "UP_ARROW": 0x26,    // VK_UP
        "DOWN_ARROW": 0x28,  // VK_DOWN
        "LEFT_ARROW": 0x25,  // VK_LEFT
        "RIGHT_ARROW": 0x27, // VK_RIGHT
        "NUM_LCK": 0x90,    // VK_NUMLOCK
        "SCR_LCK": 0x91, // VK_SCROLL
        "CAPS_LOCK": 0x14,   // VK_CAPITAL
        "PAUSE": 0x13,       // VK_PAUSE
        "PR_SCR": 0x2C, // VK_SNAPSHOT
        "NUMPAD0": 0x60,     // VK_NUMPAD0
        "NUMPAD1": 0x61,     // VK_NUMPAD1
        "NUMPAD2": 0x62,     // VK_NUMPAD2
        "NUMPAD3": 0x63,     // VK_NUMPAD3
        "NUMPAD4": 0x64,     // VK_NUMPAD4
        "NUMPAD5": 0x65,     // VK_NUMPAD5
        "NUMPAD6": 0x66,     // VK_NUMPAD6
        "NUMPAD7": 0x67,     // VK_NUMPAD7
        "NUMPAD8": 0x68,     // VK_NUMPAD8
        "NUMPAD9": 0x69,     // VK_NUMPAD9
        "MULTIPLY": 0x6A,    // VK_MULTIPLY
        "ADD": 0x6B,         // VK_ADD
        "SUBTRACT": 0x6D,    // VK_SUBTRACT
        "DECIMAL": 0x6E,     // VK_DECIMAL
        "DIVIDE": 0x6F,      // VK_DIVIDE
        "SEMI_COLON": 0xBA,  // VK_OEM_1
        "EQUALS": 0xBB,      // VK_OEM_PLUS
        "COMMA": 0xBC,       // VK_OEM_COMMA
        "MINUS": 0xBD,       // VK_OEM_MINUS
        "PERIOD": 0xBE,      // VK_OEM_PERIOD
        "FORWARD_SLASH": 0xBF, // VK_OEM_2
        "GRAVE_ACCENT": 0xC0, // VK_OEM_3
        "OPEN_BRACKET": 0xDB, // VK_OEM_4
        "BACKSLASH": 0xDC,   // VK_OEM_5
        "CLOSE_BRACKET": 0xDD, // VK_OEM_6
        "SINGLE_QUOTE": 0xDE, // VK_OEM_7
        "VOLUME_MUTE": 0xAD, // VK_VOLUME_MUTE
        "VOLUME_DOWN": 0xAE, // VK_VOLUME_DOWN
        "VOLUME_UP": 0xAF,   // VK_VOLUME_UP
        "MEDIA_NEXT": 0xB0,  // VK_MEDIA_NEXT_TRACK
        "MEDIA_PREV": 0xB1,  // VK_MEDIA_PREV_TRACK
        "MEDIA_STOP": 0xB2,  // VK_MEDIA_STOP
        "MEDIA_PLAY_PAUSE": 0xB3, // VK_MEDIA_PLAY_PAUSE
        "LAUNCH_MAIL": 0xB4, // VK_LAUNCH_MAIL
        "LAUNCH_MEDIA_SELECT": 0xB5, // VK_LAUNCH_MEDIA_SELECT
        "LAUNCH_APP1": 0xB6, // VK_LAUNCH_APP1
        "LAUNCH_APP2": 0xB7, // VK_LAUNCH_APP2
        "WIN":  0x5B,
        "LEFT_WIN": 0x5B, // VK_LWIN
        "RIGHT_WIN": 0x5C, // VK_RWIN
        "APPS": 0x5D,        // VK_APPS

        // macOS Key Codes
        "CMD": 0x37,     // ⌘ Command
        "OPT": 0x3A,      // ⌥ Option
        "CONTROL": 0x3B,     // ⌃ Control
        "SHIFT_MAC": 0x38,   // ⇧ Shift
        "FUNCTION": 0x3F,    // fn
        "DELETE_MAC": 0x75,  // Forward Delete
        "RETURN_MAC": 0x24,  // Return
        "ENTER_MAC": 0x4C,   // Enter
        "ESCAPE_MAC": 0x35,  // Escape
        "TAB_MAC": 0x30,     // Tab
        "SPACE_MAC": 0x31,   // Space
        "UP_ARROW_MAC": 0x7E,  // Up Arrow
        "DOWN_ARROW_MAC": 0x7D, // Down Arrow
        "LEFT_ARROW_MAC": 0x7B, // Left Arrow
        "RIGHT_ARROW_MAC": 0x7C, // Right Arrow
        "F1_MAC": 0x7A,      // F1
        "F2_MAC": 0x78,      // F2
        "F3_MAC": 0x63,      // F3
        "F4_MAC": 0x76,      // F4
        "F5_MAC": 0x60,      // F5
        "F6_MAC": 0x61,      // F6
        "F7_MAC": 0x62,      // F7
        "F8_MAC": 0x64,      // F8
        "F9_MAC": 0x65,      // F9
        "F10_MAC": 0x6D,     // F10
        "F11_MAC": 0x67,     // F11
        "F12_MAC": 0x6F,     // F12
        "0_MAC": 0x52,       // 0
        "1_MAC": 0x53,       // 1
        "2_MAC": 0x54,       // 2
        "3_MAC": 0x55,       // 3
        "4_MAC": 0x56,       // 4
        "5_MAC": 0x57,       // 5
        "6_MAC": 0x58,       // 6
        "7_MAC": 0x59,       // 7
        "8_MAC": 0x5A,       // 8
        "9_MAC": 0x5B,       // 9
        "NUMPAD0_MAC": 0x4F, // Numpad 0
        "NUMPAD1_MAC": 0x50, // Numpad 1
        "NUMPAD2_MAC": 0x51, // Numpad 2
        "NUMPAD3_MAC": 0x52, // Numpad 3
        "NUMPAD4_MAC": 0x53, // Numpad 4
        "NUMPAD5_MAC": 0x54, // Numpad 5
        "NUMPAD6_MAC": 0x55, // Numpad 6
        "NUMPAD7_MAC": 0x56, // Numpad 7
        "NUMPAD8_MAC": 0x57, // Numpad 8
        "NUMPAD9_MAC": 0x58, // Numpad 9
        "NUMPAD_ADD_MAC": 0x45,  // Numpad Add
        "NUMPAD_SUBTRACT_MAC": 0x4A, // Numpad Subtract
        "NUMPAD_MULTIPLY_MAC": 0x43, // Numpad Multiply
        "NUMPAD_DIVIDE_MAC": 0x4B, // Numpad Divide
        "NUMPAD_DECIMAL_MAC": 0x41, // Numpad Decimal
    ]
    
    private var commands: [RemoteCommand] = []

    public weak var viewController: CommandManagerViewController?
    
    private override init() {
        super.init()
        loadCommands()
    }
    
    @objc static func presetDefaultCommands() {
        let defaults = UserDefaults.standard
        //if true {  // save default entries if the data is empty.
        if defaults.data(forKey: "savedCommands") == nil {  // save default entries if the data is empty.
            let defaultCommands: [RemoteCommand] = [
                RemoteCommand(keyboardCmdString: "WIN", alias: "WIN"),
                RemoteCommand(keyboardCmdString: "F11", alias: "F11"),
                RemoteCommand(keyboardCmdString: "ESC", alias: "ESC"),
                RemoteCommand(keyboardCmdString: "CTRL+SHIFT+ESC", alias: "任务管理器(Task Manager)"),
                RemoteCommand(keyboardCmdString: "ALT+F1", alias: "N卡截图(Nvidia Screenshot)"),
                RemoteCommand(keyboardCmdString: "ALT+F9", alias: "N卡录屏(Nvidia Screen Recording)"),
                RemoteCommand(keyboardCmdString: "ALT+F4", alias: "关闭窗口(ALT+F4)"),
                RemoteCommand(keyboardCmdString: "CTRL+A", alias: "全选(Select All)"),
                RemoteCommand(keyboardCmdString: "CTRL+C", alias: "复制(Copy)"),
                RemoteCommand(keyboardCmdString: "CTRL+V", alias: "粘贴(Paste)"),
                RemoteCommand(keyboardCmdString: "WIN+D", alias: "切换桌面(Switch to Desktop)"),
                RemoteCommand(keyboardCmdString: "WIN+P", alias: "多显模式(Project)"),
                RemoteCommand(keyboardCmdString: "WIN+G", alias: "Xbox Game Bar"),
                RemoteCommand(keyboardCmdString: "SHIFT+TAB", alias: "Steam Overlay"),
            ]
            
            let data = try? NSKeyedArchiver.archivedData(withRootObject: defaultCommands, requiringSecureCoding: false)
            defaults.set(data, forKey: "savedCommands")
        }
    }

    @objc public func createTestKeyMappings() -> [String: Int16] {
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
        
        var validKeyStrings: [String] = []
        
        for key in keyStrings {
            if CommandManager.keyMappings.keys.contains(key) {
                validKeyStrings.append(key)
            } else {
                print(" '\(key)' is not defined in key mappings")
                return nil  //treat any illegal string as a whole
            }
        }
        
        if validKeyStrings.isEmpty {
            print("No valid key strings found in the matched string")
            return nil
        }
        
        for (index, key) in validKeyStrings.enumerated() {
            print("Valid Key \(index): \(key)")
        }
        
        return validKeyStrings

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
