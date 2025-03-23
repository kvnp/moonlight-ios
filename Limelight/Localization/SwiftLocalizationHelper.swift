//
//  SwiftLocalizationHelper.swift
//  Moonlight-ZWM
//
//  Created by ZWM on 2024/7/23.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation

class SwiftLocalizationHelper {
    
    static func localizedString(forKey key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: "", comment: "")
        return String(format: format, arguments: args)
    }
}
