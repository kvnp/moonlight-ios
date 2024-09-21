//
//  OnScreenKey.swift
//  Moonlight-ZWM
//
//  Created by ZWM on 2024/8/4.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import UIKit


@objc class OnScreenButtonView: UIView {
    @objc static public var editMode: Bool = false
    @objc static public var timestampOfButtonBeingDragged: TimeInterval = 0
    @objc public var keyLabel: String
    @objc public var keyString: String
    @objc public var timestamp: TimeInterval
    @objc public var pressed: Bool
    @objc public var widthFactor: CGFloat
    @objc public var heightFactor: CGFloat

    private let label: UILabel
    private let originalBackgroundColor: UIColor
    private var storedLocation: CGPoint = .zero

    
    @objc init(keyString: String, keyLabel: String) {
        self.keyString = keyString
        self.keyLabel = keyLabel
        self.label = UILabel()
        self.originalBackgroundColor = UIColor(white: 0.2, alpha: 0.7)
        self.timestamp = 0
        self.pressed = false
        self.widthFactor = 1.0
        self.heightFactor = 1.0
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc public func setLocation(xOffset:CGFloat, yOffset:CGFloat) {
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: self.superview!.leadingAnchor, constant: xOffset),
            self.topAnchor.constraint(equalTo: self.superview!.topAnchor, constant: yOffset),
        ])
    }
    
    @objc public func enableRelocationMode(enabled: Bool){
        OnScreenButtonView.editMode = enabled
    }
    
    @objc public func resizeButtonView(){
        guard let superview = superview else { return }
        
        
        // Deactivate existing constraints if necessary
        NSLayoutConstraint.deactivate(self.constraints)
        
        // To resize the button, we must set this to false temporarily
        translatesAutoresizingMaskIntoConstraints = false
        
        
        // replace invalid factor values
        if(self.widthFactor == 0) {self.widthFactor = 1.0}
        if(self.heightFactor == 0) {self.heightFactor = 1.0}

        // Constraints for resizing
        let newWidthConstraint = self.widthAnchor.constraint(equalToConstant: 70 * self.widthFactor)
        let newHeightConstraint = self.heightAnchor.constraint(equalToConstant: 65 * self.heightFactor)
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 70 * self.widthFactor),
            self.heightAnchor.constraint(equalToConstant: 65 * self.heightFactor),
        ])

        // Trigger layout update
        superview.layoutIfNeeded()

        // Re-setup buttonView style
        setupView()
    }
    
    @objc public func setupView() {
        label.text = self.keyLabel
        label.font = UIFont.boldSystemFont(ofSize: 19)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.1  // Adjust the scale factor as needed
        
        label.textColor = UIColor(white: 1.0, alpha: 0.82)
        label.textAlignment = .center
        label.shadowColor = .black
        label.shadowOffset = CGSize(width: 1, height: 1)
        label.translatesAutoresizingMaskIntoConstraints = false // enable auto alignment for the label
        
        self.translatesAutoresizingMaskIntoConstraints = true // this is mandatory to prevent unexpected key view location change
        self.layer.borderColor = UIColor(white: 0.2, alpha: 0.86).cgColor
        self.layer.borderWidth = 1
        self.layer.cornerRadius = 20
        self.backgroundColor = UIColor(white: 0.2, alpha: 0.57)
        self.layer.shadowColor = UIColor.clear.cgColor
        self.layer.shadowRadius = 8
        self.layer.shadowOpacity = 0.5
        
        addSubview(label)
        
        
        NSLayoutConstraint.activate([
            //self.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width * 0.088),
            //self.heightAnchor.constraint(equalToConstant: UIScreen.main.bounds.height * 0.1),
            self.widthAnchor.constraint(equalToConstant: 70 * self.widthFactor),
            self.heightAnchor.constraint(equalToConstant: 65 * self.widthFactor),
        ])
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10), // set up label size contrain within UIView
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            //label.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    private func buttonDownVisualEffect() {
        let spread = 10.2;  // 扩散的大小
        let largerRect = self.bounds.insetBy(dx: -spread, dy: -spread)
        let shadowPath = UIBezierPath(roundedRect: largerRect, cornerRadius: self.layer.cornerRadius)
        self.layer.shadowPath = shadowPath.cgPath
        
        // self.layer.shadowColor = UIColor.systemBlue.withAlphaComponent(0.7).cgColor
        self.layer.shadowColor = UIColor(red: 0.5, green: 0.5, blue: 1.0, alpha: 0.80).cgColor
        self.layer.shadowOffset = CGSize.zero
        self.layer.shadowOpacity = 1.0
        self.layer.shadowRadius = 0.0
        self.layer.borderWidth = 0
    }
    
    // Touch event handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // print("touchDown: %f", CACurrentMediaTime())
        self.pressed = true
        super.touchesBegan(touches, with: event)
        //self.backgroundColor = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.7)
        
        if !OnScreenButtonView.editMode {
            // self.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
            self.buttonDownVisualEffect()
            self.layer.borderWidth = 0
            // if the command(keystring contains "+", it's a multi-key command or a quick triggering key, rather than a physical button
            if(self.keyString.contains("+")){
                let keyboardCmdStrings = CommandManager.shared.extractKeyStrings(from: self.keyString)!
                CommandManager.shared.sendKeyDownEventWithDelay(keyboardCmdStrings: keyboardCmdStrings) // send multi-key command
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { // reset shadow color immediately 50ms later
                    self.layer.shadowColor = UIColor.clear.cgColor
                    self.layer.borderWidth = 1

                }
            }
            // if there's no "+" in the keystring, treat it as a regular button:
            else{
                if(CommandManager.mouseButtonMappings.keys.contains(self.keyString)){
                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), Int32(CommandManager.mouseButtonMappings[self.keyString]!))
                }
                else{
                    LiSendKeyboardEvent(CommandManager.keyMappings[self.keyString]!,Int8(KEY_ACTION_DOWN), 0)
                }
            }
        }
        // here is in edit mode:
        else{
            NotificationCenter.default.post(name: Notification.Name("OnScreenButtonViewSelected"),object: self) // inform layout tool controller to fetch button size factors. self will be passed as the object of the notification
            if let touch = touches.first {
                let touchLocation = touch.location(in: superview)
                storedLocation = touchLocation
            }
        }

    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        OnScreenButtonView.timestampOfButtonBeingDragged = self.timestamp
        
        // Move the buttonView based on touch movement in relocation mode
        if OnScreenButtonView.editMode {
            if let touch = touches.first {
                let currentLocation = touch.location(in: superview)
                let offsetX = currentLocation.x - storedLocation.x
                let offsetY = currentLocation.y - storedLocation.y
                
                center = CGPoint(x: center.x + offsetX, y: center.y + offsetY)
                //NSLog("x coord: %f, y coord: %f", self.frame.origin.x, self.frame.origin.y)
                storedLocation = currentLocation // Update initial center for next movement
            }
        }
    }
    
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // self.pressed = false // will be reset outside the class
        super.touchesEnded(touches, with: event)
        if !OnScreenButtonView.editMode && !self.keyString.contains("+") { // if the command(keystring contains "+", it's a multi-key command rather than a single key button
            
            if(CommandManager.mouseButtonMappings.keys.contains(self.keyString)){
                LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), Int32(CommandManager.mouseButtonMappings[self.keyString]!))
            }
            else{
                LiSendKeyboardEvent(CommandManager.keyMappings[self.keyString]!,Int8(KEY_ACTION_UP), 0)
            }
            
            // self.backgroundColor = self.originalBackgroundColor
            self.layer.shadowColor = UIColor.clear.cgColor
            self.layer.borderWidth = 1
            return;
        }
        // self.backgroundColor = self.originalBackgroundColor
        self.layer.shadowColor = UIColor.clear.cgColor
        self.layer.borderWidth = 1

        guard let superview = superview else { return }

        // Deactivate existing constraints if necessary
        NSLayoutConstraint.deactivate(self.constraints)

        // Add new constraints based on the current center position
        translatesAutoresizingMaskIntoConstraints = true
                
        // Create new constraints
        let newLeadingConstraint = self.leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: self.frame.origin.x)
        let newTopConstraint = self.topAnchor.constraint(equalTo: superview.topAnchor, constant: self.frame.origin.y)
    
        // Activate the new location constraints
        NSLayoutConstraint.activate([newLeadingConstraint, newTopConstraint])

        // Trigger layout update
        superview.layoutIfNeeded()

        setupView(); //re-setup buttonView style
    }
}
