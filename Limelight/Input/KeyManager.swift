//
//  KeyManager.swift
//  Moonlight-ZWM
//
//  Created by ZWM on 2024/7/23.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import UIKit

@objc public class KeyManager: NSObject {
    @objc public static let shared = KeyManager()

    private var strings: [String] = []
    private let keyMappings: [String: UInt16] = [
        "CTRL": 0x11,
        "ALT": 0x12,
        "DEL": 0x2E,
        "F1": 0x70,
        "F2": 0x71
    ]
    
    private weak var viewController: KeyManagerViewController?
    
    private override init() {
        super.init()
        loadStrings()
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
    
    @objc public func addString(_ string: String) {
        /* guard isValidString(string) else {
            return
        } */
        strings.append(string)
        saveStrings()
        viewController?.reloadTableView()
    }
    
    @objc public func deleteString(at index: Int) {
        guard index >= 0 && index < strings.count else {
            return
        }
        strings.remove(at: index)
        saveStrings()
        viewController?.reloadTableView()
    }
    
    @objc public func getAllStrings() -> [String] {
        return strings
    }
    
    private func isValidString(_ string: String) -> Bool {
        let keys = keyMappings.keys.joined(separator: "|")
        let pattern = "^((?:\(keys))(?:\\+\(keys))*)$"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        
        let range = NSRange(location: 0, length: string.utf16.count)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }
    
    private func loadStrings() {
        if let savedStrings = UserDefaults.standard.array(forKey: "savedStrings") as? [String] {
            strings = savedStrings
        }
    }
    
    private func saveStrings() {
        UserDefaults.standard.set(strings, forKey: "savedStrings")
    }
    
    @objc public func setupViewController(_ viewController: KeyManagerViewController) {
        self.viewController = viewController
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(promptForNewString))
        viewController.navigationItem.rightBarButtonItem = addButton
        viewController.navigationItem.title = "Manage Strings"
        
        
        viewController.tableView.delegate = viewController
        viewController.tableView.dataSource = viewController
        //viewController.tableView.backgroundColor = UIColor.black.withAlphaComponent(0.5)

    }
    
    @objc private func promptForNewString() {
        guard let topController = UIApplication.shared.keyWindow?.rootViewController else {
            return
        }
        
        let alert = UIAlertController(title: "New String", message: "Enter a new string", preferredStyle: .alert)
        alert.addTextField()
        
        let submitAction = UIAlertAction(title: "Add", style: .default) { [unowned alert] _ in
            let newString = alert.textFields![0].text ?? ""
            self.addString(newString)
        }
        
        alert.addAction(submitAction)
        topController.present(alert, animated: true)
    }
}
