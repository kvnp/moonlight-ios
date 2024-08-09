//
//  OnScreenKey.swift
//  Moonlight-ZWM
//
//  Created by ZWM on 2024/8/4.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import UIKit

@objc class OnScreenKeyView: UIView {
    @objc static var relocationMode: Bool = false
    @objc var keyLabel: String
    @objc var keyString: String
    private let label: UILabel
    private let originalBackgroundColor: UIColor
    private var storedLocation: CGPoint = .zero

    
    @objc init(keyString: String, keyLabel: String) {
        self.keyString = keyString
        self.keyLabel = keyLabel
        self.label = UILabel()
        self.originalBackgroundColor = UIColor(white: 0.2, alpha: 0.7)

        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc public func setKeyLocation(xOffset:CGFloat, yOffset:CGFloat) {
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: self.superview!.leadingAnchor, constant: xOffset),
            self.topAnchor.constraint(equalTo: self.superview!.topAnchor, constant: yOffset),
        ])
    }
    
    @objc public func enableRelocationMode(enabled: Bool){
        OnScreenKeyView.relocationMode = enabled
    }
    
    private func setupView() {
        label.text = self.keyLabel
        label.font = UIFont.systemFont(ofSize: 30)
        label.textColor = UIColor(white: 1.0, alpha: 0.8)
        label.shadowColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        
        self.layer.borderColor = UIColor.black.cgColor
        self.layer.borderWidth = 2
        self.layer.cornerRadius = 8
        self.backgroundColor = UIColor(white: 0.2, alpha: 0.7)
        self.layer.shadowRadius = 4
        self.layer.shadowOpacity = 0.5
        
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width * 0.088),
            self.heightAnchor.constraint(equalToConstant: UIScreen.main.bounds.height * 0.1),
        ]) 
    }
    
    // Touch event handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        //self.backgroundColor = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.7)
        self.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
        
        
        if !OnScreenKeyView.relocationMode { LiSendKeyboardEvent(CommandManager.keyMappings[self.keyString]!,Int8(KEY_ACTION_DOWN), 0) }
        else {
            // Store the initial center point of the key
            if let touch = touches.first {
                let touchLocation = touch.location(in: superview)
                storedLocation = touchLocation
            }
        }

    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        // Move the KeyView based on touch movement in relocation mode
        if OnScreenKeyView.relocationMode {
            if let touch = touches.first {
                let currentLocation = touch.location(in: superview)
                let offsetX = currentLocation.x - storedLocation.x
                let offsetY = currentLocation.y - storedLocation.y
                
                center = CGPoint(x: center.x + offsetX, y: center.y + offsetY)
                storedLocation = currentLocation // Update initial center for next movement
            }
        }
    }
    
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        self.backgroundColor = self.originalBackgroundColor
        if !OnScreenKeyView.relocationMode { LiSendKeyboardEvent(CommandManager.keyMappings[self.keyString]!,Int8(KEY_ACTION_UP), 0) }
    }
}
